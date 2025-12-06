module lsu_unit #(
    parameter int ROB_TAG_W = 4
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  valid_i,
    input  logic                  mem_read_i,
    input  logic [31:0]           rs1_val_i, // Base
    input  logic [31:0]           imm_i,     // Offset
    input  logic [5:0]            rd_p_i,
    input  logic [ROB_TAG_W-1:0]  rob_tag_i,

    // Backpressure to RS
    output logic                  ready_o,

    // To CDB
    output logic                  valid_o,
    output logic [31:0]           result_o,
    output logic [5:0]            rd_p_o,
    output logic [ROB_TAG_W-1:0]  rob_tag_o
);
    // BRAM Memory Array (simple model)
    logic [31:0] dmem [0:1023]; // 4KB word-addressable
	 
	 initial begin
        integer i;
        for (i = 0; i < 1024; i++) begin
            dmem[i] = '0;
        end
    end

    // State Machine
    typedef enum logic [1:0] {S_IDLE, S_ACCESS, S_WB} state_t;
    state_t state, next_state;

    logic [31:0] addr;
    assign addr = rs1_val_i + imm_i;

    // Registers to hold metadata during latency
    logic [5:0]           rd_p_q;
    logic [ROB_TAG_W-1:0] rob_tag_q;

    // BRAM Read Port (1R, synchronous-ish model)
    logic [31:0] mem_rdata;
    always_ff @(posedge clk) begin
        if (state == S_IDLE && valid_i && mem_read_i) begin
            // Word aligned access: use bits [11:2] for 4-byte words
            mem_rdata <= dmem[addr[11:2]];
            rd_p_q    <= rd_p_i;
            rob_tag_q <= rob_tag_i;
        end
    end

    // FSM state register
    always_ff @(posedge clk) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end

    // FSM next-state and outputs
    always_comb begin
        next_state = state;
        ready_o    = 1'b0;
        valid_o    = 1'b0;

        case (state)
            S_IDLE: begin
                ready_o = 1'b1;  // ready to accept a new request
                if (valid_i && mem_read_i)
                    next_state = S_ACCESS; // Cycle 1 (address issue)
            end

            S_ACCESS: begin
                // BRAM read happens; data will be available next cycle
                next_state = S_WB; // Cycle 2 (data available)
            end

            S_WB: begin
                valid_o    = 1'b1;  // send result to CDB
                next_state = S_IDLE;
            end
        endcase
    end

    // Outputs to CDB
    assign result_o  = mem_rdata;
    assign rd_p_o    = rd_p_q;
    assign rob_tag_o = rob_tag_q;

endmodule