module fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 8
) (
    input logic  clk, 
    input logic  reset, 

    input logic  write_en,
    input logic [WIDTH-1:0] write_data,
    input logic  read_en, 
    output logic [WIDTH-1:0] read_data,
    output logic full,
    output logic empty
);

typedef logic [WIDTH-1:0] T;
localparam int PW = $clog2(DEPTH);
logic [PW-1:0] wr_ptr;
logic [PW-1:0] rd_ptr;
logic [PW:0] count; //keep track of fifo status 

T mem [0:DEPTH-1]; //declare unpacked array of 8 elements 32 bit wide 

assign full = (count == DEPTH);
assign empty = (count == 0);


//write always block 
always_ff @(posedge clk) begin 
    if(reset) begin 
        wr_ptr <= '0; 
    end 
    else begin
        if(write_en && ~full) begin 
            mem[wr_ptr] <= write_data;
            wr_ptr <= wr_ptr + 1'b1;
        end 
    end 
end 



//read always block 
always_ff @(posedge clk) begin 
    if(reset) begin 
        rd_ptr <= '0; 
    end 
    else begin
        if(read_en && ~empty) begin 
            read_data <= mem[rd_ptr];
            rd_ptr <= rd_ptr + 1'b1;
        end 
    end 
end 


//count always block 
always_ff @(posedge clk) begin 
    if(reset) begin 
        count <= '0;
    end 
    else begin 
        case ({write_en && ~full,read_en && ~empty})

        2'b00: count <= count;

        2'b01: count <= count - 1'b1;

        2'b10: count <= count + 1'b1;

        2'b11: count <= count;

        default: count <= count;

        endcase 
    end 
end 

endmodule