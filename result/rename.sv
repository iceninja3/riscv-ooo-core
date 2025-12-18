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
  input  logic                      dec_is_jump_i,
  
  // ROB status (for hacks/fixes)
  input logic [4:0]                 rob_count_i,
  input logic                       rob_commit_is_branch_jump_i,

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

  localparam int FL_W = $clog2(N_PHYS);

  logic [FL_W-1:0] freelist [N_PHYS];
  logic [FL_W-1:0] fl_head;
  logic [FL_W-1:0] fl_tail;
  int              fl_count;

  logic [ROB_TAG_W-1:0]      rob_tag_q;

  // Checkpoints
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

  // --------------------------------------------------------------------------
  // Allocation Logic (Deadlock Fix)
  // --------------------------------------------------------------------------
  logic need_alloc;
  // FIX: Force need_alloc to 0 if it is a Branch, to prevent consuming registers.
  assign need_alloc = dec_valid_i && dec_rd_used_i && (dec_rd_i != 5'd0) && !dec_is_branch_i;

  logic resources_ok;
  // Check freelist and checkpoints
  assign resources_ok = (fl_count > 0 || !need_alloc) && 
                        (ckpt_sp < N_CHECKPTS || !(dec_is_branch_i || dec_is_jump_i));

  logic stage_ready_for_decode;
  assign stage_ready_for_decode = (!out_valid_q) || ren_ready_i;

  logic accept_decode;
  assign accept_decode = dec_valid_i && stage_ready_for_decode && resources_ok && !recover_i;

  // ============================================================
  // MAIN SEQUENTIAL LOGIC
  // ============================================================
  always_ff @(posedge clk) begin

    if (rst) begin
      // ------------------------------------------------------------
      // RESET LOGIC (CRITICAL FIX FOR 25SWR)
      // ------------------------------------------------------------
      // 1. Initialize Map Table to all 0s (P0). 
      // This ensures reading unwritten registers returns 0 (P0 hardwired in Top).
      for (i = 0; i < N_LOG; i++)
        map_table[i] <= 6'd0;

      // 2. Initialize Freelist
      // We fill it with 0..63.
      for (i = 0; i < N_PHYS; i++)
        freelist[i] <= i[FL_W-1:0]; 
      
      // 3. Skip P0 in Freelist
      // P0 is shared by all reset registers. We must NOT allocate it.
      // Start Head at 1. The first allocated reg will be freelist[1] = P1.
      fl_head  <= 6'd1; 
      fl_tail  <= 6'd0; 
      fl_count <= N_PHYS - 1; // 63 free registers (P1..P63).

      rob_tag_q <= '0;
      ckpt_sp   <= 0;

      out_valid_q   <= 0;
      rs1_p_q       <= 0;
      rs2_p_q       <= 0;
      rd_new_p_q    <= 0;
      rd_old_p_q    <= 0;
      rob_tag_out_q <= 0;

    end else begin
      
      // ------------------------------------------------------------
      // COMMIT FREES
      // ------------------------------------------------------------
      if (rob_commit_free_valid_i && rob_commit_free_preg_i != 6'd0) begin
         freelist[fl_tail] <= rob_commit_free_preg_i;
         fl_tail <= fl_tail + 1'b1;
         fl_count <= fl_count + 1;
      end

      // ------------------------------------------------------------
      // RECOVERY
      // ------------------------------------------------------------
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
        // ------------------------------------------------------------
        // NORMAL OPERATION
        // ------------------------------------------------------------
        
        // --- Stack Pointer Management (Reset on Empty Hack) ---
        automatic int next_sp = ckpt_sp;
        
        // Safety: If ROB is empty, reset stack.
        // This cleans up leaked checkpoints from the stack.
        if (rob_count_i == 0) begin
           next_sp = 0;
        end 
        
        if (out_valid_q && ren_ready_i)
          out_valid_q <= 0;

        if (accept_decode) begin
          payload_o <= payload_i;

          // Mapping
          // If uninitialized (reset to 0), these return P0 (which is 0). Correct.
          rs1_p_q <= dec_rs1_used_i ? map_table[dec_rs1_i] : '0;
          rs2_p_q <= dec_rs2_used_i ? map_table[dec_rs2_i] : '0;
          
          // Old Dest (Fix: Don't map for branches)
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

          rob_tag_out_q <= rob_tag_q;
          rob_tag_q     <= rob_tag_q + 1;

          // Checkpoint Creation
          if (dec_is_branch_i || dec_is_jump_i) begin
              if (next_sp < N_CHECKPTS) begin
                  map_ckpt[next_sp]      = map_table;
                  fl_head_ckpt[next_sp]  = fl_head;
                  fl_tail_ckpt[next_sp]  = fl_tail;
                  fl_count_ckpt[next_sp] = fl_count;
                  rob_tag_ckpt[next_sp]  = rob_tag_q;
                  
                  next_sp = next_sp + 1;
              end
          end
          
          ckpt_sp <= next_sp;
          out_valid_q <= 1;
        end else begin
          // Even if we don't dispatch, apply the next_sp (handle reset on empty)
          ckpt_sp <= next_sp;
        end
      end
    end
  end

endmodule