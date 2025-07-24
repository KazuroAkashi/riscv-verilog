CC = riscv64-elf-gcc
OBJDUMP = riscv64-elf-objdump
OBJCOPY = riscv64-elf-objcopy

CFLAGS = -march=rv32i -mabi=ilp32 -nostdlib -T link.ld

MEMORY_SIZE = 4096

OBJCOPYFLAGS = -O binary -j .text --pad-to=$(MEMORY_SIZE)

%.elf: %.c
	@echo "Compiling $< to $@..."
	$(CC) $(CFLAGS) $< -o $@ -lgcc
	$(OBJDUMP) -d $@ -M no-aliases

%.bin: %.elf
	@echo "Converting $< to $@..."
	$(OBJCOPY) $(OBJCOPYFLAGS) $< $@

%.hex: %.bin
	@echo "Converting $< to $@..."
	@hexdump -v -e '1/4 "%08x " "\n"' $< > $@
	@rm -f $*.bin $*.elf