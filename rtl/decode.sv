`timescale 1ns / 1ps

module decode (
    input  logic [31:0] inst, //32 bit input instruction
    input  logic [31:0] pc,

    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [4:0]  rd, 
    output logic        rs1_valid,  // tells Rename if rs1 is actually used
    output logic        rs2_valid,  // tells Rename if rs2 is actually used
    output pipeline_types::ctrl_payload_t ctrl_payload_o,

    output logic [31:0] imm, // immediate gets sign extended to 32 bits

    // control signals for EX stage
    output logic        ALUSrc,
    output logic [2:0]  ALUOp,   // carries alu_op_e encoding
    output logic        branch,
    output logic        jump,

    // control Signals for MEM Stage
    output logic        MemRead,
    output logic        MemWrite,

    // control Signals for WB Stage
    output logic        RegWrite, //in rename this connects to dec_rd_used_i
    output logic        MemToReg
);
    import pipeline_types::*;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    logic [4:0] inst_rd;
    logic [4:0] inst_rs1;
    logic [4:0] inst_rs2;
	 
    fu_type_t fu_type;

    assign opcode   = inst[6:0];
    assign inst_rd  = inst[11:7];
    assign funct3   = inst[14:12];
    assign inst_rs1 = inst[19:15];
    assign inst_rs2 = inst[24:20];
    assign funct7   = inst[31:25];

    localparam opcode_LUI    = 7'b0110111;
    localparam opcode_ITYPE  = 7'b0010011;
    localparam opcode_RTYPE  = 7'b0110011;
    localparam opcode_LOAD   = 7'b0000011;
    localparam opcode_STORE  = 7'b0100011;
    localparam opcode_BRANCH = 7'b1100011;
    localparam opcode_JALR   = 7'b1100111;

    // funct3 for I-Type
    localparam funct3_ADDI   = 3'b000;
    localparam funct3_SLTIU  = 3'b011;
    localparam funct3_ORI    = 3'b110;

    always_comb begin
        // --- STEP 1: Default values ---
        ALUSrc    = 1'b0;
        ALUOp     = ALU_ADD; // default to ADD (safe)
        branch    = 1'b0;
        jump      = 1'b0;
        MemRead   = 1'b0;
        MemWrite  = 1'b0;
        RegWrite  = 1'b0;
        MemToReg  = 1'b0;
        imm       = 32'b0;

        rs1_valid = 1'b0;
        rs2_valid = 1'b0;
        fu_type   = FU_ALU; // default

        rs1       = 5'b0;
        rs2       = 5'b0;
        rd        = 5'b0;

        // --- STEP 2: Decode by opcode ---
        unique case (opcode)
            // ---------------- LUI ----------------
            opcode_LUI: begin
                RegWrite  = 1'b1;
                rd        = inst_rd;
                fu_type   = FU_ALU;
                ALUOp     = ALU_ADD; // if you later use ALU for LUI, this is a "pass imm" style
            end

            // ------------- I-TYPE (ADDI, ORI, SLTIU) -------------
            opcode_ITYPE: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                rd        = inst_rd;
                rs1       = inst_rs1;
                rs1_valid = 1'b1;
                fu_type   = FU_ALU;

                unique case (funct3)
                    funct3_ADDI:  ALUOp = ALU_ADD; // ADDI
                    funct3_ORI:   ALUOp = ALU_OR;  // ORI
                    fu nct3_SLTIU: ALUOp = ALU_SUB; // TEMP: treat as SUB/compare later
                    default:      ALUOp = ALU_ADD;
                endcase
            end

            // ------------- R-TYPE (ADD, SUB, AND, OR, XOR, SRA, etc.) -------------
            opcode_RTYPE: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b0;
                rd        = inst_rd;
                rs1       = inst_rs1;
                rs2       = inst_rs2;
                rs1_valid = 1'b1;
                rs2_valid = 1'b1;
                fu_type   = FU_ALU;

                unique case ({funct7, funct3})
                    {7'b0000000, 3'b000}: ALUOp = ALU_ADD; // ADD
                    {7'b0100000, 3'b000}: ALUOp = ALU_SUB; // SUB
                    {7'b0000000, 3'b111}: ALUOp = ALU_AND; // AND
                    {7'b0000000, 3'b110}: ALUOp = ALU_OR;  // OR
                    {7'b0000000, 3'b100}: ALUOp = ALU_XOR; // XOR
                    // SRA/SRL/etc can be added later
                    default:              ALUOp = ALU_ADD;
                endcase
            end

            // ------------- LOAD (LW, LBU) -------------
            opcode_LOAD: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                MemRead   = 1'b1;
                MemToReg  = 1'b1;
                ALUOp     = ALU_ADD; // base + offset
                rd        = inst_rd;
                rs1       = inst_rs1;
                rs1_valid = 1'b1;
                fu_type   = FU_LSU;
            end

            // ------------- STORE (SW, SH) -------------
            opcode_STORE: begin
                ALUSrc    = 1'b1;
                MemWrite  = 1'b1;
                ALUOp     = ALU_ADD; // base + offset
                rs1       = inst_rs1;
                rs2       = inst_rs2;
                rs1_valid = 1'b1;
                rs2_valid = 1'b1;
                fu_type   = FU_LSU;
            end

            // ------------- BRANCH (BNE) -------------
            opcode_BRANCH: begin
                ALUSrc    = 1'b0;
                ALUOp     = ALU_SUB; // could be used as compare
                rs1       = inst_rs1;
                rs2       = inst_rs2;
                rs1_valid = 1'b1;
                rs2_valid = 1'b1;
                fu_type   = FU_BRANCH;

                if (funct3 == 3'b001) begin
                    // BNE
                    branch = 1'b1;
                end
            end

            // ------------- JALR -------------
            opcode_JALR: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                jump      = 1'b1;
                ALUOp     = ALU_ADD; // pc or base + imm
                rd        = inst_rd;
                rs1       = inst_rs1;
                rs1_valid = 1'b1;
                fu_type   = FU_BRANCH;
            end

            default: begin
                // keep defaults
            end
        endcase

        // --- STEP 3: Immediate generation ---
        unique case (opcode)
            opcode_LUI:
                imm = { inst[31:12], 12'b0 };

            opcode_ITYPE: begin
                if (funct3 == funct3_ORI) begin
                    // Zero-extend for ORI
                    imm = { 20'b0, inst[31:20] };
                end else begin
                    // Sign-extend for ADDI, SLTIU
                    imm = { {20{inst[31]}}, inst[31:20] };
                end
            end

            opcode_LOAD,
            opcode_JALR:
                imm = { {20{inst[31]}}, inst[31:20] };

            opcode_STORE:
                imm = { {20{inst[31]}}, inst[31:25], inst[11:7] };

            opcode_BRANCH:
                imm = { {19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0 };

            default:
                imm = 32'b0;
        endcase

        // --- STEP 4: Fill payload (goes to Rename / Dispatch) ---
        ctrl_payload_o.pc        = pc;
        ctrl_payload_o.imm       = imm;
        ctrl_payload_o.inst      = inst;
        ctrl_payload_o.ALUSrc    = ALUSrc;
        ctrl_payload_o.ALUOp     = ALUOp;      // encoded as alu_op_e (3 bits)
        ctrl_payload_o.MemRead   = MemRead;
        ctrl_payload_o.MemWrite  = MemWrite;
        ctrl_payload_o.RegWrite  = RegWrite;
        ctrl_payload_o.MemToReg  = MemToReg;
        ctrl_payload_o.fu_type   = fu_type;
        ctrl_payload_o.is_branch = branch;
        ctrl_payload_o.is_jump   = jump;
    end

endmodule