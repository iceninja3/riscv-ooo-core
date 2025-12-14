module reservation_station #(
    parameter NUM_SLOTS = 8,
    parameter N_PHYS    = 64
)(
    input logic clk, reset,

    input logic  write_en,
    input pipeline_types::rs_issue_packet_t write_data,

    input logic  src1_already_ready_i,
    input logic  src2_already_ready_i,

    output logic full,

    input logic       cdb_valid,
    input logic [5:0] cdb_tag,

    input  logic      issue_ready,
    output logic      issue_valid,
    output pipeline_types::rs_entry_t issue_data
);
    import pipeline_types::*;

    rs_entry_t slots [NUM_SLOTS-1:0];
    logic [NUM_SLOTS-1:0] slots_valid;
    logic [NUM_SLOTS-1:0] slots_runnable;

    logic [$clog2(NUM_SLOTS)-1:0] free_idx;
    logic any_free;

    logic [$clog2(NUM_SLOTS)-1:0] issue_idx;

    priority_decoder #(.WIDTH(NUM_SLOTS)) alloc_decoder (
        .in(~slots_valid),
        .out(free_idx),
        .valid(any_free)
    );
    assign full = ~any_free;

    always_ff @(posedge clk) begin
        if (reset) begin
            slots_valid <= '0;
            for (int i=0; i<NUM_SLOTS; i++) begin
                slots[i] <= '0;
            end
        end else begin
            // Allocation
            if (write_en && !full) begin
                slots_valid[free_idx] <= 1'b1;

                // *** CRITICAL: clear whole slot first ***
                slots[free_idx] <= '0;

                // Copy fields
                slots[free_idx].pc      <= write_data.pc;
                slots[free_idx].imm     <= write_data.imm;
                slots[free_idx].alu_op  <= write_data.alu_op;
                slots[free_idx].alu_src <= write_data.alu_src;
                slots[free_idx].mem_read  <= write_data.mem_read;
                slots[free_idx].mem_write <= write_data.mem_write;
                slots[free_idx].funct3    <= write_data.funct3;

                slots[free_idx].p_src1  <= write_data.rs1_p;
                slots[free_idx].p_src2  <= write_data.rs2_p;
                slots[free_idx].p_dst   <= write_data.rd_p;
                slots[free_idx].rob_tag <= write_data.rob_tag;

                slots[free_idx].is_branch <= write_data.is_branch;
                slots[free_idx].is_jump   <= write_data.is_jump;

                // Ready init ONLY from top-level “already-ready” (+ same-cycle CDB)
                slots[free_idx].src1_ready <= src1_already_ready_i ||
                                             (cdb_valid && (cdb_tag == write_data.rs1_p));

                slots[free_idx].src2_ready <= src2_already_ready_i ||
                                             (cdb_valid && (cdb_tag == write_data.rs2_p));
            end

            // Wakeup
            for (int i = 0; i < NUM_SLOTS; i++) begin
                if (slots_valid[i]) begin
                    if (cdb_valid && (slots[i].p_src1 == cdb_tag))
                        slots[i].src1_ready <= 1'b1;
                    if (cdb_valid && (slots[i].p_src2 == cdb_tag))
                        slots[i].src2_ready <= 1'b1;
                end
            end

            // Issue clear
            if (issue_valid && issue_ready) begin
                slots_valid[issue_idx] <= 1'b0;
            end
        end
    end

    always_comb begin
        for (int i=0; i<NUM_SLOTS; i++) begin
            slots_runnable[i] = slots_valid[i] && slots[i].src1_ready && slots[i].src2_ready;
        end
    end

    priority_decoder #(.WIDTH(NUM_SLOTS)) issue_decoder (
        .in(slots_runnable),
        .out(issue_idx),
        .valid(issue_valid)
    );

    // *** CRITICAL: mask issue_data when not valid ***
    always_comb begin
        issue_data = '0;
        if (issue_valid) issue_data = slots[issue_idx];
    end

endmodule