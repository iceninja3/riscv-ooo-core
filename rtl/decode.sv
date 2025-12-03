`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/06/2025 12:31:41 AM
// Design Name: 
// Module Name: decode
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module decode (
    input logic [31:0] inst, //32 bit input isntruciton

    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [4:0]  rd, 
    output logic rs1_valid,  // tells Rename if rs1 is actually used
    output logic rs2_valid,  // tells Rename if rs2 is actually used
    output pipeline_types::ctrl_payload_t ctrl_payload_o

    output logic [31:0] imm, // immediate gets sign extended to 32 bits

    // control signals for EX stage
    output logic ALUSrc,
    output logic [2:0]  ALUOp,
    output logic branch,
    output logic jump,

    // control Signals for MEM Stage
    output logic MemRead,
    output logic MemWrite,

    // control Signals for WB Stage
    output logic RegWrite, //in rename this connects to dec_rd_used_i
    output logic MemToReg
);
    import pipeline_types::*; // import for ctrl_payload_t

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    // These are now internal wires, not unconditional assignments
    logic [4:0]  inst_rd;
    logic [4:0]  inst_rs1;
    logic [4:0]  inst_rs2;

    assign opcode = inst[6:0];
    assign inst_rd = inst[11:7]; // rd is always in the same place
    assign funct3 = inst[14:12];
    assign inst_rs1 = inst[19:15]; // rs1 is always in the same place
    assign inst_rs2 = inst[24:20]; // rs2 is always in the same place
    assign funct7 = inst[31:25];


    localparam opcode_LUI   = 7'b0110111;
    localparam opcode_ITYPE = 7'b0010011;
    localparam opcode_RTYPE = 7'b0110011;
    localparam opcode_LOAD  = 7'b0000011;
    localparam opcode_STORE = 7'b0100011;
    localparam opcode_BRANCH = 7'b1100011;
    localparam opcode_JALR  = 7'b1100111;

    // funct3 for I-Type
    localparam funct3_ADDI  = 3'b000;
    localparam funct3_SLTIU = 3'b011;
    localparam funct3_ORI   = 3'b110;

    always_comb begin
        // --- STEP 1: Set default values ---
        ALUSrc    = 1'b0;
        ALUOp     = 3'b111; // Default to "Illegal"
        branch    = 1'b0;
        jump      = 1'b0;
        MemRead   = 1'b0;
        MemWrite  = 1'b0;
        RegWrite  = 1'b0;
        MemToReg  = 1'b0;
        imm       = 32'b0;

        rs1_valid = 1'b0; 
        rs2_valid = 1'b0;
        fu_type   = FU_ALU; // Default to ALU
        
        // bug fix -> default rs1, rs2, and rd to 0
        rs1       = 5'b0;
        rs2       = 5'b0;
        rd        = 5'b0;

        // --- STEP 2: Decode Control Signals & Register Addresses ---
        case (opcode)
            opcode_LUI: begin
                RegWrite  = 1'b1;
                ALUOp     = 3'b100;
                rd        = inst_rd; // U-Type has rd
                fu_type   = FU_ALU;
            end

            opcode_ITYPE: begin // ADDI, ORI, SLTIU
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                ALUOp     = 3'b010;
                rd        = inst_rd; // I-Type has rd
                rs1       = inst_rs1; // I-Type has rs1

                rs1_valid = 1'b1; // VALID
                fu_type   = FU_ALU;
            end

            opcode_RTYPE: begin // SUB, SRA, AND
                RegWrite  = 1'b1;
                ALUSrc    = 1'b0;
                ALUOp     = 3'b001;
                rd        = inst_rd; // R-Type has rd
                rs1       = inst_rs1; // R-Type has rs1
                rs2       = inst_rs2; // R-Type has rs2

                rs1_valid = 1'b1; // VALID
                rs2_valid = 1'b1; // VALID
                fu_type   = FU_ALU; 
            end

            opcode_LOAD: begin // LW, LBU
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                MemRead   = 1'b1;
                MemToReg  = 1'b1;
                ALUOp     = 3'b000;
                rd        = inst_rd; // I-Type (Load) has rd
                rs1       = inst_rs1; // I-Type (Load) has rs1

                rs1_valid = 1'b1; // VALID
                fu_type   = FU_LSU; // Send to Load/Store Unit
            end

            opcode_STORE: begin // SW, SH
                ALUSrc    = 1'b1;
                MemWrite  = 1'b1;
                ALUOp     = 3'b000;
                rs1       = inst_rs1; // S-Type has rs1
                rs2       = inst_rs2; // S-Type has rs2

                rs1_valid = 1'b1; // VALID
                rs2_valid = 1'b1; // VALID
                fu_type   = FU_LSU; // Send to Load/Store Unit
            end

            opcode_BRANCH: begin // BNE
                ALUSrc    = 1'b0;
                ALUOp     = 3'b011;
                rs1       = inst_rs1; // B-Type has rs1
                rs2       = inst_rs2; // B-Type has rs2

                rs1_valid = 1'b1; // VALID
                rs2_valid = 1'b1; // VALID
                fu_type   = FU_BRANCH; // Send to Branch Unit
                
                // only enable for BNE
                if (funct3 == 3'b001) begin 
                    branch = 1'b1;
                end
            end

            opcode_JALR: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                jump      = 1'b1;
                ALUOp     = 3'b101;
                rd        = inst_rd; // I-Type (JALR) has rd
                rs1       = inst_rs1; // I-Type (JALR) has rs1

                rs1_valid = 1'b1; // VALID
                fu_type   = FU_BRANCH; // Send to Branch Unit
            end
            default: begin
                // All defaults are set
            end
        endcase


        // --- STEP 3: Generate Immediate ---
        case (opcode)
            opcode_LUI:
                imm = { inst[31:12], 12'b0 };

            opcode_ITYPE:
                // **BUG FIX**: Handle ORI zero-extension
                if (funct3 == funct3_ORI) begin
                    // Zero-extend for ORI
                    imm = { 20'b0, inst[31:20] };
                end else begin
                    // Sign-extend for ADDI, SLTIU
                    imm = { {20{inst[31]}}, inst[31:20] };
                end

            opcode_LOAD,
            opcode_JALR:
                // Sign-extend I-Type
                imm = { {20{inst[31]}}, inst[31:20] };

            opcode_STORE:
                // Sign-extend S-Type
                imm = { {20{inst[31]}}, inst[31:25], inst[11:7] };

            opcode_BRANCH:
                // Sign-extend B-Type
                imm = { {19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0 };

            default:
                imm = 32'b0;
        endcase


        //keep payload correct
        ctrl_payload_o.pc       = pc;
        ctrl_payload_o.imm      = imm;
        ctrl_payload_o.inst     = inst;
        ctrl_payload_o.ALUSrc   = ALUSrc;
        ctrl_payload_o.ALUOp    = ALUOp;
        ctrl_payload_o.MemRead  = MemRead;
        ctrl_payload_o.MemWrite = MemWrite;
        ctrl_payload_o.RegWrite = RegWrite;
        ctrl_payload_o.MemToReg = MemToReg;
        ctrl_payload_o.fu_type  = fu_type;
        ctrl_payload_o.is_branch= branch;
        ctrl_payload_o.is_jump  = jump;

    end

endmodule


