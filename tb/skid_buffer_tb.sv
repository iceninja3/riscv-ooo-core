`timescale 1ns/1ps

module skid_buffer_tb;

    parameter T_CLK = 10; // Clock period: 10 ns (100 MHz)
    parameter DATA_WIDTH = 8;
    typedef logic [DATA_WIDTH-1:0] T;


    logic clk;
    logic reset;
    logic valid_in;
    logic ready_in; // Wire to observe DUT output
    T     data_in;
    logic valid_out; // Wire to observe DUT output
    logic ready_out;
    T     data_out;  // Wire to observe DUT output

    skid_buffer_struct #(
        .T(T)
    ) dut (
        .clk(clk),
        .reset(reset),
        .valid_in(valid_in),
        .ready_in(ready_in),
        .data_in(data_in),
        .valid_out(valid_out),
        .ready_out(ready_out),
        .data_out(data_out)
    );

    initial begin
        clk = 0;
        forever #(T_CLK/2) clk = ~clk;
    end

    initial begin
        reset = 1;
        repeat(2) @(posedge clk);
        reset = 0;
    end


    initial begin
        // driving signals
        valid_in  = 0;
        ready_out = 0;
        data_in   = '0;

        // Wait for reset to finish
        @(negedge reset);
        @(posedge clk);

        $display("--------------------------------------------------");
        $display("SCENARIO 1: Ideal throughput (consumer is always ready)");
        $display("--------------------------------------------------");
        ready_out <= 1; // Consumer is always ready
        for (int i = 0; i < 3; i++) begin
            send_data($random);
        end
        
        // Let the last piece of data drain
        valid_in <= 0;
        @(posedge clk);
        @(posedge clk);

        $display("\n--------------------------------------------------");
        $display("SCENARIO 2: Consumer stalls, buffer should fill up");
        $display("--------------------------------------------------");
        ready_out <= 1;
        send_data(8'hAA); // Send one item successfully

        // Now, consumer stalls
        ready_out <= 0;
        $display("@%0t: Consumer STALLS (ready_out=0)", $time);

        send_data(8'hBB); // Send a second item, this one should get stuck in the buffer
        valid_in <= 0;
        // At this point, ready_in should go low because the buffer is full.

        repeat(3) @(posedge clk);

        $display("\n--------------------------------------------------");
        $display("SCENARIO 3: Consumer unstalls, buffer should drain");
        $display("--------------------------------------------------");
        ready_out <= 1; // Consumer is ready again
        $display("@%0t: Consumer UNSTALLS (ready_out=1)", $time);

        // Wait for the buffer to drain and become ready again
        wait (ready_in == 1);
        $display("@%0t: Buffer is ready again (ready_in=1)", $time);
        
        send_data(8'hCC); // Send a final piece of data
        valid_in <= 0;
        
        repeat(5) @(posedge clk);
        $display("\nSimulation finished.");
        $finish;
    end
    
    
    task send_data(input T data);
        @(posedge clk);
        valid_in <= 1;
        data_in  <= data;
        $display("@%0t: Producer sends data 0x%h", $time, data);
        wait (ready_in == 1); // Wait until the buffer is ready
        @(posedge clk); // Hold for one cycle for the transfer
        valid_in <= 0;
    endtask


    initial begin
        $monitor("@%0t: [PRODUCER] valid_in=%b, ready_in=%b, data_in=0x%h | [CONSUMER] valid_out=%b, ready_out=%b, data_out=0x%h",
                 $time, valid_in, ready_in, data_in, valid_out, ready_out, data_out);
    end

endmodule


/*
module tb_skid_buffer;

    // -------------------------------------------------------------------------
    // Parameters and Types
    // -------------------------------------------------------------------------
    parameter type T = logic [7:0]; // Testing with an 8-bit vector
    
    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    logic clk;
    logic reset;

    // Upstream (Driver)
    logic valid_in;
    logic ready_in;
    T     data_in;

    // Downstream (Consumer)
    logic valid_out;
    logic ready_out;
    T     data_out;

    // Simulation variables
    int error_count = 0;
    T expected_queue[$]; // Queue to act as the golden reference

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    skid_buffer_struct #(
        .T(T)
    ) dut (
        .clk(clk),
        .reset(reset),
        .valid_in(valid_in),
        .ready_in(ready_in),
        .data_in(data_in),
        .valid_out(valid_out),
        .ready_out(ready_out),
        .data_out(data_out)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // -------------------------------------------------------------------------
    // Scoreboard / Monitor
    // -------------------------------------------------------------------------
    // This block tracks data entering and leaving the DUT to ensure integrity.
    always_ff @(posedge clk) begin
        if (!reset) begin
            
            // Monitor INPUT: If a handshake happens, add to expected queue
            if (valid_in && ready_in) begin
                expected_queue.push_back(data_in);
            end

            // Monitor OUTPUT: If a handshake happens, check against queue
            if (valid_out && ready_out) begin
                if (expected_queue.size() == 0) begin
                    $error("Time %0t: Error! DUT output valid data, but scoreboard is empty.", $time);
                    error_count++;
                end else begin
                    T expected_data;
                    expected_data = expected_queue.pop_front();
                    
                    if (data_out !== expected_data) begin
                        $error("Time %0t: Mismatch! Expected: 0x%0h, Got: 0x%0h", 
                               $time, expected_data, data_out);
                        error_count++;
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    
    // Reset routine
    task do_reset();
        valid_in = 0;
        data_in = 0;
        ready_out = 0;
        reset = 1;
        repeat(2) @(posedge clk);
        reset = 0;
        @(posedge clk); 
    endtask

    // Drive single item
    task send_single(input T data);
        valid_in = 1;
        data_in = data;
        wait(ready_in); // Wait for DUT to accept
        @(posedge clk);
        valid_in = 0;
    endtask

    // -------------------------------------------------------------------------
    // Main Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $display("Starting Testbench...");
        
        // Initialize Inputs
        valid_in = 0;
        ready_out = 0;
        data_in = 0;
        
        // 1. Reset Test
        do_reset();
        assert(valid_out == 0) else $error("Reset failed: valid_out should be 0");
        assert(ready_in == 1) else $error("Reset failed: ready_in should be 1 (empty)");

        // 2. Single Transaction (No Backpressure)
        $display("Test: Single Transaction");
        ready_out = 1; // Consumer is ready
        send_single(8'hA1);
        @(posedge clk);
        // Wait for queue to empty in scoreboard
        wait(expected_queue.size() == 0);

        // 3. Backpressure Test (Fill the buffer)
        $display("Test: Backpressure (Fill Buffer)");
        do_reset();
        ready_out = 0; // Consumer is STALLED
        
        // Send data. The buffer has 1 register.
        // It should accept the first one (into internal register)
        // It should NOT accept the second one until ready_out goes high.
        
        valid_in = 1; data_in = 8'hB1;
        @(posedge clk); // Accepted into reg
        
        valid_in = 1; data_in = 8'hB2;
        @(posedge clk); // Should stall here because occupied_ff is 1 and ready_out is 0
        
        // Check hardware state
        if (ready_in == 1) $error("Error: DUT should be busy (ready_in=0) when full and stalled.");
        
        // Release backpressure
        ready_out = 1;
        @(posedge clk); // B2 accepted now
        valid_in = 0;
        @(posedge clk);
        wait(expected_queue.size() == 0);


        // 4. Full Throughput Streaming
        // In a skid buffer, if ready_out is 1, ready_in should stay 1 
        // effectively passing data straight through (registered).
        $display("Test: Full Throughput Stream");
        do_reset();
        ready_out = 1;
        valid_in = 1;
        
        for (int i = 0; i < 10; i++) begin
            data_in = i;
            // In a perfectly pipelined system, ready_in should NEVER drop 
            // as long as ready_out is high.
            if (ready_in == 0) $error("Error: Throughput drop! ready_in dropped during stream.");
            @(posedge clk);
        end
        
        valid_in = 0;
        repeat(5) @(posedge clk); // Let drain

        // 5. Randomized Fuzzing
        $display("Test: Randomized Fuzzing");
        do_reset();
        repeat(200) begin
            // Randomize inputs
            valid_in <= $urandom_range(0, 100) < 60; // 60% chance of data
            data_in  <= $random;
            ready_out <= $urandom_range(0, 100) < 50; // 50% chance of ready
            @(posedge clk);
        end

        // Drain remainder
        valid_in = 0;
        ready_out = 1;
        repeat(5) @(posedge clk);

        // Final Report
        if (error_count == 0 && expected_queue.size() == 0)
            $display("Test PASSED: All checks successful.");
        else
            $display("Test FAILED: %0d errors, %0d items left in queue.", error_count, expected_queue.size());

        $finish;
    end

endmodule
*/