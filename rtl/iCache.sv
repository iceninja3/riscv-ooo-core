`timescale 1ns / 1ps

module iCache #(
    parameter ADDR_WIDTH = 9,
    parameter DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] rdata
);

    logic [DATA_WIDTH-1:0] mem [0:1023]; // 4KB

    // Initialize with 25swr program explicitly
    initial begin
        // Initialize all to 0 first
        for (int i = 0; i < 1024; i++) mem[i] = 32'd0;

        // HARDCODED 25SWR PROGRAM (To bypass file loading bugs)
        mem[0] = 32'h00010437; // lui x8 0x10
        mem[1] = 32'h02040413; // addi x8 x8 32
        mem[2] = 32'h000204b7; // lui x9 0x20
        mem[3] = 32'hff048493; // addi x9 x9 -16
        mem[4] = 32'h12306293; // ori x5 x0 291
        mem[5] = 32'h4062d333; // sra x6 x5 x6
        mem[6] = 32'h00542023; // sw x5 0 x8
        mem[7] = 32'h00641223; // sh x6 4 x8
        mem[8] = 32'h0ff00393; // addi x7 x0 255
        mem[9] = 32'h00742423; // sw x7 8 x8
        mem[10] = 32'h00944e03; // lbu x28 9 x8
        mem[11] = 32'h00042e83; // lw x29 0 x8
        mem[12] = 32'h007eff33; // and x30 x29 x7
        mem[13] = 32'h01e42623; // sw x30 12 x8
        mem[14] = 32'h02040913; // addi x18 x8 32
        mem[15] = 32'hffe91f23; // sh x30 -2 x18
        mem[16] = 32'hffe94f83; // lbu x31 -2 x18
        mem[17] = 32'hfff94b83; // lbu x23 -1 x18
        mem[18] = 32'h01d4a023; // sw x29 0 x9
        mem[19] = 32'h00749323; // sh x7 6 x9
        mem[20] = 32'h0004ac03; // lw x24 0 x9
        mem[21] = 32'h0074cc83; // lbu x25 7 x9
        mem[22] = 32'h0ff00993; // addi x19 x0 255
        mem[23] = 32'h013c7533; // and x10 x24 x19
        mem[24] = 32'h000e0593; // addi x11 x28 0
        mem[25] = 32'h41f00a33; // sub x20 x0 x31
        mem[26] = 32'h414585b3; // sub x11 x11 x20
        mem[27] = 32'h41700ab3; // sub x21 x0 x23
        mem[28] = 32'h41d585b3; // sub x11 x11 x29
        
        $display("HARDCODED MEMORY LOADED. Mem[0]=%h", mem[0]);
    end

    // Use word-aligned address
    assign rdata = mem[addr[ADDR_WIDTH-1:2]];

endmodule





// module iCache #(
//     parameter ADDR_WIDTH = 9, //log(2048/4)
//     parameter DATA_WIDTH = 32
// ) (
//     input logic clk, 
//     input logic [ADDR_WIDTH-1:0] addr,
//     output logic [DATA_WIDTH-1:0] rdata
// );

// logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

// initial begin 
//   //$readmemh("rProgram.hex", mem);
//   $readmemh("swrProgram.hex", mem);
//   //$readmemh("jswrprogram.hex", mem);
//   //$readmemh("TestProgram.hex", mem);
  
  
  
//   $display("---------------------------------------------------");
//         $display("DEBUG: Checking Loaded Memory...");
//         $display("Mem[0x00] = %h (Expected: 00010437)", mem[0]);
//         $display("Mem[0x44] = %h (Expected: fff94b83)", mem[17]); // 0x44 >> 2 = 17
//         $display("---------------------------------------------------");
        
//         if (mem[17] !== 32'hfff94b83) begin
//             $display("FATAL ERROR: Simulator loaded the WRONG program!");
//             $display("You are running the Branch Test, not 25swr.");
//             $stop; // Stop simulation immediately
//         end
// end

// always_ff @(posedge clk) begin
//     rdata <= mem[addr];
// end


// endmodule