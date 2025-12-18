`timescale 1ns/1ps
`include "pipeline_types.sv"

module tb_final_regs;

  import pipeline_types::*;

  // --- Clock & Reset ---
  logic clk = 0;
  logic reset = 1;
  always #5 clk = ~clk;

  // --- DUT ---
  RISCV dut (.clk(clk), .reset(reset));

  // --- Logic & Params ---
  localparam int RESET_CYCLES = 4;
  localparam int MAX_CYCLES   = 200000; 
  localparam int QUIET_CYCLES = 50;

  int cycles, quiet_ctr, completion_cycle;

  // --- Register File Macro & Tracking ---
  `define PRF_VAL(p)    dut.u_rf.registers[p]
  logic [31:0] exp_arch [0:31];
  bit          exp_valid [0:31];

  initial begin : init_expected
    for (int i = 0; i < 32; i++) begin
      exp_arch[i] = 32'h0;
      exp_valid[i] = 1'b0;
    end
    exp_arch[0] = 32'h0000_0000;
    exp_valid[0] = 1'b1;
  end

  // --- Simplified Final Dump ---
  bit dumped_once = 0;
  task automatic dump_final_regs();
    int a;
    logic [31:0] actual;
    begin
      if (dumped_once) return;
      dumped_once = 1;
      $display("\n===== FINAL ARCH REGISTER DUMP =====");
      $display("Cycles: %0d", completion_cycle);
      $display("Time:   %0t", $time);
      $display("-------------------------------------");
      for (a = 0; a < 32; a++) begin
        actual = `PRF_VAL(a);
        if (exp_valid[a])
          $display("x%-2d| 0x%08h | 0x%08h | %s", a, actual, exp_arch[a], (actual === exp_arch[a]) ? "OK" : "MISMATCH");
        else
          $display("x%-2d| 0x%08h | (n/a)", a, actual);
      end
      $display("=====================================\n");
    end
  endtask

  final dump_final_regs();

  // --- Main Control Loop ---
  initial begin
    reset = 1;
    cycles = 0;
    quiet_ctr = 0;
    completion_cycle = 0;

    repeat (RESET_CYCLES) @(posedge clk) cycles++;
    @(negedge clk);
    reset = 0;

    while (cycles < MAX_CYCLES) begin
      @(posedge clk);
      cycles++; 

      // 1. Monitor Activity (State 4 = S_WRITEBACK) [cite: 28]
      if (dut.state == 3'd4) begin 
         quiet_ctr = 0;
         completion_cycle = cycles - RESET_CYCLES; // Store last valid work cycle [cite: 31]
      end else begin
         quiet_ctr++;
      end

      // 2. Kill Switch: Stop if we hit X's or go quiet 
      // We check if the instruction is 'X' while in a state that should be fetching/decoding
      if (dut.inst_reg === 32'hxxxxxxxx && cycles > 500) begin
         $finish; 
      end

      if (quiet_ctr >= QUIET_CYCLES) begin
         $finish; 
      end
    end
    $finish;
  end

endmodule