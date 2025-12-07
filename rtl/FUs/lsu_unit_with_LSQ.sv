module lsu_unit #(
    parameter int ROB_TAG_W = 4,
    parameter int SQ_DEPTH  = 4  // Size of the Store Queue
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  valid_i,
    input  logic                  mem_read_i,
    input  logic                  mem_write_i,
    input  logic [31:0]           rs1_val_i, // Base
    input  logic [31:0]           rs2_val_i, // Store Data
    input  logic [31:0]           imm_i,     // Offset
    input  logic [5:0]            rd_p_i,
    input  logic [ROB_TAG_W-1:0]  rob_tag_i,
    input  logic [2:0]            funct3_i,    

    output logic                  ready_o,
    output logic                  valid_o,
    output logic [31:0]           result_o,
    output logic [5:0]            rd_p_o,
    output logic [ROB_TAG_W-1:0]  rob_tag_o
);

    logic [31:0] dmem [0:1023]; // 4KB Memory

    // Initialize memory for testing
    initial begin
        for (int i = 0; i < 1024; i++) dmem[i] = '0;
    end

    // =========================================================================
    // LOAD-STORE QUEUE (STORE BUFFER) DEFINITIONS
    // =========================================================================
    typedef struct packed {
        logic        valid;
        logic [31:0] addr;
        logic [31:0] data;
        logic [2:0]  funct3;
    } lsq_entry_t;

    lsq_entry_t sq [SQ_DEPTH];
    logic [$clog2(SQ_DEPTH)-1:0] sq_head, sq_tail;
    logic [$clog2(SQ_DEPTH):0]   sq_count; // Needs 1 extra bit for "full" state

    // =========================================================================
    // MAIN FSM
    // =========================================================================
    typedef enum logic [1:0] {S_IDLE, S_ACCESS, S_WB} state_t;
    state_t state, next_state;

    logic [31:0] addr;
    assign addr = rs1_val_i + imm_i;

    // Pipeline Registers
    logic [5:0]           rd_p_q;
    logic [ROB_TAG_W-1:0] rob_tag_q;
    logic [31:0]          mem_rdata_q;
    logic [31:0]          final_rdata_q; // Data after LSQ forwarding
    logic [1:0]           addr_offset_q;
    logic [2:0]           funct3_q;
    logic                 is_store_q;

    // =========================================================================
    // STORE QUEUE LOGIC (Enqueue & Drain)
    // =========================================================================
    
    // Helper: Determine write data based on Funct3 (SB/SH/SW)
    // Note: We do a read-modify-write inside the drain logic for sub-word support
    function logic [31:0] format_store_data(logic [31:0] old_mem, logic [31:0] new_val, logic [1:0] offset, logic [2:0] f3);
        logic [31:0] formatted;
        formatted = old_mem;
        case (f3)
            3'b000: begin // SB
                case (offset)
                    2'b00: formatted[7:0]   = new_val[7:0];
                    2'b01: formatted[15:8]  = new_val[7:0];
                    2'b10: formatted[23:16] = new_val[7:0];
                    2'b11: formatted[31:24] = new_val[7:0];
                endcase
            end
            3'b001: begin // SH
                case (offset[1])
                    1'b0: formatted[15:0]  = new_val[15:0];
                    1'b1: formatted[31:16] = new_val[15:0];
                endcase
            end
            3'b010: formatted = new_val; // SW
        endcase
        return formatted;
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            sq_head <= '0;
            sq_tail <= '0;
            sq_count <= '0;
            for(int i=0; i<SQ_DEPTH; i++) sq[i].valid <= 0;
        end else begin
            
            // 1. ENQUEUE (Dispatch a Store)
            // If we are in S_IDLE and receive a WRITE, we push to SQ (instead of writing dmem)
            if (state == S_IDLE && valid_i && mem_write_i && sq_count < SQ_DEPTH) begin
                sq[sq_tail].valid  <= 1'b1;
                sq[sq_tail].addr   <= addr;
                sq[sq_tail].data   <= rs2_val_i;
                sq[sq_tail].funct3 <= funct3_i;
                
                sq_tail <= sq_tail + 1'b1;
                sq_count <= sq_count + 1'b1;
            end

            // 2. DRAIN (Write to Memory)
            // If we are NOT accessing memory for a new Load, we can drain the SQ
            // (Cycle Stealing logic)
            else if (sq_count > 0 && !(state == S_IDLE && valid_i && mem_read_i)) begin
                // We perform the Write to DMEM
                // Note: For full correctness with SB/SH, we read dmem, modify, and write back.
                // Simplified here: We assume the LSQ 'drain' has exclusive access this cycle.
                
                // Read-Modify-Write for sub-word accuracy:
                dmem[sq[sq_head].addr[11:2]] <= format_store_data(
                    dmem[sq[sq_head].addr[11:2]], 
                    sq[sq_head].data, 
                    sq[sq_head].addr[1:0], 
                    sq[sq_head].funct3
                );

                sq[sq_head].valid <= 0; // Invalidate
                sq_head <= sq_head + 1'b1;
                sq_count <= sq_count - 1'b1;
            end
        end
    end

    // =========================================================================
    // LOAD FORWARDING LOGIC
    // =========================================================================
    logic [31:0] forwarded_data;
    logic        forward_hit;

    always_comb begin
        forward_hit = 1'b0;
        forwarded_data = '0;
        
        // Scan SQ from Tail (youngest) to Head (oldest) to find most recent match
        // Note: Simple linear scan for small LSQ
        for (int i=0; i<SQ_DEPTH; i++) begin
            if (sq[i].valid && sq[i].addr[31:2] == addr[31:2]) begin
                // HIT! (Word aligned match)
                // In a real CPU, you'd merge bytes. Here we assume full forwarding for simplicity.
                forwarded_data = sq[i].data;
                forward_hit = 1'b1;
            end
        end
    end

    // =========================================================================
    // PIPELINE LOGIC
    // =========================================================================
    
    always_ff @(posedge clk) begin
        if (state == S_IDLE && valid_i) begin
            // 1. Read from Memory (Default)
            mem_rdata_q   <= dmem[addr[11:2]];
            
            // 2. Latch Forwarding Status
            // If we hit in LSQ, we will overwrite mem_rdata_q in the output stage
            // or we can mux it here. Let's mux it in the S_WB stage logic or input latch.
            // Actually, BRAM read takes 1 cycle. Forwarding is combinational.
            // Let's store the fact that we hit.
            
            // Capture Metadata
            rd_p_q        <= rd_p_i;
            rob_tag_q     <= rob_tag_i;
            addr_offset_q <= addr[1:0];
            funct3_q      <= funct3_i;
            is_store_q    <= mem_write_i;
        end
    end

    // --- State Machine ---
    always_ff @(posedge clk) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end

    always_comb begin
        next_state = state;
        ready_o    = 1'b0;
        valid_o    = 1'b0;

        case (state)
            S_IDLE: begin
                // Ready unless SQ is full and we want to store
                ready_o = !(mem_write_i && sq_count == SQ_DEPTH); 
                if (valid_i && ready_o) next_state = S_ACCESS;
            end

            S_ACCESS: begin
                next_state = S_WB;
            end

            S_WB: begin
                if (!is_store_q) valid_o = 1'b1;
                next_state = S_IDLE;
            end
        endcase
    end

    // =========================================================================
    // OUTPUT GENERATION (With Forwarding Mux)
    // =========================================================================
    
    // We need to re-check forwarding in the S_ACCESS cycle or latch the hit result.
    // Ideally, forwarding happens completely combinatorially based on the LSQ state 
    // *at the time of issue*. 
    
    // Simplification for Project: 
    // We will combine the BRAM read result (mem_rdata_q) with LSQ forwarding logic.
    // Note: This logic assumes the Store hasn't drained yet.
    
    // Re-implement simplified forwarding check based on latched data? 
    // No, strictly speaking, we should have latched the 'forwarded_data' in Cycle 0.
    // Let's fix the always_ff block above to capture forwarded data.
    
    logic [31:0] effective_load_data;
    logic [31:0] latched_forward_data;
    logic        latched_hit;

    // Enhance the main always_ff to capture forwarding
    always_ff @(posedge clk) begin
        if (state == S_IDLE && valid_i) begin
            latched_forward_data <= forwarded_data;
            latched_hit          <= forward_hit;
        end
    end

    // Final Mux: Memory vs LSQ
    assign effective_load_data = (latched_hit) ? latched_forward_data : mem_rdata_q;

    // Sub-word Selection (LB/LH/LW)
    logic [31:0] final_formatted_data;
    always_comb begin
        final_formatted_data = effective_load_data; // Default

        case (funct3_q)
            3'b000: begin // LB
                case (addr_offset_q)
                    2'b00: final_formatted_data = {{24{effective_load_data[7]}},  effective_load_data[7:0]};
                    2'b01: final_formatted_data = {{24{effective_load_data[15]}}, effective_load_data[15:8]};
                    2'b10: final_formatted_data = {{24{effective_load_data[23]}}, effective_load_data[23:16]};
                    2'b11: final_formatted_data = {{24{effective_load_data[31]}}, effective_load_data[31:24]};
                endcase
            end
            3'b001: begin // LH
                case (addr_offset_q[1])
                    1'b0: final_formatted_data = {{16{effective_load_data[15]}}, effective_load_data[15:0]};
                    1'b1: final_formatted_data = {{16{effective_load_data[31]}}, effective_load_data[31:16]};
                endcase
            end
            3'b010: final_formatted_data = effective_load_data; // LW
            3'b100: begin // LBU
                case (addr_offset_q)
                    2'b00: final_formatted_data = {24'b0, effective_load_data[7:0]};
                    2'b01: final_formatted_data = {24'b0, effective_load_data[15:8]};
                    2'b10: final_formatted_data = {24'b0, effective_load_data[23:16]};
                    2'b11: final_formatted_data = {24'b0, effective_load_data[31:24]};
                endcase
            end
            3'b101: begin // LHU
                case (addr_offset_q[1])
                    1'b0: final_formatted_data = {16'b0, effective_load_data[15:0]};
                    1'b1: final_formatted_data = {16'b0, effective_load_data[31:16]};
                endcase
            end
        endcase
    end

    assign result_o  = final_formatted_data;
    assign rd_p_o    = is_store_q ? 6'd0 : rd_p_q;
    assign rob_tag_o = rob_tag_q;

endmodule