module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_op,
    output reg  [31:0] result,
    output wire        zero
);
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;

    always @(*) begin
        case (alu_op)
            ALU_ADD:  result = a + b;
            ALU_SUB:  result = a - b;
            ALU_AND:  result = a & b;
            ALU_OR:   result = a | b;
            ALU_XOR:  result = a ^ b;
            ALU_SLL:  result = a << b[4:0];
            ALU_SRL:  result = a >> b[4:0];
            ALU_SRA:  result = $signed(a) >>> b[4:0];
            ALU_SLT:  result = ($signed(a) < $signed(b)) ? 32'b1 : 32'b0;
            ALU_SLTU: result = (a < b) ? 32'b1 : 32'b0;
            default:  result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);
endmodule


module data_memory (
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output wire [31:0] read_data
);
    (* ram_style = "block" *) reg [31:0] mem [0:4095]; // 16KB

    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 0;
    end

    always @(posedge clk) begin
        if (we)
            mem[addr[11:2]] <= write_data;
    end

    assign read_data = mem[addr[11:2]];
endmodule


module register_file (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    output wire [31:0] reg10_data
);
    reg [31:0] regs [0:31];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 0;
    end

    always @(posedge clk) begin
        if (we && rd_addr != 5'b0)
            regs[rd_addr] <= rd_data;
    end

    // write-first
    assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 :
                       (we && rd_addr == rs1_addr) ? rd_data : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 :
                       (we && rd_addr == rs2_addr) ? rd_data : regs[rs2_addr];

    assign reg10_data = regs[10];

endmodule


module instruction_memory (
    input  wire [31:0] addr,
    output wire [31:0] instr
);
    (* ram_style = "block" *) reg [31:0] mem [0:255];   // 256 word = 1KB, şimdilik salt okunur (write port sonra eklenecek)

    // here is was testing for commands while debuging
    /* 
    initial begin
        mem[0] = 
        mem[1] = 
        mem[2] = 
        mem[3] = 
        mem[4] = 
        mem[5] = 
        mem[6] = 
        mem[7] = 
    end
    */

    assign instr = mem[addr[9:2]];
endmodule


module pc_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        branch_taken,
    input  wire [31:0] branch_target,
    output reg  [31:0] pc
);
    always @(posedge clk) begin
        if (rst)
            pc <= 32'b0;
        else if (branch_taken)
            pc <= branch_target;
        else
            pc <= pc + 4;
    end
endmodule


