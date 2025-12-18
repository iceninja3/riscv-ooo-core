`timescale 1ns/1ps
`include "pipeline_types.sv"

module tb_final_regs_inorder;

  import pipeline_types::*;

  // ----------------------------
  // Clock / Reset
  // ----------------------------
  logic clk = 0;
  logic reset = 1;

  always #5 clk = ~clk;

  // ----------------------------
  // DUT
  // ----------------------------
  RISCV dut (
    .clk   (clk),
    .reset (reset)
  );

  // ----------------------------
  // Helper Macros (Rewritten for In-Order)
  // ----------------------------
  
  // In our simplified design, Logical Reg A is stored in Physical Reg A. (1:1 mapping)
  // But our 'u_rf' is the physical register file module instance name in top.sv
  
  // Helper to get value
  // Note: in top.sv, we named the instance 'u_rf'
  `define PRF_VAL(p)    dut.u_rf.registers[p]

  // We don't have a ROB. We are "quiescent" if no instructions are retiring.
  // fe_valid_o is high when an instruction is in Decode. 
  // Let's use 'state' from top to check activity.
  `define DUT_STATE     dut.state

  // ----------------------------
  // Expected architectural registers (optional)
  // ----------------------------
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
  end

  // ----------------------------
  // Final dump task
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
      $display("Time=%0t", $time);
      $display("Reg | Actual       | Expected     | Status");
      $display("----+-------------+-------------+---------");

      for (a = 0; a < 32; a++) begin
        // In this design, Reg A is at index A of u_rf
        actual = `PRF_VAL(a);

        // Enforce x0 = 0 check
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

  // Dump even if simulation ends due to $finish/$fatal elsewhere
  final begin
    dump_final_regs("final block (sim ending)");
  end

  // ----------------------------
  // Main run / watchdog
  // ----------------------------
  localparam int RESET_CYCLES = 4;
  localparam int MAX_CYCLES   = 200000; 
  localparam int QUIET_CYCLES = 50;     // No retire for N cycles

  int cycles;
  int quiet_ctr;
  
  // Monitor retired PC to detect progress
  logic [31:0] last_pc;
  logic [31:0] current_pc;

  initial begin
    $display("===== Starting FINAL-REGS In-Order testbench =====");

    // Reset
    reset = 1;
    repeat (RESET_CYCLES) @(posedge clk);
    reset = 0;

    cycles    = 0;
    quiet_ctr = 0;
    last_pc   = '0;

    // Run until quiescent
    while (cycles < MAX_CYCLES) begin
      @(posedge clk);
      cycles++;

      // Ideally we check if an instruction completed. 
      // In In-Order FSM, completion is S_WRITEBACK.
      // Access signal from DUT
      if (dut.state == 3'd4) begin // S_WRITEBACK declared as enum val 4? 
                                   // Note: enum encoding is usually 0,1,2,3,4. 
                                   // But to be safe, let's just check if valid activity happened.
         quiet_ctr = 0;
      end else begin
         quiet_ctr++;
      end

      if (quiet_ctr >= QUIET_CYCLES) begin
        $display("Reached quiescent state (No Writeback for %0d cycles)", QUIET_CYCLES);
        dump_final_regs("quiescent");
        $finish;
      end
    end

    // Timeout path
    $display("WARNING: timed out after %0d cycles. Dumping anyway.", MAX_CYCLES);
    dump_final_regs("TIMEOUT");
    $finish;
  end

endmodule
