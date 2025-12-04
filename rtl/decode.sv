adriann102
adriann102
Idle

adriann102 — 11/30/25, 11:56 PM
That works
vishal — 11/30/25, 11:57 PM
Sounds great
vishal — 12/1/25, 2:49 AM
could we start at 12 or 1 if possible actually. i might need to leave at 4 or 4:15 
otherwise we can stick to 2-5 but a bit harder for me
adriann102 — 12/1/25, 11:52 AM
Yeah that works
vishal — Yesterday at 11:41 AM
Meet you at the front
vishal — Yesterday at 11:55 AM
Sitting outside Powell
adriann102 — Yesterday at 11:56 AM
Walking over
Did you eat already
Imma eat first I'll be there around 12:30 if that's okay. Can you get two spots in the computer room that's on the left when you go in bc they have monitors
vishal — Yesterday at 12:03 PM
Sg
Got two seats near the entrance of the room
adriann102 — Yesterday at 12:06 PM
Fire
vishal — Yesterday at 3:42 PM
Planning doc:
https://docs.google.com/document/d/1L6bAEIu7gX7s3ErXn8dxgDWopCFcpEXAujy0CL5_B7k/edit?tab=t.0
Google Docs
riscv-OOO-core
Todo: Get decode and rename to work together (stitch the ports together and add functionality as necessary) Decode Rename After decode+rename works, connect rename and dispatch Dispatch and Execute Connect Execute and WB Connect WB and Commit Decode only needs to do these: ADDI, LUI, ORI, SLT...
Image
adriann102 — Yesterday at 3:43 PM
Image
vishal — Yesterday at 8:32 PM
can i have your phone number
or just text me once at 6505763250
I pushed changes. There are changes in:
pipeline types (added an enum for functional units and struct for "ctrl_payload_t". you can just copy paste to replace)
Decode has more outputs + some more combo logic (copy paste to replace)
Fetch has more inputs + random lines changed throughout (copy paste to replace)

Before, modifying anything, can you move the current decode, fetch, and pipelinetypes files out into a folder to save them (and all the other modules that have "worked" so far like skid buffer) since those are the ones that we know work. 
could you just see if it compiles and lmk and I can try to fix if there are issues you don't see a simple fix too
if it does compile can you extend your testbench/simulation thing to check everything so far (and maybe just make a tb for rename itself) 
vishal
 pinned a message to this channel. See all pinned messages. — Yesterday at 8:37 PM
vishal — Yesterday at 9:00 PM
there are 3 inputs in rename that decode doesn't drive. when you test for now just hard code them (we need ROB to check them)
recover_i → 0 (Disable misprediction recovery).

rob_commit_free_valid_i → 0 (Disable freeing registers).

rob_commit_free_preg_i → 0.
Image
idk if this helps but gemini recommended adding this to your sim for the ROB stuff instead of doing the hard coding above (the code "emulates" ROB to see if the rename can recycle regs properly):


// "Magic" ROB Simulator in Testbench
logic [5:0] magic_rob_fifo [15:0]; // A tiny FIFO to hold old_p regs
logic [3:0] head = 0, tail = 0;

always @(posedge clk) begin
    // 1. Capture the "Old Physical Register" from Rename output
    if (rename_valid_o && rename_ready_i) begin
        magic_rob_fifo[tail] <= rd_old_p_o; // Capture the stale register
        tail <= tail + 1;
    end

    // 2. Randomly "Commit" (Free) it back to Rename inputs
    // In a real CPU, this happens after execution. Here, we just wait a few cycles.
    if (head != tail) begin // If we have pending instructions
        rob_commit_free_valid_i <= 1'b1;
        rob_commit_free_preg_i  <= magic_rob_fifo[head];
        head <= head + 1;
    end else begin
        rob_commit_free_valid_i <= 1'b0;
    end
end

What this verifies: This allows you to run thousands of instructions through the pipeline. You can verify that physical registers are being recycled and that p1 eventually gets reused after p64 is allocated.
adriann102 — Yesterday at 9:17 PM
Yeah give me some time
9163851969
adriann102 — 5:17 PM
for the decode you meant fu_type_t right
not fu_type
its defined as fu_type_t in the strucs file but used as fu_type in the decode
nvm fixed it
vishal — 5:27 PM
Oh mb
adriann102 — 5:29 PM
yeah it all compiles btw
after the changes you added:
Image
adriann102 — 5:45 PM
got the rename working too
i havent connected it on the top level yet tho
vishal — 5:49 PM
Oh mb was anything wrong with rename?
adriann102 — 5:51 PM
just some syntax issues
Image
this is for rename
looks correct i believe 
can you push these changes, im not on my mac rn
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/06/2025 12:31:41 AM
Expand
message.txt
8 KB
^decode
module Fetch #(
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 32,
    parameter RESET_PC   = 32'h0000_0000  //intialize pc 
)(
    input  logic                  clk,
    input  logic                  reset,

    output logic [ADDR_WIDTH-1:0] icache_addr,
    input  logic [DATA_WIDTH-1:0] icache_rdata, 

    //skid buffer 
    output logic                  valid_o,
    input  logic                  ready_i,
    output logic [31:0]           pc_o,
    output logic [DATA_WIDTH-1:0] inst_o
);


    logic [31:0] pc_req;
    logic [31:0] pc_reg;
    logic [DATA_WIDTH-1:0] inst_reg;

    // Word address into iCache: drop bottom 2 bits of PC (byte→word)
    assign icache_addr = pc_req[ADDR_WIDTH+1:2];

    // Outputs to skid buffer / decode
    assign pc_o   = pc_reg;
    assign inst_o = inst_reg;


    always_ff @(posedge clk) begin
        if (reset) begin
            pc_req   <= RESET_PC;
            pc_reg   <= '0;
            inst_reg <= '0;
            valid_o  <= 1'b0;
        end 
        else begin
            // Advance only when:
            //  downstream is ready, OR
            //  we don't yet have a valid instruction (pipeline fill)
            if (ready_i || !valid_o) begin
                // icache_rdata corresponds to pc_req from previous cycle
                inst_reg <= icache_rdata;
                pc_reg   <= pc_req;
                valid_o  <= 1'b1;
                pc_req <= pc_req + 32'd4;
            end
        end
    end

endmodule
^fetch
`timescale 1ns/1ps

import pipeline_types::*;

module tb_Rename;
Expand
message.txt
7 KB
^tb_rename
module Rename #(
  parameter int N_LOG        = 32,
  parameter int N_PHYS       = 64,
  parameter int N_CHECKPTS   = 8,
  parameter int ROB_TAG_W    = 6
)(
Expand
message.txt
6 KB
^rename
vishal — 5:59 PM
Yea I’m outside without comp but I’ll be near comp in a hour or so
adriann102 — 11/29/25, 6:28 PM
bet
﻿
vishal
unculturedpeasant
 
 
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
	 input logic [31:0] pc,

    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [4:0]  rd, 
    output logic rs1_valid,  // tells Rename if rs1 is actually used
    output logic rs2_valid,  // tells Rename if rs2 is actually used

    output pipeline_types::ctrl_payload_t ctrl_payload_o,


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
	 
	 fu_type_t fu_type;

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