module reservation_station #(
    parameter NUM_SLOTS = 8
)(
    input logic clk, reset,
    
    // --- Interface with Dispatch ---
    input logic  write_en,
    input rs_entry_t write_data, // The instruction details
    output logic full,
    
    // --- Interface with CDB (Common Data Bus) for Wakeup ---
    input logic       cdb_valid,
    input logic [6:0] cdb_tag,   // Physical Register that just computed
    
    // --- Interface with Execution ---
    input  logic      issue_ready, // Can execution unit take a job?
    output logic      issue_valid, // We have a job for you
    output rs_entry_t issue_data   // The job
);

    rs_entry_t slots [NUM_SLOTS-1:0];
    logic [NUM_SLOTS-1:0] slots_valid;      // Bitmask: 1=Busy, 0=Free
    logic [NUM_SLOTS-1:0] slots_runnable;   // Bitmask: 1=Ready to run
    
    // ---------------------------------------------------------
    // 1. ALLOCATION LOGIC (Find free slot)
    // ---------------------------------------------------------
    logic [$clog2(NUM_SLOTS)-1:0] free_idx;
    logic                         any_free;
    
    // We want to find a '0' in slots_valid. 
    // The priority decoder finds '1's. So we invert the input.
    priority_decoder #(.WIDTH(NUM_SLOTS)) alloc_decoder (
        .in(~slots_valid), 
        .out(free_idx), 
        .valid(any_free)
    );
    
    assign full = ~any_free; // If no bits are 0, we are full

    // ---------------------------------------------------------
    // 2. WAKEUP LOGIC (Listen to CDB)
    // ---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            slots_valid <= '0;
            // Clear other fields...
        end else begin
            // A. Write new instruction
            if (write_en && !full) begin
                slots[free_idx] <= write_data;
                slots_valid[free_idx] <= 1'b1;
            end

            // B. Listen to CDB (Wakeup)
            for (int i = 0; i < NUM_SLOTS; i++) begin
                if (slots_valid[i]) begin
                    // If src1 matches CDB broadcast, mark it ready
                    if (cdb_valid && slots[i].p_src1 == cdb_tag) 
                        slots[i].src1_ready <= 1'b1;
                        
                    // If src2 matches CDB broadcast, mark it ready
                    if (cdb_valid && slots[i].p_src2 == cdb_tag) 
                        slots[i].src2_ready <= 1'b1;
                end
            end
            
            // C. Clear slot after Issue (Atomic move to execution)
            if (issue_ready && issue_valid) begin
                 slots_valid[issue_idx] <= 1'b0; 
            end
        end
    end

    // ---------------------------------------------------------
    // 3. ISSUE LOGIC (Pick runnable instruction)
    // ---------------------------------------------------------
    // An instruction is runnable if Valid + Src1 Ready + Src2 Ready
    always_comb begin
        for (int i=0; i<NUM_SLOTS; i++) begin
            slots_runnable[i] = slots_valid[i] && 
                                slots[i].src1_ready && 
                                slots[i].src2_ready;
        end
    end

    logic [$clog2(NUM_SLOTS)-1:0] issue_idx;
    
    // Use your decoder again to pick the first ready instruction
    priority_decoder #(.WIDTH(NUM_SLOTS)) issue_decoder (
        .in(slots_runnable),
        .out(issue_idx),
        .valid(issue_valid)
    );

    assign issue_data = slots[issue_idx];

endmodule