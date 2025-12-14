module Dispatch (
    input  logic clk,
    input  logic rst,

    input  logic                         ren_valid_i,
    input  pipeline_types::ctrl_payload_t payload_i,
    input  logic [5:0]                   rs1_p_i,
    input  logic [5:0]                   rs2_p_i,
    input  logic [5:0]                   rd_new_p_i,
    input  logic [5:0]                   rd_old_p_i,
    output logic                         ren_ready_o,

    input  logic                         rob_full_i,
    input  logic [3:0]                   rob_alloc_tag_i,
    output logic                         rob_push_o,
    output pipeline_types::rob_entry_t    rob_entry_o,

    input  logic rs_alu_ready_i,
    input  logic rs_lsu_ready_i,
    input  logic rs_branch_ready_i,

    output logic                         dispatch_alu_valid_o,
    output logic                         dispatch_lsu_valid_o,
    output logic                         dispatch_branch_valid_o,
    output pipeline_types::rs_issue_packet_t issue_pkt_o
);
    import pipeline_types::*;

    logic         buff_valid;
    ctrl_payload_t buff_payload;
    logic [5:0]   buff_rs1_p, buff_rs2_p, buff_rd_new_p, buff_rd_old_p;

    logic fire_dispatch;
    logic buffer_accept;

    assign buffer_accept = (!buff_valid) || fire_dispatch;
    assign ren_ready_o   = buffer_accept;

    always_ff @(posedge clk) begin
        if (rst) begin
            buff_valid <= 1'b0;
            buff_payload <= '0;
            buff_rs1_p <= '0;
            buff_rs2_p <= '0;
            buff_rd_new_p <= '0;
            buff_rd_old_p <= '0;
        end else begin
            if (buffer_accept) begin
                buff_valid <= ren_valid_i;
                if (ren_valid_i) begin
                    buff_payload  <= payload_i;
                    buff_rs1_p    <= rs1_p_i;
                    buff_rs2_p    <= rs2_p_i;
                    buff_rd_new_p <= rd_new_p_i;
                    buff_rd_old_p <= rd_old_p_i;
                end else begin
                    buff_payload  <= '0;
                    buff_rs1_p    <= '0;
                    buff_rs2_p    <= '0;
                    buff_rd_new_p <= '0;
                    buff_rd_old_p <= '0;
                end
            end
        end
    end

    logic do_br, do_lsu, do_alu;
    logic target_rs_ready;

    always_comb begin
        do_br = 1'b0; do_lsu = 1'b0; do_alu = 1'b0;

        if (buff_valid) begin
            if (buff_payload.is_branch || buff_payload.is_jump) begin
                do_br = 1'b1;
            end else begin
                unique case (buff_payload.fu_type)
                    FU_ALU:    do_alu = 1'b1;
                    FU_LSU:    do_lsu = 1'b1;
                    FU_BRANCH: do_br  = 1'b1;
                    default: begin end
                endcase
            end
        end

        target_rs_ready = 1'b0;
        if (do_alu)      target_rs_ready = rs_alu_ready_i;
        else if (do_lsu) target_rs_ready = rs_lsu_ready_i;
        else if (do_br)  target_rs_ready = rs_branch_ready_i;
    end

    assign fire_dispatch = buff_valid && (!rob_full_i) && target_rs_ready;

    always_comb begin
        dispatch_alu_valid_o    = 1'b0;
        dispatch_lsu_valid_o    = 1'b0;
        dispatch_branch_valid_o = 1'b0;

        if (fire_dispatch) begin
            if (do_alu)      dispatch_alu_valid_o    = 1'b1;
            else if (do_lsu) dispatch_lsu_valid_o    = 1'b1;
            else if (do_br)  dispatch_branch_valid_o = 1'b1;
        end
    end

    // *** CRITICAL: kill X propagation ***
    always_comb begin
        issue_pkt_o = '0;

        if (buff_valid) begin
            issue_pkt_o.pc        = buff_payload.pc;
            issue_pkt_o.imm       = buff_payload.imm;
            issue_pkt_o.alu_op    = buff_payload.ALUOp;
            issue_pkt_o.alu_src   = buff_payload.ALUSrc;
            issue_pkt_o.mem_read  = buff_payload.MemRead;
            issue_pkt_o.mem_write = buff_payload.MemWrite;
            issue_pkt_o.funct3    = buff_payload.funct3;

            issue_pkt_o.rs1_p     = buff_rs1_p;
            issue_pkt_o.rs2_p     = buff_rs2_p;
            issue_pkt_o.rd_p      = buff_rd_new_p;
            issue_pkt_o.rob_tag   = rob_alloc_tag_i;

            issue_pkt_o.is_branch = buff_payload.is_branch;
            issue_pkt_o.is_jump   = buff_payload.is_jump;
        end
    end

    assign rob_push_o = fire_dispatch;

    always_comb begin
        rob_entry_o = '0;
        if (fire_dispatch) begin
            rob_entry_o.valid        = 1'b1;
            rob_entry_o.done         = 1'b0;
            rob_entry_o.rd_log       = 5'b0;
            rob_entry_o.rd_phys      = buff_rd_new_p;
            rob_entry_o.rd_old_phys  = buff_rd_old_p;
            rob_entry_o.is_branch    = buff_payload.is_branch;
            rob_entry_o.mispredicted = 1'b0;
            rob_entry_o.pc           = buff_payload.pc;
        end
    end

endmodule