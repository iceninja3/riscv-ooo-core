module Rename #(
  parameter int N_LOG        = 32,   // logical regs
  parameter int N_PHYS       = 64,   // physical regs
  parameter int N_CHECKPTS   = 8,    // max in flight branch checkpoints
  parameter int ROB_TAG_W    = 6     // width of ROB tag counter
)(
  input  logic                      clk,
  input  logic                      rst,

  // decode stage
  input  logic                      dec_valid_i,
  input  logic [4:0]                dec_rs1_i,
  input  logic [4:0]                dec_rs2_i,
  input  logic [4:0]                dec_rd_i,
  input  logic                      dec_rs1_used_i,
  input  logic                      dec_rs2_used_i,
  input  logic                      dec_rd_used_i,
  input  logic                      dec_is_branch_i,   

  // for dispatch stage 
  output logic                      ren_valid_o,
  input  logic                      ren_ready_i,

  // renamed physical registers
  output logic [$clog2(N_PHYS)-1:0] rs1_p_o,
  output logic [$clog2(N_PHYS)-1:0] rs2_p_o,
  output logic [$clog2(N_PHYS)-1:0] rd_new_p_o,  // new dest PREG
  output logic [$clog2(N_PHYS)-1:0] rd_old_p_o,  // previous dest PREG 

  // ROB tag per instruction
  output logic [ROB_TAG_W-1:0]      rob_tag_o,

  // From ROB on commit: one dest becomes free
  input  logic                      rob_commit_free_valid_i,
  input  logic [$clog2(N_PHYS)-1:0] rob_commit_free_preg_i,

  // From ROB on misprediction
  input  logic                      recover_i          // restore most recent checkpoint
);


  // Map table: logical to physical
  logic [$clog2(N_PHYS)-1:0] map_table [N_LOG];

  localparam int X0_LOG  = 0;
  localparam int P0_PHYS = 0;

  // Free list: circular buffer of PREG IDs
  localparam int FL_W = $clog2(N_PHYS);

  logic [FL_W-1:0] freelist [N_PHYS];  // stores PREG IDs
  logic [FL_W-1:0] fl_head;            // pop from head
  logic [FL_W-1:0] fl_tail;            // push at tail
  int              fl_count;           // number of free regs available

  // ROB tag counter
  logic [ROB_TAG_W-1:0] rob_tag_q;

  // checkpoint 
  logic [$clog2(N_PHYS)-1:0] map_ckpt      [N_CHECKPTS][N_LOG];
  logic [FL_W-1:0]           fl_head_ckpt  [N_CHECKPTS];
  logic [FL_W-1:0]           fl_tail_ckpt  [N_CHECKPTS];
  int                        fl_count_ckpt [N_CHECKPTS];
  logic [ROB_TAG_W-1:0]      rob_tag_ckpt  [N_CHECKPTS];
  int                        ckpt_sp;     // number of valid checkpoints 

  // Rename stage output register (for proper ready/valid)
  logic                      out_valid_q;
  logic [$clog2(N_PHYS)-1:0] rs1_p_q, rs2_p_q;
  logic [$clog2(N_PHYS)-1:0] rd_new_p_q, rd_old_p_q;
  logic [ROB_TAG_W-1:0]      rob_tag_out_q;

  assign ren_valid_o = out_valid_q;
  assign rs1_p_o     = rs1_p_q;
  assign rs2_p_o     = rs2_p_q;
  assign rd_new_p_o  = rd_new_p_q;
  assign rd_old_p_o  = rd_old_p_q;
  assign rob_tag_o   = rob_tag_out_q;

  // helper flags
  logic need_alloc;
  assign need_alloc = dec_valid_i && dec_rd_used_i && (dec_rd_i != X0_LOG);

  //allocate if either we don't need a new PREG or the free list is non empty
  logic resources_ok;
  assign resources_ok = (!need_alloc) || (fl_count > 0);

  //accept a new decode instruction if either
  //its output register is empty or
  //the consumer is ready
  logic stage_ready_for_decode;
  assign stage_ready_for_decode = (!out_valid_q) || ren_ready_i;

  logic accept_decode;
  assign accept_decode = dec_valid_i && stage_ready_for_decode && resources_ok && !recover_i;

  // Sequential logic
  always_ff @(posedge clk) begin
    if (rst) begin
      //initial logical to physical mapping
      for (int i = 0; i < N_LOG; i++) begin
        map_table[i] <= i[$clog2(N_PHYS)-1:0];
      end

      //initialize free list
      for (int p = 0; p < N_PHYS; p++) begin
        freelist[p] <= p[FL_W-1:0];
      end
      fl_head  <= N_LOG[FL_W-1:0];
      fl_tail  <= N_PHYS[FL_W-1:0];     
      fl_count <= N_PHYS - N_LOG;

      rob_tag_q      <= '0;
      ckpt_sp        <= 0;

      out_valid_q    <= 1'b0;
      rs1_p_q        <= '0;
      rs2_p_q        <= '0;
      rd_new_p_q     <= '0;
      rd_old_p_q     <= '0;
      rob_tag_out_q  <= '0;

    end else begin
      // 1) handle commit frees from ROB 
      if (rob_commit_free_valid_i) begin
        if (rob_commit_free_preg_i != P0_PHYS[$clog2(N_PHYS)-1:0]) begin
          freelist[fl_tail] <= rob_commit_free_preg_i;
          fl_tail           <= fl_tail + 1'b1;
          fl_count          <= fl_count + 1;
        end
      end

      // 2) recovery on misprediction
      if (recover_i && ckpt_sp > 0) begin
        ckpt_sp   <= ckpt_sp - 1;

        int idx   = ckpt_sp - 1; // last valid checkpoint

        for (int i = 0; i < N_LOG; i++) begin
          map_table[i] <= map_ckpt[idx][i];
        end

        fl_head   <= fl_head_ckpt[idx];
        fl_tail   <= fl_tail_ckpt[idx];
        fl_count  <= fl_count_ckpt[idx];
        rob_tag_q <= rob_tag_ckpt[idx];

        // Flush current output and dispatch will also be recovering
        out_valid_q <= 1'b0;
      end
      else begin
        // 3) normal rename / output register update

        // First, handle output valid bit like a pipeline stage
        // (1) drop current output when consumer takes it
        if (out_valid_q && ren_ready_i)
          out_valid_q <= 1'b0;

        // (2) accept new instruction if allowed
        if (accept_decode) begin
          // Compute sources
          rs1_p_q <= dec_rs1_used_i ? map_table[dec_rs1_i] : '0;
          rs2_p_q <= dec_rs2_used_i ? map_table[dec_rs2_i] : '0;

          // Old dest mapping (for ROB)
          if (dec_rd_used_i)
            rd_old_p_q <= map_table[dec_rd_i];
          else
            rd_old_p_q <= '0;

          // Allocate new physical dest if needed
          if (need_alloc) begin
            rd_new_p_q          <= freelist[fl_head];
            map_table[dec_rd_i] <= freelist[fl_head];
            fl_head             <= fl_head + 1'b1;
            fl_count            <= fl_count - 1;
          end else begin
            rd_new_p_q          <= map_table[dec_rd_i]; // pass-through / don't-care
          end

          // ROB tag for this instruction
          rob_tag_out_q <= rob_tag_q;
          rob_tag_q     <= rob_tag_q + 1'b1;

          // Checkpoint on branch/jump, if space is left
          if (dec_is_branch_i && (ckpt_sp < N_CHECKPTS)) begin
            int idx = ckpt_sp;
            for (int i = 0; i < N_LOG; i++) begin
              map_ckpt[idx][i] = map_table[i];
            end
            fl_head_ckpt[idx]  = fl_head;
            fl_tail_ckpt[idx]  = fl_tail;
            fl_count_ckpt[idx] = fl_count;
            rob_tag_ckpt[idx]  = rob_tag_q;
            ckpt_sp            <= ckpt_sp + 1;
          end

          //now have a valid renamed instruction ready for dispatch
          out_valid_q <= 1'b1;
        end
      end
    end
  end

endmodule
