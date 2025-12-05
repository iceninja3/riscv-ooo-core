module branch_unit (
    input  logic        clk, rst,
    input  logic        valid_i,
    input  logic [31:0] pc_i, imm_i,
    input  logic [31:0] rs1_val_i, rs2_val_i,
    input  logic        is_branch_i, is_jump_i, // Differentiate BEQ vs JAL
    input  logic        pred_taken_i, // Did Fetch predict taken? (Optional for now)
    input  logic [5:0]  rob_tag_i,
    
    output logic        valid_o,
    output logic [5:0]  rob_tag_o,
    output logic        mispredict_o,
    output logic [31:0] target_addr_o,
    output logic        actual_taken_o
);
    logic taken;
    logic [31:0] target;

    always_comb begin
        // Target Calc
        target = pc_i + imm_i; // Assuming imm is already offset

        // Condition Check (Simplify to just BEQ/BNE for now)
        if (is_jump_i) taken = 1'b1;
        else if (is_branch_i) taken = (rs1_val_i != rs2_val_i); // BNE
        else taken = 1'b0;
    end

    always_ff @(posedge clk) begin
        if (rst) valid_o <= 0;
        else     valid_o <= valid_i;
        
        if (valid_i) begin
            rob_tag_o      <= rob_tag_i;
            target_addr_o  <= target;
            actual_taken_o <= taken;
            
            // Phase 4 Preview: Mispredict if actual != predicted
            // For now, assume static Not-Taken prediction (pred=0)
            mispredict_o   <= (taken != 0); 
        end
    end
endmodule