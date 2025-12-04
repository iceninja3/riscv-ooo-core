`timescale 1ns/1ps

import pipeline_types::*;

module tb_Rename;

  // Use defaults from the DUT
  localparam int N_LOG      = 32;
  localparam int N_PHYS     = 64;
  localparam int N_CHECKPTS = 8;
  localparam int ROB_TAG_W  = 6;

  // Clock & reset
  logic clk = 0;
  logic rst = 1;

  always #5 clk = ~clk; // 100 MHz

  // DUT inputs
  logic                      dec_valid_i;
  logic [4:0]                dec_rs1_i;
  logic [4:0]                dec_rs2_i;
  logic [4:0]                dec_rd_i;
  logic                      dec_rs1_used_i;
  logic                      dec_rs2_used_i;
  logic                      dec_rd_used_i;
  logic                      dec_is_branch_i;

  ctrl_payload_t             payload_i;

  logic                      ren_ready_i;
  logic                      rob_commit_free_valid_i;
  logic [$clog2(N_PHYS)-1:0] rob_commit_free_preg_i;
  logic                      recover_i;

  // DUT outputs
  ctrl_payload_t             payload_o;
  logic                      ren_valid_o;
  logic [$clog2(N_PHYS)-1:0] rs1_p_o;
  logic [$clog2(N_PHYS)-1:0] rs2_p_o;
  logic [$clog2(N_PHYS)-1:0] rd_new_p_o;
  logic [$clog2(N_PHYS)-1:0] rd_old_p_o;
  logic [ROB_TAG_W-1:0]      rob_tag_o;

  // Instantiate DUT
  Rename #(
    .N_LOG      (N_LOG),
    .N_PHYS     (N_PHYS),
    .N_CHECKPTS (N_CHECKPTS),
    .ROB_TAG_W  (ROB_TAG_W)
  ) dut (
    .clk                     (clk),
    .rst                     (rst),

    .dec_valid_i             (dec_valid_i),
    .dec_rs1_i               (dec_rs1_i),
    .dec_rs2_i               (dec_rs2_i),
    .dec_rd_i                (dec_rd_i),
    .dec_rs1_used_i          (dec_rs1_used_i),
    .dec_rs2_used_i          (dec_rs2_used_i),
    .dec_rd_used_i           (dec_rd_used_i),
    .dec_is_branch_i         (dec_is_branch_i),

    .payload_i               (payload_i),
    .payload_o               (payload_o),

    .ren_valid_o             (ren_valid_o),
    .ren_ready_i             (ren_ready_i),

    .rs1_p_o                 (rs1_p_o),
    .rs2_p_o                 (rs2_p_o),
    .rd_new_p_o              (rd_new_p_o),
    .rd_old_p_o              (rd_old_p_o),

    .rob_tag_o               (rob_tag_o),

    .rob_commit_free_valid_i (rob_commit_free_valid_i),
    .rob_commit_free_preg_i  (rob_commit_free_preg_i),

    .recover_i               (recover_i)
  );

  // Simple task to send one instruction into rename and print the result
  task automatic send_instr(
    input  logic [4:0] rs1,
    input  logic [4:0] rs2,
    input  logic [4:0] rd,
    input  logic       rs1_used,
    input  logic       rs2_used,
    input  logic       rd_used,
    input  logic       is_branch,
    input  string      name
  );
  begin
    // Drive decode inputs for 1 cycle
    @(negedge clk);
    dec_valid_i      <= 1'b1;
    dec_rs1_i        <= rs1;
    dec_rs2_i        <= rs2;
    dec_rd_i         <= rd;
    dec_rs1_used_i   <= rs1_used;
    dec_rs2_used_i   <= rs2_used;
    dec_rd_used_i    <= rd_used;
    dec_is_branch_i  <= is_branch;

    // keep payload_i simple (just tag the name via pc/imm/inst if you want)
    payload_i.pc      <= 32'(0);
    payload_i.imm     <= 32'(0);
    payload_i.inst    <= 32'(0);
    payload_i.ALUSrc  <= 1'b0;
    payload_i.ALUOp   <= 3'b000;
    payload_i.MemRead <= 1'b0;
    payload_i.MemWrite<= 1'b0;
    payload_i.RegWrite<= rd_used;
    payload_i.MemToReg<= 1'b0;
    payload_i.fu_type <= FU_ALU;
    payload_i.is_branch <= is_branch;
    payload_i.is_jump   <= 1'b0;

    @(posedge clk); // instruction is sampled here
    dec_valid_i <= 1'b0;

    // Wait until rename produces a valid output
    wait (ren_valid_o === 1'b1);
    @(posedge clk); // sample outputs at a clock edge

    $display("[%0t] %s : rs1=%0d -> rs1_p=%0d | rs2=%0d -> rs2_p=%0d | rd=%0d -> rd_old_p=%0d, rd_new_p=%0d | rob_tag=%0d",
             $time, name,
             rs1, rs1_p_o,
             rs2, rs2_p_o,
             rd,  rd_old_p_o, rd_new_p_o,
             rob_tag_o);

    // downstream always ready, so ren_valid_o should drop next cycle
    @(posedge clk);
  end
  endtask

  initial begin
    // Default input values
    dec_valid_i              = 1'b0;
    dec_rs1_i                = '0;
    dec_rs2_i                = '0;
    dec_rd_i                 = '0;
    dec_rs1_used_i           = 1'b0;
    dec_rs2_used_i           = 1'b0;
    dec_rd_used_i            = 1'b0;
    dec_is_branch_i          = 1'b0;

    payload_i                = '0;

    ren_ready_i              = 1'b1;   // always ready
    rob_commit_free_valid_i  = 1'b0;
    rob_commit_free_preg_i   = '0;
    recover_i                = 1'b0;

    // Reset for a few cycles
    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);

    $display("=== Basic rename tests ===");

    // 1) Simple ALU instr: rs1=1, rs2=2, rd=3
    //    Expect:
    //      rs1_p = 1, rs2_p = 2, rd_old_p = 3, rd_new_p = 32 (first free PREG)
    send_instr(5'd1, 5'd2, 5'd3,
               1'b1, 1'b1, 1'b1,
               1'b0,
               "I1: ALU rs1=1, rs2=2, rd=3");

    // 2) Another dest write to rd=3
    //    Now map_table[3] should become the next free PREG (33),
    //    rd_old_p = 32 (from previous mapping), rd_new_p = 33.
    send_instr(5'd3, 5'd0, 5'd3,
               1'b1, 1'b0, 1'b1,
               1'b0,
               "I2: ALU rs1=3, rd=3 again");

    // 3) Write to x0 (rd=0) should NOT allocate a new physical reg
    //    Expect rd_new_p = P0_PHYS (0), and no change to freelist.
    send_instr(5'd1, 5'd2, 5'd0,
               1'b1, 1'b1, 1'b1,
               1'b0,
               "I3: Write to x0 (rd=0)");

    // 4) Branch instruction that creates a checkpoint (no dest)
    send_instr(5'd4, 5'd5, 5'd0,
               1'b1, 1'b1, 1'b0,
               1'b1,  // is_branch
               "I4: Branch, checkpoint");

    // 5) Example: commit one of the previously allocated PREGs back to free list
    //    Here we pretend the ROB told us PREG 32 is free again.
    @(posedge clk);
    rob_commit_free_valid_i <= 1'b1;
    rob_commit_free_preg_i  <= 32;
    @(posedge clk);
    rob_commit_free_valid_i <= 1'b0;

    $display("=== Done. Check waveforms / console for rename behavior. ===");
    repeat (10) @(posedge clk);
    $finish;
  end

endmodule