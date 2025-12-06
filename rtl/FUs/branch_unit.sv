module branch_unit #(
    parameter int ROB_TAG_W = 4
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  valid_i,
    input  logic [31:0]           pc_i,
    input  logic [31:0]           imm_i,
    input  logic [31:0]           rs1_val_i,
    input  logic [31:0]           rs2_val_i,
    input  logic                  is_branch_i,
    input  logic                  is_jump_i,       // Differentiate branch vs JALR/JAL
    input  logic                  pred_taken_i,    // (unused for now)
    input  logic [ROB_TAG_W-1:0]  rob_tag_i,

    output logic                  valid_o,
    output logic [ROB_TAG_W-1:0]  rob_tag_o,
    output logic                  mispredict_o,
    output logic [31:0]           target_addr_o,
    output logic                  actual_taken_o
);
    logic taken;
    logic [31:0] target;

    always_comb begin
        // Target Calc
        target = pc_i + imm_i; // Assuming imm is already PC-relative offset

        // Condition Check (simplified to BNE + JALR/JAL-style jump)
        if (is_jump_i)
            taken = 1'b1;
        else if (is_branch_i)
            taken = (rs1_val_i != rs2_val_i); // BNE
        else
            taken = 1'b0;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_o       <= 1'b0;
            mispredict_o  <= 1'b0;
            actual_taken_o<= 1'b0;
        end else begin
            valid_o <= valid_i;

            if (valid_i) begin
                rob_tag_o      <= rob_tag_i;
                target_addr_o  <= target;
                actual_taken_o <= taken;

                // For now: assume static NOT-TAKEN prediction (pred_taken_i == 0)
                mispredict_o   <= (taken != 1'b0);
            end
        end
    end
endmodule