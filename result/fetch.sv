module Fetch #(
    parameter int ADDR_WIDTH = 9,
    parameter int DATA_WIDTH = 32,
    parameter logic [31:0] RESET_PC = 32'h0000_0000
)(
    input  logic                  clk,
    input  logic                  reset,

    // I-Cache Interface (1-cycle latency assumed)
    output logic [ADDR_WIDTH-1:0] icache_addr,
    input  logic [DATA_WIDTH-1:0] icache_rdata,

    // Redirect interface (USE THIS — matches your top)
    input  logic                  redirect_valid_i,
    input  logic [31:0]           redirect_pc_i,

    // Pipeline Interface
    output logic                  valid_o,
    input  logic                  ready_i,
    output logic [31:0]           pc_o,
    output logic [DATA_WIDTH-1:0] inst_o
);

    // 3-Stage Fetch Pipeline to handle Sync ICache Latency
    // Stage 0: PC_Next (Address -> ICache)
    // Stage 1: PC_F1   (ICache Sampling)
    // Stage 2: PC_F2   (Data Arrival)
    
    logic [31:0] pc_next;
    logic [31:0] pc_f1;
    logic [31:0] pc_f2;
    logic [31:0] pc_at_icache; // new
    
    // Valid bits for the pipeline
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
                // 1. Immediately update the target for the NEXT cache request
                pc_next  <= redirect_pc_i;
                // 2. Clear the output so the FSM doesn't see a "ghost" instruction
                valid_o  <= 1'b0;
            end 
            else if (ready_i || !valid_o) begin
                // Logic: pc_next is the address CURRENTLY at the iCache input pins.
                // Therefore, the iCache will return the data for pc_next on the NEXT cycle.
                // We latch that same pc_next into pc_o so they arrive at the output together.
                
                //pc_o     <= pc_next;      // Match the 1-cycle cache latency
                pc_o         <= pc_at_icache; //new
                inst_o   <= icache_rdata; // Data from iCache for the PREVIOUS pc_next
                valid_o  <= 1'b1;         // Signal to FSM that data is ready
                pc_at_icache <= pc_next; //new
                
                pc_next  <= pc_next + 32'd4; // Increment for the next request
            end
        end // end always_ff block

endmodule


