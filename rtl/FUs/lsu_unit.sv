module lsu_unit (
    input  logic        clk, rst,
    input  logic        valid_i,
    input  logic        mem_read_i,
    input  logic [31:0] rs1_val_i, // Base
    input  logic [31:0] imm_i,     // Offset
    input  logic [5:0]  rd_p_i,
    input  logic [5:0]  rob_tag_i,
    output logic        ready_o,   // Backpressure to RS

    output logic        valid_o,
    output logic [31:0] result_o,
    output logic [5:0]  rd_p_o,
    output logic [5:0]  rob_tag_o
);
    // BRAM Memory Array
    logic [31:0] dmem [0:1023]; // 4KB

    // State Machine
    typedef enum logic [1:0] {S_IDLE, S_ACCESS, S_WB} state_t;
    state_t state, next_state;

    logic [31:0] addr;
    assign addr = rs1_val_i + imm_i;

    // Registers to hold metadata during latency
    logic [5:0] rd_p_q;
    logic [5:0] rob_tag_q;

    // BRAM Read Port
    logic [31:0] mem_rdata;
    always_ff @(posedge clk) begin
        if (state == S_IDLE && valid_i && mem_read_i) begin
            mem_rdata <= dmem[addr[11:2]]; // Word align
            rd_p_q    <= rd_p_i;
            rob_tag_q <= rob_tag_i;
        end
    end

    // FSM
    always_ff @(posedge clk) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end

    always_comb begin
        next_state = state;
        ready_o    = 0;
        valid_o    = 0;

        case (state)
            S_IDLE: begin
                ready_o = 1;
                if (valid_i) next_state = S_ACCESS; // Cycle 1 (Addr setup)
            end
            S_ACCESS: begin
                next_state = S_WB; // Cycle 2 (Data Read)
            end
            S_WB: begin
                valid_o = 1;
                next_state = S_IDLE;
            end
        endcase
    end

    assign result_o  = mem_rdata;
    assign rd_p_o    = rd_p_q;
    assign rob_tag_o = rob_tag_q;

endmodule