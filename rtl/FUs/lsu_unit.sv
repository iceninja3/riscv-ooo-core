module lsu_unit #(
    parameter int ROB_TAG_W = 4,
    parameter int SB_DEPTH  = 8   // Size of Store Buffer
)(
    input  logic                  clk,
    input  logic                  rst,
    
    // Execution / Issue Interface
    input  logic                  valid_i,
    input  logic                  mem_read_i,
    input  logic                  mem_write_i,
    input  logic [31:0]           rs1_val_i,
    input  logic [31:0]           rs2_val_i,
    input  logic [31:0]           imm_i,
    input  logic [5:0]            rd_p_i,
    input  logic [ROB_TAG_W-1:0]  rob_tag_i,
    input  logic [2:0]            funct3_i,

    // Outputs to Writeback/ROB
    output logic                  ready_o,
    output logic                  valid_o,
    output logic [31:0]           result_o,
    output logic [5:0]            rd_p_o,
    output logic [ROB_TAG_W-1:0]  rob_tag_o,

<<<<<<< HEAD
    // --- NEW: Commit Interface (Connect to ROB) ---
    input  logic                  commit_valid_i,   // High when ROB commits an instruction
    input  logic [ROB_TAG_W-1:0]  commit_tag_i,     // The ROB Tag of the committing instruction
    input  logic                  flush_i           // Flush signal (on mispredict)
=======
    // --- Commit Interface (Connect to ROB) ---
    input  logic                  commit_valid_i,
    input  logic [ROB_TAG_W-1:0]  commit_tag_i,
    input  logic                  flush_i
>>>>>>> b2aa51e (changes for lsu)
);

    // -------------------------------------------------------------------------
    // DMEM (single writer process only!)
    // -------------------------------------------------------------------------
    logic [31:0] dmem [0:1023];

    // -------------------------------------------------------------------------
    // 1. Store Buffer (FIFO) Definition
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic [31:0]          addr;
        logic [31:0]          data;
        logic [2:0]           funct3;
        logic [ROB_TAG_W-1:0] rob_tag;
        logic                 valid;
    } sb_entry_t;

<<<<<<< HEAD
    // -------------------------------------------------------------------------
    // 1. Store Buffer (FIFO) Definition
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic [31:0]          addr;
        logic [31:0]          data;
        logic [2:0]           funct3;
        logic [ROB_TAG_W-1:0] rob_tag;
        logic                 valid;
    } sb_entry_t;

    sb_entry_t sb_queue [SB_DEPTH];
    logic [$clog2(SB_DEPTH)-1:0] sb_head, sb_tail;
    logic [$clog2(SB_DEPTH):0]   sb_count;

=======
    sb_entry_t sb_queue [SB_DEPTH];
    logic [$clog2(SB_DEPTH)-1:0] sb_head, sb_tail;
    logic [$clog2(SB_DEPTH):0]   sb_count;

>>>>>>> b2aa51e (changes for lsu)
    logic sb_full, sb_empty;
    assign sb_full  = (sb_count == SB_DEPTH);
    assign sb_empty = (sb_count == 0);

    // -------------------------------------------------------------------------
    // 2. Address Calculation
    // -------------------------------------------------------------------------
    logic [31:0] addr;
    assign addr = rs1_val_i + imm_i;

    // -------------------------------------------------------------------------
