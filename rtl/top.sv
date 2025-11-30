module top #(
    parameter int ADDR_WIDTH = 9,
    parameter int DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic reset,

    output logic        fe_valid_o,
    input  logic        fe_ready_i,

    // PC going into next stage
    output logic [31:0] fe_pc_o,

    // decoded outputs to rename
    output logic [4:0]  fe_rs1_o,
    output logic [4:0]  fe_rs2_o,
    output logic [4:0]  fe_rd_o,
    output logic [31:0] fe_imm_o,
    output logic        fe_ALUSrc_o,
    output logic [2:0]  fe_ALUOp_o,
    output logic        fe_branch_o,
    output logic        fe_jump_o,
    output logic        fe_MemRead_o,
    output logic        fe_MemWrite_o,
    output logic        fe_RegWrite_o,
    output logic        fe_MemToReg_o
);


    logic [ADDR_WIDTH-1:0] icache_addr;
    logic [DATA_WIDTH-1:0] icache_rdata;
    logic        fetch_valid;
    logic        fetch_ready;
    logic [31:0] fetch_pc;
    logic [31:0] fetch_inst;

    fetch_dec_t  fetch_data_in;
    fetch_dec_t  fetch_data_out;

    assign fetch_data_in.pc   = fetch_pc;
    assign fetch_data_in.inst = fetch_inst;

    logic dec_valid;
    logic dec_ready;
    assign dec_ready = fe_ready_i;  


    iCache #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_icache (
        .clk   (clk),
        .addr  (icache_addr),
        .rdata (icache_rdata)
    );


    Fetch #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .RESET_PC   (32'h0000_0000)
    ) u_fetch (
        .clk          (clk),
        .reset        (reset),

        .icache_addr  (icache_addr),
        .icache_rdata (icache_rdata),

        .valid_o      (fetch_valid),
        .ready_i      (fetch_ready),
        .pc_o         (fetch_pc),
        .inst_o       (fetch_inst)
    );

    // skid buffer between fetch and decode
    skid_buffer_struct #(
        .T(fetch_dec_t)
    ) u_skid_fd (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (fetch_valid),
        .ready_in  (fetch_ready),
        .data_in   (fetch_data_in),
        .valid_out (dec_valid),
        .ready_out (dec_ready),
        .data_out  (fetch_data_out)
    );

    logic [4:0]  rs1, rs2, rd;
    logic [31:0] imm;
    logic        ALUSrc;
    logic [2:0]  ALUOp;
    logic        branch, jump;
    logic        MemRead, MemWrite;
    logic        RegWrite, MemToReg;

    decode u_decode (
        .inst     (fetch_data_out.inst),

        .rs1      (rs1),
        .rs2      (rs2),
        .rd       (rd),
        .imm      (imm),

        .ALUSrc   (ALUSrc),
        .ALUOp    (ALUOp),
        .branch   (branch),
        .jump     (jump),
        .MemRead  (MemRead),
        .MemWrite (MemWrite),
        .RegWrite (RegWrite),
        .MemToReg (MemToReg)
    );

    //output to rename 
    assign fe_valid_o   = dec_valid;       
    assign fe_pc_o      = fetch_data_out.pc;

    assign fe_rs1_o     = rs1;
    assign fe_rs2_o     = rs2;
    assign fe_rd_o      = rd;
    assign fe_imm_o     = imm;
    assign fe_ALUSrc_o  = ALUSrc;
    assign fe_ALUOp_o   = ALUOp;
    assign fe_branch_o  = branch;
    assign fe_jump_o    = jump;
    assign fe_MemRead_o = MemRead;
    assign fe_MemWrite_o= MemWrite;
    assign fe_RegWrite_o= RegWrite;
    assign fe_MemToReg_o= MemToReg;

endmodule
