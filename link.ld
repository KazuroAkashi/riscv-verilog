ENTRY(main)

SECTIONS {
    .text : { 
        *(.text*)
    }
    .rodata : { *(.rodata) }
}
