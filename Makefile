CC = riscv64-elf-gcc
OBJDUMP = riscv64-elf-objdump
OBJCOPY = riscv64-elf-objcopy

CFLAGS = -march=rv32i -mabi=ilp32 -T link.ld

# MEMORY_SIZE = 4096
ELF_SIZE = 1048576 # 1 MB (Must match with the definiton inside main.v)

# OBJCOPYFLAGS = -O binary -j .text --pad-to=$(MEMORY_SIZE)

%.elf: %.c
	@echo "Compiling $< to $@..."
	$(CC) $(CFLAGS) $< -o $@ -lc
	$(OBJDUMP) -d $@ -M no-aliases

# %.bin: %.elf
# 	@echo "Converting $< to $@..."
# 	$(OBJCOPY) $(OBJCOPYFLAGS) $< $@

# %.hex: %.bin
# 	@echo "Converting $< to $@..."
# 	@hexdump -v -e '1/4 "%08x " "\n"' $< > $@
# 	@rm -f $*.bin $*.elf

%.elf.hex: %.elf
	@echo "Converting $< to $@..."
	@dd if=/dev/zero of=$*.bin ibs=1 count=$(ELF_SIZE)
	@dd if=$< of=$*.bin conv=notrunc
	@hexdump -v -e '1/1 "%02x " "\n"' $*.bin > $@
	@rm -f $*.bin $*.elf