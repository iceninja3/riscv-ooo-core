module Fetch #(
    parameter int ADDR_WIDTH = 9,
    parameter int DATA_WIDTH = 32,
    parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
    input  logic                  clk,
    input  logic                  reset,
    input  logic        btb_hit_i,
    input  logic        btb_pred_taken_i,
    input  logic [31:0] btb_pred_target_i,

    output logic [ADDR_WIDTH-1:0] icache_addr,
    input  logic [DATA_WIDTH-1:0] icache_rdata,

    input  logic                  redirect_valid_i,
    input  logic [31:0]           redirect_pc_i,

    output logic                  valid_o,
    input  logic                  ready_i,
    output logic [31:0]           pc_o,
    output logic [DATA_WIDTH-1:0] inst_o
);


    logic [31:0] pc_next;
    logic [31:0] pc_f1;
    logic [31:0] pc_f2;
    logic [31:0] pc_at_icache;

    logic valid_f1;
    logic valid_f2;

    assign icache_addr = pc_next[ADDR_WIDTH+1:2];

    always_ff @(posedge clk) begin
            if (reset) begin
                pc_next  <= RESET_PC;
                pc_o     <= '0;
                inst_o   <= '0;
                valid_o  <= 1'b0;
            end
            else if (redirect_valid_i) begin
                pc_next  <= redirect_pc_i;
                valid_o  <= 1'b0;
            end
            else if (ready_i || !valid_o) begin
                if (btb_hit_i && btb_pred_taken_i) begin
                    pc_next <= btb_pred_target_i;
                end else begin
                    pc_next <= pc_next + 32'd4;   // Default sequential
                end


                pc_o         <= pc_at_icache;
                inst_o   <= icache_rdata;
                valid_o  <= 1'b1;         // Signal to FSM that data is ready
                pc_at_icache <= pc_next;

                pc_next  <= pc_next + 32'd4; // Increment for the next request
            end
        end

endmodule


