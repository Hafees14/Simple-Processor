// Computer Architecture CO2070 - Lab 04
// Design: Testbench for Lab 4 CPU (j and beq instructions)
// Team  : 06
// Members : E/22/014, E/22/035

// Test program overview:
//   loadi r1, 10          // r1 = 10
//   loadi r2, 10          // r2 = 10
//   loadi r3, 5           // r3 = 5
//   beq   +1, r1, r2      // r1 == r2, so skip next instruction (branch taken)
//   loadi r4, 0xFF        // ** skipped **
//   loadi r4, 0xBB        // r4 = 0xBB  (first instruction after branch)
//   beq   +1, r1, r3      // r1 != r3, so NOT taken (branch not taken)
//   loadi r5, 0xAA        // r5 = 0xAA  (executed because branch not taken)
//   j     +1              // jump forward 1 instruction (skip next)
//   loadi r6, 0xDE        // ** skipped by j **
//   loadi r6, 0xFF        // r6 = 0xFF  (first instruction after jump target)
//   loadi r7, 0x77        // r7 = 0x77  (normal sequential)

`include "cpu.v"

`timescale 1ns/100ps

module cpu_tb;

    reg  CLK, RESET;
    wire [31:0] PC;
    wire [31:0] INSTRUCTION;

    // Instruction memory – 1 KB byte array
    reg [7:0] instr_mem [0:1023];

    // Instruction fetch with memory access delay (#2 per timing diagram)
    assign #2 INSTRUCTION = {
        instr_mem[PC],
        instr_mem[PC + 1],
        instr_mem[PC + 2],
        instr_mem[PC + 3]
    };

    // ── Instruction Memory Initialisation ────────────────────────────────────
    // Each instruction occupies 4 bytes (big-endian):
    //   [0] = OPCODE, [1] = RD/OFFSET, [2] = RT, [3] = RS/IMM

    initial
    begin

        // ── Instruction 0 (address 0x00): loadi r1, 10 ──────────────────────
        instr_mem[0]  = 8'h00;   // OPCODE loadi
        instr_mem[1]  = 8'h01;   // RD = r1
        instr_mem[2]  = 8'h00;   // RT ignored
        instr_mem[3]  = 8'h0A;   // IMM = 10

        // ── Instruction 1 (address 0x04): loadi r2, 10 ──────────────────────
        instr_mem[4]  = 8'h00;
        instr_mem[5]  = 8'h02;   // RD = r2
        instr_mem[6]  = 8'h00;
        instr_mem[7]  = 8'h0A;   // IMM = 10

        // ── Instruction 2 (address 0x08): loadi r3, 5 ───────────────────────
        instr_mem[8]  = 8'h00;
        instr_mem[9]  = 8'h03;   // RD = r3
        instr_mem[10] = 8'h00;
        instr_mem[11] = 8'h05;   // IMM = 5

        // ── Instruction 3 (address 0x0C): beq +1, r1, r2 ────────────────────
        // r1 == r2 (both 10), so branch is TAKEN.
        // OFFSET = 0x01 means skip 1 instruction forward from PC+4
        // Target = (0x0C + 4) + (1 * 4) = 0x14
        instr_mem[12] = 8'h07;   // OPCODE beq
        instr_mem[13] = 8'h01;   // OFFSET = +1
        instr_mem[14] = 8'h01;   // RT = r1
        instr_mem[15] = 8'h02;   // RS = r2

        // ── Instruction 4 (address 0x10): loadi r4, 0xFF  (SHOULD BE SKIPPED) ─
        instr_mem[16] = 8'h00;
        instr_mem[17] = 8'h04;   // RD = r4
        instr_mem[18] = 8'h00;
        instr_mem[19] = 8'hFF;   // IMM = 0xFF (must NOT appear in r4)

        // ── Instruction 5 (address 0x14): loadi r4, 0xBB ────────────────────
        // Execution resumes here after the taken beq above
        instr_mem[20] = 8'h00;
        instr_mem[21] = 8'h04;   // RD = r4
        instr_mem[22] = 8'h00;
        instr_mem[23] = 8'hBB;   // IMM = 0xBB (r4 should become 0xBB)

        // ── Instruction 6 (address 0x18): beq +1, r1, r3 ────────────────────
        // r1 = 10, r3 = 5, they are NOT equal, branch NOT taken.
        // Execution continues sequentially to 0x1C.
        instr_mem[24] = 8'h07;   // OPCODE beq
        instr_mem[25] = 8'h01;   // OFFSET = +1
        instr_mem[26] = 8'h01;   // RT = r1
        instr_mem[27] = 8'h03;   // RS = r3

        // ── Instruction 7 (address 0x1C): loadi r5, 0xAA ────────────────────
        // Runs because the preceding beq was NOT taken
        instr_mem[28] = 8'h00;
        instr_mem[29] = 8'h05;   // RD = r5
        instr_mem[30] = 8'h00;
        instr_mem[31] = 8'hAA;   // IMM = 0xAA (r5 should become 0xAA)

        // ── Instruction 8 (address 0x20): j +1 ──────────────────────────────
        // Unconditional jump forward 1 instruction.
        // OFFSET = 0x01. Bits[15:0] are ignored.
        // Target = (0x20 + 4) + (1 * 4) = 0x28
        instr_mem[32] = 8'h06;   // OPCODE j
        instr_mem[33] = 8'h01;   // OFFSET = +1
        instr_mem[34] = 8'h00;   // ignored
        instr_mem[35] = 8'h00;   // ignored

        // ── Instruction 9 (address 0x24): loadi r6, 0xDE  (SHOULD BE SKIPPED) ─
        instr_mem[36] = 8'h00;
        instr_mem[37] = 8'h06;   // RD = r6
        instr_mem[38] = 8'h00;
        instr_mem[39] = 8'hDE;   // IMM = 0xDE (must NOT appear in r6)

        // ── Instruction 10 (address 0x28): loadi r6, 0xFF ───────────────────
        // Execution resumes here after the j above
        instr_mem[40] = 8'h00;
        instr_mem[41] = 8'h06;   // RD = r6
        instr_mem[42] = 8'h00;
        instr_mem[43] = 8'hFF;   // IMM = 0xFF (r6 should become 0xFF)

        // ── Instruction 11 (address 0x2C): loadi r7, 0x77 ───────────────────
        instr_mem[44] = 8'h00;
        instr_mem[45] = 8'h07;   // RD = r7
        instr_mem[46] = 8'h00;
        instr_mem[47] = 8'h77;   // IMM = 0x77 (r7 should become 0x77)

    end

    // ── DUT Instantiation ────────────────────────────────────────────────────

    cpu mycpu(PC, INSTRUCTION, CLK, RESET);

    // ── Simulation Control ───────────────────────────────────────────────────

    initial
    begin

        // Waveform dump for GTKWave
        $dumpfile("cpu_wavedata.vcd");
        $dumpvars(0, cpu_tb);

        CLK   = 1'b0;
        RESET = 1'b0;

        // Assert RESET for one full clock period to initialise the PC and registers
        #2  RESET = 1'b1;
        #10 RESET = 1'b0;

        // Run long enough to execute all 12 instructions
        // 12 instructions x 8 ns/cycle + reset overhead = well under 200 ns
        #200
        $finish;

    end

    // Clock: period = 8 ns  (toggle every 4 ns)
    always
        #4 CLK = ~CLK;

endmodule
