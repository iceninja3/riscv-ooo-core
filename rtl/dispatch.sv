module Dispatch (
    input logic clk,
    input logic rst,

    // --- Inputs from Rename ---
    input logic                      ren_valid_i,
    input pipeline_types::ctrl_payload_t payload_i,
    input logic [5:0]                rs1_p_i,
    input logic [5:0]                rs2_p_i,
    input logic [5:0]                rd_new_p_i,
    input logic [5:0]                rd_old_p_i,
    output logic                     ren_ready_o, // Stall signal to Rename

    // --- Inputs from ROB ---
    input logic                      rob_full_i,
    input logic [3:0]                rob_alloc_tag_i, // ROB tells us "Use Tag #5"
    output logic                     rob_push_o,      // We tell ROB "Allocate now"
    output pipeline_types::rob_entry_t rob_entry_o,   // Data for the ROB slot

    // --- Inputs from Reservation Stations (Status) ---
    input logic rs_alu_ready_i,
    input logic rs_lsu_ready_i,
    input logic rs_branch_ready_i,

    // --- Outputs to Reservation Stations (Issue) ---
    output logic                     dispatch_alu_valid_o,
    output logic                     dispatch_lsu_valid_o,
    output logic                     dispatch_branch_valid_o,
    output pipeline_types::rs_issue_packet_t issue_pkt_o
);
    import pipeline_types::*;

    // --- 1. The Pipeline Buffer (Skid Buffer) ---
    // The spec requires a buffer to hold the instruction if RS/ROB are busy.
    // We capture the Rename outputs into this register.
    
    logic        buff_valid;
    ctrl_payload_t buff_payload;
    logic [5:0]  buff_rs1_p;
    logic [5:0]  buff_rs2_p;
    logic [5:0]  buff_rd_new_p;
    logic [5:0]  buff_rd_old_p;

    // Logic to accept new data:
    // We accept if we are empty (invalid) OR if we are about to fire (move current data out)
    logic fire_dispatch;
    logic buffer_accept;
    assign buffer_accept = (!buff_valid) || fire_dispatch;
    assign ren_ready_o   = buffer_accept; // Tell Rename "Go ahead" if we can take it

    always_ff @(posedge clk) begin
        if (rst) begin
            buff_valid <= 1'b0;
            // Clear payloads (optional)
        end else begin
            if (buffer_accept) begin
                buff_valid     <= ren_valid_i; // If rename is valid, we become valid
                if (ren_valid_i) begin
                    buff_payload   <= payload_i;
                    buff_rs1_p     <= rs1_p_i;
                    buff_rs2_p     <= rs2_p_i;
                    buff_rd_new_p  <= rd_new_p_i;
                    buff_rd_old_p  <= rd_old_p_i;
                end
            end
        end
    end

    // --- 2. Routing & Stall Logic ---
    // We only dispatch if:
    // A) The buffer has a valid instruction
    // B) The ROB is not full
    // C) The SPECIFIC target Reservation Station is ready

    logic target_rs_ready;

    always_comb begin
        // Default: Not ready
        target_rs_ready = 1'b0;

        case (buff_payload.fu_type)
            FU_ALU:    target_rs_ready = rs_alu_ready_i;
            FU_LSU:    target_rs_ready = rs_lsu_ready_i;
            FU_BRANCH: target_rs_ready = rs_branch_ready_i;
            default:   target_rs_ready = 1'b1; // Should not happen, discard
        endcase
    end

    // The "Go" Signal
    assign fire_dispatch = buff_valid && (!rob_full_i) && target_rs_ready;

    // --- 3. Output Generation ---

    // A. To Reservation Stations
    always_comb begin
        dispatch_alu_valid_o    = 1'b0;
        dispatch_lsu_valid_o    = 1'b0;
        dispatch_branch_valid_o = 1'b0;

        if (fire_dispatch) begin
            case (buff_payload.fu_type)
                FU_ALU:    dispatch_alu_valid_o    = 1'b1;
                FU_LSU:    dispatch_lsu_valid_o    = 1'b1;
                FU_BRANCH: dispatch_branch_valid_o = 1'b1;
            endcase
        end
    end

    // Construct the packet for the RS
    assign issue_pkt_o.pc        = buff_payload.pc;
    assign issue_pkt_o.imm       = buff_payload.imm;
    assign issue_pkt_o.alu_op    = buff_payload.ALUOp;
    assign issue_pkt_o.alu_src   = buff_payload.ALUSrc;
    assign issue_pkt_o.mem_read  = buff_payload.MemRead;
    assign issue_pkt_o.mem_write = buff_payload.MemWrite;
    assign issue_pkt_o.rs1_p     = buff_rs1_p;
    assign issue_pkt_o.rs2_p     = buff_rs2_p;
    assign issue_pkt_o.rd_p      = buff_rd_new_p;
    assign issue_pkt_o.rob_tag   = rob_alloc_tag_i; // Use the tag the ROB gave us
	// assign issue_pkt_o.is_branch = payload_i.is_branch;
    // assign issue_pkt_o.is_jump   = payload_i.is_jump;
    assign issue_pkt_o.is_branch = buff_payload.is_branch;
    assign issue_pkt_o.is_jump   = buff_payload.is_jump; // added this bc was using 
    // current inst to module instead of inst from buffer

    // B. To ROB
    assign rob_push_o = fire_dispatch;

    // Construct the ROB Entry (Bookkeeping)
    assign rob_entry_o.valid        = 1'b1;
    assign rob_entry_o.done         = 1'b0; // Not done yet
    assign rob_entry_o.rd_log       = 5'b0; // You might want to pass logical dest from Rename for debug
    assign rob_entry_o.rd_phys      = buff_rd_new_p;
    assign rob_entry_o.rd_old_phys  = buff_rd_old_p;
    assign rob_entry_o.is_branch    = buff_payload.is_branch;
    assign rob_entry_o.mispredicted = 1'b0;
    assign rob_entry_o.pc           = buff_payload.pc;

endmodule