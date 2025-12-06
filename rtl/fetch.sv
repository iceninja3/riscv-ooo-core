module Fetch #(
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 32,
    parameter RESET_PC   = 32'h0000_0000
)(
    input  logic                  clk,
    input  logic                  reset,

    output logic [ADDR_WIDTH-1:0] icache_addr,
    input  logic [DATA_WIDTH-1:0] icache_rdata, 

    output logic                  valid_o,
    input  logic                  ready_i,
    output logic [31:0]           pc_o,
    output logic [DATA_WIDTH-1:0] inst_o
);
    logic [31:0] pc_req;      // Next PC (Address to Cache)
    logic [31:0] pc_delayed;  // PC waiting for Cache Data
    logic [31:0] pc_reg;      // Output PC (Matched with Inst)
    logic [DATA_WIDTH-1:0] inst_reg;

    // Address to ICache (Comb)
    assign icache_addr = pc_req[ADDR_WIDTH+1:2];
    
    // Outputs
    assign pc_o   = pc_reg;
    assign inst_o = inst_reg;

    // Startup counter to prevent outputting garbage on first cycle
    logic valid_warmup; 

    always_ff @(posedge clk) begin
        if (reset) begin
            pc_req       <= RESET_PC;
            pc_delayed   <= RESET_PC;
            pc_reg       <= '0;
            inst_reg     <= '0;
            valid_o      <= 1'b0;
            valid_warmup <= 1'b0;
        end 
        else begin
            // Stall logic: Only advance if downstream is ready or we aren't valid yet
            if (ready_i || !valid_o) begin
                
                // 1. Capture Data coming back from Cache (Latency = 1)
                inst_reg <= icache_rdata;

                // 2. Capture the PC that matches this data (The one from 1 cycle ago)
                pc_reg   <= pc_delayed;

                // 3. Advance the Pipeline
                pc_delayed   <= pc_req;       // Save current PC for next cycle
                pc_req       <= pc_req + 32'd4; // Calculate Next PC

                // 4. Validity Logic (Wait 1 cycle for BRAM fill)
                valid_warmup <= 1'b1;         
                valid_o      <= valid_warmup; // valid_o goes high only after 1 cycle
            end
        end
    end
endmodule