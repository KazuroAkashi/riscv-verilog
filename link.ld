ENTRY(main)

PROVIDE(__global_pointer$ = 0);

SECTIONS {
    .text : { 
        *(.text)
    }
    .rodata : { *(.rodata) }
    .data : { *(.data) }
    .bss : { 
        __bss_start = .;
        *(.bss)
        *(COMMON)
        _end = .;
    }
}
