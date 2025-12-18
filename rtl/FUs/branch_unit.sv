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
    input  logic                  is_branch_i, // High for BNE
    input  logic                  is_jump_i,   // High for JALR (since JAL is unused)
    input  logic                  pred_taken_i, 
    input  logic [ROB_TAG_W-1:0]  rob_tag_i,

    output logic                  valid_o,
    output logic [ROB_TAG_W-1:0]  rob_tag_o,
    output logic                  mispredict_o,
    output logic [31:0]           target_addr_o,
    output logic                  actual_taken_o,

    //for actually writing into register
    input  logic [5:0]            rd_p_i, // Dest Register (for JAL/JALR)
    output logic [31:0]           result_o,    // Data to write (PC+4)
    output logic [5:0]            rd_p_o       // Dest Tag for CDB

);
    logic taken;
    logic [31:0] target;

    always_comb begin
        // Defaults
        taken  = 1'b0;
        target = 32'b0;

        // ---------------------------------------------------------
        // LOGIC FOR JALR (is_jump_i)
        // ---------------------------------------------------------
        // Since you are not using JAL, 'is_jump_i' guarantees JALR.
        // JALR Target = (RS1 + Immediate) & ~1 (LSB masked to 0)
        if (is_jump_i) begin
            taken  = 1'b1; // Jumps are always taken
            target = (rs1_val_i + imm_i) & 32'hFFFF_FFFE;
        end 
        
        // ---------------------------------------------------------
        // LOGIC FOR BRANCHES (is_branch_i)
        // ---------------------------------------------------------
        // Branch Target = PC + Immediate
        else if (is_branch_i) begin
            // You only need BNE support
            taken  = (rs1_val_i != rs2_val_i);
            target = pc_i + imm_i; 
        end
    end

    always_ff @(posedge clk) begin
        if (valid_i && is_jump_i) begin
            $display("[JALR-EXEC] t=%0t PC=%h JALR Target=%h (RS1=%h + Imm=%h)", 
                    $time, pc_i, target_addr_o, rs1_val_i, imm_i);
        end
    end //debug print


    // Sequential Output Logic
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
                

                // Misprediction Check
                // (Assuming static NOT-TAKEN prediction)
                // If we took the branch/jump, it was a mispredict.
                mispredict_o   <= (taken != 1'b0);
                

                // rd_p_o <= rd_p_i; // destination reg
                
                if (is_jump_i) begin
                    result_o <= pc_i + 32'd4;
                    rd_p_o   <= rd_p_i;       // Only JALR writes back
                end else begin
                    result_o <= 32'd0;
                    rd_p_o   <= 6'd0;         // BNE must NOT write to PRF
                end 
            end //end if valid_i
            else begin
                    // 3. Clear signals when invalid
                    mispredict_o <= 1'b0;
                    valid_o      <= 1'b0;
                end
        end
    end
endmodule

