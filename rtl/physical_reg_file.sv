module physical_reg_file #(
    parameter DATA_WIDTH = 32,
    parameter NUM_REGS   = 128,
    parameter ADDR_WIDTH = 7   // log2(128)
)(
    input logic clk,
    
    // --- READ PORTS (From Reservation Stations) ---
    // Port A (e.g., for ALU Source 1)
    input  logic [ADDR_WIDTH-1:0] raddr_alu_src1,
    output logic [DATA_WIDTH-1:0] rdata_alu_src1,
    
    // Port B (e.g., for ALU Source 2)
    input  logic [ADDR_WIDTH-1:0] raddr_alu_src2,
    output logic [DATA_WIDTH-1:0] rdata_alu_src2,

    // ... Repeat for Branch and LSU units ...
    // (For brevity, I am showing just 1 set, but you would duplicate this)

    // --- WRITE PORTS (From Execution Units / CDB) ---
    input  logic                  wen,      // Write Enable
    input  logic [ADDR_WIDTH-1:0] waddr,    // Physical Register Address
    input  logic [DATA_WIDTH-1:0] wdata     // Result Data
);

    // The Register Array
    // logic [31:0] regs [0:127];
    logic [DATA_WIDTH-1:0] registers [0:NUM_REGS-1];

    // Asynchronous Read (standard for Register Files in pipelines)
    assign rdata_alu_src1 = registers[raddr_alu_src1];
    assign rdata_alu_src2 = registers[raddr_alu_src2];

    // Synchronous Write
    always_ff @(posedge clk) begin
        if (wen && waddr != '0) begin // Optional: P0 is usually hardwired 0 in arch, but strictly P0 in PRF might be valid data. 
                                      // If P0 is NOT architectural R0, remove the "&& waddr != '0" check.
            registers[waddr] <= wdata;
        end
    end

endmodule