`timescale 1ns / 1ps
import pipeline_types::*;

module reservation_station #(
    parameter NUM_SLOTS = 8,
    parameter N_PHYS    = 64
)(
    input logic clk, 
    input logic reset,
    input logic flush_i,

    // --- Interface with Dispatch ---
    input logic  write_en,
    input rs_issue_packet_t write_data, 
    
    // Ready Status from Dispatch (Busy Table checks)
    input logic  src1_already_ready_i, 
    input logic  src2_already_ready_i,

    output logic full,

    // --- Interface with CDB (Wakeup) ---
    input logic       cdb_valid,
    input logic [5:0] cdb_tag,

    // --- Interface with Execution ---
    input  logic      issue_ready,
    output logic      issue_valid,
    output rs_entry_t issue_data
);

    // -------------------------------------------------------------------------
    // SAFE WIDTH PARAMETER
    // -------------------------------------------------------------------------
    // Ensure index width is at least 1 bit to prevent [-1:0] errors
    localparam IDX_W = (NUM_SLOTS > 1) ? $clog2(NUM_SLOTS) : 1;

    rs_entry_t slots [NUM_SLOTS];
    logic [NUM_SLOTS-1:0] slots_valid;
    logic [NUM_SLOTS-1:0] slots_runnable;

    // -------------------------------------------------------------------------
    // 1. ALLOCATION (Find Free Slot)
    // -------------------------------------------------------------------------
    logic [IDX_W-1:0] free_idx; // Uses Safe Width
    logic any_free;

    priority_decoder #(.WIDTH(NUM_SLOTS)) u_alloc_dec (
        .req_i (~slots_valid), 
        .idx_o (free_idx),
        .valid_o (any_free)
    );

    assign full = !any_free;

    // -------------------------------------------------------------------------
    // 2. ISSUE SELECTION (Find Runnable Slot)
    // -------------------------------------------------------------------------
    logic [IDX_W-1:0] issue_idx; // Uses Safe Width
    logic any_runnable;

    always_comb begin
        for (int i = 0; i < NUM_SLOTS; i++) begin
            // Runnable if Valid AND Both Sources Ready
            slots_runnable[i] = slots_valid[i] && slots[i].src1_ready && slots[i].src2_ready;
        end
    end

    priority_decoder #(.WIDTH(NUM_SLOTS)) u_issue_dec (
        .req_i (slots_runnable),
        .idx_o (issue_idx),
        .valid_o (any_runnable)
    );

    assign issue_valid = any_runnable;
    // Handle the case where the index might technically be out of bounds if logic fails 
    // (though issue_valid prevents using bad data).
    assign issue_data  = slots[issue_idx]; 

    // -------------------------------------------------------------------------
    // 3. MAIN SEQUENTIAL LOGIC
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            slots_valid <= '0;
        end else if (flush_i) begin
            slots_valid <= '0; 
        end else begin
            
            // --- A. Allocation (Write from Dispatch) ---
            if (write_en && !full) begin
                slots_valid[free_idx] <= 1'b1;
                
                // Copy ALL fields
                slots[free_idx].pc       <= write_data.pc;
                slots[free_idx].imm      <= write_data.imm;
                slots[free_idx].alu_op   <= write_data.alu_op;
                slots[free_idx].alu_src  <= write_data.alu_src;
                slots[free_idx].mem_read <= write_data.mem_read;
                slots[free_idx].mem_write<= write_data.mem_write;
                slots[free_idx].funct3   <= write_data.funct3;
                slots[free_idx].p_src1   <= write_data.rs1_p;
                slots[free_idx].p_src2   <= write_data.rs2_p;
                slots[free_idx].p_dst    <= write_data.rd_p; 
                slots[free_idx].rob_tag  <= write_data.rob_tag;
                slots[free_idx].is_branch<= write_data.is_branch;
                slots[free_idx].is_jump  <= write_data.is_jump;

                // Ready Bits
                if (write_data.rs1_p == 6'd0) 
                    slots[free_idx].src1_ready <= 1'b1;
                else if (src1_already_ready_i || (cdb_valid && cdb_tag == write_data.rs1_p))
                    slots[free_idx].src1_ready <= 1'b1;
                else
                    slots[free_idx].src1_ready <= 1'b0;

                if (write_data.alu_src == 1'b1 || write_data.rs2_p == 6'd0)
                    slots[free_idx].src2_ready <= 1'b1;
                else if (src2_already_ready_i || (cdb_valid && cdb_tag == write_data.rs2_p))
                    slots[free_idx].src2_ready <= 1'b1;
                else
                    slots[free_idx].src2_ready <= 1'b0;
            end

            // --- B. Wakeup (Snoop the CDB) ---
            for (int i = 0; i < NUM_SLOTS; i++) begin
                if (slots_valid[i]) begin
                    if (cdb_valid) begin
                        if (!slots[i].src1_ready && slots[i].p_src1 == cdb_tag)
                            slots[i].src1_ready <= 1'b1;
                        if (!slots[i].src2_ready && slots[i].p_src2 == cdb_tag)
                            slots[i].src2_ready <= 1'b1;
                    end
                end
            end

            // --- C. Issue (Clear the slot) ---
            if (any_runnable && issue_ready) begin
                slots_valid[issue_idx] <= 1'b0;
                
                // Debug Print
                // $display("[RS-ISSUE] t=%0t PC=%h Tag=%d ALUSrc=%b Imm=%h Op1Tag=%d Op2Tag=%d", 
                //          $time, slots[issue_idx].pc, slots[issue_idx].p_dst,
                //          slots[issue_idx].alu_src, slots[issue_idx].imm,
                //          slots[issue_idx].p_src1, slots[issue_idx].p_src2);
            end
        end
    end

endmodule