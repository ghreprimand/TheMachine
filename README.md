# TheMachine

A fully interactive TUI hex dump tool implemented as annotated x86_64 machine-code bytes. No compiler, no assembler, no libraries, no libc — just raw bytes forming a valid ELF binary that talks directly to the Linux kernel via syscalls.

## What This Is

`machine-dump` is a terminal-based hex viewer with scrolling, color-coded output, and keyboard navigation. The program is represented byte-for-byte in `machine-dump.hex`; the binary is built directly from that source.

Run it on itself to see what it's made of:

```
./machine-dump machine-dump
```

```
┌─── machine-dump ─── machine-dump ── 4096 bytes ─────────────────────────────┐
│                                                                              │
│  Offset   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ASCII          │
│  ──────── ─────────────────────────────────────────────────── ──────────────  │
│  00000000 7F 45 4C 46 02 01 01 00 00 00 00 00 00 00 00 00    .ELF.........  │
│  00000010 02 00 3E 00 01 00 00 00 78 00 40 00 00 00 00 00    ..>.....x.@..  │
│  00000020 40 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00    @..............  │
│  ...                                                                         │
│                                                                              │
│  [↑/↓ scroll]  [PgUp/PgDn page]  [g goto]  [/ search]  [q quit]            │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Why

Two reasons:

1. **To work at the byte level.** Assembly is already low level, but it still gives you labels, mnemonics, and tooling. This project goes one step lower: every opcode, jump offset, ELF header field, and data byte is specified explicitly.

2. **To keep the result practical.** The constraint is raw bytes and Linux syscalls, but the output is still meant to be a usable file viewer with scrolling, search, color output, and real file I/O.

## Features

- **File viewing** — open any file and browse its hex representation
- **16-byte rows** — offset column, hex pairs, ASCII sidebar
- **Color coded** — null bytes dim, printable ASCII highlighted, high bytes colored
- **Keyboard navigation** — arrow keys, Page Up/Down, Home/End
- **Go to offset** — jump to any byte position in the file
- **Hex search** — find byte sequences (`/7F454C46` finds ELF headers)
- **Terminal adaptive** — detects terminal size, redraws on resize (`SIGWINCH`)
- **Raw terminal mode** — direct `termios` manipulation via `ioctl` syscalls
- **Zero dependencies** — no libc, no ncurses, no libraries of any kind
- **Tiny** — entire program fits in a few kilobytes

## How It Works

The program is a raw ELF64 executable. It uses a small set of Linux syscalls:

| Syscall | Number | Purpose |
|---------|--------|---------|
| `read` | 0 | Read file contents, keyboard input |
| `write` | 1 | Write formatted output to terminal |
| `open` | 2 | Open target file |
| `close` | 3 | Close file descriptor |
| `ioctl` | 16 | Terminal: get size, set raw mode, restore |
| `exit` | 60 | Clean shutdown |
| `mmap` | 9 | Map file into memory for random access |
| `fstat` | 5 | Get file size |
| `rt_sigaction` | 13 | Handle SIGWINCH for terminal resize |

The TUI is drawn entirely with ANSI escape sequences written to stdout:

- `\x1b[H` — cursor home
- `\x1b[2J` — clear screen
- `\x1b[{row};{col}H` — cursor positioning
- `\x1b[38;5;{n}m` — 256-color foreground
- `\x1b[0m` — reset attributes
- Box-drawing characters (UTF-8 encoded: `┌ ─ ┐ │ └ ┘`)

Keyboard input is read in raw terminal mode (no line buffering, no echo) by manipulating the `termios` struct through `ioctl` syscalls.

## Project Structure

```
TheMachine/
├── README.md              This file
├── ARCHITECTURE.md        ELF layout, memory map, and byte-level documentation
├── BUILD.md               How to construct the binary
├── LICENSE                CC0-1.0 license notice
├── machine-dump.hex       Annotated x86_64 machine-code source in hex
├── build.sh               4-line build script (sed + xxd)
├── machine-dump           The executable (built from .hex)
└── docs/
    ├── elf-header.md      ELF64 header breakdown
    ├── syscalls.md        Syscall interface reference
    ├── tui-rendering.md   ANSI escape sequence strategy
    ├── input-handling.md  Raw terminal mode and key parsing
    └── hex-format.md      Output formatting logic
```

## Building

The source is `machine-dump.hex` — an annotated hex file where every byte is a CPU instruction, ELF header field, or data constant. Comments explain what each byte does. The build step just strips comments and converts hex to binary:

```bash
./build.sh
# or without the script:
sed 's/#.*//' machine-dump.hex | tr -d ' \n\r' | xxd -r -p > machine-dump
chmod +x machine-dump
```

There is no compiler, no assembler, no build system. `build.sh` is four lines of `sed` and `xxd`. The hex file is the source: you edit raw instruction bytes to change the program.

## Running

```bash
# View a file
./machine-dump /usr/bin/ls

# View the program itself
./machine-dump machine-dump

# View a kernel image
./machine-dump /boot/vmlinuz-linux
```

### Controls

| Key | Action |
|-----|--------|
| `↑` / `↓` | Scroll one row (16 bytes) |
| `PgUp` / `PgDn` | Scroll one page |
| `Home` / `End` | Jump to start / end of file |
| `g` | Go to offset (enter hex address) |
| `/` | Search for hex byte sequence |
| `n` | Next search result |
| `q` | Quit |

## Requirements

- x86_64 Linux kernel (any version with ELF support — so, all of them)
- A terminal emulator with ANSI color support (Konsole, xterm, any modern terminal)
- `sed` and `xxd` if you want to rebuild from `machine-dump.hex`

## Repository Language

The source is `machine-dump.hex`, an annotated stream of x86_64 machine-code bytes. There is no `.c` or `.asm` file; the tracked executable is built directly from that hex source.

## License

Released under CC0-1.0. See `LICENSE`.
