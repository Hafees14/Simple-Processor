// Computer Architecture CO2070 - Lab 02
// Design: Register File of Simple Processor
// Author: Kisaru Liyanage
// Team : 06
// Members : E/22/014 , E/22/035

// Register File Module

`timescale 1ns/100ps

module reg_file(
    IN,
    OUT1,
    OUT2,
    INADDRESS,
    OUT1ADDRESS,
    OUT2ADDRESS,
    WRITE,
    CLK,
    RESET
);


// Input Ports

// data input
input [7:0] IN;

// register addresses
input [2:0] INADDRESS;
input [2:0] OUT1ADDRESS;
input [2:0] OUT2ADDRESS;

// control signals
input WRITE;
input CLK;
input RESET;


// Output Ports

// output values from registers
output reg [7:0] OUT1;
output reg [7:0] OUT2;


// Register Array
// 8 registers
// each register contains 8 bits

reg [7:0] registers [7:0];


// Asynchronous Read
// outputs change immediately when:
// - read address changes
// - register values change

always @(
    OUT1ADDRESS or
    OUT2ADDRESS or
    registers[0] or
    registers[1] or
    registers[2] or
    registers[3] or
    registers[4] or
    registers[5] or
    registers[6] or
    registers[7]
)

begin

    // read delay
    #2;

    // read data from selected registers
    OUT1 = registers[OUT1ADDRESS];
    OUT2 = registers[OUT2ADDRESS];

end


// Synchronous Write and Reset
// operations happen only at positive clock edge

always @(posedge CLK)

begin

    // Reset all registers

    if(RESET)

    begin

        // reset delay
        #1;

        registers[0] = 8'b00000000;
        registers[1] = 8'b00000000;
        registers[2] = 8'b00000000;
        registers[3] = 8'b00000000;
        registers[4] = 8'b00000000;
        registers[5] = 8'b00000000;
        registers[6] = 8'b00000000;
        registers[7] = 8'b00000000;

    end


    // Write operation

    else
    begin
        #1;              // let WRITE settle before sampling it (avoids race with MEM_BUSYWAIT)
        if(WRITE)
        begin
            // write delay
            #1;
            registers[INADDRESS] = IN;
        end
    end

end

endmodule




