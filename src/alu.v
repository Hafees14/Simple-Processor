// Computer Architecture CO2070 - Lab 04
// Design: 8-bit ALU with ZERO flag output for beq support
// Team  : 06
// Members : E/22/014, E/22/035

// Operations:
// 000 - Forward DATA2
// 001 - Addition
// 010 - Bitwise AND
// 011 - Bitwise OR
//
// Unused SELECT values are handled safely
// by sending 0 to the output.

// New output for Lab 4:
//   ZERO    is 1 when the subtraction result is all-zero,
//           used by the beq instruction to decide whether to branch.

`timescale 1ns/100ps


// Forward Unit
// RESULT = DATA2
// Delay = 1 time unit

module forward_unit(DATA2, RESULT);

    input  [7:0] DATA2;
    output reg [7:0] RESULT;

    always @(*)
    begin
        #1 RESULT = DATA2;
    end

endmodule


// Add Unit
// RESULT = DATA1 + DATA2
// Delay = 2 time units

module add_unit(DATA1, DATA2, RESULT);

    input  [7:0] DATA1, DATA2;
    output reg [7:0] RESULT;

    always @(*)
    begin
        #2 RESULT = DATA1 + DATA2;
    end

endmodule

// AND Unit
// RESULT = DATA1 & DATA2
// Delay = 1 time unit

module and_unit(DATA1, DATA2, RESULT);

    input  [7:0] DATA1, DATA2;
    output reg [7:0] RESULT;

    always @(*)
    begin
        #1 RESULT = DATA1 & DATA2;
    end

endmodule


// OR Unit
// RESULT = DATA1 | DATA2
// Delay = 1 time unit

module or_unit(DATA1, DATA2, RESULT);

    input  [7:0] DATA1, DATA2;
    output reg [7:0] RESULT;

    always @(*)
    begin
        #1 RESULT = DATA1 | DATA2;
    end

endmodule

// Main ALU Module
// New port: ZERO – HIGH (ZERO = 1) when the result of a subtract is 0.
// The ZERO flag is used by beq to decide whether to take the branch.

module alu(DATA1, DATA2, RESULT, SELECT, ZERO);

    input  [7:0] DATA1, DATA2;
    input  [2:0] SELECT;

    output reg [7:0] RESULT;

    // ZERO is 1 when RESULT == 0, used exclusively by beq.
    output ZERO;
    assign ZERO = (RESULT == 8'b00000000) ? 1'b1 : 1'b0;

    // wires to get outputs from each unit
    wire [7:0] forward_result;
    wire [7:0] add_result;
    wire [7:0] and_result;
    wire [7:0] or_result;


    // Unit Instantiations
    forward_unit f1(DATA2, forward_result);
    add_unit a1(DATA1, DATA2, add_result);
    and_unit and1(DATA1, DATA2, and_result);
    or_unit o1(DATA1, DATA2, or_result);


    // Select the required operation

    always @(*)
    begin

        case(SELECT)

            // Forward DATA2
            3'b000:
                RESULT = forward_result;

            // Addition
            3'b001:
                RESULT = add_result;

            // Bitwise AND
            3'b010:
                RESULT = and_result;

            // Bitwise OR
            3'b011:
                RESULT = or_result;

            // Unused SELECT values
            // Future operations can be added here
            default:
                RESULT = 8'b00000000;

        endcase

    end

endmodule
