// Computer Architecture CO2070 - Lab 07
// Design: Top-Level CPU Module with Data Memory + Instruction Cache Support
// Team  : 06
// Members : E/22/014, E/22/035, E/22/034, E/22/036
//
// Lab 7 change: added IFETCH_BUSYWAIT input (from the new instruction
// cache) which now jointly gates PC advancement and register-file writes
// alongside MEM_BUSYWAIT (see STALL below). No new instructions were
// introduced - the ISA is unchanged from Lab 5.

// ══════════════════════════════════════════════════════════════════════════════
//  OPCODE TABLE
// ══════════════════════════════════════════════════════════════════════════════
//  8'h00  loadi  RD, IMM            RD = IMM
//  8'h01  mov    RD, RT             RD = RT (source in RS slot per conv.)
//  8'h02  add    RD, RT, RS         RD = RT + RS
//  8'h03  sub    RD, RT, RS         RD = RT - RS
//  8'h04  and    RD, RT, RS         RD = RT & RS
//  8'h05  or     RD, RT, RS         RD = RT | RS
//  8'h06  j      OFFSET             PC += sign_ext(OFFSET)*4
//  8'h07  beq    OFFSET, RT, RS     if RT==RS: branch
//  8'h08  mult   RD, RT, RS         RD = RT * RS       [Lab 4.5]
//  8'h09  sll    RD, RT, IMM        RD = RT << IMM     [Lab 4.5]
//  8'h0A  srl    RD, RT, IMM        RD = RT >> IMM     [Lab 4.5]
//  8'h0B  sra    RD, RT, IMM        RD = RT >>> IMM    [Lab 4.5]
//  8'h0C  ror    RD, RT, IMM        RD = ror(RT,IMM)   [Lab 4.5]
//  8'h0D  bne    OFFSET, RT, RS     if RT!=RS: branch  [Lab 4.5]
//  8'h10  lwd    RD, RS             RD = mem[RS]       [Lab 5]
//  8'h11  lwi    RD, IMM            RD = mem[IMM]      [Lab 5]
//  8'h12  swd    RT, RS             mem[RS] = RT       [Lab 5]
//  8'h13  swi    RT, IMM            mem[IMM] = RT      [Lab 5]
//
// ══════════════════════════════════════════════════════════════════════════════
//  STALL MECHANISM  (Lab 5)
// ══════════════════════════════════════════════════════════════════════════════
//
//  MEM_READ and MEM_WRITE are COMBINATIONAL outputs driven directly by the
//  control unit decode of OPCODE.  They go HIGH as soon as the memory
//  instruction is decoded and stay HIGH while the PC is frozen (since the
//  OPCODE doesn't change while the PC is frozen).
//
//  data_memory asserts BUSYWAIT the moment READ or WRITE goes high.
//  CPU freezes PC (PC_NEXT = PC when BUSYWAIT=1) and gates the register-file
//  write enable (WRITE_GATED = WRITEENABLE & ~BUSYWAIT).
//
//  After #40 (5 clock cycles), data_memory:
//    - For writes: commits data, deasserts BUSYWAIT
//    - For reads : drives READDATA, deasserts BUSYWAIT
//  On the next posedge after BUSYWAIT falls, PC advances and (for loads)
//  MEM_READDATA is written into the register file.
//
// ══════════════════════════════════════════════════════════════════════════════

`include "alu.v"
`include "reg_file.v"
`include "pc.v"

`timescale 1ns/100ps

