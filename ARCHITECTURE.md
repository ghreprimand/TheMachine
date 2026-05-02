# Architecture

Complete byte-level documentation of `machine-dump`.

## Memory Layout

The program occupies a single `LOAD` segment mapped at virtual address `0x400000`:

```
┌─────────────────────────────────────────────────────────┐
│ ELF Header (64 bytes)                     0x400000      │
│ Program Header (56 bytes)                 0x400040      │
├─────────────────────────────────────────────────────────┤
│ Code Section (.text)                      0x400078      │
│                                                         │
│   ┌─ Entry Point ──────────────────────────────────┐    │
│   │ _start:                                        │    │
│   │   Parse argv for filename                      │    │
│   │   Open file (syscall 2)                        │    │
│   │   fstat file for size (syscall 5)              │    │
│   │   mmap file into memory (syscall 9)            │    │
│   │   Save original termios (ioctl)                │    │
│   │   Set raw mode (ioctl)                         │    │
│   │   Install SIGWINCH handler (syscall 13)        │    │
│   │   Get terminal size (ioctl TIOCGWINSZ)         │    │
│   │   Jump to main_loop                            │    │
│   └────────────────────────────────────────────────┘    │
│                                                         │
│   ┌─ Main Loop ────────────────────────────────────┐    │
│   │ main_loop:                                     │    │
│   │   Call render_screen                           │    │
│   │   Call read_key                                │    │
│   │   Dispatch on key value                        │    │
│   │   Update scroll offset                         │    │
│   │   Jump to main_loop                            │    │
│   └────────────────────────────────────────────────┘    │
│                                                         │
│   ┌─ Rendering ────────────────────────────────────┐    │
│   │ render_screen:                                 │    │
│   │   Write cursor-home escape                     │    │
│   │   Call draw_header                             │    │
│   │   For each visible row:                        │    │
│   │     Call draw_row                              │    │
│   │   Call draw_footer                             │    │
│   │                                                │    │
│   │ draw_row:                                      │    │
│   │   Format 8-char hex offset                     │    │
│   │   For each of 16 bytes:                        │    │
│   │     Convert byte to 2 hex chars                │    │
│   │     Apply color (null=dim, print=green,        │    │
│   │                   high=yellow)                  │    │
│   │   Write ASCII sidebar (. for non-printable)    │    │
│   │                                                │    │
│   │ draw_header:                                   │    │
│   │   Box-drawing top border                       │    │
│   │   Title bar with filename and file size        │    │
│   │   Column headers (00 01 02 ... 0F)             │    │
│   │   Separator line                               │    │
│   │                                                │    │
│   │ draw_footer:                                   │    │
│   │   Separator line                               │    │
│   │   Key hints                                    │    │
│   │   Box-drawing bottom border                    │    │
│   └────────────────────────────────────────────────┘    │
│                                                         │
│   ┌─ Input Handling ──────────────────────────────┐     │
│   │ read_key:                                      │    │
│   │   Read byte from stdin (syscall 0)             │    │
│   │   If escape (0x1B):                            │    │
│   │     Read next bytes for arrow/PgUp/PgDn/etc   │    │
│   │     Return virtual keycode                     │    │
│   │   Else return literal byte                     │    │
│   │                                                │    │
│   │ read_hex_input:                                │    │
│   │   Display prompt at footer                     │    │
│   │   Read hex chars until Enter                   │    │
│   │   Convert ASCII hex to integer                 │    │
│   │   Return value                                 │    │
│   └────────────────────────────────────────────────┘    │
│                                                         │
│   ┌─ Search ──────────────────────────────────────┐     │
│   │ search_bytes:                                  │    │
│   │   Parse hex input string to byte pattern       │    │
│   │   Scan file buffer from current offset         │    │
│   │   Return match offset or -1                    │    │
│   └────────────────────────────────────────────────┘    │
│                                                         │
│   ┌─ Utility ─────────────────────────────────────┐     │
│   │ byte_to_hex:  Convert byte → 2 ASCII hex      │    │
│   │ int_to_hex:   Convert u64 → 8-char hex string  │    │
│   │ int_to_dec:   Convert u64 → decimal string     │    │
│   │ write_str:    Write buffer to stdout           │    │
│   │ set_color:    Write ANSI color escape          │    │
│   │ reset_color:  Write ANSI reset escape          │    │
│   │ move_cursor:  Write cursor positioning escape  │    │
│   │ clear_screen: Write clear + home escapes       │    │
│   └────────────────────────────────────────────────┘    │
│                                                         │
│   ┌─ Cleanup ─────────────────────────────────────┐     │
│   │ shutdown:                                      │    │
│   │   Restore original termios (ioctl)             │    │
│   │   Clear screen                                 │    │
│   │   munmap file                                  │    │
│   │   Close file descriptor                        │    │
│   │   Exit 0 (syscall 60)                          │    │
│   └────────────────────────────────────────────────┘    │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ Data Section (.data)                                    │
│                                                         │
│   Escape sequence templates                             │
│   Box-drawing character strings (UTF-8)                 │
│   Column header string                                  │
│   Hex digit lookup table "0123456789ABCDEF"             │
│   Key hint strings                                      │
│   Error messages                                        │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ BSS Section (uninitialized, not in file)                │
│                                                         │
│   Original termios struct (60 bytes)                    │
│   Raw termios struct (60 bytes)                         │
│   Output buffer (4096 bytes)                            │
│   Input buffer (64 bytes)                               │
│   Search pattern buffer (64 bytes)                      │
│   winsize struct (8 bytes)                              │
│   State variables:                                      │
│     - file_fd (8 bytes)                                 │
│     - file_size (8 bytes)                               │
│     - file_ptr (8 bytes) — mmap'd address               │
│     - scroll_offset (8 bytes)                           │
│     - term_rows (8 bytes)                               │
│     - term_cols (8 bytes)                               │
│     - search_len (8 bytes)                              │
│     - search_offset (8 bytes)                           │
│     - dirty flag (8 bytes)                              │
│                                                         │
│   Total BSS: ~4440 bytes                                │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## ELF Header (64 bytes)

```
Offset  Bytes                            Field
──────  ──────────────────────────────── ─────────────────────────
0x00    7F 45 4C 46                      Magic: \x7fELF
0x04    02                               Class: 64-bit
0x05    01                               Data: little-endian
0x06    01                               Version: 1 (current)
0x07    00                               OS/ABI: System V
0x08    00 00 00 00 00 00 00 00          Padding
0x10    02 00                            Type: ET_EXEC (executable)
0x12    3E 00                            Machine: x86_64
0x14    01 00 00 00                      Version: 1
0x18    78 00 40 00 00 00 00 00          Entry point: 0x400078
0x20    40 00 00 00 00 00 00 00          Program header offset: 64
0x28    00 00 00 00 00 00 00 00          Section header offset: 0 (none)
0x30    00 00 00 00                      Flags: 0
0x34    40 00                            ELF header size: 64
0x36    38 00                            Program header entry size: 56
0x38    01 00                            Program header count: 1
0x3A    00 00                            Section header entry size: 0
0x3C    00 00                            Section header count: 0
0x3E    00 00                            Section name string table index: 0
```

## Program Header (56 bytes)

```
Offset  Bytes                            Field
──────  ──────────────────────────────── ─────────────────────────
0x40    01 00 00 00                      Type: PT_LOAD
0x44    07 00 00 00                      Flags: RWX
0x48    00 00 00 00 00 00 00 00          Offset: 0
0x50    00 00 40 00 00 00 00 00          Virtual addr: 0x400000
0x58    00 00 40 00 00 00 00 00          Physical addr: 0x400000
0x60    XX XX XX XX XX XX XX XX          File size: (total file size)
0x68    XX XX XX XX XX XX XX XX          Memory size: (file + BSS)
0x70    00 00 20 00 00 00 00 00          Alignment: 0x200000
```

## Syscall Convention (x86_64 Linux)

```
Syscall number:  rax
Arguments:       rdi, rsi, rdx, r10, r8, r9
Return value:    rax
Clobbered:       rcx, r11
Instruction:     syscall
```

## Register Allocation Plan

Registers are allocated to minimize save/restore overhead:

```
r12  — file descriptor (preserved across calls)
r13  — mmap base pointer (preserved)
r14  — file size (preserved)
r15  — scroll offset in bytes (preserved, always multiple of 16)
rbx  — terminal rows (preserved)
rbp  — terminal cols (preserved)
```

Scratch registers for computation: `rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`, `r9`, `r10`, `r11`.

## Color Scheme

```
Byte Value      Color                  ANSI Code
──────────────  ─────────────────────  ──────────
0x00            Dim gray               \x1b[38;5;240m
0x01-0x1F       Dark cyan (control)    \x1b[38;5;67m
0x20-0x7E       Green (printable)      \x1b[38;5;114m
0x7F            Dark cyan (DEL)        \x1b[38;5;67m
0x80-0xFF       Yellow (high bytes)    \x1b[38;5;179m
Search match    Red background         \x1b[48;5;52m
Offset column   Gold                   \x1b[38;5;178m
Box borders     Dim white              \x1b[38;5;249m
Title text      Bold white             \x1b[1;37m
Key hints       Dim gray               \x1b[38;5;245m
```

## Key Escape Sequences

```
Key         Byte Sequence        Internal Code
──────────  ───────────────────  ─────────────
Up          1B 5B 41             0x01
Down        1B 5B 42             0x02
Right       1B 5B 43             0x03
Left        1B 5B 44             0x04
Home        1B 5B 48             0x10
End         1B 5B 46             0x11
PgUp        1B 5B 35 7E         0x12
PgDn        1B 5B 36 7E         0x13
q           71                   'q'
g           67                   'g'
/           2F                   '/'
n           6E                   'n'
```

## Output Buffering Strategy

All screen output is buffered into a 4096-byte buffer before being flushed with a single `write` syscall. This prevents flicker — the terminal receives the entire frame at once rather than character by character.

```
1. Clear output buffer (reset write pointer)
2. Append cursor-home escape to buffer
3. Append header lines to buffer
4. For each visible row, append formatted line to buffer
5. Append footer to buffer
6. Single write(1, buffer, length) syscall
```

If the frame exceeds 4096 bytes (large terminals), multiple write calls are chained. The buffer is in BSS (stack-relative addressing).
