module priority_decoder #(parameter WIDTH = 4) (
    input wire [WIDTH-1:0] in, 
    output logic [$clog2(WIDTH)-1:0] out, 
    output logic valid
);

// test cases
// 0000, 1000, 0100, 1100


assign valid = | in; // or all bits of in to see if any are on. reduction operator

always_comb begin
    out = '0;
    for(int i=WIDTH-1; i>=0; i--) begin
        if(in[i]==1'b1) begin
            out = i;
            break;
        end
    end
end // end always block


endmodule

//errors I made that Gemini caught:
// 1. used clog instead of clog2
// 2. forgot to name the variable width output port
// 3. didn't use 1'b1. Just did 1
// 4. didn't have a default assignment for 0 which would have then handled the 
// case of no bits "on" wrong
// 5. gemini suggested using '0 instead of 0