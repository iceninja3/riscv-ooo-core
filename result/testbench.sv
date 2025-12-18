`timescale 1ns/1ps
`include "pipeline_types.sv"

module tb_final_regs;

  import pipeline_types::*;

  logic clk = 0;
  logic reset = 1;

  always #5 clk = ~clk;

  RISCV dut (
    .clk   (clk),
    .reset (reset)
  );

  `define PRF_VAL(p)    dut.u_rf.registers[p]

  logic [31:0] exp_arch  [0:31];
  bit          exp_valid [0:31];

  initial begin : init_expected
    for (int i = 0; i < 32; i++) begin
      exp_arch[i]  = 32'h0;
      exp_valid[i] = 1'b0;
    end

    exp_arch[0]  = 32'h0000_0000;
    exp_valid[0] = 1'b1;
  end

  bit dumped_once = 0;

  task automatic dump_final_regs(string reason);
    int a;
    logic [31:0] actual;
    string status;
    begin
      if (dumped_once) return;
      dumped_once = 1;

      $display("\n===== FINAL ARCH REGISTER DUMP =====");
      $display("Program Finished: %0d cycles", completion_cycle);
      $display("Total Sim Time:   %0t", $time);
      $display("-------------------------------------");
      $display("Reg | Actual       | Expected     | Status");
      $display("----+-------------+-------------+---------");

      for (a = 0; a < 32; a++) begin
        actual = `PRF_VAL(a);

        if (a == 0 && actual !== 32'h0) begin
          $display("x0  | 0x%08h | 0x00000000 | X0_BROKEN", actual);
        end
        else if (exp_valid[a]) begin
          status = (actual === exp_arch[a]) ? "OK" : "MISMATCH";
          $display("x%-2d| 0x%08h | 0x%08h | %s",
                   a, actual, exp_arch[a], status);
        end else begin
          $display("x%-2d| 0x%08h | (n/a)       | no-exp",
                   a, actual);
        end
      end

      $display("=====================================\n");
    end
  endtask

  final begin
    dump_final_regs("final block (sim ending)");
  end

  localparam int RESET_CYCLES = 4;
  localparam int MAX_CYCLES   = 200000;
  localparam int QUIET_CYCLES = 50;

  int cycles;
  int quiet_ctr;
  int completion_cycle;
initial begin
    $display("===== Starting FINAL-REGS In-Order testbench =====");

    // Reset Sequence
    reset = 1;
    repeat (RESET_CYCLES) @(posedge clk);
    reset = 0;

    cycles    = 0;
    quiet_ctr = 0;
    completion_cycle = 0;

    while (cycles < MAX_CYCLES) begin
      @(posedge clk);
      cycles++;

      // 1. MONITOR ACTIVITY
      if (dut.state == 3'd4) begin // S_WRITEBACK
         quiet_ctr = 0;
         completion_cycle = cycles;
      end else begin
         quiet_ctr++;
      end

      // 2. STOP IF WE HIT GARBAGE MEMORY (The "Runaway" Fix)
      // If the instruction is 'x', we've run off the end of program.hex
      if (dut.inst_reg === 32'hxxxxxxxx && cycles > 1000) begin
        $display("Detected uninitialized memory at PC=%h. Ending simulation.", dut.pc_reg);
        dump_final_regs("Program End (Memory Limit)");
        $finish;
      end

      // 3. STOP IF WE REACH THE LOGICAL END OF JSWR (PC 0xDC)
      // According to 25jswr.txt, the last instruction is at 0xdc.
      if (dut.pc_reg == 32'h000000dc && dut.state == 3'd4) begin
        $display("Reached final instruction of trace at PC=0xDC.");
        dump_final_regs("Success: Trace Complete");
        $finish;
      end

      // 4. STOP IF QUIESCENT
      if (quiet_ctr >= QUIET_CYCLES) begin
        $display("Reached quiescent state (No Writeback for %0d cycles)", QUIET_CYCLES);
        dump_final_regs("Success: Quiescent");
        $finish;
      end
    end

    // Timeout Path
    $display("WARNING: timed out after %0d cycles.", MAX_CYCLES);
    dump_final_regs("TIMEOUT");
    $finish;
  end

endmodule