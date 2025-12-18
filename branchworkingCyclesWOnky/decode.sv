`timescale 1ns / 1ps
`include "pipeline_types.sv"  

import pipeline_types::*;

module decode (
    input  logic [31:0] inst,
    input  logic [31:0] pc,

    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [4:0]  rd,
    output logic        rs1_valid,
    output logic        rs2_valid,
    output pipeline_types::ctrl_payload_t ctrl_payload_o,

    output logic [31:0] imm,

    output logic        ALUSrc,
    output logic [2:0]  ALUOp,
    output logic        branch,
    output logic        jump,

    output logic        MemRead,
    output logic        MemWrite,

    output logic        RegWrite,
    output logic        MemToReg
);
    import pipeline_types::*;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = inst[6:0];
    assign funct3 = inst[14:12];
    assign funct7 = inst[31:25];

    assign rd  = inst[11:7];
    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];

    localparam opcode_LUI    = 7'b0110111;
    localparam opcode_ITYPE  = 7'b0010011;
    localparam opcode_RTYPE  = 7'b0110011;
    localparam opcode_LOAD   = 7'b0000011;
    localparam opcode_STORE  = 7'b0100011;
    localparam opcode_BRANCH = 7'b1100011;
    localparam opcode_JALR   = 7'b1100111;

    localparam funct3_ADDI   = 3'b000;
    localparam funct3_SLTIU  = 3'b011;
    localparam funct3_ORI    = 3'b110;

    fu_type_t fu_type;

    always_comb begin
        // defaults
        ALUSrc    = 0;
        ALUOp     = ALU_ADD;
        branch    = 0;
        jump      = 0;
        MemRead   = 0;
        MemWrite  = 0;
        RegWrite  = 0;
        MemToReg  = 0;
        imm       = 32'b0;

        rs1_valid = 0;
        rs2_valid = 0;
        fu_type   = FU_ALU;

        unique case (opcode)

            // ---------- LUI ----------
            opcode_LUI: begin
                RegWrite  = 1;
                ALUSrc    = 1;           // IMPORTANT
                ALUOp     = ALU_ADD;
                imm       = {inst[31:12], 12'b0};
            end

            // ---------- I-TYPE ----------
            opcode_ITYPE: begin
                RegWrite  = 1;
                ALUSrc    = 1;
                rs1_valid = 1;
                fu_type   = FU_ALU;

                imm = {{20{inst[31]}}, inst[31:20]}; // SIGN EXTEND

                unique case (funct3)
                    funct3_ADDI:  ALUOp = ALU_ADD;
                    funct3_ORI:   ALUOp = ALU_OR;
                    funct3_SLTIU: ALUOp = ALU_SLTU;
                    default:      ALUOp = ALU_ADD;
                endcase
            end

            // ---------- R-TYPE ----------
            opcode_RTYPE: begin
                RegWrite  = 1;
                rs1_valid = 1;
                rs2_valid = 1;
                fu_type   = FU_ALU;

                unique case ({funct7, funct3})
                    {7'b0000000,3'b000}: ALUOp = ALU_ADD;
                    {7'b0100000,3'b000}: ALUOp = ALU_SUB;
                    {7'b0000000,3'b111}: ALUOp = ALU_AND;
                    {7'b0000000,3'b110}: ALUOp = ALU_OR;
                    {7'b0000000,3'b100}: ALUOp = ALU_XOR;
                    {7'b0100000,3'b101}: ALUOp = ALU_SRA;
                    default:             ALUOp = ALU_ADD;
                endcase
            end

            // ---------- LOAD ----------
            opcode_LOAD: begin
                RegWrite  = 1;
                ALUSrc    = 1;
                MemRead   = 1;
                MemToReg  = 1;
                rs1_valid = 1;
                fu_type   = FU_LSU;
                imm       = {{20{inst[31]}}, inst[31:20]};
            end

            // ---------- STORE ----------
            opcode_STORE: begin
                ALUSrc    = 1;
                MemWrite  = 1;
                rs1_valid = 1;
                rs2_valid = 1;
                fu_type   = FU_LSU;
                imm       = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            end

            // ---------- BRANCH (BNE) ----------
            opcode_BRANCH: begin
                RegWrite  = 0;       // <--- FORCE THIS TO 0 EXPLICITLY
                rs1_valid = 1;
                rs2_valid = 1;
                branch    = 1;
                ALUOp     = ALU_SUB;
                fu_type   = FU_BRANCH;
                imm       = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            end

            // ---------- JALR ----------
            opcode_JALR: begin
                RegWrite  = 1;
                ALUSrc    = 1;
                jump      = 1;
                rs1_valid = 1;
                fu_type   = FU_BRANCH;
                imm       = {{20{inst[31]}}, inst[31:20]};
            end
            default: begin
                // Treating unknown opcodes as NOPs ensures safety
                RegWrite  = 0;
                ALUSrc    = 0;
                MemRead   = 0;
                MemWrite  = 0;
                rs1_valid = 0;
                rs2_valid = 0;
                branch    = 0;
                jump      = 0;
            end
        endcase

        // payload
        ctrl_payload_o.pc        = pc;
        ctrl_payload_o.imm       = imm;
        ctrl_payload_o.inst      = inst;
        ctrl_payload_o.ALUSrc    = ALUSrc;
        ctrl_payload_o.ALUOp     = ALUOp;
        ctrl_payload_o.MemRead   = MemRead;
        ctrl_payload_o.MemWrite  = MemWrite;
        ctrl_payload_o.RegWrite  = RegWrite;
        ctrl_payload_o.MemToReg  = MemToReg;
        ctrl_payload_o.fu_type   = fu_type;
        ctrl_payload_o.is_branch = branch;
        ctrl_payload_o.is_jump   = jump;
        ctrl_payload_o.funct3    = funct3;
    end

endmodule