module decoder (
    input  wire [31:0] instr,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,
    output wire [6:0]  opcode,
    output wire [31:0] imm_i,
    output wire [31:0] imm_s,
    output wire [31:0] imm_b,
    output wire [31:0] imm_u,
    output wire [31:0] imm_j,
    output reg  [3:0]  alu_op,
    output reg         mem_read,
    output reg         mem_write,
    output reg         reg_write,
    output reg         alu_src,
    output reg         imm_sel,
    output reg         branch,
    output reg         jump,
    output reg         jalr
);
    // --- instr parsing ---
    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    // --- immediate ---
    assign imm_i = {{20{instr[31]}}, instr[31:20]};
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    assign imm_u = {instr[31:12], 12'b0};
    assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    localparam RTYPE      = 7'b0110011;
    localparam OPP_IMM    = 7'b0010011;
    localparam ITYPE_LOAD = 7'b0000011;
    localparam STYPE      = 7'b0100011;
    localparam BTYPE      = 7'b1100011;
    localparam LUI        = 7'b0110111;
    localparam AUIPC      = 7'b0010111;
    localparam JAL        = 7'b1101111;
    localparam JALR       = 7'b1100111;

    always @(*) begin
        // varsayılanlar
        alu_op    = 4'b0000;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        reg_write = 1'b0;
        alu_src   = 1'b0;
        imm_sel   = 1'b0;
        branch    = 1'b0;
        jump      = 1'b0;
        jalr      = 1'b0;

        case (opcode)
            RTYPE: begin
                reg_write = 1'b1;
                alu_src   = 1'b0;
                case (funct3)
                    3'b000: alu_op = (funct7[5]) ? 4'b0001 : 4'b0000;
                    3'b001: alu_op = 4'b0101;
                    3'b010: alu_op = 4'b1000;
                    3'b011: alu_op = 4'b1001;
                    3'b100: alu_op = 4'b0100;
                    3'b101: alu_op = (funct7[5]) ? 4'b0111 : 4'b0110;
                    3'b110: alu_op = 4'b0011;
                    3'b111: alu_op = 4'b0010;
                    default: alu_op = 4'b0000;
                endcase
            end

            OPP_IMM: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                case (funct3)
                    3'b000: alu_op = 4'b0000;
                    3'b010: alu_op = 4'b1000;
                    3'b011: alu_op = 4'b1001;
                    3'b100: alu_op = 4'b0100;
                    3'b110: alu_op = 4'b0011;
                    3'b111: alu_op = 4'b0010;
                    3'b001: alu_op = 4'b0101;
                    3'b101: alu_op = (funct7[5]) ? 4'b0111 : 4'b0110;
                    default: alu_op = 4'b0000;
                endcase
            end

            ITYPE_LOAD: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                mem_read  = 1'b1;
                alu_op    = 4'b0000;
            end

            STYPE: begin
                mem_write = 1'b1;
                alu_src   = 1'b1;
                imm_sel   = 1'b1;
                alu_op    = 4'b0000;
            end

            BTYPE: begin
                branch  = 1'b1;
                alu_src = 1'b0;
                case (funct3)
                    3'b000: alu_op = 4'b0001; // beq
                    3'b001: alu_op = 4'b0001; // bne
                    3'b100: alu_op = 4'b1000; // blt
                    3'b101: alu_op = 4'b1000; // bge
                    3'b110: alu_op = 4'b1001; // bltu
                    3'b111: alu_op = 4'b1001; // bgeu
                    default: alu_op = 4'b0000;
                endcase
            end

            LUI: begin
                reg_write = 1'b1;
            end

            AUIPC: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                alu_op    = 4'b0000;
            end

            JAL: begin
                reg_write = 1'b1;
                jump      = 1'b1;
            end

            JALR: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                imm_sel   = 1'b0;
                alu_op    = 4'b0000;
                jump      = 1'b1;
                jalr      = 1'b1;
            end

            default: ;
        endcase
    end
endmodule


module cpu_core (
    input wire clk,
    input wire rst,
    output wire [5:0]  led
);
    // ============================================================
    //                         ALL WIRES
    // ============================================================
    wire [31:0] pc;
    wire [31:0] instr;

    wire [4:0]  rs1, rs2, rd;
    wire [2:0]  funct3;
    wire [6:0]  funct7, opcode;
    wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    wire [3:0]  alu_op;
    wire        mem_read, mem_write, reg_write, alu_src, imm_sel;
    wire        branch, jump, jalr;

    wire [31:0] rs1_data, rs2_data;
    wire [31:0] write_back_data;

    wire [31:0] imm_selected;
    wire [31:0] alu_b;

    wire [31:0] alu_result;
    wire        zero_flag;

    wire [31:0] mem_read_data;

    wire        branch_condition_met_w;
    wire        branch_taken_signal;
    wire [31:0] branch_target_signal;

    wire [31:0] jump_target;
    wire        pc_branch_or_jump;
    wire [31:0] pc_next_target;

    wire [31:0] reg10_val;

    // ============================================================
    //                    MODUL CONNECTIONS
    // ============================================================

    decoder my_decoder (
        .instr(instr),
        .rs1(rs1), .rs2(rs2), .rd(rd),
        .funct3(funct3), .funct7(funct7), .opcode(opcode),
        .imm_i(imm_i), .imm_s(imm_s), .imm_b(imm_b),
        .imm_u(imm_u), .imm_j(imm_j),
        .alu_op(alu_op),
        .mem_read(mem_read), .mem_write(mem_write),
        .reg_write(reg_write), .alu_src(alu_src),
        .imm_sel(imm_sel), .branch(branch),
        .jump(jump), .jalr(jalr)
    );

    register_file my_regs (
        .clk(clk),
        .we(reg_write),
        .rs1_addr(rs1), .rs2_addr(rs2), .rd_addr(rd),
        .rd_data(write_back_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .reg10_data(reg10_val)
    );

    assign imm_selected = 
        (opcode == 7'b0110111 || opcode == 7'b0010111) ? imm_u :
        imm_sel ? imm_s : imm_i;

    assign alu_b = alu_src ? imm_selected : rs2_data;

    wire [31:0] alu_a = (opcode == 7'b0010111) ? pc : rs1_data;   // AUIPC opcode: 0010111

    alu my_alu (
        .a(alu_a), .b(alu_b),
        .alu_op(alu_op),
        .result(alu_result), .zero(zero_flag)
    );

    data_memory my_dmem (
        .clk(clk),
        .we(mem_write),
        .addr(alu_result),
        .write_data(rs2_data),
        .read_data(mem_read_data)
    );

    // ============================================================
    //                          BRANCH
    // ============================================================
    
    reg branch_condition_met;
    always @(*) begin
        case (funct3)
            3'b000: branch_condition_met = zero_flag;
            3'b001: branch_condition_met = !zero_flag;
            3'b100: branch_condition_met = alu_result[0];
            3'b101: branch_condition_met = !alu_result[0];
            3'b110: branch_condition_met = alu_result[0];
            3'b111: branch_condition_met = !alu_result[0];
            default: branch_condition_met = 1'b0;
        endcase
    end

    assign branch_taken_signal   = branch && branch_condition_met;
    assign branch_target_signal  = pc + imm_b;

    // ============================================================
    //                  JUMP TARGET CHOSING
    // ============================================================
    
    assign jump_target = jalr ? ((rs1_data + imm_i) & ~32'b1) : (pc + imm_j);
    assign pc_branch_or_jump = branch_taken_signal || jump;
    assign pc_next_target = jump ? jump_target : branch_target_signal;

    // ============================================================
    //                   WRITE-BACK CHOSING
    // ============================================================

    assign write_back_data =
        mem_read               ? mem_read_data :
        jump                   ? (pc + 4) :
        (opcode == 7'b0110111) ? imm_u :          // LUI
        alu_result;

    // ============================================================
    //                  PC and INSTRUCTION MEMORY
    // ============================================================

    pc_reg my_pc (
        .clk(clk), .rst(rst),
        .branch_taken(pc_branch_or_jump),
        .branch_target(pc_next_target),
        .pc(pc)
    );

    instruction_memory my_imem (
        .addr(pc),
        .instr(instr)
    );

    // ================ LED TRIAL ====================
    assign led = reg10_val[5:0];   // x10’un alt 6 biti

endmodule
