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
    // Commit / recovery wires (need early for redirect/gating)
    // ----------------------------
    logic        commit_valid;
    logic [5:0]  commit_old_preg;
    logic        commit_mispredict;
    logic [31:0] commit_target_pc_o;
    logic [ROB_TAG_W-1:0] commit_tag_recovery;

    // Redirect to fetch
    logic        redirect_valid;
    logic [31:0] redirect_pc;

    assign redirect_valid = commit_mispredict;
    assign redirect_pc    = commit_target_pc_o;

    // 1-cycle squash after redirect (recommended if skid buffer has no flush)
    logic squash_frontend;
    always_ff @(posedge clk) begin
        if (reset) squash_frontend <= 1'b0;
        else       squash_frontend <= commit_mispredict; // squash next cycle
    end

    // ----------------------------
    // I-Cache <-> Fetch
    // ----------------------------
    logic [ADDR_WIDTH-1:0] icache_addr;
    logic [DATA_WIDTH-1:0] icache_rdata;
    logic                  fetch_valid;
    logic                  fetch_ready;
    logic [31:0]           fetch_pc;
    logic [31:0]           fetch_inst;

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
        .clk               (clk),
        .reset             (reset),

        .redirect_valid_i  (redirect_valid),
        .redirect_pc_i     (redirect_pc),

        .icache_addr       (icache_addr),
        .icache_rdata      (icache_rdata),

        .valid_o           (fetch_valid),
        .ready_i           (fetch_ready),
        .pc_o              (fetch_pc),
        .inst_o            (fetch_inst)
    );

    // ----------------------------
    // Fetch → Decode skid buffer
    // ----------------------------
    fetch_dec_t            fetch_data_in;
    fetch_dec_t            fetch_data_out;
    logic [FD_WIDTH-1:0]   fetch_data_in_bits;
    logic [FD_WIDTH-1:0]   fetch_data_out_bits;

    logic dec_valid;
    logic dec_ready;

    always_comb begin
        fetch_data_in.pc   = fetch_pc;
        fetch_data_in.inst = fetch_inst;
    end

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

    // Gate decode->rename validity during/after redirect
    logic dec_valid_use;
    assign dec_valid_use = dec_valid && !commit_mispredict && !squash_frontend;

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

    Rename #(
        .N_LOG      (N_LOG),
        .N_PHYS     (N_PHYS),
        .N_CHECKPTS (8),
        .ROB_TAG_W  (ROB_TAG_W)
    ) u_rename (
        .clk                     (clk),
        .rst                     (reset),

        .dec_valid_i             (dec_valid_use),
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

        .rob_tag_o               (),

        .rob_commit_free_valid_i (commit_valid),
        .rob_commit_free_preg_i  (commit_old_preg),

        .recover_i               (commit_mispredict)
    );

    assign dec_ready = ren_ready;

    // Gate dispatch input on mispredict (prevents wrong-path enqueue)
    logic ren_valid_g;
    assign ren_valid_g = ren_valid && !commit_mispredict;

    // ----------------------------
    // ROB + CDB
    // ----------------------------
    logic                 rob_full;
    logic [ROB_TAG_W-1:0] rob_alloc_tag;
    logic                 rob_push;
    rob_entry_t           rob_entry;

    // Gate ROB push on mispredict (belt + suspenders)
    logic rob_push_to_rob;
    assign rob_push_to_rob = rob_push && !commit_mispredict;

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
    logic [31:0]          br_cdb_data;
    logic [5:0]           br_cdb_preg;

    logic                 cdb_valid;
    logic [31:0]          cdb_data;
    logic [5:0]           cdb_preg;
    logic [ROB_TAG_W-1:0] cdb_rob_tag;
    logic                 cdb_mispredict;
    logic [31:0]          cdb_target_pc;

    // ============================================================
    // 1-entry pending buffers per FU (prevents CDB DROPS)
    // ============================================================
    logic                 alu_pend_v;
    logic [31:0]          alu_pend_data;
    logic [5:0]           alu_pend_preg;
    logic [ROB_TAG_W-1:0] alu_pend_tag;

    logic                 lsu_pend_v;
    logic [31:0]          lsu_pend_data;
    logic [5:0]           lsu_pend_preg;
    logic [ROB_TAG_W-1:0] lsu_pend_tag;

    logic                 br_pend_v;
    logic [31:0]          br_pend_data;
    logic [5:0]           br_pend_preg;
    logic [ROB_TAG_W-1:0] br_pend_tag;
    logic                 br_pend_misp;
    logic [31:0]          br_pend_target_pc;   // ✅ NEW: carry target PC through pending buffer

    // Effective sources = pending if present else raw
    logic                 alu_src_v;
    logic [31:0]          alu_src_data;
    logic [5:0]           alu_src_preg;
    logic [ROB_TAG_W-1:0] alu_src_tag;

    logic                 lsu_src_v;
    logic [31:0]          lsu_src_data;
    logic [5:0]           lsu_src_preg;
    logic [ROB_TAG_W-1:0] lsu_src_tag;

    logic                 br_src_v;
    logic [31:0]          br_src_data;
    logic [5:0]           br_src_preg;
    logic [ROB_TAG_W-1:0] br_src_tag;
    logic                 br_src_misp;
    logic [31:0]          br_src_target_pc;     // ✅ NEW: effective target PC

    logic sel_br, sel_lsu, sel_alu;

    // Effective-source mapping
    always_comb begin
        alu_src_v    = alu_pend_v ? 1'b1 : alu_cdb_valid;
        alu_src_data = alu_pend_v ? alu_pend_data : alu_cdb_data;
        alu_src_preg = alu_pend_v ? alu_pend_preg : alu_cdb_preg;
        alu_src_tag  = alu_pend_v ? alu_pend_tag  : alu_cdb_tag;

        lsu_src_v    = lsu_pend_v ? 1'b1 : lsu_cdb_valid;
        lsu_src_data = lsu_pend_v ? lsu_pend_data : lsu_cdb_data;
        lsu_src_preg = lsu_pend_v ? lsu_pend_preg : lsu_cdb_preg;
        lsu_src_tag  = lsu_pend_v ? lsu_pend_tag  : lsu_cdb_tag;

        br_src_v        = br_pend_v ? 1'b1 : br_valid_o;
        br_src_data     = br_pend_v ? br_pend_data : br_cdb_data;
        br_src_preg     = br_pend_v ? br_pend_preg : br_cdb_preg;
        br_src_tag      = br_pend_v ? br_pend_tag  : br_rob_tag_o;
        br_src_misp     = br_pend_v ? br_pend_misp : br_mispredict_o;
        br_src_target_pc= br_pend_v ? br_pend_target_pc : br_target_addr_o; // ✅ NEW
    end

    // Choose one winner each cycle (priority BR > LSU > ALU)
    always_comb begin
        sel_br  = 1'b0;
        sel_lsu = 1'b0;
        sel_alu = 1'b0;

        if (br_src_v)       sel_br  = 1'b1;
        else if (lsu_src_v) sel_lsu = 1'b1;
        else if (alu_src_v) sel_alu = 1'b1;
    end

    // Drive the single global CDB
    always_comb begin
        cdb_valid      = 1'b0;
        cdb_data       = '0;
        cdb_preg       = '0;
        cdb_rob_tag    = '0;
        cdb_mispredict = 1'b0;
        cdb_target_pc  = '0;

        if (sel_br) begin
            cdb_valid      = 1'b1;
            cdb_data       = br_src_data;
            cdb_preg       = br_src_preg;
            cdb_rob_tag    = br_src_tag;
            cdb_mispredict = br_src_misp;
            cdb_target_pc  = br_src_target_pc;   // ✅ NEW: correct even when pending
        end else if (sel_lsu) begin
            cdb_valid      = 1'b1;
            cdb_data       = lsu_src_data;
            cdb_preg       = lsu_src_preg;
            cdb_rob_tag    = lsu_src_tag;
            cdb_mispredict = 1'b0;
            cdb_target_pc  = '0;
        end else if (sel_alu) begin
            cdb_valid      = 1'b1;
            cdb_data       = alu_src_data;
            cdb_preg       = alu_src_preg;
            cdb_rob_tag    = alu_src_tag;
            cdb_mispredict = 1'b0;
            cdb_target_pc  = '0;
        end
    end

    // Pending buffers: capture "losers" so no FU completion is lost
    always_ff @(posedge clk) begin
        if (reset) begin
            alu_pend_v <= 1'b0;
            lsu_pend_v <= 1'b0;
            br_pend_v  <= 1'b0;
            br_pend_target_pc <= '0;
        end else if (commit_mispredict) begin
            alu_pend_v <= 1'b0;
            lsu_pend_v <= 1'b0;
            br_pend_v  <= 1'b0;
            br_pend_target_pc <= '0;
        end else begin
            if (sel_alu && alu_pend_v) alu_pend_v <= 1'b0;
            if (sel_lsu && lsu_pend_v) lsu_pend_v <= 1'b0;
            if (sel_br  && br_pend_v ) br_pend_v  <= 1'b0;

            if (alu_cdb_valid && !alu_pend_v && !sel_alu) begin
                alu_pend_v    <= 1'b1;
                alu_pend_data <= alu_cdb_data;
                alu_pend_preg <= alu_cdb_preg;
                alu_pend_tag  <= alu_cdb_tag;
            end

            if (lsu_cdb_valid && !lsu_pend_v && !sel_lsu) begin
                lsu_pend_v    <= 1'b1;
                lsu_pend_data <= lsu_cdb_data;
                lsu_pend_preg <= lsu_cdb_preg;
                lsu_pend_tag  <= lsu_cdb_tag;
            end

            if (br_valid_o && !br_pend_v && !sel_br) begin
                br_pend_v        <= 1'b1;
                br_pend_data     <= br_cdb_data;
                br_pend_preg     <= br_cdb_preg;
                br_pend_tag      <= br_rob_tag_o;
                br_pend_misp     <= br_mispredict_o;
                br_pend_target_pc<= br_target_addr_o; // ✅ NEW
            end
        end
    end

    rob #(
        .ROB_DEPTH (ROB_DEPTH),
        .ROB_TAG_W (ROB_TAG_W)
    ) u_rob (
        .clk                     (clk),
        .rst                     (reset),

        .dispatch_valid_i        (rob_push_to_rob),   // ✅ gated
        .dispatch_entry_i        (rob_entry),
        .rob_full_o              (rob_full),
        .alloc_tag_o             (rob_alloc_tag),

        .cdb_valid_i             (cdb_valid),
        .cdb_tag_i               (cdb_rob_tag),
        .cdb_mispredict_i        (cdb_mispredict),
        .cdb_target_pc_i         (cdb_target_pc),

        .commit_target_pc_o      (commit_target_pc_o),
        .commit_valid_o          (commit_valid),
        .commit_old_preg_o       (commit_old_preg),
        .commit_mispredict_o     (commit_mispredict),
        .commit_tag_recovery_o   (commit_tag_recovery)
    );

    // ----------------------------
    // Physical Register File + Busy Bits
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

    logic [N_PHYS-1:0] phys_reg_busy;

    always_ff @(posedge clk) begin
        if (reset) begin
            phys_reg_busy <= '0;
        end else if (commit_mispredict) begin
            // If your Rename recovery logic rebuilds busy bits, handle here.
            // Otherwise leave as-is for now (many student designs do).
            phys_reg_busy <= phys_reg_busy;
        end else begin
            if (ren_valid && ren_ready && ren_payload.RegWrite) begin
                phys_reg_busy[rd_new_p] <= 1'b1;
            end

            if (cdb_valid && (cdb_preg != 6'd0)) begin
                phys_reg_busy[cdb_preg] <= 1'b0;
            end

            if (ren_valid && ren_ready && ren_payload.RegWrite &&
                cdb_valid && (cdb_preg != 6'd0) && (rd_new_p == cdb_preg)) begin
                phys_reg_busy[rd_new_p] <= 1'b1;
            end
        end
    end

    physical_reg_file #(
        .DATA_WIDTH (32),
        .NUM_REGS   (N_PHYS),
        .ADDR_WIDTH ($clog2(N_PHYS))
    ) u_prf (
        .clk            (clk),

        .raddr_alu_src1 (prf_raddr_alu_src1),
        .rdata_alu_src1 (prf_rdata_alu_src1),
        .raddr_alu_src2 (prf_raddr_alu_src2),
        .rdata_alu_src2 (prf_rdata_alu_src2),

        .raddr_br_src1  (prf_raddr_br_src1),
        .rdata_br_src1  (prf_rdata_br_src1),
        .raddr_br_src2  (prf_raddr_br_src2),
        .rdata_br_src2  (prf_rdata_br_src2),

        .raddr_lsu_src1 (prf_raddr_lsu_src1),
        .rdata_lsu_src1 (prf_rdata_lsu_src1),
        .raddr_lsu_src2 (prf_raddr_lsu_src2),
        .rdata_lsu_src2 (prf_rdata_lsu_src2),

        .wen            (prf_wen),
        .waddr          (prf_waddr),
        .wdata          (prf_wdata)
    );

    assign prf_wen   = cdb_valid && (cdb_preg != 6'd0);
    assign prf_waddr = cdb_preg;
    assign prf_wdata = cdb_data;

    // ----------------------------
    // Dispatch
    // ----------------------------
    rs_issue_packet_t issue_pkt;

    logic rs_alu_ready, rs_lsu_ready, rs_branch_ready;
    logic dispatch_alu_valid, dispatch_lsu_valid, dispatch_branch_valid;

    Dispatch u_dispatch (
        .clk                     (clk),
        .rst                     (reset),

        .ren_valid_i             (ren_valid_g), // ✅ gated
        .payload_i               (ren_payload),
        .rs1_p_i                 (rs1_p),
        .rs2_p_i                 (rs2_p),
        .rd_new_p_i              (rd_new_p),
        .rd_old_p_i              (rd_old_p),
        .ren_ready_o             (ren_ready),

        .rob_full_i              (rob_full),
        .rob_alloc_tag_i         (rob_alloc_tag),
        .rob_push_o              (rob_push),
        .rob_entry_o             (rob_entry),

        .rs_alu_ready_i          (rs_alu_ready),
        .rs_lsu_ready_i          (rs_lsu_ready),
        .rs_branch_ready_i       (rs_branch_ready),

        .dispatch_alu_valid_o    (dispatch_alu_valid),
        .dispatch_lsu_valid_o    (dispatch_lsu_valid),
        .dispatch_branch_valid_o (dispatch_branch_valid),
        .issue_pkt_o             (issue_pkt)
    );

    // ----------------------------
    // Used-aware "already-ready" signals
    // ----------------------------
    logic alu_src1_ready, alu_src2_ready;
    logic lsu_src1_ready, lsu_src2_ready;
    logic br_src1_ready,  br_src2_ready;

    assign alu_src1_ready = !phys_reg_busy[issue_pkt.rs1_p];
    assign alu_src2_ready = (issue_pkt.alu_src) ? 1'b1
                                                : !phys_reg_busy[issue_pkt.rs2_p];

    assign lsu_src1_ready = !phys_reg_busy[issue_pkt.rs1_p];
    assign lsu_src2_ready = (issue_pkt.mem_write) ? !phys_reg_busy[issue_pkt.rs2_p]
                                                  : 1'b1;

    assign br_src1_ready  = !phys_reg_busy[issue_pkt.rs1_p];
    assign br_src2_ready  = (issue_pkt.is_jump)   ? 1'b1
                         :  (issue_pkt.is_branch) ? !phys_reg_busy[issue_pkt.rs2_p]
                                                  : 1'b1;

    // ----------------------------
    // ALU RS + FU
    // ----------------------------
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

        .src1_already_ready_i (alu_src1_ready),
        .src2_already_ready_i (alu_src2_ready),

        .full                 (rs_alu_full),

        .cdb_valid            (cdb_valid),
        .cdb_tag              (cdb_preg),

        .issue_ready          (alu_ready),
        .issue_valid          (alu_issue_valid),
        .issue_data           (alu_issue_entry)
    );

    assign rs_alu_ready = !rs_alu_full;

    // backpressure ALU if it already has a pending completion
    assign alu_ready    = !alu_pend_v;

    assign prf_raddr_alu_src1 = alu_issue_entry.p_src1;
    assign prf_raddr_alu_src2 = alu_issue_entry.p_src2;

    logic [31:0] alu_op1, alu_op2;
    assign alu_op1 = prf_rdata_alu_src1;
    assign alu_op2 = (alu_issue_entry.alu_src) ? alu_issue_entry.imm
                                               : prf_rdata_alu_src2;

    logic alu_fire;
    assign alu_fire = alu_issue_valid && alu_ready;

    alu_unit #(
        .ROB_TAG_W(ROB_TAG_W)
    ) u_alu (
        .clk        (clk),
        .rst        (reset),
        .valid_i    (alu_fire),
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

    // ----------------------------
    // LSU RS + FU
    // ----------------------------
    rs_entry_t lsu_issue_entry;
    logic      rs_lsu_full;
    logic      lsu_issue_valid;

    logic      lsu_ready;        // to RS
    logic      lsu_ready_unit;   // from LSU

    reservation_station #(
        .NUM_SLOTS (8),
        .N_PHYS    (N_PHYS)
    ) u_rs_lsu (
        .clk                  (clk),
        .reset                (reset),

        .write_en             (dispatch_lsu_valid),
        .write_data           (issue_pkt),

        .src1_already_ready_i (lsu_src1_ready),
        .src2_already_ready_i (lsu_src2_ready),

        .full                 (rs_lsu_full),

        .cdb_valid            (cdb_valid),
        .cdb_tag              (cdb_preg),

        .issue_ready          (lsu_ready),
        .issue_valid          (lsu_issue_valid),
        .issue_data           (lsu_issue_entry)
    );

    assign rs_lsu_ready = !rs_lsu_full;

    assign lsu_ready = lsu_ready_unit && !lsu_pend_v;

    assign prf_raddr_lsu_src1 = lsu_issue_entry.p_src1;
    assign prf_raddr_lsu_src2 = lsu_issue_entry.p_src2;

    logic [31:0] lsu_base, lsu_imm;
    assign lsu_base = prf_rdata_lsu_src1;
    assign lsu_imm  = lsu_issue_entry.imm;

    logic lsu_fire;
    assign lsu_fire = lsu_issue_valid && lsu_ready;

    lsu_unit #(
        .ROB_TAG_W(ROB_TAG_W)
    ) u_lsu (
        .clk         (clk),
        .rst         (reset),

        .valid_i     (lsu_fire),

        .mem_read_i  (lsu_issue_entry.mem_read),
        .mem_write_i (lsu_issue_entry.mem_write),

        .rs1_val_i   (lsu_base),
        .rs2_val_i   (prf_rdata_lsu_src2),
        .imm_i       (lsu_imm),

        .rd_p_i      (lsu_issue_entry.p_dst),
        .rob_tag_i   (lsu_issue_entry.rob_tag),

        .funct3_i    (lsu_issue_entry.funct3),

        .ready_o     (lsu_ready_unit),

        .valid_o     (lsu_cdb_valid),
        .result_o    (lsu_cdb_data),
        .rd_p_o      (lsu_cdb_preg),
        .rob_tag_o   (lsu_cdb_tag)
    );

    // ----------------------------
    // Branch RS + FU
    // ----------------------------
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

        .src1_already_ready_i (br_src1_ready),
        .src2_already_ready_i (br_src2_ready),

        .full                 (rs_branch_full),

        .cdb_valid            (cdb_valid),
        .cdb_tag              (cdb_preg),

        .issue_ready          (br_ready),
        .issue_valid          (br_issue_valid),
        .issue_data           (br_issue_entry)
    );

    assign rs_branch_ready = !rs_branch_full;

    assign br_ready        = !br_pend_v;

    assign prf_raddr_br_src1 = br_issue_entry.p_src1;
    assign prf_raddr_br_src2 = br_issue_entry.p_src2;

    logic [31:0] br_rs1_val, br_rs2_val;
    assign br_rs1_val = prf_rdata_br_src1;
    assign br_rs2_val = prf_rdata_br_src2;

    logic br_fire;
    assign br_fire = br_issue_valid && br_ready;

    branch_unit #(
        .ROB_TAG_W(ROB_TAG_W)
    ) u_branch (
        .clk            (clk),
        .rst            (reset),
        .valid_i        (br_fire),

        .pc_i           (br_issue_entry.pc),
        .imm_i          (br_issue_entry.imm),
        .rs1_val_i      (br_rs1_val),
        .rs2_val_i      (br_rs2_val),

        .is_branch_i    (br_issue_entry.is_branch),
        .is_jump_i      (br_issue_entry.is_jump),
        .pred_taken_i   (1'b0),
        .rob_tag_i      (br_issue_entry.rob_tag),

        .rd_p_i         (br_issue_entry.p_dst),

        .valid_o        (br_valid_o),
        .rob_tag_o      (br_rob_tag_o),
        .mispredict_o   (br_mispredict_o),
        .target_addr_o  (br_target_addr_o),
        .actual_taken_o (br_taken_o),

        .result_o       (br_cdb_data),
        .rd_p_o         (br_cdb_preg)
    );

    // ----------------------------
    // Front-end outputs (still from Decode)
    // ----------------------------
    assign fe_valid_o    = dec_valid_use;
    assign fe_pc_o       = fetch_data_out.pc;

    assign fe_rs1_o      = rs1;
    assign fe_rs2_o      = rs2;
    assign fe_rd_o       = rd;
    assign fe_imm_o      = imm;
    assign fe_ALUSrc_o   = ALUSrc;
    assign fe_ALUOp_o    = ALUOp;
    assign fe_branch_o   = branch;
    assign fe_jump_o     = jump;
    assign fe_MemRead_o  = MemRead;
    assign fe_MemWrite_o = MemWrite;
    assign fe_RegWrite_o = RegWrite;
    assign fe_MemToReg_o = MemToReg;

endmodule