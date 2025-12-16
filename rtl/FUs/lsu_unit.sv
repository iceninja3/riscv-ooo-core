module lsu_unit #(
    parameter int ROB_TAG_W = 4
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
    
    // Need funct3 to distinguish LB/LBU/LH/LW/SB/SH/SW
    input  logic [2:0]            funct3_i,    

    output logic                  ready_o,
    output logic                  valid_o,
    output logic [31:0]           result_o,
    
    // CRITICAL WIRING NOTE:
    // 1. Connect 'rd_p_o'    -> Reservation Station (cdb_tag) for Wakeup.
    // 2. Connect 'rob_tag_o' -> ROB (cdb_tag_i) for Commit/Retire.
    output logic [5:0]            rd_p_o,
    output logic [ROB_TAG_W-1:0]  rob_tag_o
);

    logic [31:0] dmem [0:1023]; // 4KB Memory

    // Initialize memory for testing
    initial begin
        for (int i = 0; i < 1024; i++) dmem[i] = '0;
    end

    // FSM States
    typedef enum logic [1:0] {S_IDLE, S_ACCESS, S_WB} state_t;
    state_t state, next_state;

    // Address Calculation (Combinational)
    logic [31:0] addr;
    assign addr = rs1_val_i + imm_i;

    // Metadata storage (Pipeline Registers)
    logic [5:0]           rd_p_q;
    logic [ROB_TAG_W-1:0] rob_tag_q;
    logic [31:0]          mem_rdata_q;   // Data read from memory
    logic [31:0]          store_data_q;  // Data to store
    logic [1:0]           addr_offset_q; // Bottom 2 bits of address
    logic [9:0]           addr_idx_q;    // <--- NEW: Capture the index [11:2]
    logic [2:0]           funct3_q;
    logic                 is_store_q;

    // --- Synchronous Memory Access ---
    always @(posedge clk) begin
        // 1. CYCLE 0: S_IDLE -> Start Operation
        if (state == S_IDLE && valid_i) begin
            // Read is harmless even for Stores (needed for sub-word RMW)
            mem_rdata_q   <= dmem[addr[11:2]]; 
            
            // Capture Metadata
            rd_p_q        <= rd_p_i;
            rob_tag_q     <= rob_tag_i;
            store_data_q  <= rs2_val_i;
            
            // Capture Address Info
            addr_offset_q <= addr[1:0];      // Save byte offset
            addr_idx_q    <= addr[11:2];     // <--- FIX: Save the row index!
            
            funct3_q      <= funct3_i;
            is_store_q    <= mem_write_i;
        end 

        // 2. CYCLE 2: S_WB -> Perform Store Write (if needed)
        // We write when transitioning OUT of S_ACCESS into S_WB
        if (state == S_ACCESS && is_store_q) begin
            logic [31:0] wdata_combined;
            wdata_combined = mem_rdata_q; // Default to old data (Read-Modify-Write)

            case (funct3_q) // SB, SH, SW
                3'b000: begin // SB
                    case (addr_offset_q)
                        2'b00: wdata_combined[7:0]   = store_data_q[7:0];
                        2'b01: wdata_combined[15:8]  = store_data_q[7:0];
                        2'b10: wdata_combined[23:16] = store_data_q[7:0];
                        2'b11: wdata_combined[31:24] = store_data_q[7:0];
                    endcase
                end
                3'b001: begin // SH
                    case (addr_offset_q[1])
                        1'b0: wdata_combined[15:0]  = store_data_q[15:0];
                        1'b1: wdata_combined[31:16] = store_data_q[15:0];
                    endcase
                end
                3'b010: begin // SW
                    wdata_combined = store_data_q;
                end
            endcase

            // Perform the Write using the CAPTURED address
            // Use addr_idx_q, NOT addr[11:2] (which is now garbage)
            dmem[addr_idx_q] <= wdata_combined; 
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
                ready_o = 1'b1;
                if (valid_i) next_state = S_ACCESS;
            end

            S_ACCESS: begin
                // One cycle latency for memory access/store logic
                next_state = S_WB;
            end

            S_WB: begin
                // BOTH loads and stores signal completion to ROB via CDB.
                valid_o    = 1'b1; 
                next_state = S_IDLE;
            end
        endcase
    end

    // --- LOAD OUTPUT LOGIC (LBU / LB / LW / LH / LHU) ---
    logic [31:0] final_load_data;
    
    always_comb begin
        final_load_data = mem_rdata_q; // Default to LW

        case (funct3_q)
            3'b000: begin // LB
                case (addr_offset_q)
                    2'b00: final_load_data = {{24{mem_rdata_q[7]}},  mem_rdata_q[7:0]};
                    2'b01: final_load_data = {{24{mem_rdata_q[15]}}, mem_rdata_q[15:8]};
                    2'b10: final_load_data = {{24{mem_rdata_q[23]}}, mem_rdata_q[23:16]};
                    2'b11: final_load_data = {{24{mem_rdata_q[31]}}, mem_rdata_q[31:24]};
                endcase
            end
            3'b001: begin // LH
                case (addr_offset_q[1])
                    1'b0: final_load_data = {{16{mem_rdata_q[15]}}, mem_rdata_q[15:0]};
                    1'b1: final_load_data = {{16{mem_rdata_q[31]}}, mem_rdata_q[31:16]};
                endcase
            end
            3'b010: begin // LW
                final_load_data = mem_rdata_q;
            end
            3'b100: begin // LBU
                case (addr_offset_q)
                    2'b00: final_load_data = {24'b0, mem_rdata_q[7:0]};
                    2'b01: final_load_data = {24'b0, mem_rdata_q[15:8]};
                    2'b10: final_load_data = {24'b0, mem_rdata_q[23:16]};
                    2'b11: final_load_data = {24'b0, mem_rdata_q[31:24]};
                endcase
            end
            3'b101: begin // LHU
                case (addr_offset_q[1])
                    1'b0: final_load_data = {16'b0, mem_rdata_q[15:0]};
                    1'b1: final_load_data = {16'b0, mem_rdata_q[31:16]};
                endcase
            end
        endcase
    end

    // Stores don't write a register, so squash rd_p for them
    // This 'rd_p_o' goes to RS for Wakeup.
    // 'rob_tag_o' goes to ROB for Commit.
    assign result_o  = final_load_data;
    assign rd_p_o    = is_store_q ? 6'd0 : rd_p_q;
    assign rob_tag_o = rob_tag_q;

endmodule