module cpu(
    PC,
    INSTRUCTION,
    CLK,
    RESET,
    // ── Lab 5: Data Memory Interface ─────────────────────────────────────────
    MEM_READ,       // combinational: 1 while a load instruction is executing
    MEM_WRITE,      // combinational: 1 while a store instruction is executing
    MEM_ADDRESS,    // 8-bit address sent to data memory
    MEM_WRITEDATA,  // 8-bit data to store (from RT register)
    MEM_READDATA,   // 8-bit data read back from memory
    MEM_BUSYWAIT,   // memory stall: 1 while operation is in progress
    // ── Lab 7: Instruction Cache Interface ───────────────────────────────────
    IFETCH_BUSYWAIT // instruction-cache stall: 1 while a fetch is in progress
);

    // ─────────────────────────────────────────────────────────────────────────
    //  Port Declarations
    // ─────────────────────────────────────────────────────────────────────────

    output [31:0] PC;
    input  [31:0] INSTRUCTION;
    input         CLK;
    input         RESET;

    // MEM_READ and MEM_WRITE are WIRES (combinational), not regs.
    // They are driven by continuous assign from control-unit regs CTRL_MEM_READ/WRITE.
    output        MEM_READ;
    output        MEM_WRITE;
    output  [7:0] MEM_ADDRESS;
    output  [7:0] MEM_WRITEDATA;
    input   [7:0] MEM_READDATA;
    input         MEM_BUSYWAIT;
    input         IFETCH_BUSYWAIT;

    // Combined stall: freeze PC and gate register writes whenever EITHER
    // the data cache (Lab 6) or the instruction cache (Lab 7) is busy.
    // While IFETCH_BUSYWAIT is high, INSTRUCTION itself may not even be
    // valid yet, so OPCODE-derived control signals could glitch - but
    // since PC stays frozen and writes stay gated below, none of that
    // can leak into architectural state.
    wire STALL = MEM_BUSYWAIT | IFETCH_BUSYWAIT;


    // ─────────────────────────────────────────────────────────────────────────
    //  Instruction Field Extraction  (combinational, zero delay)
    // ─────────────────────────────────────────────────────────────────────────

    wire [7:0] OPCODE    = INSTRUCTION[31:24];
    wire [7:0] RD_ADDR   = INSTRUCTION[23:16];
    wire [7:0] RT_ADDR   = INSTRUCTION[15:8];
    wire [7:0] RS_ADDR   = INSTRUCTION[7:0];
    wire [7:0] IMMEDIATE = INSTRUCTION[7:0];   // same as RS_ADDR, aliased for readability


    // ─────────────────────────────────────────────────────────────────────────
    //  Control Signal Declarations  (all driven by always @(OPCODE) below)
    // ─────────────────────────────────────────────────────────────────────────

    reg [2:0] ALUOP;
    reg       WRITEENABLE;      // enables the register file write port
    reg       MUX_IMM_SEL;      // 1 → route IMMEDIATE to ALU DATA2 instead of REGOUT2
    reg       MUX_NEG_SEL;      // 1 → negate REGOUT2 (two's complement for sub/beq/bne)
    reg       JUMP;             // 1 → unconditional branch (j instruction)
    reg       BRANCH;           // 1 → conditional branch when ZERO=1 (beq)
    reg       BRANCH_NE;        // 1 → conditional branch when ZERO=0 (bne) [Lab 4.5]

    // Lab 4.5 barrel-shift auxiliary controls (passed through to ALU)
    reg       SHIFT_DIR;        // 0=left, 1=right
    reg       ARITH;            // 0=logical, 1=arithmetic (sign-fill for right shift)
    reg       ROTATE;           // 0=shift, 1=rotate right

    // Lab 5 decode flags
    reg       CTRL_MEM_READ;    // 1 → this is a load instruction (lwd/lwi)
    reg       CTRL_MEM_WRITE;   // 1 → this is a store instruction (swd/swi)
    reg       MEM_TO_REG;       // 1 → route MEM_READDATA to register-file write port
    reg       MEM_ADDR_IMM;     // 1 → memory address = IMMEDIATE (for lwi/swi)

    // Combinational drive of the output ports from the decode regs
    assign MEM_READ  = CTRL_MEM_READ;
    assign MEM_WRITE = CTRL_MEM_WRITE;


    // ─────────────────────────────────────────────────────────────────────────
    //  Register File
    // ─────────────────────────────────────────────────────────────────────────

    wire [7:0] REGOUT1;    // RT data output  (source 1 / store data)
    wire [7:0] REGOUT2;    // RS data output  (source 2 / address for lwd/swd)
    wire [7:0] ALURESULT;  // ALU computation result

    // Write-data mux:
    //   MEM_TO_REG=1  (lwd/lwi)  → write MEM_READDATA into register file
    //   MEM_TO_REG=0  (all other) → write ALURESULT into register file
    wire [7:0] REG_WRITEDATA;
    assign REG_WRITEDATA = MEM_TO_REG ? MEM_READDATA : ALURESULT;

    // Write-enable gate:
    // Suppress ALL register writes while memory OR the instruction fetch
    // is busy (READDATA not valid yet, or OPCODE not even reliable yet).
    // Without this gate, the register file would write garbage on every
    // stall cycle.
    wire WRITE_GATED;
    assign WRITE_GATED = WRITEENABLE & ~STALL;

    reg_file rf(
        .IN          (REG_WRITEDATA),
        .OUT1        (REGOUT1),
        .OUT2        (REGOUT2),
        .INADDRESS   (RD_ADDR[2:0]),
        .OUT1ADDRESS (RT_ADDR[2:0]),
        .OUT2ADDRESS (RS_ADDR[2:0]),
        .WRITE       (WRITE_GATED),
        .CLK         (CLK),
        .RESET       (RESET)
    );


    // ─────────────────────────────────────────────────────────────────────────
    //  Two's Complement Unit  (delay #1)
    // ─────────────────────────────────────────────────────────────────────────

    // Used for sub (negate RS before adding) and beq/bne (subtract to check equality)
    wire [7:0] NEGATED_REGOUT2;
    assign #1 NEGATED_REGOUT2 = ~REGOUT2 + 8'b1;

    // MUX1: select negated or un-negated REGOUT2
    wire [7:0] MUX1_OUT;
    assign MUX1_OUT = MUX_NEG_SEL ? NEGATED_REGOUT2 : REGOUT2;

    // MUX2: select register value (MUX1_OUT) or IMMEDIATE as ALU DATA2
    wire [7:0] ALU_DATA2;
    assign ALU_DATA2 = MUX_IMM_SEL ? IMMEDIATE : MUX1_OUT;


    // ─────────────────────────────────────────────────────────────────────────
    //  ALU  (Lab 4.5 extended version)
    // ─────────────────────────────────────────────────────────────────────────

    wire ZERO;   // asserted when ALURESULT == 0; used by beq / bne

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


    // ─────────────────────────────────────────────────────────────────────────
    //  Data Memory Address & Write-Data
    // ─────────────────────────────────────────────────────────────────────────
    //
    //  For lwd / swd:
    //    RS register value → REGOUT2 → ALU forward (ALUOP=000) → ALURESULT = address
    //    MEM_ADDR_IMM=0  → MEM_ADDRESS = ALURESULT
    //
    //  For lwi / swi:
    //    IMMEDIATE field is the byte address directly
    //    MEM_ADDR_IMM=1  → MEM_ADDRESS = IMMEDIATE  (bypasses the ALU)
    //
    //  Store data always comes from RT (REGOUT1) regardless of addressing mode.

    assign MEM_ADDRESS   = MEM_ADDR_IMM ? IMMEDIATE : ALURESULT;
    assign MEM_WRITEDATA = REGOUT1;


    // ─────────────────────────────────────────────────────────────────────────
    //  PC & Branch / Jump Logic
    // ─────────────────────────────────────────────────────────────────────────

    // PC+4 adder (runs in parallel with instruction memory read; delay #1)
    wire [31:0] PC_PLUS4;
    assign #1 PC_PLUS4 = PC + 32'd4;

    // Sign-extend the 8-bit offset in RD_ADDR to 32 bits and scale by 4
    // (each instruction is 4 bytes, so a ±1 offset = ±4 bytes)
    wire [31:0] OFFSET_EXTENDED;
    assign OFFSET_EXTENDED = {{22{RD_ADDR[7]}}, RD_ADDR, 2'b00};

    // Branch / jump target adder (runs in parallel with ALU; delay #2)
    wire [31:0] BRANCH_TARGET;
    assign #2 BRANCH_TARGET = PC_PLUS4 + OFFSET_EXTENDED;

    // PC source select:
    //   JUMP=1                 → j:   always take branch
    //   BRANCH=1 and ZERO=1    → beq: take branch if RT==RS
    //   BRANCH_NE=1 and ZERO=0 → bne: take branch if RT!=RS
    wire PC_SEL;
    assign PC_SEL = JUMP | (BRANCH & ZERO) | (BRANCH_NE & ~ZERO);

    // While STALL is high (data-memory OR instruction-cache busy), keep PC
    // unchanged so the same instruction/address keeps being re-presented.
    wire [31:0] PC_NEXT;
    assign PC_NEXT = STALL  ? PC            :
                     PC_SEL ? BRANCH_TARGET :
                              PC_PLUS4;

    pc mypc(
        .PC    (PC),
        .PC_IN (PC_NEXT),
        .CLK   (CLK),
        .RESET (RESET)
    );


    // ─────────────────────────────────────────────────────────────────────────
    //  Combinational Control Unit  (fires on every OPCODE change)
    //
    //  OPCODE is derived from INSTRUCTION which changes ~3 time units after each
    //  PC update (1 for PC register + 2 for instruction memory read).
    //  During a stall, PC does not change → OPCODE does not change → this block
    //  does NOT re-fire, keeping all control signals stable throughout the stall.
    // ─────────────────────────────────────────────────────────────────────────

    always @(OPCODE)
    begin

        // ── Safe defaults: no side-effects ────────────────────────────────
        WRITEENABLE    = 1'b0;
        MUX_IMM_SEL    = 1'b0;
        MUX_NEG_SEL    = 1'b0;
        ALUOP          = 3'b000;
        JUMP           = 1'b0;
        BRANCH         = 1'b0;
        BRANCH_NE      = 1'b0;
        SHIFT_DIR      = 1'b0;
        ARITH          = 1'b0;
        ROTATE         = 1'b0;
        CTRL_MEM_READ  = 1'b0;
        CTRL_MEM_WRITE = 1'b0;
        MEM_TO_REG     = 1'b0;
        MEM_ADDR_IMM   = 1'b0;

        // Instruction decode latency (#1 time unit)
        #1;

        case (OPCODE)

            // ── loadi  RD, IMM ────────────────────────────────────────────
            8'h00: begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;
                ALUOP       = 3'b000;   // forward IMMEDIATE through ALU
            end

            // ── mov  RD, RT ───────────────────────────────────────────────
            // Source placed in RS slot; ALU forwards REGOUT2 (=RS) to RESULT
            8'h01: begin
                WRITEENABLE = 1'b1;
                ALUOP       = 3'b000;
            end

            // ── add  RD, RT, RS ───────────────────────────────────────────
            8'h02: begin
                WRITEENABLE = 1'b1;
                ALUOP       = 3'b001;
            end

            // ── sub  RD, RT, RS ───────────────────────────────────────────
            8'h03: begin
                WRITEENABLE = 1'b1;
                MUX_NEG_SEL = 1'b1;    // negate RS, then add
                ALUOP       = 3'b001;
            end

            // ── and  RD, RT, RS ───────────────────────────────────────────
            8'h04: begin
                WRITEENABLE = 1'b1;
                ALUOP       = 3'b010;
            end

            // ── or  RD, RT, RS ────────────────────────────────────────────
            8'h05: begin
                WRITEENABLE = 1'b1;
                ALUOP       = 3'b011;
            end

            // ── j  OFFSET ─────────────────────────────────────────────────
            8'h06: begin
                JUMP  = 1'b1;
                ALUOP = 3'b000;        // ALU unused; forward is harmless
            end

            // ── beq  OFFSET, RT, RS ───────────────────────────────────────
            8'h07: begin
                MUX_NEG_SEL = 1'b1;    // RT - RS → ZERO flag
                ALUOP       = 3'b001;
                BRANCH      = 1'b1;
            end

            // ── mult  RD, RT, RS  [Lab 4.5] ──────────────────────────────
            8'h08: begin
                WRITEENABLE = 1'b1;
                ALUOP       = 3'b100;
            end

            // ── sll  RD, RT, IMM  [Lab 4.5] ──────────────────────────────
            8'h09: begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;
                ALUOP       = 3'b101;
                SHIFT_DIR   = 1'b0;
                ARITH       = 1'b0;
                ROTATE      = 1'b0;
            end

            // ── srl  RD, RT, IMM  [Lab 4.5] ──────────────────────────────
            8'h0A: begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;
                ALUOP       = 3'b101;
                SHIFT_DIR   = 1'b1;
                ARITH       = 1'b0;
                ROTATE      = 1'b0;
            end

            // ── sra  RD, RT, IMM  [Lab 4.5] ──────────────────────────────
            8'h0B: begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;
                ALUOP       = 3'b101;
                SHIFT_DIR   = 1'b1;
                ARITH       = 1'b1;
                ROTATE      = 1'b0;
            end

            // ── ror  RD, RT, IMM  [Lab 4.5] ──────────────────────────────
            8'h0C: begin
                WRITEENABLE = 1'b1;
                MUX_IMM_SEL = 1'b1;
                ALUOP       = 3'b101;
                ROTATE      = 1'b1;
            end

            // ── bne  OFFSET, RT, RS  [Lab 4.5] ───────────────────────────
            8'h0D: begin
                MUX_NEG_SEL = 1'b1;
                ALUOP       = 3'b001;
                BRANCH_NE   = 1'b1;
            end

            // ── lwd  RD, RS  [Lab 5] ──────────────────────────────────────
            //
            //  Load word (register-direct addressing):  RD = mem[RS]
            //  Instruction encoding: [OPCODE=0x10][RD][ignored][RS]
            //
            //  Datapath:
            //    decode #1 → reg-read #2 (RS via REGOUT2) →
            //    ALU forward #1 (ALURESULT = RS value = address) →
            //    BUSYWAIT stall (5 CLK cycles × 8 units = #40 in memory) →
            //    data arrives on MEM_READDATA → register write #1 to RD
            //
            //  MEM_ADDR_IMM=0 → MEM_ADDRESS comes from ALU (= REGOUT2 = RS)
            //  ALUOP=000 (forward) → ALURESULT = ALU_DATA2 = REGOUT2 = RS
            //  MEM_TO_REG=1 → REG_WRITEDATA = MEM_READDATA (not ALURESULT)
            //  WRITE_GATED = WRITEENABLE & ~BUSYWAIT → write only after stall ends

            8'h10: begin
                WRITEENABLE    = 1'b1;
                MUX_IMM_SEL    = 1'b0;    // DATA2 = REGOUT2 = RS register value
                MUX_NEG_SEL    = 1'b0;
                ALUOP          = 3'b000;   // forward RS as memory address
                CTRL_MEM_READ  = 1'b1;    // request memory read
                CTRL_MEM_WRITE = 1'b0;
                MEM_ADDR_IMM   = 1'b0;    // address from ALU result (= RS)
                MEM_TO_REG     = 1'b1;    // write read data to RD
            end

            // ── lwi  RD, IMM  [Lab 5] ─────────────────────────────────────
            //
            //  Load word (immediate addressing):  RD = mem[IMM]
            //  Instruction encoding: [OPCODE=0x11][RD][ignored][IMM]
            //
            //  Datapath:
            //    decode #1 →
            //    BUSYWAIT stall (address = IMMEDIATE, no register read needed) →
            //    data arrives → register write #1 to RD
            //
            //  MEM_ADDR_IMM=1 → MEM_ADDRESS = IMMEDIATE (direct from instruction)
            //  No need to route through ALU for the address.

            8'h11: begin
                WRITEENABLE    = 1'b1;
                MUX_IMM_SEL    = 1'b1;    // (not used for address since MEM_ADDR_IMM=1)
                MUX_NEG_SEL    = 1'b0;
                ALUOP          = 3'b000;
                CTRL_MEM_READ  = 1'b1;
                CTRL_MEM_WRITE = 1'b0;
                MEM_ADDR_IMM   = 1'b1;    // address = IMMEDIATE
                MEM_TO_REG     = 1'b1;
            end

            // ── swd  RT, RS  [Lab 5] ──────────────────────────────────────
            //
            //  Store word (register-direct addressing):  mem[RS] = RT
            //  Instruction encoding: [OPCODE=0x12][ignored][RT][RS]
            //
            //  Datapath:
            //    decode #1 → reg-read #2 (both RT for data, RS for address) →
            //    ALU forward #1 (ALURESULT = RS value = address) →
            //    BUSYWAIT stall → memory commits data
            //
            //  REGOUT1 (RT) → MEM_WRITEDATA (store data)
            //  REGOUT2 (RS) → ALU forward → ALURESULT → MEM_ADDRESS
            //  WRITEENABLE=0 (no register write for store instructions)

            8'h12: begin
                WRITEENABLE    = 1'b0;    // store: no register write
                MUX_IMM_SEL    = 1'b0;   // DATA2 = REGOUT2 = RS = address
                MUX_NEG_SEL    = 1'b0;
                ALUOP          = 3'b000;  // forward RS as address
                CTRL_MEM_READ  = 1'b0;
                CTRL_MEM_WRITE = 1'b1;   // request memory write
                MEM_ADDR_IMM   = 1'b0;   // address from ALU (= RS register)
                MEM_TO_REG     = 1'b0;
            end

            // ── swi  RT, IMM  [Lab 5] ─────────────────────────────────────
            //
            //  Store word (immediate addressing):  mem[IMM] = RT
            //  Instruction encoding: [OPCODE=0x13][ignored][RT][IMM]
            //
            //  Datapath:
            //    decode #1 → reg-read #2 (RT for data) →
            //    BUSYWAIT stall → memory commits data
            //
            //  MEM_ADDR_IMM=1 → MEM_ADDRESS = IMMEDIATE (no ALU for address)
            //  REGOUT1 (RT) → MEM_WRITEDATA
            //  WRITEENABLE=0 (no register write)

            8'h13: begin
                WRITEENABLE    = 1'b0;
                MUX_IMM_SEL    = 1'b0;
                MUX_NEG_SEL    = 1'b0;
                ALUOP          = 3'b000;
                CTRL_MEM_READ  = 1'b0;
                CTRL_MEM_WRITE = 1'b1;   // request memory write
                MEM_ADDR_IMM   = 1'b1;   // address = IMMEDIATE
                MEM_TO_REG     = 1'b0;
            end

            // ── Default: unknown/NOP ──────────────────────────────────────
            default: begin
                WRITEENABLE    = 1'b0;
                MUX_IMM_SEL    = 1'b0;
                MUX_NEG_SEL    = 1'b0;
                ALUOP          = 3'b000;
                JUMP           = 1'b0;
                BRANCH         = 1'b0;
                BRANCH_NE      = 1'b0;
                SHIFT_DIR      = 1'b0;
                ARITH          = 1'b0;
                ROTATE         = 1'b0;
                CTRL_MEM_READ  = 1'b0;
                CTRL_MEM_WRITE = 1'b0;
                MEM_TO_REG     = 1'b0;
                MEM_ADDR_IMM   = 1'b0;
            end

        endcase

    end

endmodule
