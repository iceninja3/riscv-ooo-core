module alu_exec (
    input  logic clk,
    input  logic rst,

    // From Issue (RS)
    input  logic valid_i,
    input  cpu_types_pkg::dispatch_packet_t pkt_i,
    input  logic [31:0] rs1_data_i, // From PRF Read
    input  logic [31:0] rs2_data_i, // From PRF Read

    // Output to Writeback (CDB)
    output cpu_types_pkg::cdb_t cdb_o,
    output logic ready_o // Execution is ready for new issue
);
    import cpu_types_pkg::*;

    logic [31:0] result;

    // Simple ALU Logic
    always_comb begin
        case (pkt_i.alu_op)
            3'b000: result = rs1_data_i + rs2_data_i;       // ADD/Load/Store addr
            3'b001: result = rs1_data_i - rs2_data_i;       // SUB
            3'b010: result = rs1_data_i | rs2_data_i;       // OR
            3'b011: result = (rs1_data_i < rs2_data_i) ? 1 : 0; // SLT
            3'b100: result = pkt_i.imm;                     // LUI (Result is just imm)
            default: result = 32'b0;
        endcase
    end

    // Pipeline Register (1 cycle latency)
    always_ff @(posedge clk) begin
        if (rst) begin
            cdb_o.valid <= 1'b0;
            cdb_o.tag   <= '0;
            cdb_o.data  <= '0;
        end else begin
            cdb_o.valid <= valid_i;
            // The tag we broadcast is the Physical Destination Register
            cdb_o.tag   <= pkt_i.rd_phys; 
            cdb_o.data  <= result;
        end
    end

    assign ready_o = 1'b1; // Simple ALU is always ready (pipelined)

endmodule