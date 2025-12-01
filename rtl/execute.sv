module execute #(
    parameter int DATA_WIDTH = 32,
    parameter int DMEM_AW    = 10,  // data mem address width (words)
    parameter int ROB_TAG_W  = 6
)(
    input  logic                      clk,
    input  logic                      rst,

    // From Dispatch / Issue Stage
    input  logic                      ex_valid_i,
    output logic                      ex_ready_o,

    input  logic [31:0]               pc_i,
    input  logic [31:0]               imm_i,

    input  logic                      ALUSrc_i,
    input  logic [2:0]                ALUOp_i,
    input  logic                      branch_i,
    input  logic                      jump_i,
    input  logic                      MemRead_i,   // loads only
    input  logic                      RegWrite_i,
    input  logic                      MemToReg_i,

    // Operand *values* already read from physical regfile
    input  logic [DATA_WIDTH-1:0]     rs1_val_i,
    input  logic [DATA_WIDTH-1:0]     rs2_val_i,

    // Dest physical register + ROB tag
    input  logic [5:0]                rd_p_i,      // adjust width if N_PHYS != 64
    input  logic [ROB_TAG_W-1:0]      rob_tag_i,

    // Flush from later stages (for now just kills in-flight op)
    input  logic                      flush_i,

    // To WB / ROB
    output logic                      ex_valid_o,
    input  logic                      ex_ready_i,

    output logic [DATA_WIDTH-1:0]     result_o,
    output logic [5:0]                rd_p_o,      // same width as rd_p_i
    output logic [ROB_TAG_W-1:0]      rob_tag_o,
    output logic                      RegWrite_o,
    output logic                      MemToReg_o,

    // Branch unit outputs
    output logic                      br_resolved_o,   // 1 when branch outcome valid
    output logic                      br_taken_o,
    output logic [31:0]               br_target_o,
    output logic                      br_mispredict_o  // placeholder for phase 4
);

    // -------------------------------------------------------
    // Data memory (loads only) — BRAM with 2-cycle latency
    // -------------------------------------------------------
    logic [DMEM_AW-1:0] dmem_addr;
    logic [DATA_WIDTH-1:0] dmem_rdata;

    // 2-cycle-load BRAM
    logic [DMEM_AW-1:0] addr_r1;
    logic [DATA_WIDTH-1:0] data_r1;
    logic [DATA_WIDTH-1:0] data_r2;

    // actual BRAM
    logic [DATA_WIDTH-1:0] dmem [0:(1<<DMEM_AW)-1];

    // simple pipelined 2-cycle read
    always_ff @(posedge clk) begin
        if (MemRead_i && ex_valid_i) begin
            addr_r1 <= dmem_addr;               // cycle 0: capture addr
        end
        data_r1 <= dmem[addr_r1];               // cycle 1: BRAM read
        data_r2 <= data_r1;                     // cycle 2: registered output
    end

    assign dmem_rdata = data_r2;

    // -------------------------------------------------------
    // Internal pipeline state
    // -------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE,
        S_ALU_DONE,   // normal ALU/branch result ready
        S_LOAD_WAIT1, // waiting for BRAM stage 1
        S_LOAD_WAIT2  // waiting for BRAM stage 2 (data ready)
    } ex_state_e;

    ex_state_e               state_q, state_d;

    // Latched info to survive multi-cycle load
    logic [DATA_WIDTH-1:0]   alu_result_q;
    logic [31:0]             pc_q, imm_q;
    logic                    branch_q, jump_q;
    logic                    MemRead_q;
    logic                    RegWrite_q, MemToReg_q;
    logic [5:0]              rd_p_q;
    logic [ROB_TAG_W-1:0]    rob_tag_q;
    logic [DATA_WIDTH-1:0]   rs1_val_q, rs2_val_q;

    // -------------------------------------------------------
    // ALU operand select and operation (combinational)
    // -------------------------------------------------------
    logic [DATA_WIDTH-1:0] op1, op2, alu_result_c;

    assign op1 = rs1_val_i;
    assign op2 = ALUSrc_i ? imm_i : rs2_val_i;

    always_comb begin
        unique case (ALUOp_i)
            3'b000: alu_result_c = op1 + op2;    // e.g., ADD / address gen
            3'b001: alu_result_c = op1 - op2;    // SUB
            3'b010: alu_result_c = op1 & op2;    // AND
            3'b011: alu_result_c = op1 | op2;    // OR
            3'b100: alu_result_c = op1 ^ op2;    // XOR
            default: alu_result_c = '0;
        endcase
    end

    // Address generation for loads (word address from ALU result)
    assign dmem_addr = alu_result_q[DMEM_AW+1:2]; // drop bottom 2 bits

    // Branch outcome and target (e.g., BNE)
    logic        br_taken_c;
    logic [31:0] br_target_c;

    assign br_taken_c  = branch_i ? (rs1_val_i != rs2_val_i) : 1'b0;
    assign br_target_c = pc_i + imm_i;

    // -------------------------------------------------------
    // Ready/valid
    // -------------------------------------------------------
    assign ex_ready_o = (state_q == S_IDLE) ||
                        ((state_q == S_ALU_DONE) && ex_ready_i);

    assign ex_valid_o = (state_q == S_ALU_DONE) ||
                        (state_q == S_LOAD_WAIT2);

    // Result mux
    assign result_o = (state_q == S_LOAD_WAIT2) ? dmem_rdata
                                                : alu_result_q;

    assign rd_p_o     = rd_p_q;
    assign rob_tag_o  = rob_tag_q;
    assign RegWrite_o = RegWrite_q;
    assign MemToReg_o = MemToReg_q;

    // Branch outputs: resolved when ALU/branch completes
    assign br_resolved_o   = (state_q == S_ALU_DONE) && branch_q;
    assign br_taken_o      = br_taken_c;      // recomputed
    assign br_target_o     = br_target_c;
    assign br_mispredict_o = 1'b0;           // hook up later

    always_ff @(posedge clk) begin
        if (rst || flush_i) begin
            state_q      <= S_IDLE;
            alu_result_q <= '0;
            pc_q         <= '0;
            imm_q        <= '0;
            branch_q     <= 1'b0;
            jump_q       <= 1'b0;
            MemRead_q    <= 1'b0;
            RegWrite_q   <= 1'b0;
            MemToReg_q   <= 1'b0;
            rd_p_q       <= '0;
            rob_tag_q    <= '0;
            rs1_val_q    <= '0;
            rs2_val_q    <= '0;
        end else begin
            state_q <= state_d;

            // latch new instruction when accepted
            if (ex_valid_i && ex_ready_o) begin
                alu_result_q <= alu_result_c;
                pc_q         <= pc_i;
                imm_q        <= imm_i;
                branch_q     <= branch_i;
                jump_q       <= jump_i;
                MemRead_q    <= MemRead_i;
                RegWrite_q   <= RegWrite_i;
                MemToReg_q   <= MemToReg_i;
                rd_p_q       <= rd_p_i;
                rob_tag_q    <= rob_tag_i;
                rs1_val_q    <= rs1_val_i;
                rs2_val_q    <= rs2_val_i;
            end
        end
    end

    // next-state logic
    always_comb begin
        state_d = state_q;

        unique case (state_q)
            S_IDLE: begin
                if (ex_valid_i && ex_ready_o) begin
                    if (MemRead_i)
                        state_d = S_LOAD_WAIT1;
                    else
                        state_d = S_ALU_DONE;
                end
            end

            S_ALU_DONE: begin
                if (ex_ready_i)
                    state_d = S_IDLE;
            end

            S_LOAD_WAIT1: begin
                state_d = S_LOAD_WAIT2;
            end

            S_LOAD_WAIT2: begin
                if (ex_ready_i)
                    state_d = S_IDLE;
            end

            default: state_d = S_IDLE;
        endcase
    end

endmodule
