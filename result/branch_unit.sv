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
    input  logic                  is_jump_i,
    input  logic                  pred_taken_i,
    input  logic [ROB_TAG_W-1:0]  rob_tag_i,

    output logic                  valid_o,
    output logic [ROB_TAG_W-1:0]  rob_tag_o,
    output logic                  mispredict_o,
    output logic [31:0]           target_addr_o,
    output logic                  actual_taken_o,

    input  logic [5:0]            rd_p_i,
    output logic [31:0]           result_o,
    output logic [5:0]            rd_p_o

);
    logic taken;
    logic [31:0] target;

    always_comb begin
        taken  = 1'b0;
        target = 32'b0;

        if (is_jump_i) begin
            taken  = 1'b1; // Jumps are always taken
          target = (rs1_val_i + imm_i) & 32'hFFFF_FFFE; //new
        end

        else if (is_branch_i) begin
            taken  = (rs1_val_i != rs2_val_i);
            target = pc_i + imm_i;
        end
    end



    always_ff @(posedge clk) begin
        if (rst) begin
            valid_o        <= 1'b0;
            mispredict_o   <= 1'b0;
            actual_taken_o <= 1'b0;
            target_addr_o  <= '0;
            rob_tag_o      <= '0;
        end else begin
            valid_o <= valid_i;

            if (valid_i) begin
                rob_tag_o      <= rob_tag_i;
                target_addr_o  <= target;
                actual_taken_o <= taken;


                mispredict_o   <= (taken != 1'b0);



                if (is_jump_i) begin
                    result_o <= pc_i + 32'd4;
                    rd_p_o   <= rd_p_i;
                end else begin
                    result_o <= 32'd0;
                    rd_p_o   <= 6'd0;         // BNE must NOT write to PRF
                end
            end
            else begin
                    mispredict_o <= 1'b0;
                    valid_o      <= 1'b0;
                end
        end
    end


endmodule
