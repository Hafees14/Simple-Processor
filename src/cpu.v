// Computer Architecture CO2070 - Lab 04.5
// Design: Top-Level CPU Module – Extended ISA
// Team  : 06
// Members : E/22/014, E/22/035

// OPCODE table (from CO2070Assembler.c + Lab 4.5 extensions):
//   8'b00000000  loadi
//   8'b00000001  mov
//   8'b00000010  add
//   8'b00000011  sub
//   8'b00000100  and
//   8'b00000101  or
//   8'b00000110  j
//   8'b00000111  beq
//   8'b00001000  mult   [Lab 4_5]  RD = RT * RS
//   8'b00001001  sll    [Lab 4_5]  RD = RT << IMM
//   8'b00001010  srl    [Lab 4_5]  RD = RT >> IMM  (logical)
//   8'b00001011  sra    [Lab 4_5]  RD = RT >>> IMM (arithmetic)
//   8'b00001100  ror    [Lab 4_5]  RD = rotate_right(RT, IMM)
//   8'b00001101  bne    [Lab 4_5]  branch if RT != RS

// ALU SELECT encoding:
//   3'b000  forward DATA2   (mov, loadi)
//   3'b001  add             (add, sub, beq, bne)
//   3'b010  and             (and)
//   3'b011  or              (or)
//   3'b100  multiply        (mult)
//   3'b101  shift / rotate  (sll, srl, sra, ror)

