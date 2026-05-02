# Linux Syscall Reference

Every interaction between `machine-dump` and the outside world goes through these syscalls. There are no library wrappers — we load registers and execute the `syscall` instruction directly.

## Calling Convention

```
rax = syscall number
rdi = arg1
rsi = arg2
rdx = arg3
r10 = arg4
r8  = arg5
r9  = arg6

syscall          ; trap to kernel

; Return value in rax
; rcx and r11 are clobbered (kernel uses them for return address/flags)
; All other registers preserved
```

## Syscalls Used

### read (0)

```
rax = 0
rdi = fd (0 for stdin)
rsi = buffer pointer
rdx = count
→ rax = bytes read, or negative errno
```

Used for: reading keyboard input in the main loop.

### write (1)

```
rax = 1
rdi = fd (1 for stdout, 2 for stderr)
rsi = buffer pointer
rdx = count
→ rax = bytes written, or negative errno
```

Used for: all screen output. The entire rendered frame is buffered then flushed with one write call.

### open (2)

```
rax = 2
rdi = filename pointer (null-terminated)
rsi = flags (O_RDONLY = 0)
rdx = mode (ignored for O_RDONLY)
→ rax = file descriptor, or negative errno
```

Used for: opening the target file specified on the command line.

### close (3)

```
rax = 3
rdi = fd
→ rax = 0 on success
```

Used for: closing the file on exit.

### fstat (5)

```
rax = 5
rdi = fd
rsi = pointer to stat struct (144 bytes)
→ rax = 0 on success
; File size is at offset 48 in the struct (st_size, 8 bytes)
```

Used for: getting the file size after open, before mmap.

### mmap (9)

```
rax = 9
rdi = addr (0 = kernel chooses)
rsi = length (file size)
rdx = prot (PROT_READ = 1)
r10 = flags (MAP_PRIVATE = 2)
r8  = fd
r9  = offset (0)
→ rax = mapped address, or negative errno
```

Used for: mapping the entire file into memory for random access. This is better than read() for a viewer because we can jump to any offset instantly without seeking.

### munmap (11)

```
rax = 11
rdi = addr (the mmap'd pointer)
rsi = length
→ rax = 0 on success
```

Used for: cleanup on exit.

### rt_sigaction (13)

```
rax = 13
rdi = signum (SIGWINCH = 28)
rsi = pointer to sigaction struct
rdx = pointer to old sigaction (0 = don't save)
r10 = sizeof(sigset_t) = 8
→ rax = 0 on success
```

The `sigaction` struct for our purposes:
```
offset 0:  sa_handler (8 bytes) — pointer to our handler function
offset 8:  sa_flags (8 bytes) — SA_RESTORER (0x04000000)
offset 16: sa_restorer (8 bytes) — pointer to our rt_sigreturn stub
offset 24: sa_mask (8 bytes) — 0 (don't block signals during handler)
```

The `sa_restorer` function just does:
```
mov eax, 15    ; rt_sigreturn
syscall
```

Used for: catching `SIGWINCH` (terminal resize) to update display dimensions.

### ioctl (16)

```
rax = 16
rdi = fd
rsi = request code
rdx = argument (pointer or value)
→ rax = 0 on success
```

Used with three request codes:

**TCGETS (0x5401)** — get terminal attributes
```
rsi = 0x5401
rdx = pointer to termios struct (60 bytes)
```

**TCSETS (0x5402)** — set terminal attributes
```
rsi = 0x5402
rdx = pointer to termios struct
```

**TIOCGWINSZ (0x5413)** — get terminal window size
```
rsi = 0x5413
rdx = pointer to winsize struct:
  offset 0: ws_row (2 bytes)
  offset 2: ws_col (2 bytes)
  offset 4: ws_xpixel (2 bytes, unused)
  offset 6: ws_ypixel (2 bytes, unused)
```

### exit (60)

```
rax = 60
rdi = exit code (0 = success)
; Does not return
```

## Raw Terminal Mode

To read individual keystrokes without waiting for Enter, we switch stdin to raw mode by modifying the `termios` struct:

```
1. TCGETS → save original termios
2. Copy to raw termios
3. Clear bits in c_lflag (offset 12):
   - ECHO   (0x08) — don't echo typed characters
   - ICANON (0x02) — don't buffer until newline
   - ISIG   (0x01) — don't generate signals for Ctrl+C etc.
4. Set c_cc[VMIN] = 1 (offset 23 + 6 = byte 29): read returns after 1 byte
5. Set c_cc[VTIME] = 0 (offset 23 + 5 = byte 28): no timeout
6. TCSETS → apply raw termios
```

On exit (or signal), we restore the original termios so the user's shell isn't broken.

## Error Handling

Syscalls return negative errno values on failure. We check for:
- `open` failure: print "cannot open file" to stderr and exit 1
- `mmap` failure: print "mmap failed" to stderr and exit 1
- `ioctl` failures on TIOCGWINSZ: fall back to 80x24

All other errors (write failures, etc.) are silently ignored — if stdout is broken, there's nothing useful we can do anyway.
