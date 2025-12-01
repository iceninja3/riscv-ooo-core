module tb_rob;
    import common_pkg::*;
    
    logic clk, reset;
    logic dispatch_en, full, complete_en, commit_valid, branch_mispredict;
    logic [3:0] alloc_id, complete_id, commit_id, recovery_idx;

    rob #(.DEPTH(4)) dut (.*); // Small depth for easier testing

    always #5 clk = ~clk;

    initial begin
        clk = 0; reset = 1;
        dispatch_en = 0; complete_en = 0; branch_mispredict = 0;
        #20 reset = 0;

        // Test 1: Fill the ROB
        $display("Testing Fill...");
        for(int i=0; i<4; i++) begin
            dispatch_en = 1;
            #10;
        end
        dispatch_en = 0;
        
        if (full) $display("SUCCESS: ROB is full.");
        else      $error("FAIL: ROB should be full.");

        // Test 2: Complete oldest (Index 0)
        $display("Testing Complete...");
        complete_en = 1; complete_id = 0;
        #10 complete_en = 0;

        // Test 3: Commit
        #1; // Wait for logic
        if (commit_valid && commit_id == 0) $display("SUCCESS: Committing ID 0");
        else $error("FAIL: Should commit ID 0");
        #10; // Clock edge processes commit

        // Test 4: Recovery
        // Assume we allocated a few more, then mispredicted at ID 1
        reset = 1; #10 reset = 0;
        dispatch_en = 1; #10; // ID 0
        dispatch_en = 1; #10; // ID 1 (Branch)
        dispatch_en = 1; #10; // ID 2 (Trash)
        dispatch_en = 0;
        
        $display("Testing Recovery...");
        branch_mispredict = 1; recovery_idx = 1;
        #10 branch_mispredict = 0;
        
        // Next alloc should be ID 2 again (overwriting trash)
        dispatch_en = 1; 
        #10;
        if (alloc_id == 2) $display("SUCCESS: Recovery reset pointer correctly.");
        else $error("FAIL: Recovery pointer wrong. Got %d", alloc_id);

        $finish;
    end
endmodule