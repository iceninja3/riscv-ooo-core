module rob #(
    parameter int ROB_DEPTH = 16,
    parameter int TAG_WIDTH = 6
) (
    input  logic clk,
    input  logic rst,

    // Dispatch Interface (Allocation)
    input  logic alloc_valid_i,
    input  cpu_types_pkg::dispatch_packet_t alloc_pkt_i,
    output logic full_o,
    output logic [TAG_WIDTH-1:0] tail_ptr_o,

    // WRITEBACK INTERFACE (New)
    // The CDB tells us: "Tag X is done!"
    input  cpu_types_pkg::cdb_t cdb_i,

    // COMMIT INTERFACE (New)
    // To Rename/FreeList
    output logic commit_valid_o,
    output logic [5:0] commit_free_preg_o, // The OLD phys reg to free
    output logic [5:0] commit_new_preg_o,  // The NEW phys reg (now architectural)
    output logic [4:0] commit_lreg_o       // Logical reg for debug/RAT
);
    import cpu_types_pkg::*;

    rob_entry_t entries [ROB_DEPTH];
    logic [$clog2(ROB_DEPTH)-1:0] head, tail;
    logic [$clog2(ROB_DEPTH):0]   count;

    assign full_o = (count == ROB_DEPTH);

    // ============================================================
    // COMMIT LOGIC
    // ============================================================
    // 1. Peek at the Head. Is it valid and complete?
    assign commit_valid_o = (count > 0) && entries[head].valid && entries[head].complete;

    // 2. Output the data required by Rename to free the old register
    assign commit_free_preg_o = entries[head].old_rd_phys;
    
    // (Optional) Useful for debug or Arch RAT
    assign commit_lreg_o      = entries[head].rd_log;
    assign commit_new_preg_o  = entries[head].rd_phys;

    always_ff @(posedge clk) begin
        if (rst) begin
            head  <= '0;
            tail  <= '0;
            count <= '0;
            for(int i=0; i<ROB_DEPTH; i++) begin
                entries[i].valid    <= 0;
                entries[i].complete <= 0;
            end
        end else begin
            
            // --- ALLOCATION (Dispatch) ---
            if (alloc_valid_i && !full_o) begin
                entries[tail].valid       <= 1'b1;
                entries[tail].complete    <= 1'b0; // Not done yet
                entries[tail].rd_log      <= alloc_pkt_i.rd_log;
                entries[tail].rd_phys     <= alloc_pkt_i.rd_phys;
                entries[tail].old_rd_phys <= alloc_pkt_i.old_rd_phys;
                entries[tail].pc          <= alloc_pkt_i.pc;
                
                tail  <= tail + 1'b1;
                // Only increment count if we aren't simultaneously committing
                if (!commit_valid_o) count <= count + 1'b1;
            end

            // --- WRITEBACK (Update) ---
            // If CDB says "Tag 5 finished", we find the ROB entry for Tag 5 
            // and mark it complete. 
            // Note: In a real ROB, you might index by ROB ID. 
            // Here, we scan or assume CDB tag maps to ROB. 
            // For this specific simplified "Read-After-Issue" design, 
            // let's assume the CDB carries the Physical Register ID.
            if (cdb_i.valid) begin
                // We must search which ROB entry owns this physical register.
                // (Optimization: Usually we store ROB ID in the RS to avoid this search)
                for (int i=0; i<ROB_DEPTH; i++) begin
                    if (entries[i].valid && entries[i].rd_phys == cdb_i.tag) begin
                        entries[i].complete <= 1'b1;
                    end
                end
            end

            // --- COMMIT (Retirement) ---
            if (commit_valid_o) begin
                entries[head].valid <= 1'b0; // Clear the entry
                head <= head + 1'b1;
                
                // If we aren't allocating new ones, count goes down
                if (!(alloc_valid_i && !full_o)) count <= count - 1'b1;
            end
        end
    end

endmodule