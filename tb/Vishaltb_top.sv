`timescale 1ns / 1ps

module tb_top;

    // 1. Declare signals to drive the top module
    logic clk;
    logic rst;

    // 2. Instantiate the Design Top
    cpu_top uut (
        .clk(clk),
        .rst(rst)
    );

    // 3. Clock Generation (10ns period -> 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 4. Test Sequence
    initial begin
        // A. Reset the system
        rst = 1;
        repeat(5) @(posedge clk); // Hold reset for 5 cycles
        rst = 0;
        
        // B. Let it run
        // The Fetch module should start requesting instructions.
        // The Decode should decode them.
        // The Rename should map registers.
        // The Dispatch should fill the ROB.
        
        repeat(50) @(posedge clk);
        
        // C. Stop
        $finish;
    end

endmodule