import pipeline_types::*;

module rob #(
    parameter int ROB_DEPTH = 16,
    parameter int ROB_TAG_W = 4
)(
    input  logic clk,
    input  logic rst,

    // --- Interface with Dispatch ---
    input  logic      dispatch_valid_i,
    input  rob_entry_t dispatch_entry_i,
    output logic      rob_full_o,
    output logic [ROB_TAG_W-1:0] alloc_tag_o,

    // --- Interface with Execution Units (CDB) ---
    input  logic                cdb_valid_i,
    input  logic [ROB_TAG_W-1:0] cdb_tag_i,
    input  logic                cdb_mispredict_i,

    // --- Interface with Rename (Commit Feedback) ---
    output logic                commit_valid_o,
    output logic [5:0]          commit_old_preg_o,
    output logic                commit_mispredict_o,
    output logic [ROB_TAG_W-1:0] commit_tag_recovery_o
);

    rob_entry_t rob_array [ROB_DEPTH];

    logic [ROB_TAG_W-1:0] head_ptr;
    logic [ROB_TAG_W-1:0] tail_ptr;
    logic [ROB_TAG_W:0]   count;

    // Full Signal + Tag Assignment
    assign rob_full_o  = (count == ROB_DEPTH);
    assign alloc_tag_o = tail_ptr;

    // Optional: for recovery (usually tail pointer)
    assign commit_tag_recovery_o = tail_ptr;

    // ----------------------------
    // Single-cycle decisions
    // ----------------------------
    logic do_commit;
    logic do_dispatch;

    always_comb begin
        do_commit   = (count != 0) && rob_array[head_ptr].valid && rob_array[head_ptr].done;
        do_dispatch = dispatch_valid_i && !rob_full_o;
    end

    // ----------------------------
    // Sequential updates
    // ----------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            count    <= '0;

            commit_valid_o      <= 1'b0;
            commit_old_preg_o   <= '0;
            commit_mispredict_o <= 1'b0;

            // Clear ROB entries
            for (int i = 0; i < ROB_DEPTH; i++) begin
                rob_array[i].valid        <= 1'b0;
                rob_array[i].done         <= 1'b0;
                rob_array[i].mispredicted <= 1'b0;
                rob_array[i].rd_old_phys  <= '0;
                rob_array[i].rd_phys      <= '0;
                rob_array[i].pc           <= '0;
                rob_array[i].is_branch    <= 1'b0;
                rob_array[i].rd_log       <= '0;
            end
        end else begin
            // Default commit outputs
            commit_valid_o      <= 1'b0;
            commit_old_preg_o   <= '0;
            commit_mispredict_o <= 1'b0;

            // ----------------------------
            // 1) CDB completion (can happen even with commit/dispatch)
            // ----------------------------
            if (cdb_valid_i) begin
                rob_array[cdb_tag_i].done <= 1'b1;
                if (cdb_mispredict_i)
                    rob_array[cdb_tag_i].mispredicted <= 1'b1;
            end

            // ----------------------------
            // 2) Commit head (uses OLD head_ptr)
            // ----------------------------
            if (do_commit) begin
                commit_valid_o      <= 1'b1;
                commit_old_preg_o   <= rob_array[head_ptr].rd_old_phys;
                commit_mispredict_o <= rob_array[head_ptr].mispredicted;

                rob_array[head_ptr].valid <= 1'b0; // free slot
                head_ptr <= head_ptr + 1'b1;
            end

            // ----------------------------
            // 3) Dispatch tail (uses OLD tail_ptr)
            // ----------------------------
            if (do_dispatch) begin
                rob_array[tail_ptr] <= dispatch_entry_i;
                rob_array[tail_ptr].valid <= 1'b1;
                rob_array[tail_ptr].done  <= 1'b0;
                rob_array[tail_ptr].mispredicted <= 1'b0;

                tail_ptr <= tail_ptr + 1'b1;
            end

            // ----------------------------
            // 4) Count update (ONE place, correct for both)
            // ----------------------------
            unique case ({do_dispatch, do_commit})
                2'b10: count <= count + 1'b1; // dispatch only
                2'b01: count <= count - 1'b1; // commit only
                default: count <= count;      // both or neither
            endcase
        end
    end

endmodule