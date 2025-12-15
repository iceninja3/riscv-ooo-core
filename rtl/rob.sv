import pipeline_types::*;

module rob #(
    parameter int ROB_DEPTH = 16,
    parameter int ROB_TAG_W = 4
)(
    input  logic clk,
    input  logic rst,

    // --- Interface with Dispatch ---
    input  logic       dispatch_valid_i,
    input  rob_entry_t dispatch_entry_i,
    output logic       rob_full_o,
    output logic [ROB_TAG_W-1:0] alloc_tag_o,

    // --- Interface with Execution Units (CDB) ---
    input  logic                 cdb_valid_i,
    input  logic [ROB_TAG_W-1:0] cdb_tag_i,
    input  logic                 cdb_mispredict_i,
    input  logic [31:0]          cdb_target_pc_i,   // ✅ correct redirect PC from branch/jump FU

    // --- Interface with Rename / Frontend (Commit Feedback) ---
    output logic [31:0]          commit_target_pc_o, // ✅ redirect PC on mispredict
    output logic                commit_valid_o,
    output logic [5:0]          commit_old_preg_o,
    output logic                commit_mispredict_o,
	 output logic [ROB_TAG_W-1:0] commit_tag_o,
    output logic [ROB_TAG_W-1:0] commit_tag_recovery_o
);

    rob_entry_t rob_array [ROB_DEPTH];

    logic [ROB_TAG_W-1:0] head_ptr, tail_ptr;
    logic [ROB_TAG_W:0]   count;

    // Full Signal + Tag Assignment
    assign rob_full_o  = (count == ROB_DEPTH);
    assign alloc_tag_o = tail_ptr;

    // Recovery tag (often used as "youngest in-flight tag" / tail snapshot)
    assign commit_tag_recovery_o = tail_ptr;
	 assign commit_tag_o = head_ptr;

    // ----------------------------
    // Single-cycle decisions
    // ----------------------------
    logic do_commit, do_dispatch;

    always_comb begin
        do_commit   = (count != 0) &&
                      rob_array[head_ptr].valid &&
                      rob_array[head_ptr].done;

        do_dispatch = dispatch_valid_i && !rob_full_o;
    end

    // ----------------------------
    // Sequential updates
    // ----------------------------
    integer i;
    always_ff @(posedge clk) begin
        if (rst) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            count    <= '0;
            commit_valid_o      <= 1'b0;
            commit_old_preg_o   <= '0;
            commit_mispredict_o <= 1'b0;
            commit_target_pc_o  <= '0;
            for (i = 0; i < ROB_DEPTH; i++) begin
                rob_array[i] <= '0; // Clear everything
            end
        end else begin
            // Defaults
            commit_valid_o      <= 1'b0;
            commit_old_preg_o   <= '0;
            commit_mispredict_o <= 1'b0;
            // commit_target_pc_o keeps value or 0, doesn't matter much if valid=0

            // ---------------------------------------------------------
            // 1) CDB Capture (Writeback) - Independent of Commit/Dispatch
            // ---------------------------------------------------------
            if (cdb_valid_i) begin
                rob_array[cdb_tag_i].done <= 1'b1;
                if (cdb_mispredict_i) begin
                    rob_array[cdb_tag_i].mispredicted <= 1'b1;
                    rob_array[cdb_tag_i].target_pc    <= cdb_target_pc_i;
                end
            end

            // ---------------------------------------------------------
            // 2) PRIORITY LOGIC: Flush > Commit > Dispatch
            // ---------------------------------------------------------
            
            // CASE A: FLUSH (Misprediction at Head)
            if (do_commit && rob_array[head_ptr].mispredicted) begin
                // 1. Output Recovery Signals
                commit_valid_o      <= 1'b0; // Usually 0 for a flush event itself, or 1 to indicate "handled"
                commit_mispredict_o <= 1'b1;
                commit_target_pc_o  <= rob_array[head_ptr].target_pc;
                
                // 2. NUKE THE ROB
                count    <= '0;
                head_ptr <= '0;
                tail_ptr <= '0;
                
                for (i = 0; i < ROB_DEPTH; i++) begin
                    rob_array[i].valid <= 1'b0;
                    rob_array[i].done  <= 1'b0;
                end
                
                // NOTE: We implicitly IGNORE do_dispatch here. 
                // Any instruction trying to enter right now is garbage from the old path.

            end else begin
                // CASE B: NORMAL OPERATION
                
                // Sub-case: Commit (Retire)
                if (do_commit) begin
                    commit_valid_o    <= 1'b1;
                    commit_old_preg_o <= rob_array[head_ptr].rd_old_phys;
                    
                    rob_array[head_ptr].valid <= 1'b0;
                    head_ptr <= head_ptr + 1'b1;
                end

                // Sub-case: Dispatch (Allocate)
                if (do_dispatch) begin
                    rob_array[tail_ptr]              <= dispatch_entry_i;
                    rob_array[tail_ptr].valid        <= 1'b1;
                    rob_array[tail_ptr].done         <= 1'b0;
                    rob_array[tail_ptr].mispredicted <= 1'b0;
                    rob_array[tail_ptr].target_pc    <= '0;
                    
                    tail_ptr <= tail_ptr + 1'b1;
                end

                // Sub-case: Count Update (Math)
                // We calculate net change based on what happened above
                case ({do_dispatch, do_commit})
                    2'b10: count <= count + 1'b1; // Dispatch only
                    2'b01: count <= count - 1'b1; // Commit only
                    2'b11: count <= count;        // Both (Net 0)
                    default: count <= count;
                endcase
            end
        end
    end

endmodule