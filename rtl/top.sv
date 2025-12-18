// 1. Include the package FIRST so types are defined
`include "pipeline_types.sv"  

// 2. Include all your submodules
`include "iCache.sv"
`include "fetch.sv"
`include "skid_buffer.sv"
`include "decode.sv"
`include "rename.sv"
`include "rob.sv"
`include "physical_reg_file.sv"
`include "dispatch.sv"
`include "Reservation_Station.sv"
`include "alu_unit.sv"
`include "lsu_unit.sv"
`include "branch_unit.sv"
`include "priority_decoder.sv"

// 1. Include the package FIRST so types are defined


import pipeline_types::*;

module RISCV #(
    parameter int ADDR_WIDTH = 9,
    parameter int DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic reset,

    // Front-end interface (For TB/Visualization)
    output logic        fe_valid_o,
    input  logic        fe_ready_i,

    // PC going into next stage
    output logic [31:0] fe_pc_o,

    // Decoded outputs (logical view)
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
    localparam int ROB_TAG_W  = $clog2(ROB_DEPTH); // 4

    // ----------------------------
    // Wires & Interconnects
    // ----------------------------
    logic [4:0] rob_count;         
    logic       rob_commit_is_branch; 
    
    logic [ADDR_WIDTH-1:0] icache_addr;
    logic [DATA_WIDTH-1:0] icache_rdata;
    logic        fetch_valid;
    logic        fetch_ready;
    logic [31:0] fetch_pc;
    logic [31:0] fetch_inst;
    logic        redirect_valid;
    logic [31:0] redirect_pc;

    fetch_dec_t          fetch_data_in;
    fetch_dec_t          fetch_data_out;
    logic [FD_WIDTH-1:0] fetch_data_in_bits;
    logic [FD_WIDTH-1:0] fetch_data_out_bits;
    logic                dec_valid;
    logic                dec_ready;
    logic                flush_pipeline;

    logic [4:0]  rs1, rs2, rd;
    logic [31:0] imm;
    logic        ALUSrc;
    logic [2:0]  ALUOp;
    logic        branch, jump;
    logic        MemRead, MemWrite;
    logic        RegWrite, MemToReg;
    logic        rs1_valid, rs2_valid;
    ctrl_payload_t dec_payload;

    logic          ren_valid;
    logic          ren_ready;
    logic [5:0]    rs1_p, rs2_p, rd_new_p, rd_old_p;
    ctrl_payload_t ren_payload;
    logic          commit_valid;
    logic [5:0]    commit_old_preg;
    logic          commit_mispredict;
    logic [ROB_TAG_W-1:0] commit_tag_recovery;

    logic                 rob_full;
    logic [ROB_TAG_W-1:0] rob_alloc_tag;
    logic                 rob_push;
    rob_entry_t           rob_entry;

    logic [31:0]          br_result_o;
    logic [5:0]           br_dest_preg;
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
    logic                 cdb_valid;
    logic [31:0]          cdb_data;
    logic [5:0]           cdb_preg;
    logic [ROB_TAG_W-1:0] cdb_rob_tag;
    logic                 cdb_mispredict;

    // Handshake Signal for ALU
    logic                 alu_cdb_grant;

    // ----------------------------
    // Module Instantiations
    // ----------------------------

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
        .clk              (clk),
        .reset            (reset),
        // .redirect_valid_i (redirect_valid),
        // .redirect_pc_i    (redirect_pc),
        .redirect_valid_i (redirect_valid),
        .redirect_pc_i    (redirect_pc),
        .icache_addr      (icache_addr),
        .icache_rdata     (icache_rdata),
        .valid_o          (fetch_valid),
        .ready_i          (fetch_ready),
        .pc_o             (fetch_pc),
        .inst_o           (fetch_inst)
    );

    always_comb begin
        fetch_data_in.pc   = fetch_pc;
        fetch_data_in.inst = fetch_inst;
    end
    assign fetch_data_in_bits = fetch_data_in;
    assign fetch_data_out     = fetch_dec_t'(fetch_data_out_bits);

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
        .data_out  (fetch_data_out_bits),
        .flush_i   (flush_pipeline)
    );

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
        .dec_is_jump_i           (jump),
        .rob_count_i             (rob_count),
        .rob_commit_is_branch_jump_i (rob_commit_is_branch),
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
        .recover_i               (flush_pipeline)
    );

    assign dec_ready = ren_ready;

    // Flush Logic
    assign flush_pipeline = br_valid_o && br_mispredict_o;
    assign redirect_valid = flush_pipeline;
    assign redirect_pc    = br_target_addr_o;

    // CDB Arbiter
    // Priority: Branch > LSU > ALU
    always_comb begin
        cdb_valid      = 1'b0;
        cdb_data       = '0;
        cdb_preg       = '0;
        cdb_rob_tag    = '0;
        cdb_mispredict = 1'b0;
        alu_cdb_grant  = 1'b0; // Default: ALU waits

        if (br_valid_o) begin
            cdb_valid      = 1'b1;
            cdb_rob_tag    = br_rob_tag_o;
            cdb_mispredict = br_mispredict_o;
            cdb_data       = br_result_o;
            cdb_preg       = br_dest_preg;
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
            
            // Grant the ALU access so it clears its buffer
            alu_cdb_grant  = 1'b1; 
        end
    end
    always_ff @(posedge clk) if (!reset && cdb_valid) begin
  $display("[CDB] t=%0t src=%0d rob_tag=%0d rd_p=%0d data=%h",
           $time, cdb_rob_tag, cdb_data);
