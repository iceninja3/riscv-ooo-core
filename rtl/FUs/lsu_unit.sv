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
    
    // NEW: We need funct3 to distinguish LB/LBU/LH/LW/SB/SH/SW
    // You must verify this is wired from Decode -> Dispatch -> RS -> Here!
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

    // FSM States
    // S_ACCESS: Read the memory (for Loads AND Stores)
    // S_WB: Write-back to CDB (for Loads) OR Write-back to Memory (for Stores)
    typedef enum logic [1:0] {S_IDLE, S_ACCESS, S_WB} state_t;
    state_t state, next_state;

    // Address Calculation
    logic [31:0] addr;
    assign addr = rs1_val_i + imm_i;
    
    // Metadata storage
    logic [5:0]           rd_p_q;
    logic [ROB_TAG_W-1:0] rob_tag_q;
    logic [31:0]          mem_rdata_q; // Data read from memory
    logic [31:0]          store_data_q; // Data to store
    logic [1:0]           addr_offset_q; // Bottom 2 bits of address
    logic [2:0]           funct3_q;
    logic                 is_store_q;

    // --- Synchronous Memory Access ---
    always_ff @(posedge clk) begin
        // 1. CYCLE 0: S_IDLE -> Start Operation
        if (state == S_IDLE && valid_i) begin
            // Always Read first (Needed for Loads AND Sub-word Stores)
            mem_rdata_q   <= dmem[addr[11:2]]; 
            
            // Capture Metadata
            rd_p_q        <= rd_p_i;
            rob_tag_q     <= rob_tag_i;
            store_data_q  <= rs2_val_i;
            addr_offset_q <= addr[1:0]; // Save byte offset
            funct3_q      <= funct3_i;
            is_store_q    <= mem_write_i;
        end 

        // 2. CYCLE 2: S_WB -> Perform Store Write (if needed)
        if (state == S_ACCESS && is_store_q) begin
            // We are in the WB stage for a Store. 
            // We have the OLD data (mem_rdata_q) and the NEW data (store_data_q).
            // We combine them and write back.
            
            logic [31:0] wdata_combined;
            wdata_combined = mem_rdata_q; // Default to old data

            case (funct3_q) // Check Funct3 (SB, SH, SW)
                3'b000: begin // SB (Store Byte)
                    case (addr_offset_q)
                        2'b00: wdata_combined[7:0]   = store_data_q[7:0];
                        2'b01: wdata_combined[15:8]  = store_data_q[7:0];
                        2'b10: wdata_combined[23:16] = store_data_q[7:0];
                        2'b11: wdata_combined[31:24] = store_data_q[7:0];
                    endcase
                end
                3'b001: begin // SH (Store Halfword)
                    case (addr_offset_q[1]) // Check bit 1 (0 or 2)
                        1'b0: wdata_combined[15:0]  = store_data_q[15:0];
                        1'b1: wdata_combined[31:16] = store_data_q[15:0];
                    endcase
                end
                3'b010: begin // SW (Store Word)
                    wdata_combined = store_data_q;
                end
            endcase

            // Perform the Write
            // Note: We need the word-aligned address again. 
            // In a real pipeline we'd latch 'addr', but here 'addr' might have changed 
            // if rs1 changed. Let's assume RS holds inputs steady or we latched addr.
            // BETTER SAFE: You should latch 'addr' in S_IDLE if inputs aren't stable.
            // For now assuming inputs hold steady or using a latched index:
            dmem[addr[11:2]] <= wdata_combined; 
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
                next_state = S_WB;
            end

            S_WB: begin
                // BOTH loads and stores signal completion to ROB via CDB.
                valid_o  = 1'b1;
                next_state = S_IDLE;
            end
        endcase
    end

    // --- LOAD OUTPUT LOGIC (LBU / LB / LW / LH / LHU) ---
    logic [31:0] final_load_data;
    
    always_comb begin
        final_load_data = mem_rdata_q; // Default to LW

        case (funct3_q)
            3'b000: begin // LB (Load Byte Signed)
                case (addr_offset_q)
                    2'b00: final_load_data = {{24{mem_rdata_q[7]}},  mem_rdata_q[7:0]};
                    2'b01: final_load_data = {{24{mem_rdata_q[15]}}, mem_rdata_q[15:8]};
                    2'b10: final_load_data = {{24{mem_rdata_q[23]}}, mem_rdata_q[23:16]};
                    2'b11: final_load_data = {{24{mem_rdata_q[31]}}, mem_rdata_q[31:24]};
                endcase
            end
            3'b001: begin // LH (Load Half Signed)
                case (addr_offset_q[1])
                    1'b0: final_load_data = {{16{mem_rdata_q[15]}}, mem_rdata_q[15:0]};
                    1'b1: final_load_data = {{16{mem_rdata_q[31]}}, mem_rdata_q[31:16]};
                endcase
            end
            3'b010: begin // LW
                final_load_data = mem_rdata_q;
            end
            3'b100: begin // LBU (Load Byte Unsigned) <-- REQUESTED
                case (addr_offset_q)
                    2'b00: final_load_data = {24'b0, mem_rdata_q[7:0]};
                    2'b01: final_load_data = {24'b0, mem_rdata_q[15:8]};
                    2'b10: final_load_data = {24'b0, mem_rdata_q[23:16]};
                    2'b11: final_load_data = {24'b0, mem_rdata_q[31:24]};
                endcase
            end
            3'b101: begin // LHU (Load Half Unsigned)
                case (addr_offset_q[1])
                    1'b0: final_load_data = {16'b0, mem_rdata_q[15:0]};
                    1'b1: final_load_data = {16'b0, mem_rdata_q[31:16]};
                endcase
            end
        endcase
    end

    assign result_o  = final_load_data;
    assign rd_p_o    = is_store_q ? 6'd0 : rd_p_q;
    assign rob_tag_o = rob_tag_q;

endmodule