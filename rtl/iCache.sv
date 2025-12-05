module iCache #(
    parameter ADDR_WIDTH = 9, //log(2048/4)
    parameter DATA_WIDTH = 32
) (
    input logic clk, 
    input logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] rdata
);

logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

initial begin 
    $readmemh("Simulation/program_hex.txt", mem);
end

always_ff @(posedge clk) begin
    rdata <= mem[addr];
end


endmodule