module alu_unit (
    input  logic        clk, rst,
    input  logic        valid_i,
    input  logic [2:0]  alu_op_i,
    input  logic [31:0] op1_i, op2_i,
    input  logic [5:0]  rd_p_i,
    input  logic [5:0]  rob_tag_i,
    
    // Output to Writeback/ROB (CDB)
    output logic        valid_o,
    output logic [31:0] result_o,
    output logic [5:0]  rd_p_o,
    output logic [5:0]  rob_tag_o
);
    logic [31:0] res_c;
    
    always_comb begin
        case (alu_op_i)
            3'b000: res_c = op1_i + op2_i; // ADD
            3'b001: res_c = op1_i - op2_i; // SUB
            3'b010: res_c = op1_i & op2_i; // AND
            3'b011: res_c = op1_i | op2_i; // OR
            3'b100: res_c = op1_i ^ op2_i; // XOR
            default: res_c = '0;
        endcase
    end

    // Simple 1-cycle pipeline register
    always_ff @(posedge clk) begin
        if (rst) valid_o <= 0;
        else     valid_o <= valid_i;
        
        if (valid_i) begin
            result_o  <= res_c;
            rd_p_o    <= rd_p_i;
            rob_tag_o <= rob_tag_i;
        end
    end
endmodule