// Timing per the lab diagram (single-cycle, 8 time-unit clock period):
//   PC Update            #1
//   Instruction Mem Read #2  (in testbench)
//   PC+4 Adder             #1   (runs in parallel with mem read, inside pc.v)
//   Decode               #1
//   2's Complement       #1  (sub only, in parallel with register read)
//   Register Read        #2  (in reg_file)
//   ALU                  #2  (add/sub/mult/shift/rotate) or #1 (and/or/mov/loadi)
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
    wire [7:0]  RD_ADDR;          // bits [23:16]
    wire [7:0]  RT_ADDR;          // bits [15:8]
    wire [7:0]  RS_ADDR;          // bits [7:0]
    wire [7:0]  IMMEDIATE;        // bits [7:0]   -- same field as RS_ADDR, used by loadi/sll/srl/sra/ror

    // Decode
    assign OPCODE    = INSTRUCTION[31:24];
    assign RD_ADDR   = INSTRUCTION[23:16];   // full 8-bit field; register address uses [2:0]
    assign RT_ADDR   = INSTRUCTION[15:8];
    assign RS_ADDR   = INSTRUCTION[7:0];
    assign IMMEDIATE = INSTRUCTION[7:0];     // same bits -- used by loadi and shift-amount

    // Control signals (all generated combinationally after decode)
    reg [2:0] ALUOP;         // selects ALU operation
    reg       WRITEENABLE;   // enables register-file write
    reg       MUX_IMM_SEL;   // 1 = feed IMMEDIATE into ALU DATA2  (loadi, sll, srl, sra, ror)
    reg       MUX_NEG_SEL;   // 1 = negate REGOUT2 before ALU      (sub, beq, bne)
    reg       JUMP;          // 1 = unconditional jump (j)
    reg       BRANCH;        // 1 = conditional branch  (beq)

    // Lab 4_5 auxiliary control signals for the barrel_unit
    reg       SHIFT_DIR;     // 0 = left, 1 = right  (sll vs srl/sra)
    reg       ARITH;         // 0 = logical, 1 = arithmetic right shift (sra)
    reg       ROTATE;        // 0 = shift, 1 = rotate right (ror)

    // Lab 4_5: BNE branch control
    // BNE branches when the ALU result is NOT zero (opposite of beq).
    reg       BRANCH_NE;     // 1 = conditional branch if NOT zero (bne)


    // PC Next-value Logic 

    // PC+4 is computed inside pc.v with #1 delay.
    // The branch/jump target adder below runs in parallel with the ALU (#2 delay).

    //   Branch/jump target:
    //   target = (PC + 4) + sign_extended(OFFSET) * 4
    //   The offset is stored in RD_ADDR (bits[23:16]) for j.
    //   For beq, it is also stored in RD_ADDR.
    //   The assembler stores the raw offset value; multiplying by 4 aligns
    //   the byte address because each instruction is 4 bytes wide.

    // PC+4 wire – computed by the pc module with #1 delay
    wire [31:0] PC_PLUS4;
    assign #1 PC_PLUS4 = PC + 32'd4;

    // Sign-extend the 8-bit offset field (RD_ADDR) to 32 bits, then multiply by 4
    wire [31:0] OFFSET_EXTENDED;
    assign OFFSET_EXTENDED = {{22{RD_ADDR[7]}}, RD_ADDR, 2'b00};

    // Branch/jump target adder – latency #2 (runs in parallel with ALU)
    wire [31:0] BRANCH_TARGET;
    assign #2 BRANCH_TARGET = PC_PLUS4 + OFFSET_EXTENDED;

    // ZERO flag from ALU – used by beq to detect RT == RS
    // Lab 4_5: also used by bne to detect RT != RS
    wire ZERO;

    // PC_SEL decides what goes into the PC register next cycle:
    //   j               -> always take the jump target
    //   beq + ZERO      -> take the branch target only when registers are equal
    //   bne + !ZERO     -> take the branch target only when registers are NOT equal [Lab 4_5]
    //   otherwise       -> take PC + 4 (sequential)
    wire PC_SEL;
    assign PC_SEL = JUMP | (BRANCH & ZERO) | (BRANCH_NE & ~ZERO);

    // Next PC mux: feeds the PC module
    wire [31:0] PC_NEXT;
    assign PC_NEXT = (PC_SEL) ? BRANCH_TARGET : PC_PLUS4;

    // PC module instantiation
    pc mypc(
        .PC    (PC),
        .PC_IN (PC_NEXT),
        .CLK   (CLK),
        .RESET (RESET)
    );


    // ── Register File Connections ────────────────────────────────────────────

    wire [7:0] REGOUT1;    // read data from RT (source 1)
    wire [7:0] REGOUT2;    // read data from RS (source 2)
    wire [7:0] ALURESULT;  // ALU output, written back to RD

    reg_file rf(
        .IN          (ALURESULT),
        .OUT1        (REGOUT1),
        .OUT2        (REGOUT2),
        .INADDRESS   (RD_ADDR[2:0]),
        .OUT1ADDRESS (RT_ADDR[2:0]),
        .OUT2ADDRESS (RS_ADDR[2:0]),
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
    //   MUX_IMM_SEL = 1  ->  IMMEDIATE  (loadi, sll, srl, sra, ror)
    wire [7:0] ALU_DATA2;
    assign ALU_DATA2 = (MUX_IMM_SEL) ? IMMEDIATE : MUX1_OUT;


    // ALU instantiation
    // Lab 4.5: three new auxiliary ports SHIFT_DIR, ARITH, ROTATE added.
    alu myalu(
        .DATA1     (REGOUT1),
        .DATA2     (ALU_DATA2),
        .RESULT    (ALURESULT),
        .SELECT    (ALUOP),
        .ZERO      (ZERO),
        .SHIFT_DIR (SHIFT_DIR),
        .ARITH     (ARITH),
        .ROTATE    (ROTATE)
    );


    // Control Unit (combinational)
    // Decodes OPCODE and sets all control signals + #1 decode delay
    
    always @(OPCODE)
    begin

        // Default: safe values that cause no side effects
        WRITEENABLE = 1'b0;
        MUX_IMM_SEL = 1'b0;
        MUX_NEG_SEL = 1'b0;
        ALUOP       = 3'b000;
        JUMP        = 1'b0;
        BRANCH      = 1'b0;
        BRANCH_NE   = 1'b0;   // Lab 4_5
        SHIFT_DIR   = 1'b0;   // Lab 4_5
        ARITH       = 1'b0;   // Lab 4_5
        ROTATE      = 1'b0;   // Lab 4_5

        // Apply decode latency of 1 time unit
        #1;

        case (OPCODE)

            // loadi  RD, IMM
            // Load the 8-bit immediate (bits [7:0]) into register RD.
            // ALU forwards IMMEDIATE directly (MUX_IMM_SEL=1, ALUOP=000).
            
            8'b00000000:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;   // route immediate into ALU DATA2
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b000;  // forward DATA2
            end

            // mov  RD, RT
            // Copy the value in register RT to register RD.
            // RS bits are ignored. ALU forwards REGOUT1 through forward unit.
            
            8'b00000001:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b000;  // forward DATA2 (REGOUT2 holds RT)
            end

            // add  RD, RT, RS
            // ALURESULT = REGOUT1 + REGOUT2
            8'b00000010:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b001;  // add
            end

            // sub  RD, RT, RS
            // ALURESULT = REGOUT1 - REGOUT2 = REGOUT1 + (~REGOUT2 + 1)
            // We negate REGOUT2 using the two's complement unit,
            // then feed the result to the adder.
            
            8'b00000011:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b1;   // negate REGOUT2
                ALUOP       = 3'b001;  // add (of negated operand)
            end

            // and  RD, RT, RS
            // ALURESULT = REGOUT1 & REGOUT2
            
            8'b00000100:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b010;  // bitwise AND
            end

            // or  RD, RT, RS
            // ALURESULT = REGOUT1 | REGOUT2
            
            8'b00000101:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b011;  // bitwise OR
            end

            // j  OFFSET
            // Unconditional jump: PC = (PC+4) + sign_ext(OFFSET) * 4
            // Bits [15:0] are ignored.  OFFSET is in RD_ADDR (bits [23:16]).
            // WRITEENABLE stays 0 – no register is modified.
            // JUMP = 1 forces PC_SEL high, overriding the sequential path.

            8'b00000110:
            begin
                WRITEENABLE = 1'b0;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b000;  // ALU not used – forward is harmless
                JUMP        = 1'b1;    // take the branch/jump target unconditionally
                BRANCH      = 1'b0;
            end

            // beq  OFFSET, RT, RS
            // Branch if RT == RS: PC = (PC+4) + sign_ext(OFFSET) * 4
            // RT == RS is detected by subtracting RS from RT and checking ZERO.
            // OFFSET is in RD_ADDR (bits [23:16]).
            // WRITEENABLE stays 0 – registers are compared, not written.
            // BRANCH = 1 enables the ZERO check in the PC mux.

            8'b00000111:
            begin
                WRITEENABLE = 1'b0;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b1;   // negate RS so ALU computes RT - RS
                ALUOP       = 3'b001;  // subtract to produce ZERO flag
                JUMP        = 1'b0;
                BRANCH      = 1'b1;   // branch if ALU result is zero
            end

            // ── Lab 4_5 Extended Instructions ───────────────────────────────

            // mult  RD, RT, RS
            // ALURESULT = REGOUT1 * REGOUT2  (lower 8 bits)
            // Opcode: 8'b00001000
            // ALU SELECT = 3'b100 routes to mult_unit.
            // Both register operands are used; IMMEDIATE not needed.
            // Latency: decode #1 + reg-read #2 + mult #2 + write #1 = 6 ≤ 8. OK.

            8'b00001000:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b0;   // use register operands
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b100;  // multiply
            end

            // sll  RD, RT, IMM
            // ALURESULT = REGOUT1 << IMM  (logical left shift)
            // Opcode: 8'b00001001
            // ALU SELECT = 3'b101 routes to barrel_unit.
            // SHIFT_DIR=0 (left), ARITH=0, ROTATE=0.
            // IMM (bits[7:0]) carries the shift amount into ALU DATA2 via MUX_IMM_SEL.
            // RT carries the value to shift; RS field is unused (holds IMM).
            // Latency: decode #1 + reg-read #2 + barrel #2 + write #1 = 6 ≤ 8. OK.

            8'b00001001:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;   // shift amount from immediate field
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b101;  // barrel shift / rotate
                SHIFT_DIR   = 1'b0;   // left
                ARITH       = 1'b0;   // logical
                ROTATE      = 1'b0;   // shift, not rotate
            end

            // srl  RD, RT, IMM
            // ALURESULT = REGOUT1 >> IMM  (logical right shift)
            // Opcode: 8'b00001010
            // ALU SELECT = 3'b101 routes to barrel_unit.
            // SHIFT_DIR=1 (right), ARITH=0, ROTATE=0.

            8'b00001010:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;   // shift amount from immediate field
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b101;  // barrel shift / rotate
                SHIFT_DIR   = 1'b1;   // right
                ARITH       = 1'b0;   // logical (zero fill)
                ROTATE      = 1'b0;   // shift, not rotate
            end

            // sra  RD, RT, IMM
            // ALURESULT = REGOUT1 >>> IMM  (arithmetic right shift, sign-extend)
            // Opcode: 8'b00001011
            // ALU SELECT = 3'b101 routes to barrel_unit.
            // SHIFT_DIR=1, ARITH=1, ROTATE=0.

            8'b00001011:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;   // shift amount from immediate field
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b101;  // barrel shift / rotate
                SHIFT_DIR   = 1'b1;   // right
                ARITH       = 1'b1;   // arithmetic (sign-bit fill)
                ROTATE      = 1'b0;   // shift, not rotate
            end

            // ror  RD, RT, IMM
            // ALURESULT = rotate_right(REGOUT1, IMM)
            // Opcode: 8'b00001100
            // ALU SELECT = 3'b101 routes to barrel_unit.
            // ROTATE=1; SHIFT_DIR and ARITH are don't-cares (ROTATE overrides).

            8'b00001100:
            begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;   // rotate amount from immediate field
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b101;  // barrel shift / rotate
                SHIFT_DIR   = 1'b1;   // don't-care when ROTATE=1
                ARITH       = 1'b0;   // don't-care when ROTATE=1
                ROTATE      = 1'b1;   // rotate right
            end

            // bne  OFFSET, RT, RS
            // Branch if RT != RS: PC = (PC+4) + sign_ext(OFFSET) * 4
            // RT != RS is detected by subtracting RS from RT and checking ~ZERO.
            // Opcode: 8'b00001101
            // OFFSET is in RD_ADDR (bits [23:16]).
            // WRITEENABLE stays 0 – registers are compared, not written.
            // BRANCH_NE = 1 enables the ~ZERO check in the PC mux.

            8'b00001101:
            begin
                WRITEENABLE = 1'b0;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b1;   // negate RS so ALU computes RT - RS
                ALUOP       = 3'b001;  // subtract to produce ZERO flag
                JUMP        = 1'b0;
                BRANCH      = 1'b0;
                BRANCH_NE   = 1'b1;   // branch if ALU result is NOT zero
            end

            // Default: unrecognised opcode -- do nothing, don't write
            
            default:
            begin
                WRITEENABLE = 1'b0;
                MUX_IMM_SEL = 1'b0;
                MUX_NEG_SEL = 1'b0;
                ALUOP       = 3'b000;
                JUMP        = 1'b0;
                BRANCH      = 1'b0;
                BRANCH_NE   = 1'b0;
                SHIFT_DIR   = 1'b0;
                ARITH       = 1'b0;
                ROTATE      = 1'b0;
            end

        endcase

    end

endmodule