end


    rob #(
        .ROB_DEPTH (ROB_DEPTH),
        .ROB_TAG_W (ROB_TAG_W)
    ) u_rob (
        .clk                     (clk),
        .rst                     (reset),
        .flush_i                 (flush_pipeline),
        .flush_tag_i             (br_rob_tag_o),
        .dispatch_valid_i        (rob_push),
        .dispatch_entry_i        (rob_entry),
        .rob_full_o              (rob_full),
        .alloc_tag_o             (rob_alloc_tag),
        .commit_is_branch_jump_o (rob_commit_is_branch), 
        .count_o                 (rob_count), 
        .cdb_valid_i             (cdb_valid),
        .cdb_tag_i               (cdb_rob_tag),
        .cdb_mispredict_i        (cdb_mispredict),
        .commit_valid_o          (commit_valid),
        .commit_old_preg_o       (commit_old_preg),
        .commit_mispredict_o     (commit_mispredict),
        .commit_tag_recovery_o   (commit_tag_recovery)
    );

    // Physical Register File (Busy Table)
    logic [N_PHYS-1:0] phys_reg_busy;
    always_ff @(posedge clk) begin
        if (reset) begin
            phys_reg_busy <= '0;
        end else begin
            if (ren_valid && ren_ready && ren_payload.RegWrite && (rd_new_p != 6'd0)) begin
                phys_reg_busy[rd_new_p] <= 1'b1;
            end
            if (cdb_valid && (cdb_preg != 6'd0)) begin
                phys_reg_busy[cdb_preg] <= 1'b0;
            end
            if (ren_valid && ren_ready && ren_payload.RegWrite &&
                cdb_valid && (rd_new_p == cdb_preg) && (rd_new_p != 6'd0)) begin
                phys_reg_busy[rd_new_p] <= 1'b1;
            end
        end
    end

    // PRF
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
        .rst            (reset), 
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

    // Dispatch
    rs_issue_packet_t issue_pkt;
    logic rs_alu_ready, rs_lsu_ready, rs_branch_ready;
    logic dispatch_alu_valid, dispatch_lsu_valid, dispatch_branch_valid;

    Dispatch u_dispatch (
        .clk                     (clk),
        .rst                     (reset),
        .flush_i                 (flush_pipeline),
        .ren_valid_i             (ren_valid),
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

    // ALU RS
    rs_entry_t alu_issue_entry;
    logic      rs_alu_full, alu_issue_valid, alu_ready;

  reservation_station #(.NUM_SLOTS(8), .N_PHYS(N_PHYS)) u_rs_alu (
        .clk(clk), .reset(reset), .flush_i(flush_pipeline),
        .write_en(dispatch_alu_valid), .write_data(issue_pkt),
        .src1_already_ready_i(!phys_reg_busy[issue_pkt.rs1_p]),
        .src2_already_ready_i(!phys_reg_busy[issue_pkt.rs2_p]),
        .full(rs_alu_full),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_preg),
        .issue_ready(alu_ready), .issue_valid(alu_issue_valid), .issue_data(alu_issue_entry)
    );
    assign rs_alu_ready = !rs_alu_full;
    assign alu_ready    = 1'b1;
    assign prf_raddr_alu_src1 = alu_issue_entry.p_src1;
    assign prf_raddr_alu_src2 = alu_issue_entry.p_src2;

    // ALU Unit (With Handshake)
    logic [31:0] alu_op1, alu_op2, alu_reg2_val;
    assign alu_op1 = (alu_issue_entry.p_src1 == '0) ? 32'd0 : prf_rdata_alu_src1;
    assign alu_reg2_val = (alu_issue_entry.p_src2 == '0) ? 32'd0 : prf_rdata_alu_src2;
    assign alu_op2 = (alu_issue_entry.alu_src) ? alu_issue_entry.imm : alu_reg2_val;

    alu_unit #(.ROB_TAG_W(ROB_TAG_W)) u_alu (
        .clk(clk), .rst(reset),
        .valid_i(alu_issue_valid), .alu_op_i(alu_issue_entry.alu_op),
        .op1_i(alu_op1), .op2_i(alu_op2),
        .rd_p_i(alu_issue_entry.p_dst), .rob_tag_i(alu_issue_entry.rob_tag),
        .ready_i(alu_cdb_grant), // <--- CONNECTED!
        .valid_o(alu_cdb_valid), .result_o(alu_cdb_data),
        .rd_p_o(alu_cdb_preg), .rob_tag_o(alu_cdb_tag)
    );

    // LSU RS
    rs_entry_t lsu_issue_entry;
    logic      rs_lsu_full, lsu_issue_valid, lsu_ready;

  reservation_station #(.NUM_SLOTS(1), .N_PHYS(N_PHYS)) u_rs_lsu (
        .clk(clk), .reset(reset), .flush_i(flush_pipeline),
        .write_en(dispatch_lsu_valid), .write_data(issue_pkt),
        .src1_already_ready_i(!phys_reg_busy[issue_pkt.rs1_p]),
        .src2_already_ready_i(!phys_reg_busy[issue_pkt.rs2_p]),
        .full(rs_lsu_full),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_preg),
        .issue_ready(lsu_ready), .issue_valid(lsu_issue_valid), .issue_data(lsu_issue_entry)
    );
    assign rs_lsu_ready = !rs_lsu_full;
    assign prf_raddr_lsu_src1 = lsu_issue_entry.p_src1;
    assign prf_raddr_lsu_src2 = lsu_issue_entry.p_src2;

    // LSU Unit
    logic [31:0] lsu_base, lsu_store_val;
    assign lsu_base      = (lsu_issue_entry.p_src1 == '0) ? 32'd0 : prf_rdata_lsu_src1;
    assign lsu_store_val = (lsu_issue_entry.p_src2 == '0) ? 32'd0 : prf_rdata_lsu_src2;

    lsu_unit #(.ROB_TAG_W(ROB_TAG_W)) u_lsu (
        .clk(clk), .rst(reset),
        .valid_i(lsu_issue_valid), .mem_read_i(lsu_issue_entry.mem_read),
        .mem_write_i(lsu_issue_entry.mem_write), .rs1_val_i(lsu_base),
        .rs2_val_i(lsu_store_val), .imm_i(lsu_issue_entry.imm),
        .rd_p_i(lsu_issue_entry.p_dst), .rob_tag_i(lsu_issue_entry.rob_tag),
        .funct3_i(lsu_issue_entry.funct3),
        .ready_o(lsu_ready), .valid_o(lsu_cdb_valid), .result_o(lsu_cdb_data),
        .rd_p_o(lsu_cdb_preg), .rob_tag_o(lsu_cdb_tag)
    );

    // Branch RS
    rs_entry_t br_issue_entry;
    logic      rs_branch_full, br_issue_valid, br_ready;

    reservation_station #(.NUM_SLOTS(4), .N_PHYS(N_PHYS)) u_rs_branch (
        .clk(clk), .reset(reset), .flush_i(flush_pipeline),
        .write_en(dispatch_branch_valid), .write_data(issue_pkt),
        .src1_already_ready_i(!phys_reg_busy[issue_pkt.rs1_p]),
        .src2_already_ready_i(!phys_reg_busy[issue_pkt.rs2_p]),
        .full(rs_branch_full),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_preg),
        .issue_ready(br_ready), .issue_valid(br_issue_valid), .issue_data(br_issue_entry)
    );
    assign rs_branch_ready = !rs_branch_full;
    assign br_ready        = 1'b1;
    assign prf_raddr_br_src1 = br_issue_entry.p_src1;
    assign prf_raddr_br_src2 = br_issue_entry.p_src2;

    // Branch Unit
    logic [31:0] br_rs1_val, br_rs2_val;
    assign br_rs1_val = (br_issue_entry.p_src1 == '0) ? 32'd0 : prf_rdata_br_src1;
    assign br_rs2_val = (br_issue_entry.p_src2 == '0) ? 32'd0 : prf_rdata_br_src2;

    branch_unit #(.ROB_TAG_W(ROB_TAG_W)) u_branch (
        .clk(clk), .rst(reset),
        .valid_i(br_issue_valid), .pc_i(br_issue_entry.pc), .imm_i(br_issue_entry.imm),
        .rs1_val_i(br_rs1_val), .rs2_val_i(br_rs2_val),
        .is_branch_i(br_issue_entry.is_branch), .is_jump_i(br_issue_entry.is_jump),
        .pred_taken_i(1'b0), .rob_tag_i(br_issue_entry.rob_tag),
        .rd_p_i(br_issue_entry.p_dst),
        .valid_o(br_valid_o), .rob_tag_o(br_rob_tag_o), .mispredict_o(br_mispredict_o),
        .target_addr_o(br_target_addr_o), .actual_taken_o(br_taken_o),
        .result_o(br_result_o), .rd_p_o(br_dest_preg)
    );

    always_ff @(posedge clk) begin
        if (flush_pipeline) begin
            $display("[FLUSH] t=%0t Redirect to %08h", $time, redirect_pc);
        end
    end

    assign fe_valid_o    = dec_valid;
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