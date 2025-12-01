`timescale 1ns / 1ps
import cpu_types_pkg::*; // Import the struct we defined in the previous step

module cpu_top (
    input logic clk,
    input logic rst
);

    // ==========================================
    // Wires connecting stages
    // ==========================================

    // Fetch -> Decode
    logic [31:0] if_pc;
    logic [31:0] if_inst;
    logic        if_valid; // Output from fetch (skid buffer)
    logic        dec_ready; // Input to fetch

    // Decode -> Rename
    logic [31:0] dec_imm;
    logic [4:0]  dec_rs1, dec_rs2, dec_rd;
    logic        dec_rs1_used, dec_rs2_used, dec_rd_used; // You need to generate these based on opcode
    logic        dec_is_branch;
    logic [2:0]  dec_alu_op;
    logic        dec_mem_read, dec_mem_write, dec_jump;
    logic        ren_ready; // Backpressure from Rename

    // Rename -> Dispatch (The complex part)
    logic        ren_valid_out;     // From Rename module
    logic [5:0]  ren_rs1_p, ren_rs2_p, ren_rd_new_p, ren_rd_old_p;
    logic [5:0]  ren_rob_tag;
    
    // Pipelined Decode Signals (To match Rename Latency)
    // We need to delay these by 1 cycle to sync with the Rename module output
    logic [31:0] dec_pc_q, dec_imm_q;
    logic [2:0]  dec_alu_op_q;
    logic        dec_mem_read_q, dec_mem_write_q, dec_branch_q, dec_jump_q;

    // Dispatch Interface
    dispatch_packet_t dispatch_pkt;
    logic             disp_ready_from_dispatch; // Backpressure from Dispatch

    // ==========================================
    // 1. FETCH STAGE
    // ==========================================
    // Assuming your Fetch module has the skid buffer built-in as shown in your files
    Fetch fetch_inst (
        .clk(clk),
        .reset(rst),
        .icache_addr(),     // Connected to memory (ignored for now or auto-handled)
        .icache_rdata(32'h00000013), // HARDCODED NOP for test if you don't have iCache connected yet
        .valid_o(if_valid),
        .ready_i(ren_ready), // Connect to downstream backpressure
        .pc_o(if_pc),
        .inst_o(if_inst)
    );

    // ==========================================
    // 2. DECODE STAGE
    // ==========================================
    decode decode_inst (
        .inst(if_inst),
        .rs1(dec_rs1),
        .rs2(dec_rs2),
        .rd(dec_rd),
        .imm(dec_imm),
        .ALUOp(dec_alu_op),
        .MemRead(dec_mem_read),
        .MemWrite(dec_mem_write),
        .branch(dec_is_branch),
        .jump(dec_jump),
        // Note: Your decode module needs to output "Use" bits or we derive them:
        .RegWrite(dec_rd_used), 
        .MemToReg() // Unused for now
    );
    
    // Simple derivation for rs1_used/rs2_used if not in Decode module
    // (This is a simplification; ideally put this logic inside Decode)
    assign dec_rs1_used = (if_inst[6:0] != 7'b0110111); // LUI doesn't use RS1
    assign dec_rs2_used = (if_inst[6:0] == 7'b0110011) || (if_inst[6:0] == 7'b0100011) || (if_inst[6:0] == 7'b1100011); // R-type, Store, Branch use RS2

    // ==========================================
    // 3. RENAME STAGE
    // ==========================================
    
    // Pipeline the "Payload" signals (PC, Imm, Op) to match Rename Module latency
    always_ff @(posedge clk) begin
        if (rst) begin
            dec_pc_q <= '0;
            // ... reset others ...
        end else if (ren_ready) begin // Only update if Rename stage accepts data
            dec_pc_q        <= if_pc;
            dec_imm_q       <= dec_imm;
            dec_alu_op_q    <= dec_alu_op;
            dec_mem_read_q  <= dec_mem_read;
            dec_mem_write_q <= dec_mem_write;
            dec_branch_q    <= dec_is_branch;
            dec_jump_q      <= dec_jump;
        end
    end

    Rename rename_inst (
        .clk(clk),
        .rst(rst),
        // Inputs from Decode
        .dec_valid_i(if_valid),
        .dec_rs1_i(dec_rs1),
        .dec_rs2_i(dec_rs2),
        .dec_rd_i(dec_rd),
        .dec_rs1_used_i(dec_rs1_used),
        .dec_rs2_used_i(dec_rs2_used),
        .dec_rd_used_i(dec_rd_used),
        .dec_is_branch_i(dec_is_branch),
        // Outputs
        .ren_valid_o(ren_valid_out),
        .ren_ready_i(disp_ready_from_dispatch), // Controlled by Dispatch availability
        .rs1_p_o(ren_rs1_p),
        .rs2_p_o(ren_rs2_p),
        .rd_new_p_o(ren_rd_new_p),
        .rd_old_p_o(ren_rd_old_p),
        .rob_tag_o(ren_rob_tag),
        // Feedback from ROB (Stubbed for now)
        .rob_commit_free_valid_i(1'b0),
        .rob_commit_free_preg_i('0),
        .recover_i(1'b0) 
    );

    // ==========================================
    // PACKAGING FOR DISPATCH
    // ==========================================
    // Combine the output of Rename logic with the pipelined Decode signals
    always_comb begin
        dispatch_pkt.pc          = dec_pc_q;
        dispatch_pkt.imm         = dec_imm_q;
        dispatch_pkt.alu_op      = dec_alu_op_q;
        dispatch_pkt.mem_read    = dec_mem_read_q;
        dispatch_pkt.mem_write   = dec_mem_write_q;
        dispatch_pkt.branch      = dec_branch_q;
        dispatch_pkt.jump        = dec_jump_q;
        // From Rename
        dispatch_pkt.rs1_phys    = ren_rs1_p;
        dispatch_pkt.rs2_phys    = ren_rs2_p;
        dispatch_pkt.rd_phys     = ren_rd_new_p;
        dispatch_pkt.old_rd_phys = ren_rd_old_p;
        dispatch_pkt.rob_tag     = ren_rob_tag;
        dispatch_pkt.rs1_ready   = 1'b0; // STUB: Needs RAT lookup for readiness
        dispatch_pkt.rs2_ready   = 1'b0; // STUB
        dispatch_pkt.rd_log      = 5'b0; // Should come from pipeline reg
    end

    // ==========================================
    // 4. DISPATCH STAGE
    // ==========================================
    dispatch dispatch_inst (
        .clk(clk),
        .rst(rst),
        .rename_valid_i(ren_valid_out),
        .rename_ready_o(disp_ready_from_dispatch),
        .rename_pkt_i(dispatch_pkt),
        // Connections to Execution (Stubs)
        .cdb_valid_i(1'b0),
        .cdb_tag_i('0),
        .alu_issue_valid_o(),
        .alu_issue_pkt_o(),
        .alu_ready_i(1'b1) // Always ready for test
    );

endmodule