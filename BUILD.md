# Building machine-dump

## Philosophy

There is no compiler. There is no assembler. The source is `machine-dump.hex` — raw x86_64 instruction bytes laid out with comments. The build step strips comments and converts hex to binary. That's it.

## Prerequisites

- `xxd` (part of vim, present on virtually all Linux systems)
- `sed` (POSIX standard)
- Linux x86_64 (to run the result)

## Build

```bash
./build.sh
```

Or without the script:

```bash
sed 's/#.*//' machine-dump.hex | tr -d ' \n\r' | xxd -r -p > machine-dump
chmod +x machine-dump
```

## Verify

```bash
file machine-dump                              # Should say: ELF 64-bit LSB executable
ls -la machine-dump                            # Should be ~3829 bytes
./machine-dump machine-dump                    # View itself
objdump -D -b binary -m i386:x86-64 machine-dump | less  # Disassemble
```

## How the hex source works

`machine-dump.hex` is the annotated source. Every line contains hex bytes followed by a `#` comment:

```
48 31 ff                        # 0146: xor rdi,rdi
be 01 54 00 00                  # 0149: mov esi,0x5401
48 8d 95 00 00 00 00            # 014e: lea rdx,[rbp+0x0]
b8 10 00 00 00                  # 0155: mov eax,0x10
0f 05                           # 015a: syscall
```

Each line is one x86_64 instruction. The comment shows the file offset and what the CPU sees when it decodes those bytes. Labels mark function boundaries and jump targets.

## Modifying

To change the program, you edit `machine-dump.hex` directly. This means:

1. Looking up the x86_64 instruction encoding (Intel SDM Volume 2)
2. Writing the raw opcode bytes
3. **Recalculating every jump offset that crosses your edit point**

The third step is the hard part. Every `jmp`, `je`, `call` etc. contains a relative offset — the signed distance from the end of the instruction to the target. If you add or remove bytes, every jump that crosses that point shifts. A single inserted byte can invalidate dozens of offsets.

The ELF header also contains the file size (`p_filesz` at offset 0x60 and `p_memsz` at offset 0x68). These must be updated after any size change.

## Debugging

```bash
# Disassemble (since there are no section headers, use raw binary mode)
objdump -D -b binary -m i386:x86-64 machine-dump | less

# Trace syscalls
strace ./machine-dump testfile

# Debug with gdb (no symbols, break on virtual addresses)
gdb ./machine-dump
(gdb) break *0x400078
(gdb) run testfile
(gdb) stepi
(gdb) info registers
```

`objdump -D -b binary -m i386:x86-64` shows the decoded instructions, which should match the comments in the hex file.
