# Hex Dump Format

The core output format — how file bytes become a readable hex display.

## Row Format

Each row displays 16 bytes:

```
│  00000120 48 89 E5 48 83 EC 10 C7 45 FC 00 00 00 00 8B 45  H..H..E......E  │
   ^^^^^^^^ ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^
   offset   hex pairs (16 bytes, grouped 8+8)                     ASCII sidebar
```

### Offset Column

- 8 uppercase hex digits representing the byte offset of the first byte in the row
- Color: gold (ANSI 178)
- Followed by 1 space

### Hex Pairs

- 16 bytes displayed as uppercase hex pairs separated by spaces
- Extra space between bytes 7 and 8 (visual grouping into two octets)
- Color per byte class:
  - `0x00`: dim gray (240) — nulls are visually suppressed
  - `0x01-0x1F`, `0x7F`: muted blue (67) — control characters
  - `0x20-0x7E`: green (114) — printable ASCII
  - `0x80-0xFF`: warm yellow (179) — high bytes

If a search match overlaps this row, matched bytes get a dark red background (ANSI 256-color bg 52) in addition to their foreground color.

### ASCII Sidebar

- 16 characters showing the printable ASCII representation
- Printable bytes (`0x20-0x7E`): shown as-is, in green
- Non-printable bytes: shown as `.` (period), in dim gray
- Separated from hex by 2 spaces

### Partial Last Row

If the file size is not a multiple of 16, the last row has fewer bytes. Missing hex positions are filled with spaces to keep the ASCII sidebar aligned.

```
│  000003F0 48 65 6C 6C 6F 0A                                 Hello.          │
                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                              spaces where bytes 6-15 would be
```

## Column Headers

```
│  Offset   00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F   ASCII          │
│  ──────── ──────────────────────── ──────────────────────────  ──────────────  │
```

Headers use dim white (249). The separator line uses box-drawing `─` characters.

## Width Calculation

Minimum terminal width for full display:

```
│  = 3 bytes (E2 94 82) + 2 spaces
Offset = 8 chars + 1 space
Hex pairs = (16 × 3) - 1 + 1 = 48 + 1 extra mid-gap = 49
Gap = 2 spaces
ASCII = 16 chars
Border + padding = 3
Total = 3 + 8 + 1 + 49 + 2 + 16 + 3 = 82 columns minimum
```

If the terminal is narrower than 82 columns, the ASCII sidebar is hidden. If narrower than 60, a warning message replaces the display.

## File Size Display

The title bar shows the file size in bytes, formatted as decimal:

```
┌─── machine-dump ─── kernel.bin ── 14680064 bytes ──────────────────────┐
```

For files over 1MB, we also show a human-readable size:

```
14680064 bytes (14.0 MB)
```

The MB/KB suffix is calculated with integer arithmetic (no floating point — we don't have it). We multiply by 10, divide, and insert a decimal point manually.
