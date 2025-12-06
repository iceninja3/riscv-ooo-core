module alu_unit #(
    parameter int ROB_TAG_W = 4  // must match ROB_TAG_W in top-level/ROB
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  valid_i,
    input  logic [2:0]            alu_op_i,   // carries alu_op_e encoding
    input  logic [31:0]           op1_i,
    input  logic [31:0]           op2_i,
    input  logic [5:0]            rd_p_i,
    input  logic [ROB_TAG_W-1:0]  rob_tag_i,

    // Output to Writeback/ROB (CDB)
    output logic                  valid_o,
    output logic [31:0]           result_o,
    output logic [5:0]            rd_p_o,
    output logic [ROB_TAG_W-1:0]  rob_tag_o
);
    import pipeline_types::*;

    logic [31:0] res_c;

    always_comb begin
        unique case (alu_op_i)
            ALU_ADD: res_c = op1_i + op2_i;
            ALU_SUB: res_c = op1_i - op2_i;
            ALU_AND: res_c = op1_i & op2_i;
            ALU_OR : res_c = op1_i | op2_i;
            ALU_XOR: res_c = op1_i ^ op2_i;
            default: res_c = '0;
        endcase
    end

    // Simple 1-cycle pipeline register
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_o <= 1'b0;
        end else begin
            valid_o <= valid_i;
        end

        if (valid_i) begin
            result_o  <= res_c;
            rd_p_o    <= rd_p_i;
            rob_tag_o <= rob_tag_i;
        end
    end
endmodule