module main(input clk);

    parameter MEMORY_LEN = 1024;
    parameter MEMORY_BITS = $clog2(MEMORY_LEN);

    reg [31:0] memory [MEMORY_LEN-1:0];
    reg [31:0] regfile [31:0];

    reg [31:0] pc = 4; // Start at 4 because inst gets updated in the clock 
    reg [31:0] inst;

    wire [6:0] opcode = inst[6:0];

    wire [4:0] i_rs1 = inst[19:15];
    wire [4:0] i_rd = inst[11:7];
    wire [31:0] i_imm = { {20{inst[31]}}, inst[31:20] };
    wire [2:0] i_funct3 = inst[14:12];
    wire [31:0] i_mem_addr_full = (i_imm + regfile[i_rs1]);
    wire [MEMORY_BITS-1:0] i_mem_addr = (i_mem_addr_full >> 2) & (MEMORY_LEN-1);
    wire [7:0] i_mem_byte = (memory[i_mem_addr] >> (i_mem_addr_full[1:0] * 8)) & 8'hFF;
    wire [15:0] i_mem_hw = (memory[i_mem_addr] >> (i_mem_addr_full[1] * 16)) & 16'hFFFF;

    wire [31:0] s_imm = { {20{inst[31]}}, inst[31:25], inst[11:7] };
    wire [31:0] s_imm_u = { {20{1'b0}}, inst[31:25], inst[11:7] };
    wire [4:0] s_rs1 = inst[19:15];
    wire [4:0] s_rs2 = inst[24:20];
    wire [2:0] s_funct3 = inst[14:12];
    wire [31:0] s_mem_addr_full = (s_imm + regfile[s_rs1]);
    wire [MEMORY_BITS-1:0] s_mem_addr = (s_mem_addr_full >> 2) & (MEMORY_LEN-1);
    wire [31:0] s_rs2_data = regfile[s_rs2];
    wire [7:0] s_rs2_data_byte = s_rs2_data[7:0];
    wire [15:0] s_rs2_data_hw = s_rs2_data[15:0];

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

    reg [31:0] entrypoint;
    reg [31:0] elf_sections_start;
    reg [31:0] elf_text_start = 32'b0;
    reg [31:0] elf_text_size = 32'b0;
    reg [31:0] elf_rodata_start = 32'b0;
    reg [31:0] elf_rodata_size = 32'b0;

    reg [7:0] elf_data [65535:0];
    integer i;
    initial begin

        $readmemh("test.elf.hex", elf_data, 0, 65535);

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
        for (i = 0; i < 16 && (elf_text_start == 32'b0 || elf_rodata_start == 32'b0); i = i + 1) begin
            if ({elf_data[elf_sections_start+8'h28*i+4+3], elf_data[elf_sections_start+8'h28*i+4+2], elf_data[elf_sections_start+8'h28*i+4+1], elf_data[elf_sections_start+8'h28*i+4]} == 8'h01) begin
                if ({elf_data[elf_sections_start+8'h28*i+8+3], elf_data[elf_sections_start+8'h28*i+8+2], elf_data[elf_sections_start+8'h28*i+8+1], elf_data[elf_sections_start+8'h28*i+8]} == 8'h06) begin
                    elf_text_start = {elf_data[elf_sections_start+8'h28*i+16+3], elf_data[elf_sections_start+8'h28*i+16+2], elf_data[elf_sections_start+8'h28*i+16+1], elf_data[elf_sections_start+8'h28*i+16]};
                    elf_text_size = {elf_data[elf_sections_start+8'h28*i+20+3], elf_data[elf_sections_start+8'h28*i+20+2], elf_data[elf_sections_start+8'h28*i+20+1], elf_data[elf_sections_start+8'h28*i+20]};
                end
            end
            // Assume .rodata follows right after .text for now
            if (elf_text_start != 0) begin
                elf_rodata_start = {elf_data[elf_sections_start+8'h28*i+16+3], elf_data[elf_sections_start+8'h28*i+16+2], elf_data[elf_sections_start+8'h28*i+16+1], elf_data[elf_sections_start+8'h28*i+16]};
                elf_rodata_size = {elf_data[elf_sections_start+8'h28*i+20+3], elf_data[elf_sections_start+8'h28*i+20+2], elf_data[elf_sections_start+8'h28*i+20+1], elf_data[elf_sections_start+8'h28*i+20]};
            end
        end

        if (elf_text_start == 32'b0) begin
            $display("Error: ELF .text section not found.");
            $finish;
        end

        for (i = 0; i < MEMORY_LEN; i = i + 1) begin
            memory[i] = 32'b0;
        end
        for (i = 0; i < elf_text_size; i = i + 4) begin
            memory[i >> 2] = { elf_data[elf_text_start + i + 3], elf_data[elf_text_start + i + 2], elf_data[elf_text_start + i + 1], elf_data[elf_text_start + i] };
        end
        for (; i < elf_text_size + elf_rodata_size; i = i + 4) begin
            memory[i >> 2] = { elf_data[elf_rodata_start + i + 3], elf_data[elf_rodata_start + i + 2], elf_data[elf_rodata_start + i + 1], elf_data[elf_rodata_start + i] };
        end


        inst = memory[entrypoint >> 2];
        pc = entrypoint + 4;

        for (i = 0; i < 32; i = i + 1) begin
            regfile[i] = 32'b0;
        end
        regfile[2] = MEMORY_LEN*4-1; // sp initialization
        regfile[3] = MEMORY_LEN*4/2-1; // gp initialization
    end

    always @(posedge clk) begin
        // $display("Clock");        
        
        // These should be able to be overwritten
        inst <= memory[pc >> 2];
        pc <= pc + 4;

        // #1;
        // $display("pc = %h | inst = %h", pc, inst);
        // $display("%h", regfile[15]);

        // Decoder
        case(opcode)
            7'b0000011: begin
                // LOAD (I-type)
                // $display("Loading %h from %h (%h)", memory[i_mem_addr], i_mem_addr_full, i_mem_addr);
                if (i_rd != 5'b00000) begin
                    case (i_funct3)
                        3'b000: regfile[i_rd] <= { {24{i_mem_byte[7]}}, i_mem_byte }; // LB 
                        3'b001: regfile[i_rd] <= { {16{i_mem_hw[15]}}, i_mem_hw }; // LH
                        3'b010: regfile[i_rd] <= memory[i_mem_addr]; // LW
                        3'b100: regfile[i_rd] <= { {24{1'b0}}, i_mem_byte }; // LBU
                        3'b101: regfile[i_rd] <= { {16{1'b0}}, i_mem_hw }; // LHU
                    endcase
                end
            end
            7'b0100011: begin
                // STORE (S-type)
                // $display("Storing %h to %h (%h)", s_rs2_data, s_mem_addr_full, s_mem_addr);
                case (s_mem_addr_full)
                    32'hFFFF0000: $write("%c", s_rs2_data[7:0]);  // Print a character
                    32'hABCD0000: begin 
                        // Exit the program
                        $write("\n\nProgram exited with code %0d\n", s_rs2_data);
                        $finish;
                    end
                    default: begin
                        case (s_funct3)
                            3'b000: begin // SB
                                case (s_mem_addr_full[1:0]) 
                                    2'b00: memory[s_mem_addr][7:0] <= s_rs2_data_byte;
                                    2'b01: memory[s_mem_addr][15:8] <= s_rs2_data_byte;
                                    2'b10: memory[s_mem_addr][23:16] <= s_rs2_data_byte;
                                    2'b11: memory[s_mem_addr][31:24] <= s_rs2_data_byte;
                                endcase
                            end
                            3'b001: begin // SH
                                case (s_mem_addr_full[1:0]) 
                                    2'b00: memory[s_mem_addr][15:0] <= s_rs2_data_hw;
                                    2'b10: memory[s_mem_addr][31:16] <= s_rs2_data_hw;
                                endcase
                            end
                            3'b010: memory[s_mem_addr] <= s_rs2_data; // SW
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
                regfile[u_rd] <= pc + u_imm;
            end
            7'b0010011: begin
                // Immediate ALU (I-type)
                if (i_rd != 5'b00000) begin
                    case (i_funct3)
                        3'b000: regfile[i_rd] <= regfile[i_rs1] + i_imm; // ADDI
                        3'b010: regfile[i_rd] <= $signed(regfile[i_rs1]) < $signed(i_imm) ? 32'd1 : 32'd0; // SLTI
                        3'b011: regfile[i_rd] <= regfile[i_rs1] < i_imm ? 32'd1 : 32'd0; // SLTIU
                        3'b100: regfile[i_rd] <= regfile[i_rs1] ^ i_imm; // XORI
                        3'b110: regfile[i_rd] <= regfile[i_rs1] | i_imm; // ORI
                        3'b111: regfile[i_rd] <= regfile[i_rs1] & i_imm; // ANDI
                        3'b001: regfile[i_rd] <= regfile[i_rs1] << i_imm[4:0]; // SLLI
                        3'b101: begin 
                            case (i_imm[11:5])
                                7'b0000000: regfile[i_rd] <= regfile[i_rs1] >> i_imm[4:0]; // SRLI
                                7'b0100000: regfile[i_rd] <= $signed(regfile[i_rs1]) >>> i_imm[4:0]; // SRAI
                            endcase
                        end
                    endcase
                end
            end
            7'b0110011: begin
                // ALU (R-type)
                if (r_rd != 5'b00000) begin
                    case (r_funct3)
                        3'b000: begin
                            case (r_funct7)
                                7'b0000000: regfile[r_rd] <= regfile[r_rs1] + regfile[r_rs2]; // ADD
                                7'b0100000: regfile[r_rd] <= regfile[r_rs1] - regfile[r_rs2]; // SUB
                            endcase
                        end
                        3'b010: regfile[r_rd] <= $signed(regfile[r_rs1]) < $signed(regfile[r_rs2]) ? 32'd1 : 32'd0; // SLT
                        3'b011: regfile[r_rd] <= regfile[r_rs1] < regfile[r_rs2] ? 32'd1 : 32'd0; // SLTU
                        3'b100: regfile[r_rd] <= regfile[r_rs1] ^ regfile[r_rs2]; // XOR
                        3'b110: regfile[r_rd] <= regfile[r_rs1] | regfile[r_rs2]; // OR
                        3'b111: regfile[r_rd] <= regfile[r_rs1] & regfile[r_rs2]; // AND
                        3'b001: regfile[r_rd] <= regfile[r_rs1] << regfile[r_rs2][4:0]; // SLL
                        3'b101: begin 
                            case (r_funct7)
                                7'b0000000: regfile[r_rd] <= regfile[r_rs1] >> regfile[r_rs2][4:0]; // SRL
                                7'b0100000: regfile[r_rd] <= $signed(regfile[r_rs1]) >>> regfile[r_rs2][4:0]; // SRA
                            endcase
                        end
                    endcase
                end
            end
            7'b1100011: begin
                // BRANCH (SB-type)
                // $display("Branch test: comparing %h and %h\nTrying to go to %h", regfile[b_rs1], regfile[b_rs2], pc + b_imm);
                case (b_funct3)
                    3'b000: begin // BEQ
                        if (regfile[b_rs1] == regfile[b_rs2]) begin
                            inst <= memory[(pc + b_imm -4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                    3'b001: begin // BNE
                        if (regfile[b_rs1] != regfile[b_rs2]) begin
                            inst <= memory[(pc + b_imm - 4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                    3'b100: begin // BLT
                        if ($signed(regfile[b_rs1]) < $signed(regfile[b_rs2])) begin
                            inst <= memory[(pc + b_imm - 4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                    3'b101: begin // BGE
                        if ($signed(regfile[b_rs1]) >= $signed(regfile[b_rs2])) begin
                            inst <= memory[(pc + b_imm - 4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                    3'b110: begin // BLTU
                        if (regfile[b_rs1] < regfile[b_rs2]) begin
                            inst <= memory[(pc + b_imm - 4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                    3'b111: begin // BGEU
                        if (regfile[b_rs1] >= regfile[b_rs2]) begin
                            inst <= memory[(pc + b_imm - 4) >> 2];
                            pc <= (pc + b_imm);
                        end
                    end
                endcase
            end
            7'b1101111: begin
                // JAL (UJ-type)
                // $display("JAL: Trying to go to %h, and will return to %h", pc + uj_imm, pc);
                if (uj_rd != 5'b00000) begin
                    regfile[uj_rd] <= pc; // This is the next address since inst would be assigned to memory[pc >> 2] in this clock cycle
                    inst <= memory[(pc-4 + uj_imm) >> 2];
                    pc <= (pc + uj_imm);
                end
            end
            7'b1100111: begin
                // JALR (I-type)
                // $display("JALR: Trying to go to %h, and will return to %h", regfile[i_rs1] + i_imm, pc);
                if (i_funct3 == 3'b000) begin
                    if (i_rd == 5'b00000) regfile[i_rd] <= pc; // This is the next address since inst would be assigned to memory[pc >> 2] in this clock cycle
                    inst <= memory[((regfile[i_rs1] + i_imm) & ~32'h1) >> 2];
                    pc <= ((regfile[i_rs1] + i_imm)  & ~32'h1) + 4;
                end
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