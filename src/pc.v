// Computer Architecture CO2070 - Lab 03
// Design: Program Counter (PC) Module
// Team  : 06
// Members : E/22/014, E/22/035

`timescale 1ns/100ps

module pc(PC, CLK, RESET);

    // Outputs
    output reg [31:0] PC;

    // Inputs
    input         CLK;
    input         RESET;


    // PC + 4 adder
    // Runs in parallel with instruction memory read (#1 delay)
    
    wire [31:0] PC_NEXT;
    assign #1 PC_NEXT = PC + 32'd4;


    // PC Register
    // Synchronous update on positive clock edge.
    // RESET overrides the next PC value with 0 to restart execution.
    // Normal operation: PC <- PC + 4  (every instruction is 4 bytes)

    always @(posedge CLK)
    begin

        if (RESET)
        begin
            // Reset latency = 1 time unit (same as regular PC write)
            #1 PC = 32'b0;
        end
        else
        begin
            // Advance to next instruction (PC+4 already computed by the adder)
            #1 PC = PC_NEXT;
        end

    end

endmodule
