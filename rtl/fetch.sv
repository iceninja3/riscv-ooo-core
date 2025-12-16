module Fetch #(
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 32,
    parameter RESET_PC   = 32'h0000_0000
)(
    input  logic                  clk,
    input  logic                  reset,

    // NEW: redirect from branch/jump resolution
    input  logic                  redirect_valid_i,
    input  logic [31:0]           redirect_pc_i,

    output logic [ADDR_WIDTH-1:0] icache_addr,
    input  logic [DATA_WIDTH-1:0] icache_rdata,

    output logic                  valid_o,
    input  logic                  ready_i,
    output logic [31:0]           pc_o,
    output logic [DATA_WIDTH-1:0] inst_o
);
    logic [31:0] pc_req;
    logic [31:0] pc_reg;
    logic [DATA_WIDTH-1:0] inst_reg;
    logic valid_warmup;

    assign icache_addr = pc_req[ADDR_WIDTH+1:2];
    assign pc_o   = pc_reg;
    assign inst_o = inst_reg;

    always_ff @(posedge clk) begin
        if (reset) begin
            pc_req       <= RESET_PC;
            pc_reg       <= '0;
            inst_reg     <= '0;
            valid_o      <= 1'b0;
            valid_warmup <= 1'b0;
        end else begin
            // redirect has priority
            if (redirect_valid_i) begin
                pc_req       <= redirect_pc_i;
                valid_o      <= 1'b0;     // squash 1-cycle garbage after redirect
                valid_warmup <= 1'b0;
            end else if (ready_i || !valid_o) begin
                inst_reg <= icache_rdata;
                pc_reg   <= pc_req;
                pc_req   <= pc_req + 32'd4;

                valid_warmup <= 1'b1;
                valid_o      <= valid_warmup;
            end
        end
    end
endmodule