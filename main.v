module main(input clk);

    reg [31:0] memory [31:0];
    reg [31:0] regfile [31:0];

    reg [6:0] pc = 0;
    reg [6:0] pc_next = 0;
    reg [31:0] inst;

    wire [6:0] opcode = inst[6:0];

    wire [4:0] i_rs1 = inst[19:15];
    wire [4:0] i_rd = inst[11:7];
    wire [31:0] i_imm = { {20{inst[31]}}, inst[31:20] };
    wire [2:0] i_funct3 = inst[14:12];
    wire [31:0] i_mem_addr_full = (i_imm + regfile[i_rs1]);
    wire [4:0] i_mem_addr = (i_mem_addr_full >> 2) & 5'b11111;
    wire [7:0] i_mem_byte = (memory[i_mem_addr] >> (i_mem_addr_full[1:0] * 8)) & 8'hFF;
    wire [15:0] i_mem_hw = (memory[i_mem_addr] >> (i_mem_addr_full[1] * 16)) & 16'hFFFF;

    wire [31:0] s_imm = { {20{inst[31]}}, inst[31:25], inst[11:7] };
    wire [4:0] s_rs1 = inst[19:15];
    wire [4:0] s_rs2 = inst[24:20];
    wire [2:0] s_funct3 = inst[14:12];

    wire [4:0] r_rd = inst[11:7];
    wire [4:0] r_rs1 = inst[19:15];
    wire [4:0] r_rs2 = inst[24:20];
    wire [2:0] r_funct3 = inst[14:12];
    wire [9:0] r_funct7 = inst[31:25];

    initial $readmemh("instructions.hex", memory, 31, 0);
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            regfile[i] = 32'b0;
        end
    end

    always @(posedge clk) begin
        $display("Clock");
        pc_next <= pc + 4;
        inst <= memory[pc >> 2];
        
        #1;
        $display("pc = %h | inst = %h", pc, inst);

        // Decoder
        case(opcode)
            7'b0000011: begin
                // LOAD (I-type)
                case (i_funct3)
                    3'b000: regfile[i_rd] <= { {24{i_mem_byte[7]}}, i_mem_byte };
                    3'b001: regfile[i_rd] <= { {16{i_mem_hw[15]}}, i_mem_hw };
                    3'b010: regfile[i_rd] <= memory[i_mem_addr];
                endcase
            end
            7'b0100011: begin
                // STORE (S-type)
            end
        endcase

        #1;
        $display("x1 = %h", regfile[1]);

        regfile[0] <= 32'b0;
        pc <= pc_next;
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
        #500;
        $finish;
    end
    
endmodule