# RISC-V CPU Core Implementation

This is a RISC-V CPU core implementation using Verilog HDL, implementing the R32I instruction set. It is a single cycle processor, with fetch, execute, and memory stages.

## Features

- R32I Instruction Set with system calls
- ELF Loader (It runs C programs compiled with riscv64-elf-gcc)
- Newlib support (Standard C Library, so that functions like printf and putchar work)

## Testing

`iverilog` has been used to simulate the processor. Makefile contains necessary compiling steps for running `test.c`. Make sure `riscv64-elf-gcc`, `riscv64-elf-objdump` and `riscv64-elf-newlib` are installed.

Run

```bash
iverilog -o test main.v
make test.elf.hex
./test
```
