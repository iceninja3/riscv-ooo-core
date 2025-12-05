import pipeline_types::*;
module rob #(
    parameter int ROB_DEPTH = 16,   // Size of 16 
    parameter int ROB_TAG_W = 4     // $clog2(16)
)(
    input  logic clk,
    input  logic rst,

    // --- Interface with Dispatch ---
    input  logic dispatch_valid_i,
    input  rob_entry_t dispatch_entry_i, // Struct we defined above
    output logic rob_full_o,             // Stalls Dispatch if high
    output logic [ROB_TAG_W-1:0] alloc_tag_o, // The ID (index) given to this instr

    // --- Interface with Execution Units (CDB) ---
    // When an ALU finishes, it broadcasts "Tag X is done!"
    input  logic cdb_valid_i,
    input  logic [ROB_TAG_W-1:0] cdb_tag_i,
    input  logic cdb_mispredict_i, // Optional: if it was a bad branch

    // --- Interface with Rename (Commit Feedback) ---
    output logic commit_valid_o,          // "Instruction retired!"
    output logic [5:0] commit_old_preg_o, // "Free this physical register"
    output logic commit_mispredict_o,     // "Flush the pipeline!"
    output logic [ROB_TAG_W-1:0] commit_tag_recovery_o // Tail pointer to restore to
);

    // Storage [cite: 51-52]
    rob_entry_t rob_array [ROB_DEPTH];
    logic [ROB_TAG_W-1:0] head_ptr; // Commit pointer
    logic [ROB_TAG_W-1:0] tail_ptr; // Allocate pointer
    logic [ROB_TAG_W:0]   count;    // To track full/empty status

    // Full Signal
    assign rob_full_o = (count == ROB_DEPTH);
    
    // Tag Assignment
    assign alloc_tag_o = tail_ptr;

    always_ff @(posedge clk) begin
        if (rst) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            count    <= '0;
            commit_valid_o <= 1'b0;
            // Clear valid bits in array...
        end else begin
            
            // --- 1. COMMIT LOGIC (Head) ---
            commit_valid_o <= 1'b0; // Default
            
            // If the oldest instruction (head) is valid AND execution is done:
            if (count > 0 && rob_array[head_ptr].valid && rob_array[head_ptr].done) begin
                commit_valid_o      <= 1'b1;
                commit_old_preg_o   <= rob_array[head_ptr].rd_old_phys;
                commit_mispredict_o <= rob_array[head_ptr].mispredicted;
                
                // Advance Head
                head_ptr <= head_ptr + 1'b1;
                count    <= count - 1'b1; // (Note: handle simultaneous dispatch carefully)
                
                // Mark slot as invalid
                rob_array[head_ptr].valid <= 1'b0;
            end

            // --- 2. DISPATCH LOGIC (Tail) ---
            // If Dispatch sends something and we aren't full:
            if (dispatch_valid_i && !rob_full_o) begin
                rob_array[tail_ptr] <= dispatch_entry_i;
                rob_array[tail_ptr].valid <= 1'b1;
                rob_array[tail_ptr].done  <= 1'b0; // Not done yet!
                
                tail_ptr <= tail_ptr + 1'b1;
                count    <= count + 1'b1; // (Again, handle simulataneous commit/dispatch)
            end

            // --- 3. WRITEBACK / COMPLETION LOGIC ---
            // Execution unit says "Tag X finished"
            if (cdb_valid_i) begin
                rob_array[cdb_tag_i].done <= 1'b1;
                if (cdb_mispredict_i) begin
                   rob_array[cdb_tag_i].mispredicted <= 1'b1;
                end
            end
        end
    end
endmodule