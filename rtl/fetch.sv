module Fetch #(
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 32,
    parameter RESET_PC   = 32'h0000_0000
)(
    input  logic                  clk,
    input  logic                  reset,

    input  logic                  redirect_valid_i,
    input  logic [31:0]           redirect_pc_i,

    output logic [ADDR_WIDTH-1:0] icache_addr,
    input  logic [DATA_WIDTH-1:0] icache_rdata,

    output logic                  valid_o,
    input  logic                  ready_i,
    output logic [31:0]           pc_o,
    output logic [DATA_WIDTH-1:0] inst_o
);

    logic [31:0] pc_req;       // address being requested *this* cycle
    logic [31:0] pc_delayed;   // address requested *last* cycle (matches icache_rdata)
    logic [31:0] pc_reg;
    logic [DATA_WIDTH-1:0] inst_reg;

    logic valid_warmup;

    assign icache_addr = pc_req[ADDR_WIDTH+1:2];

    assign pc_o   = pc_reg;
    assign inst_o = inst_reg;

    // "advance" means we accept / present a new fetch packet
    wire adv = (ready_i || !valid_o);

    always_ff @(posedge clk) begin
        if (reset) begin
            pc_req       <= RESET_PC;
            pc_delayed   <= RESET_PC;
            pc_reg       <= '0;
            inst_reg     <= '0;
            valid_o      <= 1'b0;
            valid_warmup <= 1'b0;
        end else begin
            // Highest priority: redirect/flush
            if (redirect_valid_i) begin
                pc_req       <= redirect_pc_i;
                pc_delayed   <= redirect_pc_i;

                // flush current output; wait 1 cycle for new icache_rdata
                valid_o      <= 1'b0;
                valid_warmup <= 1'b0;
            end
            else if (adv) begin
                // Capture returning data (from last cycle request)
                inst_reg <= icache_rdata;
                pc_reg   <= pc_delayed;

                // advance pipeline of PCs
                pc_delayed <= pc_req;
                pc_req     <= pc_req + 32'd4;

                // warmup: first returned word after reset/redirect is not valid until next cycle
                valid_warmup <= 1'b1;
                valid_o      <= valid_warmup;
            end
        end
    end

endmodule