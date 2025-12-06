module reservation_station #(
    parameter NUM_SLOTS = 8,
    parameter N_PHYS    = 64
)(
    input logic clk, reset,

    // --- Interface with Dispatch ---
    input logic  write_en,
    // Note: This input is the PACKET from Dispatch (no ready bits yet)
    input pipeline_types::rs_issue_packet_t write_data, 
    
    // NEW: We need to know if registers are ALREADY ready in the PRF
    // (You need a busy-bit table in your top-level to drive these)
    input logic  src1_already_ready_i, 
    input logic  src2_already_ready_i,

    output logic full,

    // --- Interface with CDB (Wakeup) ---
    input logic       cdb_valid,
    input logic [5:0] cdb_tag,

    // --- Interface with Execution ---
    input  logic      issue_ready,
    output logic      issue_valid,
    output pipeline_types::rs_entry_t issue_data // Output full struct
);
    import pipeline_types::*;

    rs_entry_t slots [NUM_SLOTS-1:0];
    logic [NUM_SLOTS-1:0] slots_valid;
    logic [NUM_SLOTS-1:0] slots_runnable;

    // 1. ALLOCATION (Standard Priority Decoder)
    logic [$clog2(NUM_SLOTS)-1:0] free_idx;
    logic any_free;
	 
	 logic [$clog2(NUM_SLOTS)-1:0] issue_idx;
    
    // Use your priority decoder module here
    // (Assuming valid output means "found a 1")
    // We invert slots_valid to find the first '0'
    priority_decoder #(.WIDTH(NUM_SLOTS)) alloc_decoder (
        .in(~slots_valid),
        .out(free_idx),
        .valid(any_free)
    );
    assign full = ~any_free;

    // 2. LOGIC
    always_ff @(posedge clk) begin
        if (reset) begin
            slots_valid <= '0;
        end else begin
            
            // --- A. Allocation (Write from Dispatch) ---
            if (write_en && !full) begin
                slots_valid[free_idx] <= 1'b1;
                
                // Copy Data Fields
                slots[free_idx].pc      <= write_data.pc;
                slots[free_idx].imm     <= write_data.imm;
                slots[free_idx].alu_op  <= write_data.alu_op;
                slots[free_idx].alu_src <= write_data.alu_src;
                slots[free_idx].p_src1  <= write_data.rs1_p;
                slots[free_idx].p_src2  <= write_data.rs2_p;
                slots[free_idx].p_dst   <= write_data.rd_p;
                slots[free_idx].rob_tag <= write_data.rob_tag;
					 
					 slots[free_idx].is_branch <= write_data.is_branch;
					 slots[free_idx].is_jump   <= write_data.is_jump;

                // --- SMART READY BIT INITIALIZATION ---
                
                // SRC 1: Ready if (Already Ready in PRF) OR (Waking up on CDB right now!)
                if (src1_already_ready_i || (cdb_valid && cdb_tag == write_data.rs1_p))
                    slots[free_idx].src1_ready <= 1'b1;
                else
                    slots[free_idx].src1_ready <= 1'b0;

                // SRC 2: Ready if (Immediate Mode) OR (Already Ready) OR (Waking up)
                if (write_data.alu_src == 1'b1) // Immediate? Always ready!
                    slots[free_idx].src2_ready <= 1'b1;
                else if (src2_already_ready_i || (cdb_valid && cdb_tag == write_data.rs2_p))
                    slots[free_idx].src2_ready <= 1'b1;
                else
                    slots[free_idx].src2_ready <= 1'b0;
            end

            // --- B. Wakeup (Snoop the CDB) ---
            for (int i = 0; i < NUM_SLOTS; i++) begin
                if (slots_valid[i]) begin
                    // If we are waiting for this tag, set ready
                    if (cdb_valid && slots[i].p_src1 == cdb_tag)
                        slots[i].src1_ready <= 1'b1;
                    if (cdb_valid && slots[i].p_src2 == cdb_tag)
                        slots[i].src2_ready <= 1'b1;
                end
            end

            // --- C. Issue (Clear the slot) ---
            if (issue_valid && issue_ready) begin
                slots_valid[issue_idx] <= 1'b0;
            end
        end
    end

    // 3. ISSUE SELECTION
    always_comb begin
        for (int i=0; i<NUM_SLOTS; i++) begin
            // Runnable if Valid AND Both Sources Ready
            slots_runnable[i] = slots_valid[i] && slots[i].src1_ready && slots[i].src2_ready;
        end
    end
    
    
    priority_decoder #(.WIDTH(NUM_SLOTS)) issue_decoder (
        .in(slots_runnable),
        .out(issue_idx),
        .valid(issue_valid)
    );

    assign issue_data = slots[issue_idx];

endmodule