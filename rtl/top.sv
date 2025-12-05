import pipeline_types::*;

module RISCV #(
    parameter int ADDR_WIDTH = 9,
    parameter int DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic reset,

    // Front-end interface (still driven from Decode for now)
    output logic        fe_valid_o,
    input  logic        fe_ready_i,   // currently unused internally

    // PC going into next stage
    output logic [31:0] fe_pc_o,

    // decoded outputs to rename (logical view)
    output logic [4:0]  fe_rs1_o,
    output logic [4:0]  fe_rs2_o,
    output logic [4:0]  fe_rd_o,
    output logic [31:0] fe_imm_o,
    output logic        fe_ALUSrc_o,
    output logic [2:0]  fe_ALUOp_o,
    output logic        fe_branch_o,
    output logic        fe_jump_o,
    output logic        fe_MemRead_o,
    output logic        fe_MemWrite_o,
    output logic        fe_RegWrite_o,
    output logic        fe_MemToReg_o
);

    // ----------------------------
    // Local parameters
    // ----------------------------
    localparam int FD_WIDTH   = $bits(fetch_dec_t);
    localparam int N_LOG      = 32;
    localparam int N_PHYS     = 64;
    localparam int ROB_DEPTH  = 16;
    localparam int ROB_TAG_W  = $clog2(ROB_DEPTH); // = 4

    // ----------------------------
    // I-Cache <-> Fetch
    // ----------------------------
    logic [ADDR_WIDTH-1:0] icache_addr;
    logic [DATA_WIDTH-1:0] icache_rdata;
    logic        fetch_valid;
    logic        fetch_ready;
    logic [31:0] fetch_pc;
    logic [31:0] fetch_inst;

    iCache #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_icache (
        .clk   (clk),
        .addr  (icache_addr),
        .rdata (icache_rdata)
    );

    Fetch #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .RESET_PC   (32'h0000_0000)
    ) u_fetch (
        .clk          (clk),
        .reset        (reset),

        .icache_addr  (icache_addr),
        .icache_rdata (icache_rdata),

        .valid_o      (fetch_valid),
        .ready_i      (fetch_ready),
        .pc_o         (fetch_pc),
        .inst_o       (fetch_inst)
    );

    // ----------------------------
    // Fetch → Decode skid buffer (struct packed into bits)
    // ----------------------------
    fetch_dec_t            fetch_data_in;
    fetch_dec_t            fetch_data_out;
    logic [FD_WIDTH-1:0]   fetch_data_in_bits;
    logic [FD_WIDTH-1:0]   fetch_data_out_bits;

    logic dec_valid;
    logic dec_ready;   // driven later by Rename/Dispatch

    // Build struct from Fetch outputs
    always_comb begin
        fetch_data_in.pc    = fetch_pc;
        fetch_data_in.inst  = fetch_inst;
    end

    // Pack/unpack struct <-> bit-vectors
    assign fetch_data_in_bits  = fetch_data_in;
    assign fetch_data_out      = fetch_dec_t'(fetch_data_out_bits);

    skid_buffer_struct #(
        .WIDTH(FD_WIDTH)
    ) u_skid_fd (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (fetch_valid),
        .ready_in  (fetch_ready),
        .data_in   (fetch_data_in_bits),
        .valid_out (dec_valid),
        .ready_out (dec_ready),
        .data_out  (fetch_data_out_bits)
    );

    // ----------------------------
    // Decode
    // ----------------------------
    logic [4:0]  rs1, rs2, rd;
    logic [31:0] imm;
    logic        ALUSrc;
    logic [2:0]  ALUOp;
    logic        branch, jump;
    logic        MemRead, MemWrite;
    logic        RegWrite, MemToReg;
    logic        rs1_valid, rs2_valid;
    ctrl_payload_t dec_payload;

    decode u_decode (
        .inst           (fetch_data_out.inst),
        .pc             (fetch_data_out.pc),

        .rs1            (rs1),
        .rs2            (rs2),
        .rd             (rd),
        .rs1_valid      (rs1_valid),
        .rs2_valid      (rs2_valid),
        .ctrl_payload_o (dec_payload),

        .imm            (imm),

        .ALUSrc         (ALUSrc),
        .ALUOp          (ALUOp),
        .branch         (branch),
        .jump           (jump),
        .MemRead        (MemRead),
        .MemWrite       (MemWrite),
        .RegWrite       (RegWrite),
        .MemToReg       (MemToReg)
    );

    // ----------------------------
    // Rename
    // ----------------------------
    logic          ren_valid;
    logic          ren_ready;
    logic [5:0]    rs1_p, rs2_p, rd_new_p, rd_old_p;
    ctrl_payload_t ren_payload;

    // ROB commit feedback to Rename
    logic                  commit_valid;
    logic [5:0]            commit_old_preg;
    logic                  commit_mispredict;
    logic [ROB_TAG_W-1:0]  commit_tag_recovery; // not used yet

    Rename #(
        .N_LOG      (N_LOG),
        .N_PHYS     (N_PHYS),
        .N_CHECKPTS (8),
        .ROB_TAG_W  (ROB_TAG_W)
    ) u_rename (
        .clk                     (clk),
        .rst                     (reset),

        .dec_valid_i             (dec_valid),
        .dec_rs1_i               (rs1),
        .dec_rs2_i               (rs2),
        .dec_rd_i                (rd),
        .dec_rs1_used_i          (rs1_valid),
        .dec_rs2_used_i          (rs2_valid),
        .dec_rd_used_i           (RegWrite),
        .dec_is_branch_i         (branch),

        .payload_i               (dec_payload),
        .payload_o               (ren_payload),

        .ren_valid_o             (ren_valid),
        .ren_ready_i             (ren_ready),

        .rs1_p_o                 (rs1_p),
        .rs2_p_o                 (rs2_p),
        .rd_new_p_o              (rd_new_p),
        .rd_old_p_o              (rd_old_p),

        .rob_tag_o               (),   // Dispatcher uses ROB's alloc_tag

        .rob_commit_free_valid_i (commit_valid),
        .rob_commit_free_preg_i  (commit_old_preg),

        .recover_i               (1'b0)
    );

    // Decode ready comes from Rename/Dispatch
    assign dec_ready = ren_ready;

    // ----------------------------
    // ROB + CDB stub
    // ----------------------------
    logic                 rob_full;
    logic [ROB_TAG_W-1:0] rob_alloc_tag;
    logic                 rob_push;
    rob_entry_t           rob_entry;

    // For now, no real execution/CDB; stubbed
    logic                 cdb_valid;
    logic [ROB_TAG_W-1:0] cdb_tag;
    logic                 cdb_mispredict;

    assign cdb_valid      = 1'b0;
    assign cdb_tag        = '0;
    assign cdb_mispredict = 1'b0;

    rob #(
        .ROB_DEPTH (ROB_DEPTH),
        .ROB_TAG_W (ROB_TAG_W)
    ) u_rob (
        .clk                     (clk),
        .rst                     (reset),

        .dispatch_valid_i        (rob_push),
        .dispatch_entry_i        (rob_entry),
        .rob_full_o              (rob_full),
        .alloc_tag_o             (rob_alloc_tag),

        .cdb_valid_i             (cdb_valid),
        .cdb_tag_i               (cdb_tag),
        .cdb_mispredict_i        (cdb_mispredict),

        .commit_valid_o          (commit_valid),
        .commit_old_preg_o       (commit_old_preg),
        .commit_mispredict_o     (commit_mispredict),
        .commit_tag_recovery_o   (commit_tag_recovery)
    );

    // ----------------------------
    // Dispatch (between Rename and ROB/RS)
    // ----------------------------
    rs_issue_packet_t issue_pkt;

    // Stub: all reservation stations always ready
    logic rs_alu_ready;
    logic rs_lsu_ready;
    logic rs_branch_ready;

    assign rs_alu_ready    = 1'b1;
    assign rs_lsu_ready    = 1'b1;
    assign rs_branch_ready = 1'b1;

    logic dispatch_alu_valid;
    logic dispatch_lsu_valid;
    logic dispatch_branch_valid;

    Dispatch u_dispatch (
        .clk                     (clk),
        .rst                     (reset),

        // From Rename
        .ren_valid_i             (ren_valid),
        .payload_i               (ren_payload),
        .rs1_p_i                 (rs1_p),
        .rs2_p_i                 (rs2_p),
        .rd_new_p_i              (rd_new_p),
        .rd_old_p_i              (rd_old_p),
        .ren_ready_o             (ren_ready),

        // From ROB
        .rob_full_i              (rob_full),
        .rob_alloc_tag_i         (rob_alloc_tag),
        .rob_push_o              (rob_push),
        .rob_entry_o             (rob_entry),

        // From RS (ready)
        .rs_alu_ready_i          (rs_alu_ready),
        .rs_lsu_ready_i          (rs_lsu_ready),
        .rs_branch_ready_i       (rs_branch_ready),

        // To RS (issue)
        .dispatch_alu_valid_o    (dispatch_alu_valid),
        .dispatch_lsu_valid_o    (dispatch_lsu_valid),
        .dispatch_branch_valid_o (dispatch_branch_valid),
        .issue_pkt_o             (issue_pkt)
    );

    // ----------------------------
    // Front-end outputs (still from Decode)
    // ----------------------------
    assign fe_valid_o   = dec_valid;              // front-end "has instruction"
    assign fe_pc_o      = fetch_data_out.pc;

    assign fe_rs1_o     = rs1;
    assign fe_rs2_o     = rs2;
    assign fe_rd_o      = rd;
    assign fe_imm_o     = imm;
    assign fe_ALUSrc_o  = ALUSrc;
    assign fe_ALUOp_o   = ALUOp;
    assign fe_branch_o  = branch;
    assign fe_jump_o    = jump;
    assign fe_MemRead_o = MemRead;
    assign fe_MemWrite_o= MemWrite;
    assign fe_RegWrite_o= RegWrite;
    assign fe_MemToReg_o= MemToReg;

    // NOTE: fe_ready_i is currently not used to backpressure the FE.
    // Decode/FETCH backpressure is driven purely by Rename/Dispatch via dec_ready.

endmodule