# ELF64 Header Reference

The Executable and Linkable Format is how Linux knows what to do with the binary. This project specifies a minimal ELF layout: 64 bytes for the ELF header, 56 bytes for one program header.

## Why Minimal

A typical ELF binary has section headers, a string table, symbol tables, dynamic linking info, and more. We need none of it. The kernel only requires:

1. A valid ELF header identifying the file
2. At least one `PT_LOAD` program header telling it what to map into memory

Section headers are optional — they're for tools like `objdump` and `gdb`, not the kernel. We omit them entirely. The kernel reads our single program header, maps the file into memory at `0x400000`, and jumps to the entry point. That's it.

## ELF Header (bytes 0x00 – 0x3F)

```
Offset  Size  Value               Meaning
──────  ────  ──────────────────  ──────────────────────────────────
0x00    4     7F 45 4C 46         Magic number: \x7fELF
0x04    1     02                  EI_CLASS: ELFCLASS64 (64-bit)
0x05    1     01                  EI_DATA: ELFDATA2LSB (little-endian)
0x06    1     01                  EI_VERSION: EV_CURRENT
0x07    1     00                  EI_OSABI: ELFOSABI_NONE (System V)
0x08    8     00 00 00 00         EI_ABIVERSION + padding
              00 00 00 00
0x10    2     02 00               e_type: ET_EXEC (static executable)
0x12    2     3E 00               e_machine: EM_X86_64
0x14    4     01 00 00 00         e_version: EV_CURRENT
0x18    8     (entry point)       e_entry: virtual address of _start
0x20    8     40 00 00 00         e_phoff: program header offset (64)
              00 00 00 00
0x28    8     00 00 00 00         e_shoff: 0 (no section headers)
              00 00 00 00
0x30    4     00 00 00 00         e_flags: 0
0x34    2     40 00               e_ehsize: 64 (ELF header size)
0x36    2     38 00               e_phentsize: 56 (program header entry size)
0x38    2     01 00               e_phnum: 1 (one program header)
0x3A    2     00 00               e_shentsize: 0
0x3C    2     00 00               e_shnum: 0
0x3E    2     00 00               e_shstrndx: 0
```

## Program Header (bytes 0x40 – 0x77)

```
Offset  Size  Value               Meaning
──────  ────  ──────────────────  ──────────────────────────────────
0x40    4     01 00 00 00         p_type: PT_LOAD
0x44    4     07 00 00 00         p_flags: PF_R | PF_W | PF_X (rwx)
0x48    8     00 00 00 00         p_offset: 0 (load from file start)
              00 00 00 00
0x50    8     00 00 40 00         p_vaddr: 0x400000
              00 00 00 00
0x58    8     00 00 40 00         p_paddr: 0x400000 (same)
              00 00 00 00
0x60    8     (file size)         p_filesz: total bytes in file
0x68    8     (mem size)          p_memsz: file + BSS (zeroed by kernel)
0x70    8     00 00 20 00         p_align: 0x200000
              00 00 00 00
```

## Key Decisions

**Single RWX segment.** Normally you'd separate code (rx) and data (rw) into different segments. We use one RWX segment because:
- It keeps the program header count at 1
- We need writable data (buffers) near our code for short addressing
- The tradeoff is acceptable for this local, single-purpose binary

**Static executable.** `ET_EXEC` with a fixed load address (`0x400000`). No PIE, no ASLR, no dynamic linker. The kernel maps us and jumps — no `ld-linux.so` involved.

**No section headers.** The kernel ignores them for execution. Tools like `objdump` will still work (they fall back to program headers) but `readelf -S` will show nothing. This is valid per the ELF spec.

**Entry at 0x400078.** Code starts immediately after the program header (byte 120 in the file). No alignment padding — we pack everything tight.

**BSS via p_memsz > p_filesz.** The kernel zeros memory between `p_filesz` and `p_memsz`, giving us uninitialized storage (buffers, state variables) without bloating the file. This is standard ELF BSS behavior.
