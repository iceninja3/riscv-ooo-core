module skid_buffer_struct #(
    parameter int WIDTH = 32
) (
    input logic clk,
    input logic reset,

    // upstream (producer -> skid)
    input logic valid_in,
    output logic ready_in,
    input logic [WIDTH-1:0]     data_in,

    // downstream (skid -> consumer)
    output logic valid_out,
    input logic ready_out,
    output logic [WIDTH-1:0]     data_out
);

typedef logic [WIDTH-1:0] T;
    // Internal state registers
    logic occupied_ff; // Tracks if our buffer slot is full. 1'b0 = empty, 1'b1 = full.
    T     data_reg;    // The register to store the data.

    // A transfer happens from producer to us (we accept data) when the producer has valid
    // data AND we are ready for it.
    logic upstream_transfer;
    assign upstream_transfer = valid_in && ready_in;

    // A transfer happens from us to the consumer when we have valid data AND the consumer
    // is ready for it.
    logic downstream_transfer;
    assign downstream_transfer = valid_out && ready_out;


    // combinational logic blocks

    // 1. We are ready to accept new data if we are currently empty, OR if we are full
    //    but the data is about to be drained by the consumer in this same cycle.
    //    This allows for a full throughput of 1 transaction/cycle.
    assign ready_in = !occupied_ff || downstream_transfer;

    // 2. Our output data is valid if our internal register is occupied.
    assign valid_out = occupied_ff;

    // 3. The data we output is always the data from our internal storage register.
    assign data_out = data_reg;


    // sequential block
    always_ff @(posedge clk) begin
        if (reset) begin
            // On reset, the buffer is empty.
            occupied_ff <= 1'b0;
            // The data register can be uninitialized, as it's only valid when occupied_ff is high.
        end else begin
            // Data reg only needs to update when producer is sending data
            if (upstream_transfer) begin
                data_reg <= data_in;
            end

            
            occupied_ff <= (occupied_ff && !downstream_transfer) || upstream_transfer;
        end
    end

endmodule

// When does the occupied status change?
            // Case 1: Data comes in, but none goes out. We become full.
            // Case 2: Data goes out, but none comes in. We become empty.
            // Case 3: Data comes in AND goes out in the same cycle. We remain full (with new data).
            // Case 4: No change. We stay as we are.
            //
            // This logic covers all cases:
            // The buffer will be occupied next cycle if it's already occupied AND the data is NOT
            // taken, OR if new data is accepted.