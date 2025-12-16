`timescale 1ns/1ps

module tb_final_regs;

  // Clock + reset
  logic clk   = 0;
  logic reset = 1;

  // Front-end signals (keep if your RISCV requires these ports)
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

  // DUT
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

  // ---- ONLY hierarchical paths we rely on ----
  `define ARCH2PHYS(a)  dut.u_rename.map_table[a]
  `define PRF_VAL(p)    dut.u_prf.registers[p]
  `define ROB_COUNT     dut.u_rob.count   // if your ROB instance name differs, change this line

  // --------------------------------------------------
  // Expected architectural register values (FILL THESE)
  // --------------------------------------------------
  logic [31:0] exp_arch  [0:31];
  bit          exp_valid [0:31];

  initial begin : init_expected
    for (int i = 0; i < 32; i++) begin
      exp_arch[i]  = 32'h0;
      exp_valid[i] = 1'b0;
    end

    // x0 is always 0
    exp_arch[0]  = 32'h0000_0000;
    exp_valid[0] = 1'b1;

    // ------------------------------------------------
    // TODO: fill expected regs for your program here.
    // Example:
    // exp_arch[5]  = 32'h0000_0678; exp_valid[5]  = 1'b1;
    // exp_arch[6]  = 32'h0000_0def; exp_valid[6]  = 1'b1;
    // ------------------------------------------------
  end

  // --------------------------------------------------
  // Final dump
  // --------------------------------------------------
  task automatic dump_final_regs;
    int a;
    logic [5:0]  phys;
    logic [31:0] actual;
    string status;
    begin
      $display("\n===== FINAL ARCH REGISTER CHECK =====");
      $display("Reg | Phys | Actual       | Expected     | Status");
      $display("----+------+-------------+-------------+---------");

      for (a = 0; a < 32; a++) begin
        phys   = `ARCH2PHYS(a);
        actual = `PRF_VAL(phys);

        if (exp_valid[a]) begin
          status = (actual === exp_arch[a]) ? "OK" : "MISMATCH";
          $display("x%-2d| %-4d | 0x%08h | 0x%08h | %s",
                   a, phys, actual, exp_arch[a], status);
        end else begin
          $display("x%-2d| %-4d | 0x%08h | (n/a)       | no-exp",
                   a, phys, actual);
        end
      end

      $display("=====================================\n");
    end
  endtask

  // --------------------------------------------------
  // Main test
  // --------------------------------------------------
  localparam int RESET_CYCLES   = 4;
  localparam int MAX_CYCLES     = 50000; // big timeout so you don't miss completion
  localparam int QUIET_CYCLES   = 10;    // require ROB empty for N cycles before dump

  int cycles;
  int quiet_ctr;

  initial begin
    $display("===== Starting FINAL-REGS testbench =====");

    // Reset
    reset = 1;
    repeat (RESET_CYCLES) @(posedge clk);
    reset = 0;

    cycles    = 0;
    quiet_ctr = 0;

    // Run until ROB empties (stable) OR timeout
    while (cycles < MAX_CYCLES) begin
      @(posedge clk);
      cycles++;

      if (`ROB_COUNT == 0)
        quiet_ctr++;
      else
        quiet_ctr = 0;

      if (quiet_ctr >= QUIET_CYCLES) begin
        $display("Reached quiescent state: ROB_COUNT==0 for %0d cycles (total cycles=%0d)",
                 QUIET_CYCLES, cycles);
        break;
      end
    end

    if (cycles >= MAX_CYCLES)
      $display("WARNING: timed out after %0d cycles (ROB_COUNT=%0d). Dumping anyway.",
               MAX_CYCLES, `ROB_COUNT);

    dump_final_regs();

    $display("===== Done =====");
    $stop;
  end

endmodule