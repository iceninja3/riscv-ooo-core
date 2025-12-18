`timescale 1ns / 1ps

module priority_decoder #(
    parameter WIDTH = 8
)(
    input  logic [WIDTH-1:0] req_i,
    
    // SAFE WIDTH CALCULATION:
    // If WIDTH > 1, use $clog2(WIDTH).
    // If WIDTH == 1, use 1 (to avoid 0-1 = -1 range).
    output logic [(WIDTH > 1 ? $clog2(WIDTH) : 1) - 1 : 0] idx_o,
    
    output logic valid_o
);

    always_comb begin
        idx_o   = '0;
        valid_o = 1'b0;
        
        for (int i = 0; i < WIDTH; i++) begin
            if (req_i[i]) begin
                // Cast i to the correct width to avoid warnings
                idx_o   = i[(WIDTH > 1 ? $clog2(WIDTH) : 1) - 1 : 0];
                valid_o = 1'b1;
                break; 
            end
        end
    end

endmodule