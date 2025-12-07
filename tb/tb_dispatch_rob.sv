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

    // For this test, always ready at the FE interface
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

    // --------------------------------------------------
    // Macros to peek internal signals (hierarchical)
    // --------------------------------------------------

    // From ROB
    `define ROB_COUNT      dut.u_rob.count
    `define ROB_FULL       dut.rob_full

    // From Rename / Decode / Dispatch
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

    // ---- LSU internals for visibility / checking ----
    `define LSU_DMEM(i)     dut.u_lsu.dmem[i]
    `define LSU_IS_STORE    dut.u_lsu.is_store_q
    `define LSU_FUNCT3      dut.u_lsu.funct3_q
    `define LSU_ADDR_IDX    dut.u_lsu.addr[11:2]
    `define LSU_OFFS        dut.u_lsu.addr_offset_q

    // Clock
    always #5 clk = ~clk;

    // --------------------------------------------------
    // Helper macros
    // --------------------------------------------------

    `define PRINT_CYCLE \
        $display("[%0t] PC=%08h dec_v=%0d ren_v=%0d ren_rdy=%0d buff_v=%0d rob_cnt=%0d rob_full=%0d fire_disp=%0d", \
                 $time, fe_pc, `DEC_VALID, `REN_VALID, `REN_READY, `BUFF_VALID, \
                 `ROB_COUNT, `ROB_FULL, `FIRE_DISPATCH);

    `define STEP(n) \
      repeat (n) begin \
          @(posedge clk); \
          `PRINT_CYCLE; \
      end

    // --------------------------------------------------
    // Extra monitors for FU / CDB activity
    // --------------------------------------------------

    // Print ALU events
    always @(posedge clk) begin
        if (`RS_ALU_ISSUE_V)
            $display("  [ALU RS ] issue_valid=1  (time=%0t)", $time);

        if (`ALU_CDB_VALID)
            $display("  [ALU FU ] CDB valid=1  result=0x%08h  rd_p=%0d  rob_tag=%0d",
                     `ALU_CDB_DATA, `ALU_CDB_PREG, `ALU_CDB_TAG);
    end

    // Print LSU events + correctness checks (LW + LBU)
    always @(posedge clk) begin
        if (`RS_LSU_ISSUE_V)
            $display("  [LSU RS ] issue_valid=1  (time=%0t)", $time);

        if (`LSU_CDB_VALID) begin
            int idx;
            idx = `LSU_ADDR_IDX;

            if (`LSU_IS_STORE) begin
                // STORE completed: show memory after the write
                $display("  [LSU STORE] rob_tag=%0d word_idx=%0d dmem_after=0x%08h (rd_p=%0d)",
                         `LSU_CDB_TAG, idx, `LSU_DMEM(idx), `LSU_CDB_PREG);
            end
            else begin
                // LOAD completed: compare result to memory
                logic [31:0] mem_word;
                mem_word = `LSU_DMEM(idx);

                $display("  [LSU LOAD ] rob_tag=%0d word_idx=%0d dmem=0x%08h  result=0x%08h funct3=%0b offs=%0d",
                         `LSU_CDB_TAG, idx, mem_word, `LSU_CDB_DATA, `LSU_FUNCT3, `LSU_OFFS);

                // LW check (funct3 == 3'b010)
                if (`LSU_FUNCT3 == 3'b010) begin
                    if (`LSU_CDB_DATA !== mem_word)
                        $error("LOAD MISMATCH (LW): expected 0x%08h got 0x%08h",
                               mem_word, `LSU_CDB_DATA);
                end
                // LBU check (funct3 == 3'b100)
                else if (`LSU_FUNCT3 == 3'b100) begin
                    logic [7:0] expected_byte;
                    case (`LSU_OFFS)
                        2'b00: expected_byte = mem_word[7:0];
                        2'b01: expected_byte = mem_word[15:8];
                        2'b10: expected_byte = mem_word[23:16];
                        2'b11: expected_byte = mem_word[31:24];
                    endcase

                    if (`LSU_CDB_DATA !== {24'b0, expected_byte})
                        $error("LOAD MISMATCH (LBU): expected 0x%02h got 0x%08h (mem=0x%08h offs=%0d)",
                               expected_byte, `LSU_CDB_DATA, mem_word, `LSU_OFFS);
                end
            end
        end
    end

    // Print Branch events
    always @(posedge clk) begin
        if (`RS_BR_ISSUE_V)
            $display("  [BR RS  ] issue_valid=1  (time=%0t)", $time);

        if (`BR_VALID)
            $display("  [BRANCH ] valid=1  rob_tag=%0d  target=0x%08h  mispred=%0d",
                     `BR_TAG, `BR_TARGET, `BR_MISPRED);
    end

    // Global CDB monitor (after mux)
    always @(posedge clk) begin
        if (`CDB_VALID)
            $display("  [CDB    ] valid=1  data=0x%08h  preg=%0d  rob_tag=%0d  mispred=%0d",
                     `CDB_DATA, `CDB_PREG, `CDB_ROB_TAG, `CDB_MISP);
    end

    // --------------------------------------------------
    // Test sequence
    // --------------------------------------------------
    initial begin
        $display("===== Starting RISCV pipeline + ROB/FU test =====");

        // Reset
        reset = 1;
        `STEP(4);
        reset = 0;
        $display("===== Release reset =====");

        // Initialize LSU memory for LOAD tests.
        // These are word indices; byte address = idx * 4.
        // You can tweak these to match what your trace expects.
        `LSU_DMEM(0) = 32'hDEADBEEF;
        `LSU_DMEM(1) = 32'h11223344;
        `LSU_DMEM(2) = 32'hAABBCCDD;

        $display("[TB] Preloaded dmem[0]=0x%08h dmem[1]=0x%08h dmem[2]=0x%08h",
                 `LSU_DMEM(0), `LSU_DMEM(1), `LSU_DMEM(2));

        // Let it run for a while to see FU activity and ROB filling
        `STEP(120);

        if (`ROB_FULL)
            $display("ROB FULL condition detected as expected!");
        else
            $display("WARNING: ROB did NOT fill — something is still stalling before dispatch.");

        `STEP(20);

        // Final memory dump to visually inspect stores
        $display("===== Final dmem dump (first 16 words) =====");
        for (int i = 0; i < 16; i++) begin
            $display("  dmem[%0d] = 0x%08h", i, `LSU_DMEM(i));
        end

        $display("===== Testbench finished =====");
        $stop;
    end

endmodule