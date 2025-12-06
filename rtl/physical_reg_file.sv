module physical_reg_file #(
    parameter DATA_WIDTH = 32,
    parameter NUM_REGS   = 64,                  // match N_PHYS
    parameter ADDR_WIDTH = $clog2(NUM_REGS)
)(
    input logic clk,

    // --- 1. ALU Unit Read Ports ---
    input  logic [ADDR_WIDTH-1:0] raddr_alu_src1,
    output logic [DATA_WIDTH-1:0] rdata_alu_src1,

    input  logic [ADDR_WIDTH-1:0] raddr_alu_src2,
    output logic [DATA_WIDTH-1:0] rdata_alu_src2,

    // --- 2. Branch Unit Read Ports ---
    input  logic [ADDR_WIDTH-1:0] raddr_br_src1,
    output logic [DATA_WIDTH-1:0] rdata_br_src1,

    input  logic [ADDR_WIDTH-1:0] raddr_br_src2,
    output logic [DATA_WIDTH-1:0] rdata_br_src2,

    // --- 3. LSU Unit Read Ports ---
    input  logic [ADDR_WIDTH-1:0] raddr_lsu_src1, // Base Address
    output logic [DATA_WIDTH-1:0] rdata_lsu_src1,

    input  logic [ADDR_WIDTH-1:0] raddr_lsu_src2, // Store Data
    output logic [DATA_WIDTH-1:0] rdata_lsu_src2,

    // --- WRITE PORT (From CDB) ---
    input  logic                  wen,
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata
);

    logic [DATA_WIDTH-1:0] registers [0:NUM_REGS-1];

     initial begin
        integer i;
        for (i = 0; i < NUM_REGS; i++) begin
            registers[i] = '0;
        end
    end

    // async reads
    assign rdata_alu_src1 = registers[raddr_alu_src1];
    assign rdata_alu_src2 = registers[raddr_alu_src2];

    assign rdata_br_src1  = registers[raddr_br_src1];
    assign rdata_br_src2  = registers[raddr_br_src2];

    assign rdata_lsu_src1 = registers[raddr_lsu_src1];
    assign rdata_lsu_src2 = registers[raddr_lsu_src2];

    // sync write
    always_ff @(posedge clk) begin
        if (wen && waddr != '0) begin
            registers[waddr] <= wdata;
        end
    end
endmodule