`include "pipeline_types.sv"

import pipeline_types::*;

`timescale 1ns / 1ps
import pipeline_types::*;

module alu_unit #(
    parameter ROB_TAG_W = 4
)(
    input  logic                  clk,
    input  logic                  rst,

    input  logic                  valid_i,
    input  logic [2:0]            alu_op_i,
    input  logic [31:0]           op1_i,
    input  logic [31:0]           op2_i,
    input  logic [5:0]            rd_p_i,
    input  logic [ROB_TAG_W-1:0]  rob_tag_i,

    input  logic                  ready_i,

    output logic                  valid_o,
    output logic [31:0]           result_o,
    output logic [5:0]            rd_p_o,
    output logic [ROB_TAG_W-1:0]  rob_tag_o
);

    logic [31:0] result_comb;
    always_comb begin
        unique case (alu_op_i)
            ALU_ADD:  result_comb = op1_i + op2_i;
            ALU_SUB:  result_comb = op1_i - op2_i;
            ALU_AND:  result_comb = op1_i & op2_i;
            ALU_OR:   result_comb = op1_i | op2_i;
            ALU_XOR:  result_comb = op1_i ^ op2_i;
            ALU_SRA:  result_comb = $signed(op1_i) >>> op2_i[4:0];
            ALU_SLTU: result_comb = (op1_i < op2_i) ? 32'd1 : 32'd0;
            default:  result_comb = '0;
        endcase
    end

    logic        buff_valid;
    logic [31:0] buff_result;
    logic [5:0]  buff_rd_p;
    logic [ROB_TAG_W-1:0] buff_rob_tag;

    always_ff @(posedge clk) begin
        if (rst) begin
            buff_valid <= 1'b0;
            buff_result <= '0;
            buff_rd_p <= '0;
            buff_rob_tag <= '0;
        end else begin
            if (valid_i) begin
                buff_valid   <= 1'b1;
                buff_result  <= result_comb;
                buff_rd_p    <= rd_p_i;
                buff_rob_tag <= rob_tag_i;

            end
            else if (ready_i) begin
                buff_valid <= 1'b0;
            end
        end
    end

    assign valid_o   = buff_valid;
    assign result_o  = buff_result;
    assign rd_p_o    = buff_rd_p;
    assign rob_tag_o = buff_rob_tag;



endmodule