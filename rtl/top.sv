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
        // fetch_data_in.valid is unused for now
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

        .rob_tag_o               (),   // Dispatcher uses ROB's alloc_tag instead

        .rob_commit_free_valid_i (commit_valid),
        .rob_commit_free_preg_i  (commit_old_preg),

        .recover_i               (1'b0) // hook this up to commit_mispredict later
    );

    // Decode ready comes from Rename/Dispatch
    assign dec_ready = ren_ready;

    // ----------------------------
    // ROB + CDB
    // ----------------------------
    logic                 rob_full;
    logic [ROB_TAG_W-1:0] rob_alloc_tag;
    logic                 rob_push;
    rob_entry_t           rob_entry;

    // CDB from FUs
    logic                 alu_cdb_valid;
    logic [31:0]          alu_cdb_data;
    logic [5:0]           alu_cdb_preg;
    logic [ROB_TAG_W-1:0] alu_cdb_tag;

    logic                 lsu_cdb_valid;
    logic [31:0]          lsu_cdb_data;
    logic [5:0]           lsu_cdb_preg;
    logic [ROB_TAG_W-1:0] lsu_cdb_tag;

    logic                 br_valid_o;
    logic [ROB_TAG_W-1:0] br_rob_tag_o;
    logic                 br_mispredict_o;
    logic [31:0]          br_target_addr_o;
    logic                 br_taken_o;

    // Global CDB signals
    logic                 cdb_valid;
    logic [31:0]          cdb_data;
    logic [5:0]           cdb_preg;
    logic [ROB_TAG_W-1:0] cdb_rob_tag;
    logic                 cdb_mispredict;

    // Simple priority: Branch > LSU > ALU
    always_comb begin
        // defaults
        cdb_valid      = 1'b0;
        cdb_data       = '0;
        cdb_preg       = '0;
        cdb_rob_tag    = '0;
        cdb_mispredict = 1'b0;

        if (br_valid_o) begin
            cdb_valid      = 1'b1;
            cdb_rob_tag    = br_rob_tag_o;
            cdb_mispredict = br_mispredict_o;
        end
        else if (lsu_cdb_valid) begin
            cdb_valid      = 1'b1;
            cdb_data       = lsu_cdb_data;
            cdb_preg       = lsu_cdb_preg;
            cdb_rob_tag    = lsu_cdb_tag;
            cdb_mispredict = 1'b0;
        end
        else if (alu_cdb_valid) begin
            cdb_valid      = 1'b1;
            cdb_data       = alu_cdb_data;
            cdb_preg       = alu_cdb_preg;
            cdb_rob_tag    = alu_cdb_tag;
            cdb_mispredict = 1'b0;
        end
    end

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
        .cdb_tag_i               (cdb_rob_tag),
        .cdb_mispredict_i        (cdb_mispredict),

        .commit_valid_o          (commit_valid),
        .commit_old_preg_o       (commit_old_preg),
        .commit_mispredict_o     (commit_mispredict),
        .commit_tag_recovery_o   (commit_tag_recovery)
    );

    // ----------------------------
    // Physical Register File
    // ----------------------------
    logic [5:0]  prf_raddr_alu_src1, prf_raddr_alu_src2;
    logic [5:0]  prf_raddr_br_src1,  prf_raddr_br_src2;
    logic [5:0]  prf_raddr_lsu_src1, prf_raddr_lsu_src2;

    logic [31:0] prf_rdata_alu_src1, prf_rdata_alu_src2;
    logic [31:0] prf_rdata_br_src1,  prf_rdata_br_src2;
    logic [31:0] prf_rdata_lsu_src1, prf_rdata_lsu_src2;

    logic        prf_wen;
    logic [5:0]  prf_waddr;
    logic [31:0] prf_wdata;

    physical_reg_file #(
        .DATA_WIDTH (32),
        .NUM_REGS   (N_PHYS),
        .ADDR_WIDTH ($clog2(N_PHYS))
    ) u_prf (
        .clk            (clk),

        // ALU reads
        .raddr_alu_src1 (prf_raddr_alu_src1),
        .rdata_alu_src1 (prf_rdata_alu_src1),
        .raddr_alu_src2 (prf_raddr_alu_src2),
        .rdata_alu_src2 (prf_rdata_alu_src2),

        // Branch reads
        .raddr_br_src1  (prf_raddr_br_src1),
        .rdata_br_src1  (prf_rdata_br_src1),
        .raddr_br_src2  (prf_raddr_br_src2),
        .rdata_br_src2  (prf_rdata_br_src2),

        // LSU reads
        .raddr_lsu_src1 (prf_raddr_lsu_src1),
        .rdata_lsu_src1 (prf_rdata_lsu_src1),
        .raddr_lsu_src2 (prf_raddr_lsu_src2),
        .rdata_lsu_src2 (prf_rdata_lsu_src2),

        // Writeback from CDB
        .wen            (prf_wen),
        .waddr          (prf_waddr),
        .wdata          (prf_wdata)
    );

    // PRF write-back from CDB
    assign prf_wen   = cdb_valid && (cdb_preg != 6'd0);  // never write phys0
    assign prf_waddr = cdb_preg;
    assign prf_wdata = cdb_data;

    // ----------------------------
    // Dispatch (between Rename and ROB/RS)
    // ----------------------------
    rs_issue_packet_t issue_pkt;

    // Reservation station ready inputs (from RS)
    logic rs_alu_ready;
    logic rs_lsu_ready;
    logic rs_branch_ready;

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
    // Reservation Stations + FUs
    // ----------------------------

    // ---- ALU RS + FU ----
    rs_entry_t alu_issue_entry;
    logic      rs_alu_full;
    logic      alu_issue_valid;
    logic      alu_ready;

    reservation_station #(
        .NUM_SLOTS (8),
        .N_PHYS    (N_PHYS)
    ) u_rs_alu (
        .clk                  (clk),
        .reset                (reset),

        .write_en             (dispatch_alu_valid),
        .write_data           (issue_pkt),

        .src1_already_ready_i (1'b1), // no busy-bit tracking yet
        .src2_already_ready_i (1'b1),

        .full                 (rs_alu_full),

        .cdb_valid            (cdb_valid),
        .cdb_tag              (cdb_preg),

        .issue_ready          (alu_ready),
        .issue_valid          (alu_issue_valid),
        .issue_data           (alu_issue_entry)
    );

    assign rs_alu_ready = !rs_alu_full;
    assign alu_ready    = 1'b1;  // ALU can always accept one per cycle

    // ALU PRF read addresses / operands
    assign prf_raddr_alu_src1 = alu_issue_entry.p_src1;
    assign prf_raddr_alu_src2 = alu_issue_entry.p_src2;

    logic [31:0] alu_op1, alu_op2;
    assign alu_op1 = prf_rdata_alu_src1;
    assign alu_op2 = (alu_issue_entry.alu_src)
                     ? alu_issue_entry.imm
                     : prf_rdata_alu_src2;
	always_ff @(posedge clk) begin
    if (alu_issue_valid) begin
        $display("[ALU DBG] t=%0t pc=%08h rs1_p=%0d rs2_p=%0d  op1=%08h op2=%08h  alu_src=%0b imm=%08h alu_op=%0d",
                 $time,
                 alu_issue_entry.pc,
                 alu_issue_entry.p_src1,
                 alu_issue_entry.p_src2,
                 alu_op1,
                 alu_op2,
                 alu_issue_entry.alu_src,
                 alu_issue_entry.imm,
                 alu_issue_entry.alu_op);
    end
	end

    alu_unit #(
        .ROB_TAG_W(ROB_TAG_W)
    ) u_alu (
        .clk        (clk),
        .rst        (reset),
        .valid_i    (alu_issue_valid),
        .alu_op_i   (alu_issue_entry.alu_op),
        .op1_i      (alu_op1),
        .op2_i      (alu_op2),
        .rd_p_i     (alu_issue_entry.p_dst),
        .rob_tag_i  (alu_issue_entry.rob_tag),

        .valid_o    (alu_cdb_valid),
        .result_o   (alu_cdb_data),
        .rd_p_o     (alu_cdb_preg),
        .rob_tag_o  (alu_cdb_tag)
    );

    // ---- LSU RS + FU ----
    rs_entry_t lsu_issue_entry;
    logic      rs_lsu_full;
    logic      lsu_issue_valid;
    logic      lsu_ready;

    reservation_station #(
        .NUM_SLOTS (8),
        .N_PHYS    (N_PHYS)
    ) u_rs_lsu (
        .clk                  (clk),
        .reset                (reset),

        .write_en             (dispatch_lsu_valid),
        .write_data           (issue_pkt),

        .src1_already_ready_i (1'b1),
        .src2_already_ready_i (1'b1),

        .full                 (rs_lsu_full),

        .cdb_valid            (cdb_valid),
        .cdb_tag              (cdb_preg),

        .issue_ready          (lsu_ready),
        .issue_valid          (lsu_issue_valid),
        .issue_data           (lsu_issue_entry)
    );

    assign rs_lsu_ready = !rs_lsu_full;

    // LSU operands from PRF
    assign prf_raddr_lsu_src1 = lsu_issue_entry.p_src1;
    assign prf_raddr_lsu_src2 = lsu_issue_entry.p_src2; // for stores later

    logic [31:0] lsu_base, lsu_imm;
    assign lsu_base = prf_rdata_lsu_src1;
    assign lsu_imm  = lsu_issue_entry.imm;

    lsu_unit #(
        .ROB_TAG_W(ROB_TAG_W)
    ) u_lsu (
        .clk         (clk),
        .rst         (reset),
        .valid_i     (lsu_issue_valid),
        .mem_read_i  (lsu_issue_entry.mem_read),
        .rs1_val_i   (lsu_base),
        .imm_i       (lsu_imm),
        .rd_p_i      (lsu_issue_entry.p_dst),
        .rob_tag_i   (lsu_issue_entry.rob_tag),

        .ready_o     (lsu_ready),

        .valid_o     (lsu_cdb_valid),
        .result_o    (lsu_cdb_data),
        .rd_p_o      (lsu_cdb_preg),
        .rob_tag_o   (lsu_cdb_tag)
    );

    // ---- Branch RS + FU ----
    rs_entry_t br_issue_entry;
    logic      rs_branch_full;
    logic      br_issue_valid;
    logic      br_ready;

    reservation_station #(
        .NUM_SLOTS (4),
        .N_PHYS    (N_PHYS)
    ) u_rs_branch (
        .clk                  (clk),
        .reset                (reset),

        .write_en             (dispatch_branch_valid),
        .write_data           (issue_pkt),

        .src1_already_ready_i (1'b1),
        .src2_already_ready_i (1'b1),

        .full                 (rs_branch_full),

        .cdb_valid            (cdb_valid),
        .cdb_tag              (cdb_preg),

        .issue_ready          (br_ready),
        .issue_valid          (br_issue_valid),
        .issue_data           (br_issue_entry)
    );

    assign rs_branch_ready = !rs_branch_full;
    assign br_ready        = 1'b1;  // simple 1-cycle branch unit

    // Branch operands from PRF
    assign prf_raddr_br_src1 = br_issue_entry.p_src1;
    assign prf_raddr_br_src2 = br_issue_entry.p_src2;

    logic [31:0] br_rs1_val, br_rs2_val;
    assign br_rs1_val = prf_rdata_br_src1;
    assign br_rs2_val = prf_rdata_br_src2;

    branch_unit #(
        .ROB_TAG_W(ROB_TAG_W)
    ) u_branch (
        .clk            (clk),
        .rst            (reset),
        .valid_i        (br_issue_valid),
        .pc_i           (br_issue_entry.pc),
        .imm_i          (br_issue_entry.imm),
        .rs1_val_i      (br_rs1_val),
        .rs2_val_i      (br_rs2_val),
        .is_branch_i    (br_issue_entry.is_branch),
        .is_jump_i      (br_issue_entry.is_jump),
        .pred_taken_i   (1'b0),               // static not-taken for now
        .rob_tag_i      (br_issue_entry.rob_tag),

        .valid_o        (br_valid_o),
        .rob_tag_o      (br_rob_tag_o),
        .mispredict_o   (br_mispredict_o),
        .target_addr_o  (br_target_addr_o),
        .actual_taken_o (br_taken_o)
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