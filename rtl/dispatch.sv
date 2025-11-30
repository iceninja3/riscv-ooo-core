module dispatch (
    input logic clk, reset,

    // From Rename Stage
    input logic             rename_valid,
    input dispatch_packet_t rename_pkt,
    output logic            dispatch_ready, // Stop Rename if we are full

    // To ROB
    output logic [3:0]      rob_alloc_id,
    
    // To Execution Units (Just valid signals for now)
    output logic            alu_issue_valid,
    output logic            lsu_issue_valid
);

    // 1. Pipeline Buffer (Skid Buffer)
    logic             skid_valid_out;
    logic             skid_ready_out;
    dispatch_packet_t skid_data_out;

    skid_buffer_struct #(.T(dispatch_packet_t)) dispatch_buffer (
        .clk(clk), .reset(reset),
        .valid_in(rename_valid),
        .data_in(rename_pkt),
        .ready_in(dispatch_ready),      // Output to Rename
        .valid_out(skid_valid_out),     // Internal valid
        .data_out(skid_data_out),       // Internal data
        .ready_out(skid_ready_out)      // We drive this based on stalls
    );

    // 2. ROB Controller
    logic rob_full;
    logic [3:0] rob_tail;
    
    rob_controller rob (
        .clk(clk), .reset(reset),
        .dispatch_en(skid_valid_out && !skid_ready_out), // Alloc when we successfully move data
        .full(rob_full),
        .rob_tail_idx(rob_tail)
        // .commit_en connected later
    );

    // 3. RS Stalls Logic
    logic rs_alu_full, rs_lsu_full, rs_br_full;
    logic current_rs_full;

    // Check which RS the current instruction needs
    always_comb begin
        if (skid_data_out.is_load || skid_data_out.is_store)
            current_rs_full = rs_lsu_full;
        else if (skid_data_out.is_branch)
            current_rs_full = rs_br_full;
        else
            current_rs_full = rs_alu_full;
    end

    // We can accept data from Skid Buffer if ROB isn't full AND target RS isn't full
    assign skid_ready_out = !rob_full && !current_rs_full;

    // 4. Instantiate RS Modules
    // Example: ALU RS
    reservation_station #(.NUM_SLOTS(8)) rs_alu (
        .clk(clk), .reset(reset),
        .write_en(skid_valid_out && !skid_ready_out && !skid_data_out.is_load && !skid_data_out.is_branch),
        .write_data({1'b1, rob_tail, skid_data_out.p_dest, ...}), // Map dispatch pkt to RS entry
        .full(rs_alu_full),
        .issue_valid(alu_issue_valid)
        // ... connect other ports
    );

    // Instantiate rs_lsu and rs_branch similarly...

endmodule