module alu_unit #(
    parameter int ROB_TAG_W = 4
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  valid_i,
    input  logic [2:0]            alu_op_i,   // carries alu_op_e encoding
    input  logic [31:0]           op1_i,
    input  logic [31:0]           op2_i,
    input  logic [5:0]            rd_p_i,
    input  logic [ROB_TAG_W-1:0]  rob_tag_i,

    output logic                  valid_o,
    output logic [31:0]           result_o,
    output logic [5:0]            rd_p_o,
    output logic [ROB_TAG_W-1:0]  rob_tag_o
);
    import pipeline_types::*;

    logic [31:0] res_c;

    always_comb begin
        unique case (alu_op_i)
            // Existing
            ALU_ADD: res_c = op1_i + op2_i;        // Handles ADD, ADDI, LUI (if rs1=0)
            ALU_SUB: res_c = op1_i - op2_i;        // Handles SUB
            ALU_AND: res_c = op1_i & op2_i;        // Handles AND
            ALU_OR : res_c = op1_i | op2_i;        // Handles OR, ORI
            ALU_XOR: res_c = op1_i ^ op2_i;        // Handles XOR

            // NEW: SRA (Shift Right Arithmetic)
            // Must cast to $signed to get arithmetic shift (preserving sign bit)
            ALU_SRA: res_c = $signed(op1_i) >>> op2_i[4:0]; 

            // NEW: SLTU (Set Less Than Unsigned)
            // Handles SLTIU. Result is 1 if op1 < op2 (unsigned), else 0.
            ALU_SLTU: res_c = (op1_i < op2_i) ? 32'd1 : 32'd0;

            default: res_c = '0;
        endcase
    end

    // Pipeline Register
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