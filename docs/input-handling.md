# Input Handling

Keyboard input is read byte-by-byte from stdin in raw terminal mode. We parse escape sequences to detect special keys.

## Raw Mode

Normal terminal mode buffers input until Enter and echoes characters back. We disable both:

```
termios.c_lflag &= ~(ICANON | ECHO | ISIG)
termios.c_cc[VMIN] = 1     // return after 1 byte
termios.c_cc[VTIME] = 0    // no timeout
```

This means `read(0, buf, 1)` blocks until exactly one byte is available, then returns immediately.

## Key Parsing

### Simple Keys

Single-byte keys are returned directly:

| Key | Byte | Action |
|-----|------|--------|
| `q` | `0x71` | Quit |
| `g` | `0x67` | Go to offset prompt |
| `/` | `0x2F` | Search prompt |
| `n` | `0x6E` | Next search result |

### Escape Sequences (Arrow Keys, etc.)

When we read `0x1B` (ESC), we attempt to read more bytes to form a complete sequence:

```
Read byte → 0x1B (ESC)
  Read byte → 0x5B ('[')
    Read byte →
      0x41 → Up
      0x42 → Down
      0x43 → Right (unused)
      0x44 → Left (unused)
      0x48 → Home
      0x46 → End
      0x35 → Read one more: 0x7E → Page Up
      0x36 → Read one more: 0x7E → Page Down
```

If ESC is followed by something unexpected, we discard the sequence and wait for the next key.

### Timing Concern

A bare ESC key (user pressing Escape) sends just `0x1B`. Escape sequences send `0x1B` followed immediately by more bytes. In raw mode with VMIN=1/VTIME=0, we can't distinguish these by timing — read() blocks indefinitely on each byte.

Our approach: after reading `0x1B`, we do a non-blocking read (set VMIN=0, VTIME=1 temporarily — 100ms timeout). If nothing arrives, it was a bare ESC. If `[` arrives, we continue parsing the sequence.

This is how most terminal programs handle it. The 100ms timeout is imperceptible to humans but long enough that the terminal's escape sequence bytes (which arrive within microseconds of each other) are always caught.

## Interactive Prompts

### Go To Offset (`g`)

```
1. Draw prompt at footer: "Go to: 0x"
2. Show cursor
3. Read hex digits until Enter (0x0A) or Escape (0x1B)
   - Accept: 0-9 (0x30-0x39), a-f (0x61-0x66), A-F (0x41-0x46)
   - Backspace (0x7F): remove last digit
   - Escape: cancel, return to viewer
4. Convert hex string to integer
5. Clamp to file size (round down to 16-byte boundary)
6. Set scroll_offset = clamped value
7. Hide cursor, redraw
```

### Search (`/`)

```
1. Draw prompt at footer: "Search: "
2. Show cursor
3. Read hex digit pairs until Enter or Escape
   - Display as typed: "7F 45 4C 46"
   - Backspace removes last nibble/pair
   - Escape: cancel
4. Parse hex pairs into byte pattern (stored in search_pattern buffer)
5. Scan file from current offset + 1 forward
   - Byte-by-byte comparison (brute force — simple and sufficient)
   - Wrap around to start if end reached without match
6. If found: set scroll_offset to show match row, set search_offset for highlighting
7. If not found: flash "Not found" in footer for one frame
```

### Next Result (`n`)

Resume search from `search_offset + 1` using the same pattern. Same wrap-around behavior.

## Scroll Logic

```
scroll_offset: byte offset into file (always multiple of 16)
visible_rows:  terminal_rows - 6
max_offset:    (file_size / 16) * 16 - (visible_rows * 16)
               (clamped to 0 if file smaller than screen)

Up:     scroll_offset = max(0, scroll_offset - 16)
Down:   scroll_offset = min(max_offset, scroll_offset + 16)
PgUp:   scroll_offset = max(0, scroll_offset - visible_rows * 16)
PgDn:   scroll_offset = min(max_offset, scroll_offset + visible_rows * 16)
Home:   scroll_offset = 0
End:    scroll_offset = max_offset
```
