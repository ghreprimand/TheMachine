# TUI Rendering

All visual output is ANSI escape sequences and UTF-8 text written to stdout. No ncurses, no terminfo — we emit raw bytes.

## Screen Layout

```
Row 0:  ┌─── machine-dump ─── filename.bin ── 12345 bytes ──────────────────┐
Row 1:  │                                                                    │
Row 2:  │  Offset   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  ASCII │
Row 3:  │  ──────── ─────────────────────────────────────────────────── ───── │
Row 4:  │  00000000 7F 45 4C 46 02 01 01 00 00 00 00 00 00 00 00 00  .ELF.. │
Row 5:  │  00000010 02 00 3E 00 01 00 00 00 78 00 40 00 00 00 00 00  ..>..x │
 ...    │  ...                                                               │
Row N-2:│                                                                    │
Row N-1:│  ↑/↓ scroll  PgUp/PgDn page  g goto  / search  n next  q quit    │
Row N:  └────────────────────────────────────────────────────────────────────┘
```

Visible data rows = terminal rows - 6 (header: 4 rows, footer: 2 rows).

## ANSI Escape Sequences

All sequences start with ESC (`\x1B`, byte `0x1B`), followed by `[` (`0x5B`):

### Cursor Control

| Sequence | Bytes | Effect |
|----------|-------|--------|
| `\x1b[H` | `1B 5B 48` | Cursor to row 1, col 1 (home) |
| `\x1b[{r};{c}H` | `1B 5B {r} 3B {c} 48` | Cursor to row r, col c |
| `\x1b[2J` | `1B 5B 32 4A` | Clear entire screen |
| `\x1b[K` | `1B 5B 4B` | Clear from cursor to end of line |
| `\x1b[?25l` | `1B 5B 3F 32 35 6C` | Hide cursor |
| `\x1b[?25h` | `1B 5B 3F 32 35 68` | Show cursor |
| `\x1b[?1049h` | ... | Switch to alternate screen buffer |
| `\x1b[?1049l` | ... | Restore original screen buffer |

### Color (256-color mode)

| Sequence | Effect |
|----------|--------|
| `\x1b[38;5;{n}m` | Set foreground to color n |
| `\x1b[48;5;{n}m` | Set background to color n |
| `\x1b[0m` | Reset all attributes |
| `\x1b[1m` | Bold |
| `\x1b[2m` | Dim |

### Colors Used

```
240 — dark gray (null bytes, non-data)
 67 — muted blue (control chars 0x01-0x1F, 0x7F)
114 — green (printable ASCII 0x20-0x7E)
179 — warm yellow (high bytes 0x80-0xFF)
178 — gold (offset column)
249 — light gray (box borders)
245 — medium gray (key hints)
 52 — dark red background (search match highlight)
```

## Box Drawing Characters (UTF-8)

| Char | UTF-8 Bytes | Usage |
|------|-------------|-------|
| `┌` | `E2 94 8C` | Top-left corner |
| `┐` | `E2 94 90` | Top-right corner |
| `└` | `E2 94 94` | Bottom-left corner |
| `┘` | `E2 94 98` | Bottom-right corner |
| `│` | `E2 94 82` | Vertical border |
| `─` | `E2 94 80` | Horizontal border |

Each box-drawing character is 3 bytes in UTF-8 but occupies 1 column in the terminal.

## Rendering Strategy

### Buffered Output

All rendering goes through an output buffer to minimize syscalls and prevent flicker:

```
1. Reset buffer write pointer to 0
2. Append alternate-screen + hide-cursor (first frame only)
3. Append cursor-home sequence
4. Build header into buffer
5. For each visible row:
   a. Append cursor-position sequence for row start
   b. Append "│  " border + padding
   c. Append offset in gold (8 hex digits + 2 spaces)
   d. For each of 16 columns:
      - Append color escape for byte class
      - Append 2 hex digits + space
      - Track ASCII for sidebar
   e. Append color reset
   f. Append ASCII sidebar (. for non-printable)
   g. Append border + newline
6. Build footer into buffer
7. Single write(1, buffer, length)
```

### Frame Updates

On every keypress, the entire visible portion is redrawn. Since we buffer everything and flush once, this is fast enough — a typical frame is ~3-5KB of escape sequences and text, well within a single write's capability.

The cursor is hidden during rendering to prevent flicker artifacts.

### Terminal Resize

When `SIGWINCH` fires, the handler sets a dirty flag. The main loop checks this flag before rendering and calls `ioctl(TIOCGWINSZ)` to get the new dimensions. The next render adapts to the new size.

## Filename Display

The filename from argv is displayed in the title bar. Since we're working with raw bytes, we just copy the argv pointer contents. The display is truncated if the terminal is too narrow, with priority given to:

1. Program name ("machine-dump") — always shown
2. File size — always shown
3. Filename — truncated with "..." if needed

## Number Formatting

### Byte to Hex (used per-byte in hex dump)

```
input: byte value 0x00-0xFF
output: 2 ASCII characters

lookup_table: "0123456789ABCDEF" (16 bytes in .data)

high_nibble = (byte >> 4) & 0x0F
low_nibble  = byte & 0x0F
char1 = lookup_table[high_nibble]
char2 = lookup_table[low_nibble]
```

### Integer to Hex (used for offset column)

Same lookup table, applied to each nibble of a 32-bit value (8 hex digits, big-endian output for human readability).

### Integer to Decimal (used for file size display)

Repeated division by 10, digits emitted in reverse then flipped. Maximum file size we display: 2^63 (19 decimal digits).
