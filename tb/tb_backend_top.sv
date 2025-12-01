//this file is a testbench for the integrated 

module tb_backend_top;
    import common_pkg::*;

    logic clk, reset;
    
    // Inputs
    logic rename_valid;
    dispatch_packet_t rename_pkt;
    logic             alu_ex_ready;
    cdb_t             cdb_in;

    // Outputs
    logic             dispatch_ready;
    logic [31:0]      alu_op_a, alu_op_b;
    logic [6:0]       alu_opcode;

    // Instance
    backend_top dut (.*);

    always #5 clk = ~clk;

    initial begin
        clk = 0; reset = 1;
        rename_valid = 0; rename_pkt = '0;
        alu_ex_ready = 1; cdb_in = '0;
        #20 reset = 0;

        // --- Setup PRF with some data ---
        // We will "cheat" and write to PRF using the CDB port 
        // to pretend P1=10, P2=20 exist.
        cdb_in.valid = 1; cdb_in.tag = 1; cdb_in.data = 32'd10; #10;
        cdb_in.valid = 1; cdb_in.tag = 2; cdb_in.data = 32'd20; #10;
        cdb_in.valid = 0;

        // --- Scenario 1: Dispatch an ADD instruction (P3 = P1 + P2) ---
        $display("Dispatching ADD P3 = P1 + P2...");
        rename_valid = 1;
        rename_pkt.pc = 32'h1000;
        rename_pkt.p_dest = 3;
        rename_pkt.p_src1 = 1; rename_pkt.src1_valid = 1;
        rename_pkt.p_src2 = 2; rename_pkt.src2_valid = 1;
        rename_pkt.is_alu = 1;
        rename_pkt.opcode = 7'b0110011; // R-Type
        
        #10; 
        rename_valid = 0; // Single pulse

        // Wait for Issue
        wait (alu_opcode == 7'b0110011);
        $display("Issued! Op A: %d, Op B: %d", alu_op_a, alu_op_b);
        
        if (alu_op_a == 10 && alu_op_b == 20) $display("SUCCESS: Correct operands read from PRF.");
        else $error("FAIL: PRF read mismatch.");

        // --- Scenario 2: Dispatch Dependent Instr (P4 = P3 + P1) ---
        // P3 is not ready yet! It is currently "executing".
        $display("Dispatching Dependent ADD P4 = P3 + P1...");
        rename_valid = 1;
        rename_pkt.p_dest = 4;
        rename_pkt.p_src1 = 3; // Dependent on previous result
        rename_pkt.p_src2 = 1;
        #10 rename_valid = 0;

        // We expect it to NOT issue yet because P3 is busy.
        #20;
        
        // Now, broadcast P3 on CDB (Result of first ADD)
        $display("Broadcasting P3 = 30 on CDB...");
        cdb_in.valid = 1; cdb_in.tag = 3; cdb_in.data = 32'd30;
        #10 cdb_in.valid = 0;

        // Now it should issue
        #10;
        $display("Checking for Dependent Issue...");
        if (alu_op_a == 30) $display("SUCCESS: Dependent instruction picked up forwarded data.");
        else $error("FAIL: Did not get forwarded data. Got %d", alu_op_a);

        $finish;
    end
endmodule