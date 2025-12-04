module Fetch #(
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 32,
    parameter RESET_PC   = 32'h0000_0000  //intialize pc 
)(
    input  logic                  clk,
    input  logic                  reset,

    output logic [ADDR_WIDTH-1:0] icache_addr,
    input  logic [DATA_WIDTH-1:0] icache_rdata, 

    //skid buffer 
    output logic                  valid_o,
    input  logic                  ready_i,
    output logic [31:0]           pc_o,
    output logic [DATA_WIDTH-1:0] inst_o
);


    logic [31:0] pc_req;
    logic [31:0] pc_reg;
    logic [DATA_WIDTH-1:0] inst_reg;

    // Word address into iCache: drop bottom 2 bits of PC (byte→word)
    assign icache_addr = pc_req[ADDR_WIDTH+1:2];

    // Outputs to skid buffer / decode
    assign pc_o   = pc_reg;
    assign inst_o = inst_reg;


    always_ff @(posedge clk) begin
        if (reset) begin
            pc_req   <= RESET_PC;
            pc_reg   <= '0;
            inst_reg <= '0;
            valid_o  <= 1'b0;
        end 
        else begin
            // Advance only when:
            //  downstream is ready, OR
            //  we don't yet have a valid instruction (pipeline fill)
            if (ready_i || !valid_o) begin
                // icache_rdata corresponds to pc_req from previous cycle
                inst_reg <= icache_rdata;
                pc_reg   <= pc_req;
                valid_o  <= 1'b1;
                pc_req <= pc_req + 32'd4;
            end
        end
    end

endmodule