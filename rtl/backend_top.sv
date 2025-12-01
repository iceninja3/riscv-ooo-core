module backend_top (
    input logic clk, reset,

    // Rename Interface
    input logic             rename_valid,
    input common_pkg::dispatch_packet_t rename_pkt,
    output logic            dispatch_ready,

    // Mock Execution Units Interface (Issue -> PRF Read)
    output logic [31:0]     alu_operand_a,
    output logic [31:0]     alu_operand_b,
    output logic [6:0]      alu_opcode,
    input  logic            alu_ex_ready, // Is ALU free?
    
    // CDB Interface (Writeback)
    input common_pkg::cdb_t cdb_in
);
    import common_pkg::*;

    // Wires between Dispatch and PRF
    logic      alu_issue_valid;
    rs_entry_t alu_issue_pkt;

    logic      lsu_issue_valid; // Not fully used in this top example
    rs_entry_t lsu_issue_pkt;

    // 1. Dispatch Module (Contains ROB + RS)
    dispatch dispatch_inst (
        .clk(clk), .reset(reset),
        .rename_valid(rename_valid),
        .rename_pkt(rename_pkt),
        .dispatch_ready(dispatch_ready),
        .cdb_in(cdb_in),
        .alu_ready(alu_ex_ready),
        .alu_issue_valid(alu_issue_valid),
        .alu_issue_pkt(alu_issue_pkt),
        .lsu_ready(1'b1), // Mock LSU always ready
        .lsu_issue_valid(lsu_issue_valid),
        .lsu_issue_pkt(lsu_issue_pkt)
    );

    // 2. Physical Register File
    physical_reg_file prf_inst (
        .clk(clk),
        // ALU reads
        .raddr_a(alu_issue_pkt.p_src1),
        .rdata_a(alu_operand_a),
        .raddr_b(alu_issue_pkt.p_src2),
        .rdata_b(alu_operand_b),
        // CDB Write
        .wen(cdb_in.valid),
        .waddr(cdb_in.tag),
        .wdata(cdb_in.data)
    );
    
    assign alu_opcode = alu_issue_pkt.opcode;

endmodule