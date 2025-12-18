module btb (
    input  logic        clk,
    input  logic        rst,
    // Fetch Stage: Prediction logic
    input  logic [31:0] fetch_pc_i,
    output logic        pred_taken_o,
    output logic [31:0] pred_target_o,
    output logic        btb_hit_o,
    // Writeback Stage: Update logic
    input  logic        update_en_i,
    input  logic [31:0] update_pc_i,
    input  logic [31:0] update_target_i,
    input  logic        update_actual_taken_i
);
    typedef struct packed {
        logic        valid;
        logic [31:0] tag;
        logic [31:0] target;
        logic [1:0]  bht; // 00: Strong NT, 01: Weak NT, 10: Weak T, 11: Strong T
    } btb_entry_t;

    btb_entry_t entries [7:0];

    // PREDICTION (Combinational)
    always_comb begin
        pred_taken_o  = 1'b0;
        pred_target_o = 32'h0;
        btb_hit_o     = 1'b0;
        for (int i = 0; i < 8; i++) begin
            if (entries[i].valid && (entries[i].tag == fetch_pc_i)) begin
                btb_hit_o     = 1'b1;
                pred_target_o = entries[i].target;
                pred_taken_o  = entries[i].bht[1]; // Predict taken if MSB is 1
                break;
            end
        end
    end

    // UPDATE (Sequential)
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 8; i++) entries[i].valid <= 1'b0;
        end else if (update_en_i) begin
            bit found; found = 1'b0;
            for (int i = 0; i < 8; i++) begin
                if (entries[i].valid && (entries[i].tag == update_pc_i)) begin
                    found = 1'b1;
                    entries[i].target <= update_target_i;
                    if (update_actual_taken_i && entries[i].bht != 2'b11) entries[i].bht <= entries[i].bht + 1;
                    else if (!update_actual_taken_i && entries[i].bht != 2'b00) entries[i].bht <= entries[i].bht - 1;
                end
            end
            if (!found) begin // Simple index replacement
                automatic int idx = update_pc_i[5:3]; 
                entries[idx].valid <= 1'b1;
                entries[idx].tag   <= update_pc_i;
                entries[idx].target <= update_target_i;
                entries[idx].bht    <= update_actual_taken_i ? 2'b10 : 2'b01;
            end
        end
    end
endmodule