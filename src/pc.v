// Computer Architecture CO2070 - Lab 04
// Design: Program Counter (PC) Module with Branch/Jump Support
// Team  : 06
// Members : E/22/014, E/22/035

// PC now accepts an external PC_IN so the cpu can mux between
// PC+4 (sequential) and the branch/jump target.
// PC_SEL = 0  :  PC_IN = PC + 4   (normal sequential execution)
// PC_SEL = 1  :  PC_IN = branch/jump target from the branch adder

`timescale 1ns/100ps

module pc(PC, PC_IN, CLK, RESET);

    // Current PC value visible to instruction memory and cpu
    output reg [31:0] PC;

    // Next PC already selected by the cpu-level mux (PC+4 or branch target)
    input  [31:0] PC_IN;

    input         CLK;
    input         RESET;


    // PC + 4 adder
    // Runs in parallel with instruction memory read (#1 latency per timing diagram)

    wire [31:0] PC_PLUS4;
    assign #1 PC_PLUS4 = PC + 32'd4;


    // PC register: synchronous update on rising clock edge

    always @(posedge CLK)
    begin

        if (RESET)
        begin
            // Restart execution from address 0
            #1 PC = 32'b0;
        end
        else
        begin
            // Load whichever PC source the cpu selected
            #1 PC = PC_IN;
        end

    end

endmodule
