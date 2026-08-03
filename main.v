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

module mem_decoder (
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data,
    output wire [5:0]  led,
    input  wire        button
);
    wire [3:0] region = addr[31:28];

    wire        bram_sel = (region == 4'h0);
    wire        gpio_sel = (region == 4'h1);
    // flash_sel, sd_sel, sdram_sel...

    wire [31:0] bram_read_data;
    wire [31:0] gpio_read_data;

    unified_memory u_bram (
        .clk(clk),
        .we(we && bram_sel),
        .addr(addr),
        .write_data(write_data),
        .read_data(bram_read_data)
    );

    gpio_ctrl u_gpio (
        .clk(clk),
        .we(we && gpio_sel),
        .addr(addr),
        .write_data(write_data),
        .read_data(gpio_read_data),
        .led(led),
        .button(button)
    );

    always @(posedge clk) begin
        if (bram_sel) read_data <= bram_read_data;
        else if (gpio_sel) read_data <= gpio_read_data;
        else read_data <= 32'hDEAD_BEEF; // debug: undifened
    end
endmodule

module gpio_ctrl (
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data,
    output wire [5:0]  led,
    input  wire        button
);
    reg [5:0] led_reg;

    always @(posedge clk) begin
        if (we && addr[7:0] == 8'h00)
            led_reg <= write_data[5:0];
    end

    always @(posedge clk) begin
        if (addr[7:0] == 8'h00)
            read_data <= {26'b0, led_reg};
        else if (addr[7:0] == 8'h04)
            read_data <= {31'b0, button};
        else
            read_data <= 32'b0;
    end

    assign led = ~led_reg; // active-low
endmodule

module unified_memory (
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data
);
    (* ram_style = "block" *) reg [31:0] mem [0:4095]; // 16KB, komut + veri

    initial begin
        $readmemh("prog.hex", mem);
    end

    always @(posedge clk) begin
        if (we)
            mem[addr[13:2]] <= write_data;
        read_data <= mem[addr[13:2]];
    end
endmodule


module register_file (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
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

    assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 : regs[rs2_addr];
endmodule


module pc_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire        branch_taken,
    input  wire [31:0] branch_target,
    output reg  [31:0] pc
);
    always @(posedge clk or posedge rst) begin
        if (rst)
            pc <= 32'b0;
        else if (en) begin
            if (branch_taken)
                pc <= branch_target;
            else
                pc <= pc + 4;
        end
    end
endmodule


module control_unit (
    input  wire        clk,
    input  wire        rst,
    input  wire        memory_ready,  // BRAM için hep 1, SDRAM eklenince gerçek sinyale bağlanacak çünkü gecikme falan var protokolden kaynaklı
    output reg  [2:0]  state
);
    localparam FETCH     = 3'd0;
    localparam DECODE    = 3'd1;
    localparam EXECUTE   = 3'd2;
    localparam MEMORY    = 3'd3;
    localparam WRITEBACK = 3'd4;

    always @(posedge clk) begin
        if (rst) begin
            state <= FETCH;
        end else begin
            case (state)
                FETCH:     state <= memory_ready ? DECODE    : FETCH;
                DECODE:    state <= EXECUTE;
                EXECUTE:   state <= MEMORY;
                MEMORY:    state <= memory_ready ? WRITEBACK : MEMORY;
                WRITEBACK: state <= FETCH;
                default:   state <= FETCH;
            endcase
        end
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
    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

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
                    3'b000: alu_op = 4'b0001;
                    3'b001: alu_op = 4'b0001;
                    3'b100: alu_op = 4'b1000;
                    3'b101: alu_op = 4'b1000;
                    3'b110: alu_op = 4'b1001;
                    3'b111: alu_op = 4'b1001;
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
    input  wire        clk,
    input  wire        rst,
    output wire [5:0]  led,
    input  wire        button
);
    // ============================================================
    //                         ALL WIRES
    // ============================================================
    wire [2:0]  state;
    localparam FETCH     = 3'd0;
    localparam DECODE    = 3'd1;
    localparam EXECUTE   = 3'd2;
    localparam MEMORY    = 3'd3;
    localparam WRITEBACK = 3'd4;

    wire [31:0] pc;
    reg  [31:0] IR;

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
    wire [31:0] alu_a;

    wire [31:0] alu_result;
    wire        zero_flag;

    wire [31:0] mem_addr;
    wire        mem_we;
    wire [31:0] mem_data_out;

    reg         branch_condition_met;
    wire        branch_taken_signal;
    wire [31:0] branch_target_signal;

    wire [31:0] jump_target;
    wire        pc_branch_or_jump;
    wire [31:0] pc_next_target;
    wire        pc_en;

    wire        regfile_we;

    // ============================================================
    //                    CONTROL UNIT
    // ============================================================
    control_unit my_ctrl (
        .clk(clk), .rst(rst),
        .memory_ready(1'b1),
        .state(state)
    );

    // ============================================================
    //          INSTRUCTION REGISTER (IR)
    // ============================================================
    always @(posedge clk) begin
        if (state == DECODE)
            IR <= mem_data_out;
    end

    // ============================================================
    //                       DECODER
    // ============================================================
    decoder my_decoder (
        .instr(IR),
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

    // ============================================================
    //                    REGISTER FILE
    // ============================================================
    assign regfile_we = (state == WRITEBACK) && reg_write;

    register_file my_regs (
        .clk(clk),
        .we(regfile_we),
        .rs1_addr(rs1), .rs2_addr(rs2), .rd_addr(rd),
        .rd_data(write_back_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    // ============================================================
    //                          ALU
    // ============================================================
    assign imm_selected =
        (opcode == 7'b0110111 || opcode == 7'b0010111) ? imm_u :
        imm_sel ? imm_s : imm_i;

    assign alu_b = alu_src ? imm_selected : rs2_data;
    assign alu_a = (opcode == 7'b0010111) ? pc : rs1_data; // AUIPC: pc + imm_u

    alu my_alu (
        .a(alu_a), .b(alu_b),
        .alu_op(alu_op),
        .result(alu_result), .zero(zero_flag)
    );

    // ============================================================
    //                    UNIFIED MEMORY
    // ============================================================
    assign mem_addr = (state == FETCH) ? pc : alu_result;
    assign mem_we   = (state == MEMORY) && mem_write;

    mem_decoder my_mem (
        .clk(clk),
        .we(mem_we),
        .addr(mem_addr),
        .write_data(rs2_data),
        .read_data(mem_data_out),
        .led(led),
        .button(button)
    );

    // ============================================================
    //                    BRANCH KARARI
    // ============================================================
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

    assign branch_taken_signal  = branch && branch_condition_met;
    assign branch_target_signal = pc + imm_b;

    // ============================================================
    //                    JUMP HEDEFİ
    // ============================================================
    assign jump_target      = jalr ? ((rs1_data + imm_i) & ~32'b1) : (pc + imm_j);
    assign pc_branch_or_jump = branch_taken_signal || jump;
    assign pc_next_target    = jump ? jump_target : branch_target_signal;

    // ============================================================
    //                    WRITE-BACK SEÇİMİ
    // ============================================================
    assign write_back_data =
        mem_read               ? mem_data_out :
        jump                   ? (pc + 4) :
        (opcode == 7'b0110111) ? imm_u :
        alu_result;

    // ============================================================
    //                    PC GÜNCELLEMESİ
    // ============================================================
    assign pc_en = (state == WRITEBACK);

    pc_reg my_pc (
        .clk(clk), .rst(rst),
        .en(pc_en),
        .branch_taken(pc_branch_or_jump),
        .branch_target(pc_next_target),
        .pc(pc)
    );
endmodule


module top (
    input  wire       clk,
    input  wire       rst_n,      // S1 button
    input  wire       button,     // S2 button
    output wire [5:0] led         // 6 LED
);
    wire rst = rst_n; // NOTE: S1 butonu bu kartta ters calisiyor, ~rst_n degil rst_n dogru polarite

    cpu_core u_cpu (
        .clk(clk),
        .rst(rst),
        .led(led),
        .button(button)
    );
endmodule
