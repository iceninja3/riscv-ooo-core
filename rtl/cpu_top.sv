`timescale 1ns / 1ps


module cpu_top (
    input logic clk,
    input logic rst
);
    import cpu_types_pkg::*;

    // ... (Fetch, Decode, Rename, Dispatch signals from previous step) ...
    
    // ISSUE SIGNALS (From RS to Execution)
    logic             alu_issue_valid;
    dispatch_packet_t alu_issue_pkt;
    logic             alu_ready;
    logic [31:0]      prf_rdata1, prf_rdata2;

    // CDB SIGNALS (From Execution to WB/RS/ROB)
    cdb_t cdb;

    // COMMIT SIGNALS (From ROB to Rename)
    logic       rob_commit_valid;
    logic [5:0] rob_commit_free_preg;

    // ... (Instantiate Fetch, Decode, Rename as before) ...

    // Note regarding Rename: Connect the commit signals now!
    // Rename rename_inst (
    //     ...
    //     .rob_commit_free_valid_i(rob_commit_valid), // NON-BLOCKING connection
    //     .rob_commit_free_preg_i(rob_commit_free_preg),
    //     ...
    // );


    // ==========================================
    // DISPATCH
    // ==========================================
    // We pass the CDB into Dispatch so it can reach the RS modules for Wakeup
    dispatch dispatch_inst (
        .clk(clk),
        .rst(rst),
        .rename_valid_i(ren_valid_out),
        .rename_ready_o(disp_ready_from_dispatch),
        .rename_pkt_i(dispatch_pkt),
        
        // CDB BROADCAST (Wakeup Logic)
        .cdb_valid_i(cdb.valid),
        .cdb_tag_i(cdb.tag),
        
        // Issue Interface
        .alu_issue_valid_o(alu_issue_valid),
        .alu_issue_pkt_o(alu_issue_pkt),
        .alu_ready_i(alu_ready) 
    );

    // ==========================================
    // PHYSICAL REGISTER FILE (Read-After-Issue)
    // ==========================================
    physical_regfile PRF (
        .clk(clk),
        // Write Port (Writeback Stage)
        .we(cdb.valid),
        .waddr(cdb.tag),
        .wdata(cdb.data),
        
        // Read Ports (Issue Stage)
        .raddr1(alu_issue_pkt.rs1_phys),
        .rdata1(prf_rdata1),
        .raddr2(alu_issue_pkt.rs2_phys),
        .rdata2(prf_rdata2)
    );

    // ==========================================
    // EXECUTION STAGE
    // ==========================================
    alu_exec ALU (
        .clk(clk),
        .rst(rst),
        .valid_i(alu_issue_valid),
        .pkt_i(alu_issue_pkt),
        .rs1_data_i(prf_rdata1),
        .rs2_data_i(prf_rdata2),
        .cdb_o(cdb),      // Output to Common Data Bus
        .ready_o(alu_ready)
    );

    // ==========================================
    // ROB (Tracking Writeback & Commit)
    // ==========================================
    rob #(.ROB_DEPTH(16)) ROB (
        .clk(clk),
        .rst(rst),
        .alloc_valid_i(ren_valid_out && disp_ready_from_dispatch), // Simplified alloc logic
        .alloc_pkt_i(dispatch_pkt),
        .full_o(), // Connected inside Dispatch logic usually
        
        // Writeback: Mark complete
        .cdb_i(cdb), 
        
        // Commit: Release resources
        .commit_valid_o(rob_commit_valid),
        .commit_free_preg_o(rob_commit_free_preg),
        .commit_new_preg_o(),
        .commit_lreg_o()
    );

endmodule