module main(input clk);

    parameter MEMORY_LEN = 65536;
    parameter MEMORY_BITS = $clog2(MEMORY_LEN);

    parameter ELF_SIZE = 1048576; // 1 MB

    parameter TERMINATE_PROGRAM_ADDR = 32'hFFFFF000;

    parameter PRINT_ADDR = 32'hFFFFFF00;

    parameter STACK_END = MEMORY_LEN*4 - 1;

    parameter HEAP_START = STACK_END - 16*1024;

    reg [31:0] memory [MEMORY_LEN-1:0];
    reg [31:0] regfile [31:0];

    reg [31:0] heap_break = HEAP_START;

    reg [31:0] pc = 4; // Start at 4 because inst gets updated in the clock 
    reg [31:0] inst;

    wire [6:0] opcode = inst[6:0];

    wire [4:0] i_rs1 = inst[19:15];
    wire [4:0] i_rd = inst[11:7];
    wire [31:0] i_imm = { {20{inst[31]}}, inst[31:20] };
    wire [2:0] i_funct3 = inst[14:12];

    wire [31:0] s_imm = { {20{inst[31]}}, inst[31:25], inst[11:7] };
    wire [4:0] s_rs1 = inst[19:15];
    wire [4:0] s_rs2 = inst[24:20];
    wire [2:0] s_funct3 = inst[14:12];

    wire [4:0] r_rd = inst[11:7];
    wire [4:0] r_rs1 = inst[19:15];
    wire [4:0] r_rs2 = inst[24:20];
    wire [2:0] r_funct3 = inst[14:12];
    wire [9:0] r_funct7 = inst[31:25];
    
    wire [4:0] u_rd = inst[11:7];
    wire [31:0] u_imm = { inst[31:12], 12'b0 };

    wire [4:0] uj_rd = inst[11:7];
    wire [31:0] uj_imm = { {12{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0 };

    wire [31:0] b_imm = { {19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0 };
    wire [2:0] b_funct3 = inst[14:12];
    wire [4:0] b_rs1 = inst[19:15];
    wire [4:0] b_rs2 = inst[24:20];

    reg [31:0] mem_store_data = 32'b0;
    reg [31:0] mem_store_addr_full = 32'b0;
    reg [2:0] mem_store_funct3 = 3'b000;
    reg mem_store_en = 0;

    reg [4:0] mem_load_reg = 5'b00000;
    reg [31:0] mem_load_addr_full = 32'b0;
    reg [2:0] mem_load_funct3 = 3'b000;
    reg mem_load_en = 0;

    reg [31:0] entrypoint;
    reg [31:0] elf_sections_start;
    reg [31:0] elf_text_start = 32'b0;
    reg [31:0] elf_text_size = 32'b0;
    reg [31:0] elf_bss_start = 32'b0;

    reg [15:0] elf_section_count = 16'b0;
    reg [15:0] elf_shstrtab_index = 16'b0;

    reg [31:0] elf_prev_section_start = 32'b0;
    reg [31:0] elf_current_section_start = 32'b0;
    wire [31:0] elf_current_section_type = { elf_data[elf_current_section_start + 8'h04 + 3], elf_data[elf_current_section_start + 8'h04 + 2], elf_data[elf_current_section_start + 8'h04 + 1], elf_data[elf_current_section_start + 8'h04] };
    wire [31:0] elf_current_section_name_offset = { elf_data[elf_current_section_start + 3], elf_data[elf_current_section_start + 2], elf_data[elf_current_section_start + 1], elf_data[elf_current_section_start] };
    wire [31:0] elf_current_section_content_start = { elf_data[elf_current_section_start + 8'h10 + 3], elf_data[elf_current_section_start + 8'h10 + 2], elf_data[elf_current_section_start + 8'h10 + 1], elf_data[elf_current_section_start + 8'h10] };

    reg [31:0] elf_shstrtab_start = 32'b0;

    reg [7:0] elf_data [ELF_SIZE-1:0];
    integer i, j;
    // ELF Parsing
    initial begin

        $readmemh("test.elf.hex", elf_data, 0, ELF_SIZE-1);

        // ELF header
        if (elf_data[0] != 8'h7f || elf_data[1] != 8'h45 || elf_data[2] != 8'h4c || elf_data[3] != 8'h46) begin
            $display("Error: Invalid ELF file.");
            $finish;
        end

        // 32-bit or 64-bit (We want 32-bit)
        if (elf_data[8'h04] != 8'h01) begin
            $display("Error: 64-bit ELF is not supported.");
            $finish;
        end

        // Endianness (We want little-endian)
        if (elf_data[8'h05] != 8'h01) begin
            $display("Error: Big-endian ELF is not supported.");
            $finish;
        end

        // ELF Version (It should always be 1)
        if (elf_data[8'h06] != 8'h01) begin
            $display("Error: Unsupported ELF version.");
            $finish;
        end

        // ABI (We want SystemV)
        if (elf_data[8'h07] != 8'h00) begin
            $display("Error: Unsupported ELF ABI.");
            $finish;
        end

        // Ignore elf_data[8'h08] (ABI version)
        // Ignore elf_data[8'h09:8'h0f] (reserved padding)
        
        // ELF type (We want executable)
        if (elf_data[8'h10] != 8'h02 || elf_data[8'h11] != 8'h00) begin
            $display("Error: Unsupported ELF type.");
            $finish;
        end

        // Target ISA (We want RISC-V)
        if (elf_data[8'h12] != 8'hf3 || elf_data[8'h13] != 8'h00) begin
            $display("Error: Unsupported ELF target ISA.");
            $finish;
        end

        // ELF Version (It should always be 1)
        if (elf_data[8'h14] != 8'h01 || elf_data[8'h15] != 8'h00 || elf_data[8'h16] != 8'h00 || elf_data[8'h17] != 8'h00) begin
            $display("Error: Unsupported ELF version.");
            $finish;
        end

        // Entrypoint address
        entrypoint = {elf_data[8'h1b], elf_data[8'h1a], elf_data[8'h19], elf_data[8'h18]};
        // $display("Entry point: %h", entrypoint);

        elf_sections_start = { elf_data[8'h23], elf_data[8'h22], elf_data[8'h21], elf_data[8'h20] };
        elf_section_count = { elf_data[8'h31], elf_data[8'h30] };
        elf_shstrtab_index = { elf_data[8'h33], elf_data[8'h32] };
        elf_shstrtab_start = { elf_data[elf_sections_start + elf_shstrtab_index*8'h28 + 8'h10 + 3], elf_data[elf_sections_start + elf_shstrtab_index*8'h28 + 8'h10 + 2], elf_data[elf_sections_start + elf_shstrtab_index*8'h28 + 8'h10 + 1], elf_data[elf_sections_start + elf_shstrtab_index*8'h28 + 8'h10] };

        // Skip the first null section
        for (i = 1; i < elf_section_count && elf_bss_start == 0; i = i + 1) begin
            elf_current_section_start = elf_sections_start + i*8'h28;
            if (elf_text_start == 0 && ".text" == {elf_data[elf_shstrtab_start +elf_current_section_name_offset], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 1], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 2], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 3], elf_data[elf_shstrtab_start + elf_current_section_name_offset + 4]}) begin
                elf_text_start = { elf_data[elf_current_section_start + 8'h10 + 3], elf_data[elf_current_section_start + 8'h10 + 2], elf_data[elf_current_section_start + 8'h10 + 1], elf_data[elf_current_section_start + 8'h10] };
            end
            // if (".text" != {elf_data[elf_shstrtab_start +elf_current_section_name_offset], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 1], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 2], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 3], elf_data[elf_shstrtab_start + elf_current_section_name_offset + 4]}) begin
            //     elf_rodata_start = { elf_data[elf_current_section_start + 8'h10 + 3], elf_data[elf_current_section_start + 8'h10 + 2], elf_data[elf_current_section_start + 8'h10 + 1], elf_data[elf_current_section_start + 8'h10] };
            //     elf_rodata_size = { elf_data[elf_current_section_start + 8'h14 + 3], elf_data[elf_current_section_start + 8'h14 + 2], elf_data[elf_current_section_start + 8'h14 + 1], elf_data[elf_current_section_start + 8'h14] };
            // end
            // if (".rodata" == {elf_data[elf_shstrtab_start +elf_current_section_name_offset], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 1], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 2], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 3], elf_data[elf_shstrtab_start + elf_current_section_name_offset + 4], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 5], elf_data[elf_shstrtab_start +elf_current_section_name_offset + 6]}) begin
            //     elf_rodata_start = { elf_data[elf_current_section_start + 8'h10 + 3], elf_data[elf_current_section_start + 8'h10 + 2], elf_data[elf_current_section_start + 8'h10 + 1], elf_data[elf_current_section_start + 8'h10] };
            // end
            if (elf_current_section_type == 32'h08) begin
                elf_bss_start = { elf_data[elf_current_section_start + 8'h10 + 3], elf_data[elf_current_section_start + 8'h10 + 2], elf_data[elf_current_section_start + 8'h10 + 1], elf_data[elf_current_section_start + 8'h10] };
            end
        end

        if (elf_text_start == 32'b0) begin
            $display("Error: ELF .text section not found.");
            $finish;
        end

        for (i = 0; i < MEMORY_LEN; i = i + 1) begin
            memory[i] = 32'b0;
        end

        for (i = 0; i < elf_bss_start - elf_text_start; i = i + 4) begin
            memory[i >> 2] = { elf_data[elf_text_start + i + 3], elf_data[elf_text_start + i + 2], elf_data[elf_text_start + i + 1], elf_data[elf_text_start + i] };
        end

        // Start from _start for newlib
        entrypoint = 0;
        inst = memory[entrypoint >> 2];
        pc = entrypoint + 4;

        for (i = 0; i < 32; i = i + 1) begin
            regfile[i] = 32'b0;
        end
        regfile[1] = TERMINATE_PROGRAM_ADDR; // ra initialization (will be used to terminate the program)
        regfile[2] = MEMORY_LEN*4-1; // sp initialization
        regfile[3] = 0; // gp initialization
    end

    function [31:0] read_register(input [4:0] reg_num);
        begin
            if (reg_num == 5'b00000) read_register = 32'b0;
            // Safe-guard for data hazard
            else if (mem_load_en == 1 && mem_load_reg == reg_num) begin
                // $display("Data hazard | reg: %h | funct3: %h | addr: %h | memory data: %h", reg_num, mem_load_funct3, mem_load_addr_full, memory[mem_load_addr_full >> 2]);
                // We cannot call tasks from functions, ok
                case (mem_load_funct3)
                    3'b000: read_register = read_memory_byte_signextended(mem_load_addr_full); // LB
                    3'b001: read_register = read_memory_hw_signextended(mem_load_addr_full); // LH
                    3'b010: read_register = read_memory_word(mem_load_addr_full); // LW
                    3'b100: read_register = read_memory_byte_zeroextended(mem_load_addr_full); // LBU
                    3'b101: read_register = read_memory_hw_zeroextended(mem_load_addr_full); // LHU
                    default: read_register = 32'b0;
                endcase
                // Initiate memory load now to avoid data hazard
                regfile[mem_load_reg] = read_register;
                mem_load_en = 0;
            end
            else read_register = regfile[reg_num];
        end
    endfunction

    function [63:0] read_register_extended(input [4:0] reg_num, input sign_extended);
        reg [31:0] register;
        begin
            register = read_register(reg_num);
            if (sign_extended) read_register_extended = { {32{register[31]}}, register };
            else read_register_extended = { 32'b0, register };
        end
    endfunction

    function [7:0] read_memory_byte(input [31:0] addr);
        begin
            read_memory_byte = (memory[(addr >> 2) & (MEMORY_LEN-1)] >> (addr[1:0] * 8)) & 8'hFF;
        end
    endfunction

    function [31:0] read_memory_byte_signextended(input [31:0] addr);
        reg [7:0] byte;
        begin
            byte = read_memory_byte(addr);
            read_memory_byte_signextended = { {24{byte[7]}}, byte };
        end
    endfunction

    function [31:0] read_memory_byte_zeroextended(input [31:0] addr);
        reg [7:0] byte;
        begin
            byte = read_memory_byte(addr);
            read_memory_byte_zeroextended = { 24'b0, byte };
        end
    endfunction

    function [15:0] read_memory_hw(input [31:0] addr);
        begin
            read_memory_hw = (memory[(addr >> 2) & (MEMORY_LEN-1)] >> (addr[1] * 16)) & 16'hFFFF;
        end
    endfunction

    function [31:0] read_memory_hw_signextended(input [31:0] addr);
        reg [15:0] hw;
        begin
            hw = read_memory_hw(addr);
            read_memory_hw_signextended = { {16{hw[15]}}, hw };
        end
    endfunction

    function [31:0] read_memory_hw_zeroextended(input [31:0] addr);
        reg [15:0] hw;
        begin
            hw = read_memory_hw(addr);
            read_memory_hw_zeroextended = { 16'b0, hw };
        end
    endfunction

    function [31:0] read_memory_word(input [31:0] addr);
        begin
            read_memory_word = memory[(addr >> 2) & (MEMORY_LEN-1)];
        end
    endfunction

    task invalid_instruction;
        begin
            $display("pc = %h | inst = %h", pc, inst);
            $display("Invalid instruction: %h", inst);
            $finish;
        end
    endtask

    task mem_store;
        begin
            // $display("STORE | addr: %h | data: %h", mem_store_addr_full, mem_store_data);
            case (mem_store_funct3)
                3'b000: begin
                    case (mem_store_addr_full[1:0])
                        2'b00: memory[(mem_store_addr_full >> 2) & (MEMORY_LEN-1)][7:0] <= mem_store_data[7:0];
                        2'b01: memory[(mem_store_addr_full >> 2) & (MEMORY_LEN-1)][15:8] <= mem_store_data[7:0];
                        2'b10: memory[(mem_store_addr_full >> 2) & (MEMORY_LEN-1)][23:16] <= mem_store_data[7:0];
                        2'b11: memory[(mem_store_addr_full >> 2) & (MEMORY_LEN-1)][31:24] <= mem_store_data[7:0];
                    endcase
                end
                3'b001: begin
                    case (mem_store_addr_full[1:0])
                        2'b00: memory[(mem_store_addr_full >> 2) & (MEMORY_LEN-1)][15:0] <= mem_store_data[15:0];
                        2'b10: memory[(mem_store_addr_full >> 2) & (MEMORY_LEN-1)][31:16] <= mem_store_data[15:0];
                    endcase
                end
                3'b010: memory[(mem_store_addr_full >> 2) & (MEMORY_LEN-1)] <= mem_store_data;
            endcase
            mem_store_en <= 0;
        end
    endtask

    task mem_load;
        begin
            case (mem_load_funct3)
                3'b000: regfile[mem_load_reg] <= read_memory_byte_signextended(mem_load_addr_full); // LB
                3'b001: regfile[mem_load_reg] <= read_memory_hw_signextended(mem_load_addr_full); // LH
                3'b010: regfile[mem_load_reg] <= read_memory_word(mem_load_addr_full); // LW
                3'b100: regfile[mem_load_reg] <= read_memory_byte_zeroextended(mem_load_addr_full); // LBU
                3'b101: regfile[mem_load_reg] <= read_memory_hw_zeroextended(mem_load_addr_full); // LHU
            endcase
            mem_load_en <= 0;
        end
    endtask

    task system_call;
        begin
            case (read_register(17)) // call opcode is stored in a7, parameter is stored in a0..a2
                80: begin // SYS_fstat
                end
                214: begin // SYS_brk
                    // TODO: Heap overflow
                    if (read_register(10) == 0) regfile[10] <= heap_break;
                    else heap_break <= read_register(10);
                end
                57: begin // SYS_close
                end
                93: begin // SYS_exit
                    exit_program;
                end
                64: begin // SYS_write
                    case (read_register(10))
                        1: begin // stdout
                            for (i = 0; i < read_register(12); i = i + 1) begin
                                $write("%c", read_memory_byte_zeroextended(read_register(11) + i));
                            end
                            regfile[10] <= read_register(12); // return number of bytes written
                        end
                    endcase
                end
            endcase
        end
    endtask

    task exit_program;
        begin
            $write("\n\nProgram exited with code %0d\n", read_register(10));
            $finish;
        end
    endtask

    always @(posedge clk) begin
        // $display("Clock");        
        
        // These should be able to be overwritten
        inst <= memory[pc >> 2];
        pc <= pc + 4;

        // #1;
        // $display("pc = %h | inst = %h", pc, inst);
        // $display("%h", memory[16'h040c >> 2]);
        // $display("s0: %h", regfile[8]);
        // $display("s1: %h", regfile[9]);
        // $display("s7: %h", regfile[23]);
        // $display("a0: %h", regfile[10]);
        // $display("a1: %h", regfile[11]);
        // $display("a3: %h", regfile[13]);
        // $display("ra: %h", regfile[1]);
        // $display("sp: %h", regfile[2]);

        // We are putting these before decode and execute, since the order doesn't matter in
        // the clock cycle, but we want to be able to overwrite mem_load_en and mem_store_en if
        // the current instruction is a load or store (otherwise, consecutive stores don't work).
        // Memory load
        if (mem_load_en) begin
            mem_load;
        end

        // Memory store
        if (mem_store_en) begin
            mem_store;
        end

        // Decode and execute
        case(opcode)
            7'b0000011: begin
                // LOAD (I-type)
                // $display("Initiating load | addr: %h | register: %h", i_imm + read_register(i_rs1), i_rd);
                case (i_funct3)
                    3'b000, // LB
                    3'b001, // LH
                    3'b010, // LW
                    3'b100, // LBU
                    3'b101: // LHU
                        begin
                            mem_load_addr_full <= i_imm + read_register(i_rs1);
                            mem_load_reg <= i_rd;
                            mem_load_funct3 <= i_funct3;
                            mem_load_en <= 1;
                        end
                    default: begin 
                        invalid_instruction;
                    end
                endcase
            end
            7'b0100011: begin
                // STORE (S-type)
                // $display("Initiating store | addr: %h | data: %h", s_imm + read_register(s_rs1), read_register(s_rs2));
                case (s_imm + read_register(s_rs1))
                    // PRINT_ADDR: begin
                    //     $write("%h", read_register(s_rs2));
                    // end
                    default: begin
                        case (s_funct3)
                            3'b000, // SB
                            3'b001, // SH
                            3'b010: // SW
                                begin
                                    mem_store_addr_full <= s_imm + read_register(s_rs1);
                                    mem_store_data <= read_register(s_rs2);
                                    mem_store_funct3 <= s_funct3;
                                    mem_store_en <= 1;
                                end
                            default: begin 
                                invalid_instruction;
                            end
                        endcase
                    end
                endcase
            end
            7'b0110111: begin
                // LUI (U-type)
                regfile[u_rd] <= u_imm;
            end
            7'b0010111: begin
                // AUIPC (U-type)
                regfile[u_rd] <= pc + u_imm - 4;
            end
            7'b0010011: begin
                // Immediate ALU (I-type)
                case (i_funct3)
                    3'b000: begin
                        regfile[i_rd] <= read_register(i_rs1) + i_imm; // ADDI
                    end
                    3'b010: regfile[i_rd] <= $signed(read_register(i_rs1)) < $signed(i_imm) ? 32'd1 : 32'd0; // SLTI
                    3'b011: regfile[i_rd] <= read_register(i_rs1) < i_imm ? 32'd1 : 32'd0; // SLTIU
                    3'b100: regfile[i_rd] <= read_register(i_rs1) ^ i_imm; // XORI
                    3'b110: regfile[i_rd] <= read_register(i_rs1) | i_imm; // ORI
                    3'b111: regfile[i_rd] <= read_register(i_rs1) & i_imm; // ANDI
                    3'b001: regfile[i_rd] <= read_register(i_rs1) << i_imm[4:0]; // SLLI
                    3'b101: begin 
                        case (i_imm[11:5])
                            7'b0000000: regfile[i_rd] <= read_register(i_rs1) >> i_imm[4:0]; // SRLI
                            7'b0100000: regfile[i_rd] <= $signed(read_register(i_rs1)) >>> i_imm[4:0]; // SRAI
                        endcase
                    end
                endcase
            end
            7'b0110011: begin
                // ALU (R-type)
                case (r_funct7)
                    7'b0000001: begin // MULDIV
                        case (r_funct3)
                            3'b000: begin // MUL
                                regfile[r_rd] <= (read_register_extended(r_rs1, 0) * read_register_extended(r_rs2, 0));
                            end
                            3'b001: begin // MULH
                                regfile[r_rd] <= ($signed(read_register_extended(r_rs1, 1)) * $signed(read_register_extended(r_rs2, 1))) >> 32;
                            end
                            3'b010: begin // MULHSU
                                regfile[r_rd] <= ($signed(read_register_extended(r_rs1, 1)) * read_register_extended(r_rs2, 0)) >> 32;
                            end
                            3'b011: begin // MULHU
                                regfile[r_rd] <= (read_register_extended(r_rs1, 0) * read_register_extended(r_rs2, 0)) >> 32;
                            end
                            3'b100: begin // DIV
                                if (read_register(r_rs2) == 32'b0) regfile[r_rd] <= 32'b1;
                                else if (read_register(r_rs1) == (1 << 31) && read_register(r_rs2) == -1) regfile[r_rd] <= (1 << 31);
                                else regfile[r_rd] <= $signed(read_register_extended(r_rs1, 1)) / $signed(read_register_extended(r_rs2, 1));
                            end
                            3'b101: begin // DIVU
                                if (read_register(r_rs2) == 32'b0) regfile[r_rd] <= 32'b1;
                                else regfile[r_rd] <= read_register_extended(r_rs1, 0) / read_register_extended(r_rs2, 0);
                            end
                            3'b110: begin // REM
                                if (read_register(r_rs2) == 32'b0) regfile[r_rd] <= read_register(r_rs1);
                                else if (read_register(r_rs1) == (1 << 31) && read_register(r_rs2) == -1) regfile[r_rd] <= 0;
                                else regfile[r_rd] <= $signed(read_register_extended(r_rs1, 1)) % $signed(read_register_extended (r_rs2, 1));
                            end
                            3'b111: begin // REMU
                                if (read_register(r_rs2) == 32'b0) regfile[r_rd] <= read_register(r_rs1);
                                else regfile[r_rd] <= read_register_extended(r_rs1, 0) % read_register_extended(r_rs2, 0);
                            end
                        endcase
                    end
                    default: begin
                        case (r_funct3)
                            3'b000: begin
                                case (r_funct7)
                                    7'b0000000: regfile[r_rd] <= read_register(r_rs1) + read_register(r_rs2); // ADD
                                    7'b0100000: regfile[r_rd] <= read_register(r_rs1) - read_register(r_rs2); // SUB
                                endcase
                            end
                            3'b010: regfile[r_rd] <= $signed(read_register(r_rs1)) < $signed(read_register(r_rs2)) ? 32'd1 : 32'd0; // SLT
                            3'b011: regfile[r_rd] <= read_register(r_rs1) < read_register(r_rs2) ? 32'd1 : 32'd0; // SLTU
                            3'b100: regfile[r_rd] <= read_register(r_rs1) ^ read_register(r_rs2); // XOR
                            3'b110: regfile[r_rd] <= read_register(r_rs1) | read_register(r_rs2); // OR
                            3'b111: regfile[r_rd] <= read_register(r_rs1) & read_register(r_rs2); // AND
                            3'b001: regfile[r_rd] <= read_register(r_rs1) << (read_register(r_rs2) & 5'b11111); // SLL
                            3'b101: begin 
                                case (r_funct7)
                                    7'b0000000: regfile[r_rd] <= read_register(r_rs1) >> (read_register(r_rs2) & 5'b11111); // SRL
                                    7'b0100000: regfile[r_rd] <= $signed(read_register(r_rs1)) >>> (read_register(r_rs2) & 5'b11111); // SRA
                                endcase
                            end
                        endcase
                    end
                endcase
            end
            7'b1100011: begin
                // BRANCH (SB-type)
                // $display("Branch test: comparing %h and %h\nTrying to go to %h", regfile[b_rs1], regfile[b_rs2], pc + b_imm);
                case (b_funct3)
                    3'b000: begin // BEQ
                        if (read_register(b_rs1) == read_register(b_rs2)) begin
                            inst <= memory[(pc + b_imm -4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                    3'b001: begin // BNE
                        if (read_register(b_rs1) != read_register(b_rs2)) begin
                            inst <= memory[(pc + b_imm - 4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                    3'b100: begin // BLT
                        if ($signed(read_register(b_rs1)) < $signed(read_register(b_rs2))) begin
                            inst <= memory[(pc + b_imm - 4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                    3'b101: begin // BGE
                        if ($signed(read_register(b_rs1)) >= $signed(read_register(b_rs2))) begin
                            inst <= memory[(pc + b_imm - 4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                    3'b110: begin // BLTU
                        if (read_register(b_rs1) < read_register(b_rs2)) begin
                            inst <= memory[(pc + b_imm - 4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                    3'b111: begin // BGEU
                        if (read_register(b_rs1) >= read_register(b_rs2)) begin
                            inst <= memory[(pc + b_imm - 4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                endcase
            end
            7'b1101111: begin
                // JAL (UJ-type)
                // $display("JAL: Trying to go to %h, and will return to %h", pc + uj_imm, pc);
                if ((pc-4 + uj_imm) == TERMINATE_PROGRAM_ADDR) begin
                    exit_program;
                end
                regfile[uj_rd] <= pc; // This is the next address since inst would be assigned to memory[pc >> 2] in this clock cycle
                // Reading memory in-place since it must be followed immediately
                inst <= memory[(pc-4 + uj_imm) >> 2];
                pc <= (pc + uj_imm);
            end
            7'b1100111: begin
                // JALR (I-type)
                // $display("JALR: Trying to go to %h, and will return to %h", read_register(i_rs1) + i_imm, pc);
                if (i_funct3 == 3'b000) begin
                    if (((read_register(i_rs1) + i_imm) & ~32'h1) == TERMINATE_PROGRAM_ADDR) begin
                        exit_program;
                    end

                    regfile[i_rd] <= pc; // This is the next address since inst would be assigned to memory[pc >> 2] in this clock cycle
                    // Reading memory in-place since it must be followed immediately
                    inst <= memory[((read_register(i_rs1) + i_imm) & ~32'h1) >> 2];
                    pc <= ((read_register(i_rs1) + i_imm)  & ~32'h1) + 4;
                end
            end
            7'b1110011: begin
                // SYSTEM (Special type)
                // $display("SYSCALL | %d %d %d %d", read_register(17), read_register(10), read_register(11), read_register(12));
                if (inst == 32'h00000073) begin // ECALL
                    system_call;
                end
            end
            default: begin
                invalid_instruction;
            end
        endcase

        // This should overwrite any assignment to regfile[0]
        regfile[0] <= 32'b0;
    end

endmodule

module test;

    reg clk;

    main main_inst(.clk(clk));

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        #1000;
        // $finish;
    end
    
endmodule