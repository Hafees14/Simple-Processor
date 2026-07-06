// Computer Architecture CO2070 - Lab 03
// Design: Top-Level CPU Module - Control & Integration
// Team  : 06
// Members : E/22/014, E/22/035

// OPCODE table (from CO2070Assembler.c):
//   8'b00000000  loadi
//   8'b00000001  mov
//   8'b00000010  add
//   8'b00000011  sub
//   8'b00000100  and
//   8'b00000101  or

// ALU SELECT encoding:
//   3'b000  forward DATA2   (mov, loadi)
//   3'b001  add             (add, sub)
//   3'b010  and             (and)
//   3'b011  or              (or)

// Timing per the lab diagram (single-cycle, 8 time-unit clock period):
//   PC Update            #1
//   Instruction Mem Read #2  (in testbench)
//   Decode               #1
//   2's Complement       #1  (sub only, in parallel with register read)
//   Register Read        #2  (in reg_file)
//   ALU                  #2  (add/sub) or #1 (and/or/mov/loadi)
//   Register Write       #1  (in reg_file)
//   PC+4 Adder           #1  (runs in parallel with mem read)


`include "alu.v"
`include "reg_file.v"
`include "pc.v"

`timescale 1ns/100ps

module cpu(PC, INSTRUCTION, CLK, RESET);

    // Outputs
    output [31:0] PC;

    // Inputs
    input  [31:0] INSTRUCTION;
    input         CLK;
    input         RESET;


    // Wires coming out of the instruction decode stage

    wire [7:0]  OPCODE;           // bits [31:24]
    wire [2:0]  RD_ADDR;          // bits [23:21]
    wire [2:0]  RT_ADDR;          // bits [15:13] 
    wire [2:0]  RS_ADDR;          // bits [7:5]   
    wire [7:0]  IMMEDIATE;        // bits [7:0]   

    // Decode
    assign OPCODE    = INSTRUCTION[31:24];
    assign RD_ADDR   = INSTRUCTION[23:16];   // 8-bit field; reg file uses [2:0]
    assign RT_ADDR   = INSTRUCTION[15:8];
    assign RS_ADDR   = INSTRUCTION[7:0];
    assign IMMEDIATE = INSTRUCTION[7:0];     // same bits -- used by loadi

    // Control signals (all generated combinationally after decode)

    reg [2:0]  ALUOP;            // selects ALU operation
    reg        WRITEENABLE;      // enables register file write
    reg        MUX_IMM_SEL;      // 1 = use IMMEDIATE as ALU DATA2 input (loadi)
    reg        MUX_NEG_SEL;      // 1 = use two's complement of REGOUT2   (sub)

    // PC + 4 adder
    // Runs in parallel with instruction memory read (#1 delay)
    // PC register and PC_NEXT adder are encapsulated in the pc module

    pc mypc(
        .PC    (PC),
        .CLK   (CLK),
        .RESET (RESET)
    );


    // Register file connections
    
    wire [7:0] REGOUT1;      // data from source register RT
    wire [7:0] REGOUT2;      // data from source register RS
    wire [7:0] ALURESULT;    // result coming out of ALU -- fed back as write data


    reg_file rf(
        .IN          (ALURESULT),
        .OUT1        (REGOUT1),
        .OUT2        (REGOUT2),
        .INADDRESS   (RD_ADDR),
        .OUT1ADDRESS (RT_ADDR),
        .OUT2ADDRESS (RS_ADDR),
        .WRITE       (WRITEENABLE),
        .CLK         (CLK),
        .RESET       (RESET)
    );


    // Two's complement unit
    // Negates REGOUT2 for the sub instruction. Delay = #1.

    wire [7:0] NEGATED_REGOUT2;
    assign #1 NEGATED_REGOUT2 = ~REGOUT2 + 8'b00000001;


    //   MUX 1: select between REGOUT2 and its two's complement
    //   MUX_NEG_SEL = 0  ->  REGOUT2          (add, and, or, mov)
    //   MUX_NEG_SEL = 1  ->  NEGATED_REGOUT2  (sub)
    
    wire [7:0] MUX1_OUT;
    assign MUX1_OUT = (MUX_NEG_SEL) ? NEGATED_REGOUT2 : REGOUT2;

    // MUX 2: select between MUX1_OUT and IMMEDIATE
    //   MUX_IMM_SEL = 0  ->  MUX1_OUT   (register instructions)
    //   MUX_IMM_SEL = 1  ->  IMMEDIATE  (loadi)
   
    wire [7:0] ALU_DATA2;
    assign ALU_DATA2 = (MUX_IMM_SEL) ? IMMEDIATE : MUX1_OUT;


    // ALU instantiation
    // DATA1 = REGOUT1 (always from RT)
    // DATA2 = ALU_DATA2 (either register, negated register, or immediate)
    
    alu myalu(
        .DATA1  (REGOUT1),
        .DATA2  (ALU_DATA2),
        .RESULT (ALURESULT),
        .SELECT (ALUOP)
    );


    // Control Unit (combinational)
    // Decodes OPCODE and sets all control signals + #1 decode delay
    
    always @(OPCODE)
    begin

        // Default: safe values that cause no side effects
        WRITEENABLE  = 1'b0;
        MUX_IMM_SEL  = 1'b0;
        MUX_NEG_SEL  = 1'b0;
        ALUOP        = 3'b000;

        // Apply decode latency of 1 time unit
        #1;

        case (OPCODE)

            //------------------------------------------------------------------
            // loadi  RD, IMM
            // Load the 8-bit immediate (bits [7:0]) into register RD.
            // ALU forwards IMMEDIATE directly (MUX_IMM_SEL=1, ALUOP=000).
            //------------------------------------------------------------------
            8'b00000000:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;   // pick IMMEDIATE as ALU DATA2
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b000;  // forward DATA2 -> ALURESULT = IMMEDIATE
            end

            //------------------------------------------------------------------
            // mov  RD, RT
            // Copy the value in register RT to register RD.
            // RS bits are ignored. ALU forwards REGOUT1 through forward unit.
            //------------------------------------------------------------------
            8'b00000001:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;   // use register path
                MUX_NEG_SEL = 1'b0;   // no negation
                ALUOP       = 3'b000;  // forward DATA2 (REGOUT2) -> ALURESULT
            end

            //------------------------------------------------------------------
            // add  RD, RT, RS
            // ALURESULT = REGOUT1 + REGOUT2
            //------------------------------------------------------------------
            8'b00000010:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b0;   // use REGOUT2 as-is
                ALUOP       = 3'b001;  // addition
            end

            //------------------------------------------------------------------
            // sub  RD, RT, RS
            // ALURESULT = REGOUT1 - REGOUT2 = REGOUT1 + (~REGOUT2 + 1)
            // We negate REGOUT2 using the two's complement unit,
            // then feed the result to the adder.
            //------------------------------------------------------------------
            8'b00000011:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b1;   // two's complement REGOUT2 before ALU
                ALUOP       = 3'b001;  // addition (of negated second operand)
            end

            //------------------------------------------------------------------
            // and  RD, RT, RS
            // ALURESULT = REGOUT1 & REGOUT2
            //------------------------------------------------------------------
            8'b00000100:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b010;  // bitwise AND
            end

            //------------------------------------------------------------------
            // or  RD, RT, RS
            // ALURESULT = REGOUT1 | REGOUT2
            //------------------------------------------------------------------
            8'b00000101:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b011;  // bitwise OR
            end

            //------------------------------------------------------------------
            // Default: unrecognised opcode -- do nothing, don't write
            //------------------------------------------------------------------
            default:
            begin
                WRITEENABLE = 1'b0;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b000;
            end

        endcase

    end

endmodule
