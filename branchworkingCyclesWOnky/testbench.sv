`timescale 1ns/1ps
`include "pipeline_types.sv"
// branch prediction tb

module tb_final_regs;

  import pipeline_types::*;

  // ----------------------------
  // Signal Declarations
  // ----------------------------
  logic clk = 0;
  logic reset = 1;

  // ----------------------------
  // Clock Generation
  // ----------------------------
  always #5 clk = ~clk;

  // ----------------------------
  // DUT Instance
  // ----------------------------
  RISCV dut (
    .clk   (clk),
    .reset (reset)
  );

  // ----------------------------
  // Parameters & Tracking Variables
  // ----------------------------
  localparam int RESET_CYCLES = 4;   // Fixed: Declared before use [cite: 20]
  localparam int MAX_CYCLES   = 200000; 
  localparam int QUIET_CYCLES = 50;

  int cycles;           // Fixed: Declared before use [cite: 22]
  int quiet_ctr;        // Fixed: Declared before use [cite: 22]
  int completion_cycle; // Fixed: Declared before use [cite: 22]

  // ----------------------------
  // Expected Register Array
  // ----------------------------
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

  // ----------------------------
  // Final Dump Task
  // ----------------------------
  bit dumped_once = 0;

  task automatic dump_final_regs(string reason);
    int a;
    logic [31:0] actual;
    string status;
    begin
      if (dumped_once) return;
      dumped_once = 1;

      $display("\n===== FINAL ARCH REGISTER DUMP =====");
      $display("Reason: %s", reason);
      $display("Program Finished: %0d cycles (after reset)", completion_cycle);
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
          $display("x%-2d| 0x%08h | 0x%08h | %s", a, actual, exp_arch[a], status);
        end else begin
          $display("x%-2d| 0x%08h | (n/a)       | no-exp", a, actual);
        end
      end
      $display("=====================================\n");
    end
  endtask

  final begin
    dump_final_regs("final block (sim ending)");
  end

  // ----------------------------
  // Main Control Logic
  // ----------------------------
  initial begin
    $display("===== Starting FINAL-REGS In-Order testbench =====");

    // 1. Synchronous Reset Sequence
    reset = 1;
    cycles = 0;
    quiet_ctr = 0;
    completion_cycle = 0;

    repeat (RESET_CYCLES) begin
      @(posedge clk);
      cycles++; 
    end
    
    // De-assert reset on negedge to ensure stability for next posedge
    @(negedge clk);
    reset = 0;
    $display("Reset de-asserted at cycle %0d", cycles);

    // 2. Main Execution Loop
    while (cycles < MAX_CYCLES) begin
      @(posedge clk);
      cycles++; 

      // MONITOR ACTIVITY: Check for retirement in S_WRITEBACK (State 4) [cite: 28]
      if (dut.state == 3'd4) begin 
         quiet_ctr = 0;
         completion_cycle = cycles - RESET_CYCLES; 
      end else begin
         quiet_ctr++;
      end

      // 3. RUNAWAY DETECTION
      if (cycles > 1000 && quiet_ctr > 10) begin
        if (dut.inst_reg === 32'hxxxxxxxx) begin
          $display("ABORT: Hit uninitialized memory at PC=%h", dut.pc_reg);
          $finish; 
        end
      end

      // 4. QUIESCENCE TERMINATION
      if (quiet_ctr >= QUIET_CYCLES) begin
        $display("Reached quiescent state (No activity for %0d cycles)", QUIET_CYCLES);
        $finish; 
      end
    end

    // 5. Timeout Path
    $display("ERROR: Timed out after %0d cycles.", MAX_CYCLES);
    $finish;
  end

endmodule