<<<<<<< HEAD
    // 3. Store Buffer: Enqueue Logic (Execution Stage)
    // -------------------------------------------------------------------------
    // We only accept new Stores if the Buffer isn't full
    logic fire_store;
    assign fire_store = valid_i && mem_write_i && !sb_full;

    // We only accept new Loads if they don't hazard (see forwarding logic below)
    logic fire_load;
    logic stall_load; // logic defined later

    // Ready if we are not blocked by a full SB (for stores) or a hazard (for loads)
    assign ready_o = (mem_write_i) ? !sb_full : !stall_load;

    always_ff @(posedge clk) begin
        if (rst || flush_i) begin
            // On flush, we clear "speculative" entries by resetting tail to head
            // (Preserve committed stores that haven't written to RAM yet, discard the rest)
            // Ideally: sb_tail <= sb_head; 
            // Simplified: For this lab, assuming flush clears everything not yet in MEM:
            sb_tail <= sb_head; 
            sb_count <= 0; // Simplified reset
        end else begin
            // Enqueue Store
            if (fire_store) begin
                sb_queue[sb_tail].addr    <= addr;
                sb_queue[sb_tail].data    <= rs2_val_i; // Store Data
                sb_queue[sb_tail].funct3  <= funct3_i;
                sb_queue[sb_tail].rob_tag <= rob_tag_i;
                sb_queue[sb_tail].valid   <= 1'b1;
                
                sb_tail  <= sb_tail + 1'b1;
                sb_count <= sb_count + 1'b1;
            end
            
            // Dequeue Store (Commit Logic Handled Below, just updating count/head here if needed)
            // See the Commit Block for the actual memory write
             if (commit_valid_i && !sb_empty && (sb_queue[sb_head].rob_tag == commit_tag_i)) begin
                 // If we pushed and popped same cycle, count stays same. 
                 // Otherwise decrement.
                 if (!fire_store) sb_count <= sb_count - 1'b1;
                 sb_head <= sb_head + 1'b1;
             end
        end
    end

    // -------------------------------------------------------------------------
    // 4. Store Buffer: Commit Logic (Write to DMEM)
    // -------------------------------------------------------------------------
    // This is the critical fix: Only write to memory when ROB says "Commit"
    always_ff @(posedge clk) begin
        if (commit_valid_i && !sb_empty) begin
            // Check if the head of our queue matches the committing instruction
            if (sb_queue[sb_head].rob_tag == commit_tag_i) begin
                // PERFORM THE WRITE
                case (sb_queue[sb_head].funct3)
                    3'b000: begin // SB
                        case (sb_queue[sb_head].addr[1:0])
                            2'b00: dmem[sb_queue[sb_head].addr[31:2]][7:0]   <= sb_queue[sb_head].data[7:0];
                            2'b01: dmem[sb_queue[sb_head].addr[31:2]][15:8]  <= sb_queue[sb_head].data[7:0];
                            2'b10: dmem[sb_queue[sb_head].addr[31:2]][23:16] <= sb_queue[sb_head].data[7:0];
                            2'b11: dmem[sb_queue[sb_head].addr[31:2]][31:24] <= sb_queue[sb_head].data[7:0];
                        endcase
                    end
                    3'b001: begin // SH
                        case (sb_queue[sb_head].addr[1])
                            1'b0: dmem[sb_queue[sb_head].addr[31:2]][15:0]  <= sb_queue[sb_head].data[15:0];
                            1'b1: dmem[sb_queue[sb_head].addr[31:2]][31:16] <= sb_queue[sb_head].data[15:0];
                        endcase
                    end
                    3'b010: begin // SW
                        dmem[sb_queue[sb_head].addr[31:2]] <= sb_queue[sb_head].data;
                    end
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // 5. Load Logic (with Forwarding)
    // -------------------------------------------------------------------------
    logic [31:0] load_data_from_mem;
    logic [31:0] load_data_final;
    logic        forward_hit;
    logic [31:0] forward_data;

    // A. Read from Memory (Default)
    assign load_data_from_mem = dmem[addr[31:2]];

    // B. Check Store Buffer for hazards (Combinational)
    // We iterate from Tail (youngest) to Head (oldest) to find the most recent store to this address.
    always_comb begin
        forward_hit  = 1'b0;
        forward_data = 32'b0;
        stall_load   = 1'b0;

        if (valid_i && mem_read_i) begin
            // Loop through valid entries in SB
            for (int i = 0; i < SB_DEPTH; i++) begin
                // Note: In a real circular buffer check, you carefully iterate from tail-1 down to head.
                // For this simple implementation, we can just iterate all and take the youngest match.
                // However, SystemVerilog loops are tricky. 
                
                // simpler approach: Stall on ANY address match
                // This is "Safe" and easy to implement.
                // If you want performance, you implement full forwarding.
                
                // Check if entry 'i' is valid and addresses match
                /* Wait, we need to know if entry 'i' is actually "inside" the active window [Head, Tail].
                   Given the complexity of indices wrapping, the safest simple fix is:
                */
            end
        end
    end
    
    // --- SIMPLIFIED FORWARDING LOGIC ---
    // If ANY valid entry in the Store Buffer matches the Load Address, 
    // we STALL until that store commits. This is lower performance but 100% correct 
    // and much easier to write than full byte-mask forwarding.
    always_comb begin
        stall_load = 1'b0;
        if (valid_i && mem_read_i) begin
            for (int i = 0; i < SB_DEPTH; i++) begin
                 // Check if index i is valid (between head and tail)
                 // A simple way is to check if valid bit is high? We didn't clear valid bits on pop.
                 // Better: Use the count.
                 
                 // Actually, let's just cheat and check the whole array.
                 // If queue is not empty, check all.
                 // (Ideally you only check active ones, but checking stale data just causes unnecessary stalls, no bugs).
                 if (!sb_empty && (sb_queue[i].addr[31:2] == addr[31:2])) begin
                     // Check if this entry is actually active? 
                     // It's hard without complex pointer math.
                     
                     // Correct "Active" Check:
                     // active if (head <= tail) ? (i >= head && i < tail) : (i >= head || i < tail)
                     logic is_active;
                     if (sb_head <= sb_tail) 
                         is_active = (i >= sb_head && i < sb_tail);
                     else 
                         is_active = (i >= sb_head || i < sb_tail);
                         
                     if (is_active) stall_load = 1'b1; 
                 end
            end
        end
    end

    // C. Final Result Selection
    logic [31:0] mem_rdata;
    assign mem_rdata = load_data_from_mem; // Since we stall on hazard, we always read mem

    always_comb begin
        // Standard Load Extension Logic
