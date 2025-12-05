`timescale 1ns/1ps

module tb_riscv_rob_full;

    // Clock + reset
    logic clk = 0;
    logic reset = 1;

    // Front-end signals
    logic        fe_valid;
    logic        fe_ready;
    logic [31:0] fe_pc;
    logic [4:0]  fe_rs1, fe_rs2, fe_rd;
    logic [31:0] fe_imm;
    logic        fe_ALUSrc;
    logic [2:0]  fe_ALUOp;
    logic        fe_branch, fe_jump;
    logic        fe_MemRead, fe_MemWrite;
    logic        fe_RegWrite, fe_MemToReg;

    // Connect FE ready permanently high (decode uses rename stall instead)
    assign fe_ready = 1'b1;

    // Instantiate DUT
    RISCV dut (
        .clk(clk),
        .reset(reset),
        .fe_valid_o(fe_valid),
        .fe_ready_i(fe_ready),
        .fe_pc_o(fe_pc),
        .fe_rs1_o(fe_rs1),
        .fe_rs2_o(fe_rs2),
        .fe_rd_o(fe_rd),
        .fe_imm_o(fe_imm),
        .fe_ALUSrc_o(fe_ALUSrc),
        .fe_ALUOp_o(fe_ALUOp),
        .fe_branch_o(fe_branch),
        .fe_jump_o(fe_jump),
        .fe_MemRead_o(fe_MemRead),
        .fe_MemWrite_o(fe_MemWrite),
        .fe_RegWrite_o(fe_RegWrite),
        .fe_MemToReg_o(fe_MemToReg)
    );

    // Extract internal signals for monitoring
    // (These match your RISCV signal names)
    `define ROB_COUNT       dut.u_rob.count
    `define ROB_FULL        dut.u_rob.rob_full_o
    `define REN_READY       dut.ren_ready
    `define REN_VALID       dut.ren_valid
    `define DEC_VALID       dut.dec_valid
    `define FIRE_DISPATCH   dut.u_dispatch.fire_dispatch
    `define BUFF_VALID      dut.u_dispatch.buff_valid

    // Clock generator
    always #5 clk = ~clk;

    // -------------------------------
    // Testing macros
    //-------------------------------

    `define PRINT_CYCLE \
       $display("[%0t] PC=%08h  dec_v=%0d  ren_v=%0d  ren_ready=%0d  buff_v=%0d  rob_cnt=%0d  rob_full=%0d  fire_disp=%0d", \
           $time, fe_pc, `DEC_VALID, `REN_VALID, `REN_READY, `BUFF_VALID, `ROB_COUNT, `ROB_FULL, `FIRE_DISPATCH);

    `define STEP(n) \
        repeat(n) begin \
            @(posedge clk); \
            `PRINT_CYCLE; \
        end

    `define ASSERT_EQ(sig,val,msg) \
        if ((sig) !== (val)) begin \
            $display("ASSERTION FAILED: %s  Expected=%0d Got=%0d", msg, val, sig); \
            $stop; \
        end

    // -------------------------------
    // Test sequence
    //-------------------------------

    initial begin
        $display("===== Starting RISCV pipeline testbench =====");

        // Reset pulse
        reset = 1;
        `STEP(4);
        reset = 0;
        $display("===== Release reset =====");

        // Run long enough to fill ROB
        `STEP(40);

        // Check that ROB eventually fills
        if (`ROB_FULL) begin
            $display("ROB FULL condition detected as expected!");
        end else begin
            $display("WARNING: ROB did NOT fill — something is stalling before dispatch.");
        end

        // Extra cycles to verify rename stalls
        `STEP(10);

        $display("===== Testbench finished =====");
        $stop;
    end

endmodule
