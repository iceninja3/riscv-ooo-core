module physical_reg_file #(
    parameter DATA_WIDTH = 32,
    parameter NUM_REGS   = 128,
    parameter ADDR_WIDTH = 7   // log2(128)
)(
    input logic clk,
    
    // ---------------------------------------------------------
    // READ PORTS (From Reservation Stations)
    // ---------------------------------------------------------

    // --- 1. ALU Unit Read Ports ---
    input  logic [ADDR_WIDTH-1:0] raddr_alu_src1,
    output logic [DATA_WIDTH-1:0] rdata_alu_src1,
    
    input  logic [ADDR_WIDTH-1:0] raddr_alu_src2,
    output logic [DATA_WIDTH-1:0] rdata_alu_src2,

    // --- 2. Branch Unit Read Ports ---
    // (Needed for BEQ/BNE comparisons)
    input  logic [ADDR_WIDTH-1:0] raddr_br_src1,
    output logic [DATA_WIDTH-1:0] rdata_br_src1,

    input  logic [ADDR_WIDTH-1:0] raddr_br_src2,
    output logic [DATA_WIDTH-1:0] rdata_br_src2,

    // --- 3. LSU Unit Read Ports ---
    // (Needed for Address calculation and Store Data)
    input  logic [ADDR_WIDTH-1:0] raddr_lsu_src1, // Base Address
    output logic [DATA_WIDTH-1:0] rdata_lsu_src1,

    input  logic [ADDR_WIDTH-1:0] raddr_lsu_src2, // Store Data
    output logic [DATA_WIDTH-1:0] rdata_lsu_src2,


    // ---------------------------------------------------------
    // WRITE PORT (From CDB / Execution Units)
    // ---------------------------------------------------------
    input  logic                  wen,      // Write Enable
    input  logic [ADDR_WIDTH-1:0] waddr,    // Physical Register Address
    input  logic [DATA_WIDTH-1:0] wdata     // Result Data
);

    // The Physical Register Array
    logic [DATA_WIDTH-1:0] registers [0:NUM_REGS-1];

    // ---------------------------------------------------------
    // Asynchronous Read Logic
    // ---------------------------------------------------------
    
    // ALU
    assign rdata_alu_src1 = registers[raddr_alu_src1];
    assign rdata_alu_src2 = registers[raddr_alu_src2];

    // Branch
    assign rdata_br_src1  = registers[raddr_br_src1];
    assign rdata_br_src2  = registers[raddr_br_src2];

    // LSU
    assign rdata_lsu_src1 = registers[raddr_lsu_src1];
    assign rdata_lsu_src2 = registers[raddr_lsu_src2];


    // ---------------------------------------------------------
    // Synchronous Write Logic
    // ---------------------------------------------------------
    always_ff @(posedge clk) begin
        // P0 is typically hardwired to 0 in the logical architectural file (ARF),
        // but in the PRF, P0 is just a valid physical index like any other.
        // However, if your Rename logic explicitly maps x0 -> P0, you should protect it.
        if (wen && waddr != '0) begin 
            registers[waddr] <= wdata;
        end
    end

endmodule