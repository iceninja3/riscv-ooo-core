`timescale 1ns / 1ps
import pipeline_types::*;

module rob #(
    parameter int ROB_DEPTH = 16,
    parameter int ROB_TAG_W = 4
)(
    input  logic clk,
    input  logic rst,

    // Flush Interface
    input  logic                      flush_i,
    input  logic [ROB_TAG_W-1:0]      flush_tag_i,

    // Dispatch Interface
    input  logic                      dispatch_valid_i,
    input  rob_entry_t                dispatch_entry_i,
    output logic                      rob_full_o,
    output logic [ROB_TAG_W-1:0]      alloc_tag_o,

    // CDB Interface
    input  logic                      cdb_valid_i,
    input  logic [ROB_TAG_W-1:0]      cdb_tag_i,
    input  logic                      cdb_mispredict_i,

    // Commit Interface
    output logic                      commit_valid_o,
    output logic [5:0]                commit_old_preg_o,
    output logic                      commit_mispredict_o,
    output logic [ROB_TAG_W-1:0]      commit_tag_recovery_o,

    // Fix Ports
    output logic [ROB_TAG_W:0]        count_o,
    output logic                      commit_is_branch_jump_o
);

    // -------------------------------------------------------------------------
    // Internal Signals
    // -------------------------------------------------------------------------
    rob_entry_t rob_array [ROB_DEPTH];
    logic [ROB_TAG_W-1:0] head_ptr;
    logic [ROB_TAG_W-1:0] tail_ptr;
    
    // RENAMED BACK TO 'count' SO TESTBENCH CAN FIND IT
    logic [ROB_TAG_W:0]   count; 

    // -------------------------------------------------------------------------
    // Assignments
    // -------------------------------------------------------------------------
    assign alloc_tag_o = tail_ptr;
    assign count_o     = count; // output connection
    assign rob_full_o  = (count == ROB_DEPTH);

    assign commit_is_branch_jump_o = (count > 0) && rob_array[head_ptr].valid && 
                                     (rob_array[head_ptr].is_branch || rob_array[head_ptr].is_jump);

    // -------------------------------------------------------------------------
    // Sequential Logic
    // -------------------------------------------------------------------------
    integer i;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            head_ptr       <= '0;
            tail_ptr       <= '0;
            count          <= '0;
            commit_valid_o <= 1'b0;
            commit_old_preg_o <= '0;
            commit_mispredict_o <= 1'b0;
            commit_tag_recovery_o <= '0;

            for (i = 0; i < ROB_DEPTH; i++) begin
                rob_array[i].valid <= 1'b0;
                rob_array[i].done  <= 1'b0;
            end

        end else if (flush_i) begin
            // =================================================================
            // FLUSH LOGIC
            // =================================================================
            // DECLARATION MUST BE FIRST
            logic [ROB_TAG_W-1:0] new_tail; 
            
            // 1. Rollback Tail
            new_tail = flush_tag_i + 1'b1;
            tail_ptr <= new_tail;

            // 2. Recalculate Count
            if (new_tail >= head_ptr)
                count <= new_tail - head_ptr;
            else
                count <= ROB_DEPTH - (head_ptr - new_tail);

            // 3. Halt Commit
            commit_valid_o <= 1'b0;

            // 4. Process CDB writes (race condition safety)
            if (cdb_valid_i) begin
                rob_array[cdb_tag_i].done <= 1'b1;
                if (cdb_mispredict_i) rob_array[cdb_tag_i].mispredicted <= 1'b1;
            end

        end else begin
            // =================================================================
            // NORMAL OPERATION
            // =================================================================
            // DECLARATIONS MUST BE FIRST
            logic did_commit;
            logic did_dispatch;
            
            // --- 1. COMMIT ---
            commit_valid_o <= 1'b0; // Default
            did_commit = 1'b0;

            if (count > 0 && rob_array[head_ptr].valid && rob_array[head_ptr].done) begin
                commit_valid_o        <= 1'b1;
                commit_old_preg_o     <= rob_array[head_ptr].rd_old_phys;
                commit_mispredict_o   <= rob_array[head_ptr].mispredicted;
                commit_tag_recovery_o <= head_ptr;

                // Invalidate and Advance
                rob_array[head_ptr].valid <= 1'b0;
                head_ptr   <= head_ptr + 1'b1;
                did_commit = 1'b1;
            end

            // --- 2. DISPATCH ---
            did_dispatch = 1'b0;

            if (dispatch_valid_i && !rob_full_o) begin
                rob_array[tail_ptr] <= dispatch_entry_i;
                rob_array[tail_ptr].valid <= 1'b1;
                rob_array[tail_ptr].done  <= 1'b0;
                rob_array[tail_ptr].mispredicted <= 1'b0; 

                tail_ptr     <= tail_ptr + 1'b1;
                did_dispatch = 1'b1;
            end

            // --- 3. COUNT UPDATE ---
            if (did_dispatch && !did_commit)
                count <= count + 1;
            else if (!did_dispatch && did_commit)
                count <= count - 1;
            
            // --- 4. CDB WRITEBACK ---
            if (cdb_valid_i) begin
                rob_array[cdb_tag_i].done <= 1'b1;
                if (cdb_mispredict_i) begin
                    rob_array[cdb_tag_i].mispredicted <= 1'b1;
                end
            end
        end
    end

endmodule