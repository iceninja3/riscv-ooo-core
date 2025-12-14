`timescale 1ns/1ps

module tb_riscv_rob_full;

    // Clock + reset
    logic clk   = 0;
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

    assign fe_ready = 1'b1;

    // Instantiate DUT
    RISCV dut (
        .clk           (clk),
        .reset         (reset),
        .fe_valid_o    (fe_valid),
        .fe_ready_i    (fe_ready),
        .fe_pc_o       (fe_pc),
        .fe_rs1_o      (fe_rs1),
        .fe_rs2_o      (fe_rs2),
        .fe_rd_o       (fe_rd),
        .fe_imm_o      (fe_imm),
        .fe_ALUSrc_o   (fe_ALUSrc),
        .fe_ALUOp_o    (fe_ALUOp),
        .fe_branch_o   (fe_branch),
        .fe_jump_o     (fe_jump),
        .fe_MemRead_o  (fe_MemRead),
        .fe_MemWrite_o (fe_MemWrite),
        .fe_RegWrite_o (fe_RegWrite),
        .fe_MemToReg_o (fe_MemToReg)
    );

    // Clock
    always #5 clk = ~clk;

    // --------------------------------------------------
    // Macros to peek internal signals (hierarchical)
    // --------------------------------------------------

    // ROB + commit
    `define ROB_COUNT        dut.u_rob.count
    `define ROB_FULL         dut.rob_full
    `define COMMIT_VALID     dut.commit_valid
    `define COMMIT_OLDP      dut.commit_old_preg

    // NEW: ROB head visibility (THIS is what you were missing)
    `define ROB_HEAD_PTR     dut.u_rob.head_ptr
    `define ROB_TAIL_PTR     dut.u_rob.tail_ptr
    `define ROB_HEAD_VALID   dut.u_rob.rob_array[`ROB_HEAD_PTR].valid
    `define ROB_HEAD_DONE    dut.u_rob.rob_array[`ROB_HEAD_PTR].done
    `define ROB_HEAD_MISP    dut.u_rob.rob_array[`ROB_HEAD_PTR].mispredicted
    `define ROB_HEAD_OLDP    dut.u_rob.rob_array[`ROB_HEAD_PTR].rd_old_phys
    `define ROB_HEAD_PC      dut.u_rob.rob_array[`ROB_HEAD_PTR].pc

    // Rename / Decode / Dispatch
    `define REN_READY      dut.ren_ready
    `define REN_VALID      dut.ren_valid
    `define DEC_VALID      dut.dec_valid
    `define FIRE_DISPATCH  dut.u_dispatch.fire_dispatch
    `define BUFF_VALID     dut.u_dispatch.buff_valid

    // ---- ALU path ----
    `define RS_ALU_FULL     dut.rs_alu_full
    `define RS_ALU_ISSUE_V  dut.alu_issue_valid
    `define ALU_CDB_VALID   dut.alu_cdb_valid
    `define ALU_CDB_DATA    dut.alu_cdb_data
    `define ALU_CDB_PREG    dut.alu_cdb_preg
    `define ALU_CDB_TAG     dut.alu_cdb_tag

    // ---- LSU path ----
    `define RS_LSU_FULL     dut.rs_lsu_full
    `define RS_LSU_ISSUE_V  dut.lsu_issue_valid
    `define LSU_CDB_VALID   dut.lsu_cdb_valid
    `define LSU_CDB_DATA    dut.lsu_cdb_data
    `define LSU_CDB_PREG    dut.lsu_cdb_preg
    `define LSU_CDB_TAG     dut.lsu_cdb_tag

    // ---- Branch path ----
    `define RS_BR_FULL      dut.rs_branch_full
    `define RS_BR_ISSUE_V   dut.br_issue_valid
    `define BR_VALID        dut.br_valid_o
    `define BR_MISPRED      dut.br_mispredict_o
    `define BR_TAG          dut.br_rob_tag_o
    `define BR_TARGET       dut.br_target_addr_o

    // ---- Global CDB (after mux) ----
    `define CDB_VALID       dut.cdb_valid
    `define CDB_DATA        dut.cdb_data
    `define CDB_PREG        dut.cdb_preg
    `define CDB_ROB_TAG     dut.cdb_rob_tag
    `define CDB_MISP        dut.cdb_mispredict

    // ---- Extra branch internals for checking ----
    `define BR_IS_BRANCH    dut.br_issue_entry.is_branch
    `define BR_IS_JUMP      dut.br_issue_entry.is_jump
    `define BR_PC           dut.br_issue_entry.pc
    `define BR_IMM          dut.br_issue_entry.imm
    `define BR_RS1_VAL      dut.br_rs1_val
    `define BR_RS2_VAL      dut.br_rs2_val
    `define BR_TAKEN        dut.br_taken_o

    // --------------------------------------------------
    // Helper macros
    // --------------------------------------------------
    `define PRINT_CYCLE \
        $display("[%0t] PC=%08h dec_v=%0d ren_v=%0d ren_rdy=%0d buff_v=%0d rob_cnt=%0d rob_full=%0d fire_disp=%0d | head=%0d v=%0d d=%0d pc=%08h", \
                 $time, fe_pc, `DEC_VALID, `REN_VALID, `REN_READY, `BUFF_VALID, \
                 `ROB_COUNT, `ROB_FULL, `FIRE_DISPATCH, \
                 `ROB_HEAD_PTR, `ROB_HEAD_VALID, `ROB_HEAD_DONE, `ROB_HEAD_PC);

    `define STEP(n) \
      repeat (n) begin \
          @(posedge clk); \
          `PRINT_CYCLE; \
      end

    // --------------------------------------------------
    // FU / CDB activity monitors
    // --------------------------------------------------

    always @(posedge clk) begin
        if (`RS_ALU_ISSUE_V)
            $display("  [ALU RS ] issue_valid=1  (time=%0t)", $time);

        if (`ALU_CDB_VALID)
            $display("  [ALU FU ] CDB valid=1  result=0x%08h  rd_p=%0d  rob_tag=%0d",
                     `ALU_CDB_DATA, `ALU_CDB_PREG, `ALU_CDB_TAG);
    end

    always @(posedge clk) begin
        if (`RS_LSU_ISSUE_V)
            $display("  [LSU RS ] issue_valid=1  (time=%0t)", $time);

        if (`LSU_CDB_VALID)
            $display("  [LSU FU ] CDB valid=1  result=0x%08h  rd_p=%0d  rob_tag=%0d",
                     `LSU_CDB_DATA, `LSU_CDB_PREG, `LSU_CDB_TAG);
    end

    always @(posedge clk) begin
        if (`RS_BR_ISSUE_V)
            $display("  [BR RS  ] issue_valid=1  (time=%0t)", $time);

        if (`BR_VALID)
            $display("  [BRANCH ] valid=1  rob_tag=%0d  target=0x%08h  mispred=%0d",
                     `BR_TAG, `BR_TARGET, `BR_MISPRED);
    end

    always @(posedge clk) begin
        if (`CDB_VALID)
            $display("  [CDB    ] valid=1  data=0x%08h  preg=%0d  rob_tag=%0d  mispred=%0d",
                     `CDB_DATA, `CDB_PREG, `CDB_ROB_TAG, `CDB_MISP);
    end

    // NEW: Commit monitor (so you can see drain progress)
    always @(posedge clk) begin
        if (`COMMIT_VALID)
            $display("  [COMMIT ] valid=1  head_tag=%0d free_old_preg=%0d mispred=%0d",
                     `ROB_HEAD_PTR, `COMMIT_OLDP, dut.commit_mispredict);
    end

    // --------------------------------------------------
    // Branch + JALR correctness checker
    // --------------------------------------------------
    always @(posedge clk) begin
        if (`BR_VALID) begin
            if (`BR_IS_BRANCH && !`BR_IS_JUMP) begin
                logic        exp_taken;
                logic [31:0] exp_target;
                logic        exp_misp;

                exp_taken  = (`BR_RS1_VAL != `BR_RS2_VAL);
                exp_target = `BR_PC + `BR_IMM;
                exp_misp   = exp_taken;

                $display("  [CHECK BNE] pc=0x%08h rs1_val=0x%08h rs2_val=0x%08h imm=0x%08h",
                         `BR_PC, `BR_RS1_VAL, `BR_RS2_VAL, `BR_IMM);
                $display("              expected_taken=%0d  actual_taken=%0d",
                         exp_taken, `BR_TAKEN);
                $display("              expected_target=0x%08h actual_target=0x%08h",
                         exp_target, `BR_TARGET);
                $display("              expected_misp=%0d   actual_misp=%0d",
                         exp_misp, `BR_MISPRED);

                if (exp_taken !== `BR_TAKEN)
                    $display("              ** ERROR: BNE taken mismatch **");
                if (exp_target !== `BR_TARGET)
                    $display("              ** ERROR: BNE target mismatch **");
                if (exp_misp !== `BR_MISPRED)
                    $display("              ** ERROR: BNE mispredict flag mismatch **");
                if (exp_taken === `BR_TAKEN &&
                    exp_target === `BR_TARGET &&
                    exp_misp   === `BR_MISPRED)
                    $display("              [OK] BNE behavior matches expectation.");
            end
            else if (!`BR_IS_BRANCH && `BR_IS_JUMP) begin
                logic [31:0] exp_target;
                exp_target = (`BR_RS1_VAL + `BR_IMM) & 32'hFFFF_FFFE;

                $display("  [CHECK JALR] pc=0x%08h rs1_val=0x%08h imm=0x%08h",
                         `BR_PC, `BR_RS1_VAL, `BR_IMM);
                $display("                expected_target=0x%08h actual_target=0x%08h",
                         exp_target, `BR_TARGET);

                if (exp_target !== `BR_TARGET)
                    $display("                ** ERROR: JALR target mismatch **");
                else
                    $display("                [OK] JALR target matches expectation.");
            end
            else begin
                $display("  [CHECK BR/JMP] Unrecognized combo is_branch=%0d is_jump=%0d",
                         `BR_IS_BRANCH, `BR_IS_JUMP);
            end
        end
    end

    // --------------------------------------------------
    // Watchdog: ROB full but head never becomes done/commits
    // --------------------------------------------------
    int no_commit_ctr;
    always @(posedge clk) begin
        if (reset) begin
            no_commit_ctr <= 0;
        end else begin
            if (`ROB_FULL && !`COMMIT_VALID)
                no_commit_ctr <= no_commit_ctr + 1;
            else
                no_commit_ctr <= 0;

            if (no_commit_ctr == 200) begin
                $display("** WATCHDOG: ROB full with no commit for 200 cycles -> likely wedged **");
                $display("   head_ptr=%0d head_valid=%0d head_done=%0d head_pc=%08h head_oldpreg=%0d head_misp=%0d",
                         `ROB_HEAD_PTR, `ROB_HEAD_VALID, `ROB_HEAD_DONE, `ROB_HEAD_PC,
                         `ROB_HEAD_OLDP, `ROB_HEAD_MISP);
                $display("   last_cdb: valid=%0d tag=%0d preg=%0d data=%08h",
                         `CDB_VALID, `CDB_ROB_TAG, `CDB_PREG, `CDB_DATA);
                $stop;
            end
        end
    end

    // --------------------------------------------------
    // Test sequence
    // --------------------------------------------------
    initial begin
        $display("===== Starting RISCV pipeline + ROB/FU test =====");

        reset = 1;
        `STEP(4);
        reset = 0;
        $display("===== Release reset =====");

        `STEP(2000);

        $display("===== Testbench finished =====");
        $stop;
    end

endmodule