=======
    // 3. Store / Load fire + stall
    // -------------------------------------------------------------------------
    logic stall_load;
    logic fire_store, fire_load;

    assign fire_store = valid_i && mem_write_i && !sb_full;
    assign fire_load  = valid_i && mem_read_i  && !stall_load;

    // Ready if store buffer not full (stores) OR no hazard (loads)
    assign ready_o = (mem_write_i) ? !sb_full : !stall_load;

    // -------------------------------------------------------------------------
    // 4. Load hazard detection (single driver for stall_load)
    // -------------------------------------------------------------------------
    always_comb begin
        stall_load = 1'b0;

        if (valid_i && mem_read_i && !sb_empty) begin
            for (int i = 0; i < SB_DEPTH; i++) begin
                if (sb_queue[i].addr[31:2] == addr[31:2]) begin
                    logic is_active;
                    if (sb_head <= sb_tail)
                        is_active = (i >= sb_head && i < sb_tail);
                    else
                        is_active = (i >= sb_head || i < sb_tail);

                    if (is_active) stall_load = 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 5. Read memory for loads (combinational read for now)
    // -------------------------------------------------------------------------
    logic [31:0] mem_rdata;
    assign mem_rdata = dmem[addr[31:2]];

    // Load sign/zero extension
    always_comb begin
>>>>>>> b2aa51e (changes for lsu)
        case (funct3_i)
            3'b000: begin // LB
                case (addr[1:0])
                    2'b00: result_o = {{24{mem_rdata[7]}},   mem_rdata[7:0]};
                    2'b01: result_o = {{24{mem_rdata[15]}},  mem_rdata[15:8]};
                    2'b10: result_o = {{24{mem_rdata[23]}},  mem_rdata[23:16]};
                    2'b11: result_o = {{24{mem_rdata[31]}},  mem_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH
                case (addr[1])
                    1'b0: result_o = {{16{mem_rdata[15]}},  mem_rdata[15:0]};
                    1'b1: result_o = {{16{mem_rdata[31]}},  mem_rdata[31:16]};
                endcase
            end
<<<<<<< HEAD
            3'b010: begin // LW
                result_o = mem_rdata;
            end
=======
            3'b010: result_o = mem_rdata; // LW
>>>>>>> b2aa51e (changes for lsu)
            3'b100: begin // LBU
                case (addr[1:0])
                    2'b00: result_o = {24'b0, mem_rdata[7:0]};
                    2'b01: result_o = {24'b0, mem_rdata[15:8]};
                    2'b10: result_o = {24'b0, mem_rdata[23:16]};
                    2'b11: result_o = {24'b0, mem_rdata[31:24]};
                endcase
            end
            3'b101: begin // LHU
                case (addr[1])
                    1'b0: result_o = {16'b0, mem_rdata[15:0]};
                    1'b1: result_o = {16'b0, mem_rdata[31:16]};
                endcase
            end
            default: result_o = 32'b0;
        endcase
    end

    // -------------------------------------------------------------------------
