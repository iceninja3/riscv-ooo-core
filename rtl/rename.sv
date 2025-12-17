module Rename #(
  parameter int N_LOG        = 32,
  parameter int N_PHYS       = 64,
  parameter int N_CHECKPTS   = 8,
  parameter int ROB_TAG_W    = 4
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
  input  logic                      dec_is_jump_i,     // <--- NEW INPUT
  input logic [4:0]                 rob_count_i,
  input logic rob_commit_is_branch_jump_i, // <--- ADD THIS

  input  pipeline_types::ctrl_payload_t payload_i,
  output pipeline_types::ctrl_payload_t payload_o,

  // dispatch stage handshake
  output logic                      ren_valid_o,
  input  logic                      ren_ready_i,

  // renamed physical registers
  output logic [$clog2(N_PHYS)-1:0] rs1_p_o,
  output logic [$clog2(N_PHYS)-1:0] rs2_p_o,
  output logic [$clog2(N_PHYS)-1:0] rd_new_p_o,
  output logic [$clog2(N_PHYS)-1:0] rd_old_p_o,

  output logic [ROB_TAG_W-1:0]      rob_tag_o,

  // commit frees
  input  logic                      rob_commit_free_valid_i,
  input  logic [$clog2(N_PHYS)-1:0] rob_commit_free_preg_i,

  // misprediction recovery
  input  logic                      recover_i
);

  // declarations
  int i;
  int idx;

  logic [$clog2(N_PHYS)-1:0] map_table [N_LOG];

  localparam int X0_LOG  = 0;
  localparam int P0_PHYS = 0;

  localparam int FL_W = $clog2(N_PHYS);

  logic [FL_W-1:0] freelist [N_PHYS];
  logic [FL_W-1:0] fl_head;
  logic [FL_W-1:0] fl_tail;
  int              fl_count;

  logic [ROB_TAG_W-1:0]      rob_tag_q;
  logic [$clog2(N_PHYS)-1:0] map_ckpt      [N_CHECKPTS][N_LOG];
  logic [FL_W-1:0]           fl_head_ckpt  [N_CHECKPTS];
  logic [FL_W-1:0]           fl_tail_ckpt  [N_CHECKPTS];
  int                        fl_count_ckpt [N_CHECKPTS];
  logic [ROB_TAG_W-1:0]      rob_tag_ckpt  [N_CHECKPTS];
  int                        ckpt_sp;

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

  logic need_alloc;

  assign need_alloc = dec_valid_i && dec_rd_used_i && (dec_rd_i != 5'd0) && !dec_is_branch_i;

  logic resources_ok;
  // <--- FIXED: Check checkpoints for Jumps too
  assign resources_ok = ((!need_alloc) || (fl_count > 0))
                        && (!(dec_is_branch_i || dec_is_jump_i) || ckpt_sp < N_CHECKPTS);

  logic stage_ready_for_decode;
  assign stage_ready_for_decode = (!out_valid_q) || ren_ready_i;

  logic accept_decode;
  assign accept_decode = dec_valid_i && stage_ready_for_decode &&
                         resources_ok && !recover_i;

  // ============================================================
  // MAIN SEQUENTIAL LOGIC
  // ============================================================
  always_ff @(posedge clk) begin
    if (dec_valid_i && payload_i.pc == 32'h44) begin
        $display("[RENAME DEBUG] PC=0x44. dec_rd_used_i=%b (If 1, top.sv wiring is wrong!)", dec_rd_used_i);
    end
    if (rst) begin

      for (i = 0; i < N_LOG; i++)
        map_table[i] <= i[$clog2(N_PHYS)-1:0];

      for (i = 0; i < N_PHYS; i++)
        freelist[i] <= i[FL_W-1:0];

      fl_head  <= N_LOG[FL_W-1:0];
      fl_tail  <= N_PHYS[FL_W-1:0];
      fl_count <= N_PHYS - N_LOG;

      rob_tag_q <= '0;
      ckpt_sp   <= 0;

      out_valid_q   <= 0;
      rs1_p_q       <= 0;
      rs2_p_q       <= 0;
      rd_new_p_q    <= 0;
      rd_old_p_q    <= 0;
      rob_tag_out_q <= 0;

    end else begin

      // commit frees
      if (rob_commit_free_valid_i &&
          rob_commit_free_preg_i != P0_PHYS[$clog2(N_PHYS)-1:0]) begin
        freelist[fl_tail] <= rob_commit_free_preg_i;
        fl_tail           <= fl_tail + 1'b1;
        fl_count          <= fl_count + 1;
      end

      // ================================================================
      // RECOVERY
      // ================================================================
      if (recover_i && ckpt_sp > 0) begin

        idx = ckpt_sp - 1;
        ckpt_sp <= ckpt_sp - 1;

        for (i = 0; i < N_LOG; i++)
          map_table[i] <= map_ckpt[idx][i];

        fl_head   <= fl_head_ckpt[idx];
        fl_tail   <= fl_tail_ckpt[idx];
        fl_count  <= fl_count_ckpt[idx];
        rob_tag_q <= rob_tag_ckpt[idx];

        out_valid_q <= 0;

      end else begin
                  // ... inside the else block of always_ff ...
              
              // -------------------------------------------------------------
              // 1. Calculate Next Stack Pointer (Handle Freeing + Allocating)
              // -------------------------------------------------------------
              automatic int next_sp = ckpt_sp; // Start with current value

              // FREE: If ROB says a branch/jump committed successfully, free a slot.
              // (Note: Check 'rob_commit_free_valid_i' to ensure it's a valid commit)
              if (rob_commit_free_valid_i && rob_commit_is_branch_jump_i && ckpt_sp > 0) begin
                  next_sp = next_sp - 1;
              end
              
              // -------------------------------------------------------------
              // 2. Main Decode Logic
              // -------------------------------------------------------------
              if (rob_count_i == 0) begin
                  ckpt_sp <= 0;
                  // Safety: If ROB is empty, reset stack entirely.
                  next_sp = 0; 
              end

              if (out_valid_q && ren_ready_i)
                  out_valid_q <= 0;

              if (accept_decode) begin
                    $display("[RENAME] t=%0t PC=%h Inst=%h | Mapping: rs1(x%0d)->P%0d  rs2(x%0d)->P%0d  rd(x%0d)->P%0d (Old: P%0d)",
                      $time, payload_i.pc, payload_i.inst,
                      dec_rs1_i, rs1_p_q, 
                      dec_rs2_i, rs2_p_q,
                      dec_rd_i, rd_new_p_q, rd_old_p_q);

                    payload_o <= payload_i;

                    // Standard Mapping
                    rs1_p_q <= dec_rs1_used_i ? map_table[dec_rs1_i] : '0;
                    rs2_p_q <= dec_rs2_used_i ? map_table[dec_rs2_i] : '0;
                    rd_old_p_q <= (dec_rd_used_i && !dec_is_branch_i) ? map_table[dec_rd_i] : '0;

                    // Allocation
                    if (need_alloc) begin
                      rd_new_p_q          <= freelist[fl_head];
                      map_table[dec_rd_i] <= freelist[fl_head];
                      fl_head             <= fl_head + 1;
                      fl_count            <= fl_count - 1;
                    end else begin
                      rd_new_p_q <= map_table[dec_rd_i];
                    end

                    // Tag tracking (Technically unused by Dispatch, but fine to keep)
                    rob_tag_out_q <= rob_tag_q;
                    rob_tag_q     <= rob_tag_q + 1;

                    // -------------------------------------------------------------
                    // 3. Checkpoint Creation (Using the calculated next_sp)
                    // -------------------------------------------------------------
                    if (dec_is_branch_i || dec_is_jump_i) begin
                        
                        if (next_sp < N_CHECKPTS) begin
                            // Capture Snapshot
                            // Note: Since map_table update is non-blocking (<=), 
                            // this blocking read (=) correctly captures the OLD table state.
                            map_ckpt[next_sp]      = map_table; 
                            fl_head_ckpt[next_sp]  = fl_head;
                            fl_tail_ckpt[next_sp]  = fl_tail;
                            fl_count_ckpt[next_sp] = fl_count;
                            rob_tag_ckpt[next_sp]  = rob_tag_q;
                            
                            // Increment local variable
                            next_sp = next_sp + 1;
                        end
                    end
                    
                    // Apply the final calculated SP to the register
                    ckpt_sp <= next_sp;

                    out_valid_q <= 1;
              end
              // ... end else block ...

      
      
    end
  end

endmodule