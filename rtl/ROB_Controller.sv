module rob_controller #(
    parameter DEPTH = 16,
    parameter IDX_W = 4
)(
    input  logic clk, reset,
    
    // Normal Operation
    input  logic dispatch_en,
    input  logic commit_en,
    output logic full,
    output logic [IDX_W-1:0] rob_tail_idx, // Current Tail (for Dispatch)
    
    // Recovery Logic
    input  logic branch_mispredict,        // From Execution/Branch Unit
    input  logic [IDX_W-1:0] recovery_idx  // The ROB ID of the branch that failed
);

    logic [IDX_W-1:0] wr_ptr, rd_ptr;
    logic [IDX_W:0]   count;

    // The tail pointer is the write pointer
    assign rob_tail_idx = wr_ptr; 
    assign full = (count == DEPTH);

    always_ff @(posedge clk) begin
        if (reset) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else if (branch_mispredict) begin
            // --- RECOVERY MECHANISM ---
            // If branch at ID 'X' failed, we valid instructions up to X.
            // Everything AFTER X is garbage. 
            // So, set the Write Pointer to strictly after the branch.
            wr_ptr <= recovery_idx + 1'b1; 
            
            // Recalculate count (Optional: simplifed for circular buffer)
            // In a real CPU, you might need 1 cycle to reset the count logic
            // or use pointer math: count <= (recovery_idx + 1) - rd_ptr;
            count <= (recovery_idx + 1'b1) - rd_ptr; 
        end else begin
            // ... (Normal Dispatch/Commit logic from previous response) ...
        end
    end
endmodule