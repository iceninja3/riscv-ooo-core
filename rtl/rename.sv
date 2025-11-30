module Rename #(
  parameter int N_LOG        = 32,   // logical (architectural) regs
  parameter int N_PHYS       = 64,   // physical regs
  parameter int N_CHECKPTS   = 8,    // max in-flight branch checkpoints
  parameter int ROB_TAG_W    = 6     // width of ROB tag counter
)(
  input  logic                      clk,
  input  logic                      rst,

  // From Decode / ID stage
  input  logic                      dec_valid_i,
  input  logic [4:0]                dec_rs1_i,
  input  logic [4:0]                dec_rs2_i,
  input  logic [4:0]                dec_rd_i,
  input  logic                      dec_rs1_used_i,
  input  logic                      dec_rs2_used_i,
  input  logic                      dec_rd_used_i,
  input  logic                      dec_is_branch_i,   // from decode.is_branch_like

  // To Dispatch stage (ready/valid)
  output logic                      ren_valid_o,
  input  logic                      ren_ready_i,

  // Renamed physical registers
  output logic [$clog2(N_PHYS)-1:0] rs1_p_o,
  output logic [$clog2(N_PHYS)-1:0] rs2_p_o,
  output logic [$clog2(N_PHYS)-1:0] rd_new_p_o,  // new dest PREG
  output logic [$clog2(N_PHYS)-1:0] rd_old_p_o,  // previous dest PREG (to free on commit)

  // ROB tag per instruction
  output logic [ROB_TAG_W-1:0]      rob_tag_o,

  // From ROB on commit: free this physical reg
  input  logic                      rob_commit_free_valid_i,
  input  logic [$clog2(N_PHYS)-1:0] rob_commit_free_preg_i,

  // From ROB on misprediction
  input  logic                      recover_i          // restore most recent checkpoint
);

  // -------------------------
  // Map table: logical -> physical
  // -------------------------
  logic [$clog2(N_PHYS)-1:0] map_table [N_LOG];

  localparam int X0_LOG  = 0;
  localparam int P0_PHYS = 0;

  // -------------------------
  // Free list: simple circular buffer of PREG IDs
  // -------------------------
  localparam int FL_W = $clog2(N_PHYS);

  logic [FL_W-1:0] freelist [N_PHYS];  // only entries [0 .. N_PHYS-1) used
  logic [FL_W-1:0] fl_head;            // pop from head
  logic [FL_W-1:0] fl_tail;            // push at tail
  int              fl_count;           // number of free regs available

  // -------------------------
  // ROB tag counter
  // -------------------------
  logic [ROB_TAG_W-1:0] rob_tag_q;

  assign rob_tag_o = rob_tag_q;

  // -------------------------
  // Checkpoint storage
  //   We snapshot: map_table, fl_head, fl_count, rob_tag
  // -------------------------
  logic [$clog2(N_PHYS)-1:0] map_ckpt      [N_CHECKPTS][N_LOG];
  logic [FL_W-1:0]           fl_head_ckpt  [N_CHECKPTS];
  int                        fl_count_ckpt [N_CHECKPTS];
  logic [ROB_TAG_W-1:0]      rob_tag_ckpt  [N_CHECKPTS];
  int                        ckpt_sp;     // number of valid checkpoints (stack pointer)

  // -------------------------
  // Indicates whether we must allocate a new PREG this cycle
  // -------------------------
  logic need_alloc;
  assign need_alloc = dec_valid_i && dec_rd_used_i && (dec_rd_i != X0_LOG);

  // Can this instruction be accepted + renamed this cycle?
  logic can_fire;
  assign can_fire = dec_valid_i &&
                    ren_ready_i &&
                    (!need_alloc || (fl_count > 0));

  // -------------------------
  // Source mapping (combinational)
  // -------------------------
  always_comb begin
    rs1_p_o = dec_rs1_used_i ? map_table[dec_rs1_i] : '0;
    rs2_p_o = dec_rs2_used_i ? map_table[dec_rs2_i] : '0;
  end

  // Rename outputs are valid only when we actually fire an instruction
  assign ren_valid_o = can_fire;

  // -------------------------
  // Sequential logic
  // -------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      // ---- Initial logical->physical mapping: xi -> pi ----
      for (int i = 0; i < N_LOG; i++) begin
        map_table[i] <= i[$clog2(N_PHYS)-1:0];
      end

      // ---- Initialize free list: p[N_LOG] .. p[N_PHYS-1] ----
      for (int p = 0; p < N_PHYS; p++) begin
        freelist[p] <= p[FL_W-1:0];
      end
      fl_head  <= N_LOG[FL_W-1:0];
      fl_tail  <= N_PHYS[FL_W-1:0];
      fl_count <= N_PHYS - N_LOG;

      // ROB tag and checkpoints
      rob_tag_q <= '0;
      ckpt_sp   <= 0;

      rd_new_p_o <= '0;
      rd_old_p_o <= '0;

    end else begin
      // ---------------------
      // 1) Handle commit frees from ROB
      // ---------------------
      if (rob_commit_free_valid_i) begin
        if (rob_commit_free_preg_i != P0_PHYS[$clog2(N_PHYS)-1:0]) begin
          freelist[fl_tail] <= rob_commit_free_preg_i;
          fl_tail           <= fl_tail + 1'b1;
          fl_count          <= fl_count + 1;
        end
      end

      // ---------------------
      // 2) Recovery on misprediction
      // ---------------------
      if (recover_i && ckpt_sp > 0) begin
        ckpt_sp   <= ckpt_sp - 1;

        int idx   = ckpt_sp - 1; // last valid checkpoint

        for (int i = 0; i < N_LOG; i++) begin
          map_table[i] <= map_ckpt[idx][i];
        end

        fl_head   <= fl_head_ckpt[idx];
        fl_count  <= fl_count_ckpt[idx];
        rob_tag_q <= rob_tag_ckpt[idx];

        // On recovery we don't accept a new instruction this cycle
      end
      // ---------------------
      // 3) Normal rename when we can fire
      // ---------------------
      else if (can_fire) begin
        // Old dest mapping (for ROB to free at commit)
        if (dec_rd_used_i)
          rd_old_p_o <= map_table[dec_rd_i];
        else
          rd_old_p_o <= '0;

        // Allocate new physical dest if needed (rd != x0 and rd_used)
        if (need_alloc) begin
          rd_new_p_o          <= freelist[fl_head];
          map_table[dec_rd_i] <= freelist[fl_head];
          fl_head             <= fl_head + 1'b1;
          fl_count            <= fl_count - 1;
        end else begin
          rd_new_p_o          <= map_table[dec_rd_i]; // pass-through / don't-care
        end

        // ---- Take a checkpoint on branch/jump, if space is left ----
        if (dec_is_branch_i && (ckpt_sp < N_CHECKPTS)) begin
          int idx = ckpt_sp;
          for (int i = 0; i < N_LOG; i++) begin
            map_ckpt[idx][i] = map_table[i];
          end
          fl_head_ckpt[idx]  = fl_head;
          fl_count_ckpt[idx] = fl_count;
          rob_tag_ckpt[idx]  = rob_tag_q;
          ckpt_sp            <= ckpt_sp + 1;
        end

        // Advance ROB tag for this (renamed) instruction
        rob_tag_q <= rob_tag_q + 1'b1;
      end
      // else: stall, hold all state
    end
  end

endmodule
