# RISC-V CPU Core Implementation

This is a RISC-V CPU core implementation using Verilog HDL, implementing the R32IM instruction set. It is 3-stage pipelined with hazard detection, with fetch, execute, and memory stages.

## Features

- R32IM Instruction Set with system calls
- 3-stage pipeline: Fetch, Decode/Execute, Memory
- Hazard detection for pipeline stages
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
