`include "pipeline_types.sv"

`include "iCache.sv"
`include "fetch.sv"
`include "decode.sv"
`include "physical_reg_file.sv"
`include "alu_unit.sv"
`include "lsu.sv"
`include "branch_unit.sv"
`include "priority_decoder.sv"
`include "rob.sv"
`include "rename.sv"
`include "Reservation_Station.sv"
`include "dispatch.sv"

`include "rob.sv"
`include "dispatch.sv"
`include "Reservation_Station.sv"

import pipeline_types::*;

module RISCV #(
    parameter int ADDR_WIDTH = 9,
    parameter int DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic reset,

    output logic        fe_valid_o,
    input  logic        fe_ready_i,
    output logic [31:0] fe_pc_o,
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

    typedef enum logic [2:0] {
        S_FETCH,
        S_DECODE,
        S_READ_RF,
        S_EXECUTE,
        S_WRITEBACK
    } state_t;

    state_t state, next_state;

    logic [ADDR_WIDTH-1:0] icache_addr;
    logic [DATA_WIDTH-1:0] icache_rdata;
    logic        fetch_valid, fetch_ready;
    logic [31:0] fetch_pc, fetch_inst;
    logic        redirect_valid;
    logic [31:0] redirect_pc;

    logic [4:0]  rs1, rs2, rd;
    logic [31:0] imm;
    logic        ALUSrc, branch, jump, MemRead, MemWrite, RegWrite, MemToReg;
    ctrl_payload_t dec_payload;

    logic [31:0] rs1_data, rs2_data, rd_data;
    logic        alu_valid_out, lsu_valid_out, br_valid_out, br_taken;
    logic [31:0] alu_result, lsu_result, br_result, br_target;

    logic [31:0] pc_reg, inst_reg, rs1_val_reg, rs2_val_reg, result_reg;
    logic        taken_reg, redirect_in_progress;
    logic        reg_write_q, mem_to_reg_q;
    logic [4:0]  rd_q;

    logic                      dummy_rob_full, dummy_rob_push;
    logic [3:0]                dummy_rob_tag;
    rob_entry_t                dummy_rob_entry;
    logic                      dummy_ren_ready;
    logic                      dummy_dispatch_alu_v, dummy_dispatch_lsu_v, dummy_dispatch_br_v;
    rs_issue_packet_t          dummy_issue_pkt;
    logic                      dummy_rs_full, dummy_issue_valid;
    rs_entry_t                 dummy_issue_data;


    iCache #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_icache (
        .clk(clk), .addr(icache_addr), .rdata(icache_rdata)
    );

    Fetch #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_fetch (
        .clk(clk), .reset(reset),
        .redirect_valid_i(redirect_valid), .redirect_pc_i(redirect_pc),
        .icache_addr(icache_addr), .icache_rdata(icache_rdata),
        .valid_o(fetch_valid), .ready_i(fetch_ready),
        .pc_o(fetch_pc), .inst_o(fetch_inst)
    );

    decode u_decode (
        .inst(inst_reg), .pc(pc_reg), .rs1(rs1), .rs2(rs2), .rd(rd),
        .ctrl_payload_o(dec_payload), .imm(imm),
        .ALUSrc(ALUSrc), .ALUOp(), .branch(branch), .jump(jump),
        .MemRead(MemRead), .MemWrite(MemWrite), .RegWrite(RegWrite), .MemToReg(MemToReg)
    );

    rob #(.ROB_DEPTH(16), .ROB_TAG_W(4)) u_rob_skeleton (
        .clk(clk), .rst(reset),
        .flush_i(redirect_valid), .flush_tag_i(4'd0),
        .dispatch_valid_i(state == S_DECODE), .dispatch_entry_i(dummy_rob_entry),
        .rob_full_o(dummy_rob_full), .alloc_tag_o(dummy_rob_tag),
        .cdb_valid_i(state == S_WRITEBACK), .cdb_tag_i(4'd0), .cdb_mispredict_i(1'b0),
        .commit_valid_o(), .commit_old_preg_o(), .commit_mispredict_o(),
        .commit_tag_recovery_o(), .count_o(), .commit_is_branch_jump_o()
    );

    Dispatch u_dispatch_skeleton (
        .clk(clk), .rst(reset), .flush_i(redirect_valid),
        .ren_valid_i(state == S_DECODE), .payload_i(dec_payload),
        .rs1_p_i(6'd0), .rs2_p_i(6'd0), .rd_new_p_i(6'd0), .rd_old_p_i(6'd0),
        .ren_ready_o(dummy_ren_ready),
        .rob_full_i(dummy_rob_full), .rob_alloc_tag_i(dummy_rob_tag),
        .rob_push_o(dummy_rob_push), .rob_entry_o(dummy_rob_entry),
        .rs_alu_ready_i(1'b1), .rs_lsu_ready_i(1'b1), .rs_branch_ready_i(1'b1),
        .dispatch_alu_valid_o(dummy_dispatch_alu_v),
        .dispatch_lsu_valid_o(dummy_dispatch_lsu_v),
        .dispatch_branch_valid_o(dummy_dispatch_br_v),
        .issue_pkt_o(dummy_issue_pkt)
    );

    reservation_station #(.NUM_SLOTS(8), .N_PHYS(64)) u_rs_alu_skeleton (
        .clk(clk), .reset(reset), .flush_i(redirect_valid),
        .write_en(dummy_dispatch_alu_v), .write_data(dummy_issue_pkt),
        .src1_already_ready_i(1'b1), .src2_already_ready_i(1'b1),
        .full(dummy_rs_full), .cdb_valid(1'b0), .cdb_tag(6'd0),
        .issue_ready(1'b1), .issue_valid(dummy_issue_valid), .issue_data(dummy_issue_data)
    );

    physical_reg_file #(.NUM_REGS(32), .ADDR_WIDTH(5)) u_rf (
        .clk(clk), .rst(reset),
        .raddr_alu_src1(rs1), .rdata_alu_src1(rs1_data),
        .raddr_alu_src2(rs2), .rdata_alu_src2(rs2_data),
        .raddr_br_src1('0), .rdata_br_src1(), .raddr_br_src2('0), .rdata_br_src2(),
        .raddr_lsu_src1('0), .rdata_lsu_src1(), .raddr_lsu_src2('0), .rdata_lsu_src2(),
        .wen(state == S_WRITEBACK && reg_write_q && (rd_q != 0)),
        .waddr(rd_q), .wdata(rd_data)
    );

    alu_unit #(.ROB_TAG_W(1)) u_alu (
        .clk(clk), .rst(reset),
        .valid_i(state == S_EXECUTE && dec_payload.fu_type == FU_ALU),
        .alu_op_i(dec_payload.ALUOp), .op1_i(rs1_val_reg), .op2_i(ALUSrc ? imm : rs2_val_reg),
        .rd_p_i('0), .rob_tag_i('0), .ready_i(1'b1),
        .valid_o(alu_valid_out), .result_o(alu_result), .rd_p_o(), .rob_tag_o()
    );

    lsu_unit #(.ROB_TAG_W(1)) u_lsu (
        .clk(clk), .rst(reset),
        .valid_i(state == S_EXECUTE && dec_payload.fu_type == FU_LSU),
        .mem_read_i(MemRead), .mem_write_i(MemWrite),
        .rs1_val_i(rs1_val_reg), .rs2_val_i(rs2_val_reg), .imm_i(imm),
        .rd_p_i('0), .rob_tag_i('0), .funct3_i(dec_payload.funct3),
        .ready_i(1'b1), .ready_o(), .valid_o(lsu_valid_out),
        .result_o(lsu_result), .rd_p_o(), .rob_tag_o()
    );

    branch_unit #(.ROB_TAG_W(1)) u_branch (
        .clk(clk), .rst(reset),
        .valid_i(state == S_EXECUTE && dec_payload.fu_type == FU_BRANCH),
        .pc_i(pc_reg), .imm_i(imm), .rs1_val_i(rs1_val_reg), .rs2_val_i(rs2_val_reg),
        .is_branch_i(branch), .is_jump_i(jump),
        .pred_taken_i(1'b0), .rob_tag_i('0), .rd_p_i('0),
        .valid_o(br_valid_out), .rob_tag_o(), .mispredict_o(),
        .target_addr_o(br_target), .actual_taken_o(br_taken),
        .result_o(br_result), .rd_p_o()
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= S_FETCH; pc_reg <= '0; inst_reg <= '0; taken_reg <= 1'b0;
            redirect_valid <= 1'b0; redirect_in_progress <= 1'b0;
            reg_write_q <= 1'b0; rd_q <= 5'd0;
        end else begin
            state <= next_state;

            if (redirect_valid) begin
                redirect_valid <= 1'b0; redirect_in_progress <= 1'b1;
            end else if (state == S_FETCH && fetch_valid) begin
                redirect_in_progress <= 1'b0;
            end

            case (state)
                S_FETCH: if (fetch_valid && !redirect_valid && !redirect_in_progress) begin
                    inst_reg <= fetch_inst; pc_reg <= fetch_pc;
                end
                S_DECODE: begin
                    reg_write_q <= RegWrite; rd_q <= rd; mem_to_reg_q <= MemToReg;
                end
                S_READ_RF: begin
                    rs1_val_reg <= rs1_data; rs2_val_reg <= rs2_data;
                end
                S_EXECUTE: begin
                    if (alu_valid_out) result_reg <= alu_result;
                    else if (lsu_valid_out) result_reg <= lsu_result;
                    else if (br_valid_out) begin result_reg <= br_result; taken_reg <= br_taken; end
                end
                S_WRITEBACK: if ((branch && taken_reg) || jump) begin
                    redirect_valid <= 1'b1; redirect_pc <= br_target; inst_reg <= 32'h00000013;
                end
            endcase
        end
    end

    always_comb begin
        next_state = state; fetch_ready = 1'b0;
        case (state)
            S_FETCH: begin
                if (!redirect_valid && !redirect_in_progress) begin
                    fetch_ready = 1'b1; if (fetch_valid) next_state = S_DECODE;
                end else next_state = S_FETCH;
            end
            S_DECODE:    next_state = S_READ_RF;
            S_READ_RF:   next_state = S_EXECUTE;
            S_EXECUTE:   if (alu_valid_out || lsu_valid_out || br_valid_out) next_state = S_WRITEBACK;
            S_WRITEBACK: next_state = S_FETCH;
            default:     next_state = S_FETCH;
        endcase
    end

    assign rd_data = result_reg;
    assign fe_valid_o = (state == S_DECODE); assign fe_pc_o = pc_reg;
    assign fe_RegWrite_o = RegWrite; assign fe_MemToReg_o = MemToReg;
endmodule