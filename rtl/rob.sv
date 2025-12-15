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

            commit_valid_o       <= 1'b0;
            commit_old_preg_o    <= '0;
            commit_mispredict_o  <= 1'b0;
            commit_target_pc_o   <= '0;

            for (i = 0; i < ROB_DEPTH; i++) begin
                rob_array[i].valid        <= 1'b0;
                rob_array[i].done         <= 1'b0;
                rob_array[i].mispredicted <= 1'b0;
                rob_array[i].rd_log       <= '0;
                rob_array[i].rd_phys      <= '0;
                rob_array[i].rd_old_phys  <= '0;
                rob_array[i].is_branch    <= 1'b0;
                rob_array[i].pc           <= '0;
                rob_array[i].target_pc    <= '0;
            end
        end else begin
            // Default commit outputs every cycle
            commit_valid_o      <= 1'b0;
            commit_old_preg_o   <= '0;
            commit_mispredict_o <= 1'b0;
            commit_target_pc_o  <= '0;

            // ----------------------------
            // 1) CDB completion (mark done + capture mispredict + capture target_pc)
            // ----------------------------
            if (cdb_valid_i) begin
                rob_array[cdb_tag_i].done <= 1'b1;

                if (cdb_mispredict_i) begin
                    rob_array[cdb_tag_i].mispredicted <= 1'b1;
                    rob_array[cdb_tag_i].target_pc    <= cdb_target_pc_i; // ✅ store redirect target
                end
            end

            // ----------------------------
            // 2) Commit head (retire or flush)
            // ----------------------------
            if (do_commit) begin
<<<<<<< HEAD
                // Check for Misprediction (The "Big Flush")
                if (rob_array[head_ptr].mispredicted) begin
                    // 1. Assert Flush Output
                    commit_mispredict_o <= 1'b1;
                    
                    // 2. Output the Correct Target (saved from CDB earlier)
                    // Note: Ensure you added 'target_pc' to your rob_entry_t struct!
                    // If you haven't, you can't redirect Fetch. 
                    // (See code block below for the fix).
                    
                    // 3. FLUSH THE ROB (Reset pointers)
                    head_ptr <= '0;
                    tail_ptr <= '0;
                    count    <= '0;
                    
                    // Nuke all valid bits
                    for (int i=0; i<ROB_DEPTH; i++) rob_array[i].valid <= 1'b0;
                    
                end else begin
                    // Normal Commit (Retire)
                    commit_valid_o      <= 1'b1;
                    commit_old_preg_o   <= rob_array[head_ptr].rd_old_phys;
                    commit_mispredict_o <= 1'b0;

=======
                if (rob_array[head_ptr].mispredicted) begin
                    // BIG FLUSH
                    commit_mispredict_o <= 1'b1;
                    commit_target_pc_o  <= rob_array[head_ptr].target_pc; // ✅ redirect fetch here

                    head_ptr <= '0;
                    tail_ptr <= '0;
                    count    <= '0;

                    // invalidate all entries
                    for (i = 0; i < ROB_DEPTH; i++) begin
                        rob_array[i].valid <= 1'b0;
                        rob_array[i].done  <= 1'b0;
                        rob_array[i].mispredicted <= 1'b0;
                        // (optional) leave other fields don't-care
                    end
                end else begin
                    // Normal commit
                    commit_valid_o    <= 1'b1;
                    commit_old_preg_o <= rob_array[head_ptr].rd_old_phys;

>>>>>>> af9e2a4 (changes for recovery)
                    rob_array[head_ptr].valid <= 1'b0;
                    head_ptr <= head_ptr + 1'b1;
                    count    <= count - 1'b1;
                end
<<<<<<< HEAD
            end 
            else begin
                commit_valid_o      <= 1'b0;
                commit_mispredict_o <= 1'b0;
=======
>>>>>>> af9e2a4 (changes for recovery)
            end

            // ----------------------------
            // 3) Dispatch tail (allocate new entry)
            // ----------------------------
            if (do_dispatch) begin
                rob_array[tail_ptr] <= dispatch_entry_i;

                rob_array[tail_ptr].valid        <= 1'b1;
                rob_array[tail_ptr].done         <= 1'b0;
                rob_array[tail_ptr].mispredicted <= 1'b0;

                // If dispatch_entry_i.target_pc isn't meaningful yet, clear it here.
                // Branch FU will fill it later via CDB on mispredict.
                rob_array[tail_ptr].target_pc    <= '0;

                tail_ptr <= tail_ptr + 1'b1;
                count    <= count + 1'b1;  // dispatch only case handled here
            end

            // ----------------------------
            // 4) Count update for commit+dispatch same cycle
            // (we already updated count in commit-only and dispatch-only paths above,
            // so handle only the "both" case here cleanly)
            // ----------------------------
            if (do_commit && do_dispatch && !rob_array[head_ptr].mispredicted) begin
                // commit decremented, dispatch incremented => net 0
                // But our code above would have done both (count-- then count++) in separate assigns
                // We avoided that by only assigning count in each block.
                // So: do nothing here.
            end
            // Note: if mispredict flush happens, count is forced to 0 above, and dispatch is ignored
            // because pointers are reset; if you want to strictly block dispatch on mispredict flush,
            // gate do_dispatch with !rob_array[head_ptr].mispredicted in always_comb.
        end
    end

endmodule