<<<<<<< HEAD
    // 6. Final Output Registration
    // -------------------------------------------------------------------------
    // We register the output to match your original pipeline timing
    // Note: If you stall, we shouldn't update the output valid? 
    // Your original code just registered valid_i.
    
    assign fire_load = valid_i && mem_read_i && !stall_load;
    
    always_ff @(posedge clk) begin
        if (rst || flush_i) begin
            valid_o   <= 1'b0;
            rd_p_o    <= '0;
            rob_tag_o <= '0;
        end else begin
            // Stores are "done" as soon as they hit the buffer (from Execute perspective)
            if (fire_store) begin
                valid_o   <= 1'b1;
                rd_p_o    <= rd_p_i; // Stores usually don't write back, but we keep protocol
                rob_tag_o <= rob_tag_i;
            end 
            // Loads are done if they didn't stall
            else if (fire_load) begin
                valid_o   <= 1'b1;
                rd_p_o    <= rd_p_i;
                rob_tag_o <= rob_tag_i;
            end 
            else begin
                valid_o   <= 1'b0;
=======
    // 6. ONE sequential process for:
    //    - DMEM init on reset (simulation-friendly)
    //    - SB enqueue/dequeue
    //    - DMEM write on commit
    //    - output valid/tag registration
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            // clear SB
            sb_head  <= '0;
            sb_tail  <= '0;
            sb_count <= '0;

            // clear outputs
            valid_o   <= 1'b0;
            rd_p_o    <= '0;
            rob_tag_o <= '0;

            // clear memory (simulation ok; synth may not like this)
            for (int k = 0; k < 1024; k++) begin
                dmem[k] <= '0;
            end

        end else if (flush_i) begin
            // flush: drop speculative SB contents (simple policy)
            sb_head  <= '0;
            sb_tail  <= '0;
            sb_count <= '0;

            valid_o   <= 1'b0;
            rd_p_o    <= '0;
            rob_tag_o <= '0;

        end else begin
            // --------------------
            // ENQUEUE STORE
            // --------------------
            if (fire_store) begin
                sb_queue[sb_tail].addr    <= addr;
                sb_queue[sb_tail].data    <= rs2_val_i;
                sb_queue[sb_tail].funct3  <= funct3_i;
                sb_queue[sb_tail].rob_tag <= rob_tag_i;
                sb_queue[sb_tail].valid   <= 1'b1;

                sb_tail  <= sb_tail + 1'b1;
                sb_count <= sb_count + 1'b1;
            end

            // --------------------
            // COMMIT STORE: write DMEM + dequeue if head matches
            // --------------------
            if (commit_valid_i && !sb_empty && (sb_queue[sb_head].rob_tag == commit_tag_i)) begin
                // DMEM write
                case (sb_queue[sb_head].funct3)
                    3'b000: begin // SB
                        case (sb_queue[sb_head].addr[1:0])
                            2'b00: dmem[sb_queue[sb_head].addr[31:2]][7:0]   <= sb_queue[sb_head].data[7:0];
                            2'b01: dmem[sb_queue[sb_head].addr[31:2]][15:8]  <= sb_queue[sb_head].data[7:0];
                            2'b10: dmem[sb_queue[sb_head].addr[31:2]][23:16] <= sb_queue[sb_head].data[7:0];
                            2'b11: dmem[sb_queue[sb_head].addr[31:2]][31:24] <= sb_queue[sb_head].data[7:0];
                        endcase
                    end
                    3'b001: begin // SH
                        case (sb_queue[sb_head].addr[1])
                            1'b0: dmem[sb_queue[sb_head].addr[31:2]][15:0]  <= sb_queue[sb_head].data[15:0];
                            1'b1: dmem[sb_queue[sb_head].addr[31:2]][31:16] <= sb_queue[sb_head].data[15:0];
                        endcase
                    end
                    3'b010: begin // SW
                        dmem[sb_queue[sb_head].addr[31:2]] <= sb_queue[sb_head].data;
                    end
                    default: ;
                endcase

                // dequeue
                sb_head <= sb_head + 1'b1;
                if (!fire_store) sb_count <= sb_count - 1'b1;
            end

            // --------------------
            // "Done" protocol to ROB (same as your original intent)
            // --------------------
            if (fire_store) begin
                valid_o   <= 1'b1;
                rd_p_o    <= rd_p_i;
                rob_tag_o <= rob_tag_i;
            end else if (fire_load) begin
                valid_o   <= 1'b1;
                rd_p_o    <= rd_p_i;
                rob_tag_o <= rob_tag_i;
            end else begin
                valid_o <= 1'b0;
>>>>>>> b2aa51e (changes for lsu)
            end
        end
    end

endmodule