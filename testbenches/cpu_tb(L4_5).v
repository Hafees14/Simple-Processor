// Computer Architecture CO2070 - Lab 04.5
// Design: Testbench for Extended ISA CPU
// Team  : 06
// Members : E/22/014, E/22/035

// Test program overview:
//   ── Setup ──
//   loadi r1, 3             // r1 = 3
//   loadi r2, 4             // r2 = 4
//   loadi r3, 0xFF          // r3 = 0xFF  (11111111b, negative in two's complement)
//
//   ── mult ──
//   mult  r4, r1, r2        // r4 = r1 * r2 = 3 * 4 = 12 = 0x0C
//
//   ── sll ──
//   sll   r5, r1, 0x02      // r5 = r1 << 2 = 3 << 2 = 12 = 0x0C
//
//   ── srl ──
//   srl   r6, r2, 0x01      // r6 = r2 >> 1 = 4 >> 1 = 2  (logical, MSB fills with 0)
//
//   ── sra ──
//   sra   r7, r3, 0x02      // r7 = r3 >>> 2 = 0xFF >>> 2 = 0xFE (sign-extended)
//                            //   0xFF = 11111111b, sra 2 -> 11111111b = 0xFF
//                            //   wait -- 11111111 >>> 2 = 11111111 (sign = 1 fills in)
//                            //   expected: 0xFF
//
//   ── ror ──
//   loadi r0, 0x81           // r0 = 0x81 = 10000001b
//   ror   r5, r0, 0x01       // r5 = rotate_right(0x81, 1) = 11000000b = 0xC0
//                             //   LSB (1) wraps to MSB
//
//   ── bne (branch taken) ──
//   loadi r1, 5              // r1 = 5  (r1 != r2=4, so branch TAKEN)
//   bne   +1, r1, r2         // r1 != r2 → skip next instruction
//   loadi r6, 0xDE           // ** SKIPPED **
//   loadi r6, 0xAA           // r6 = 0xAA  (first instruction after branch target)
//
//   ── bne (branch not taken) ──
//   loadi r1, 4              // r1 = 4  (r1 == r2=4, branch NOT taken)
//   bne   +1, r1, r2         // r1 == r2 → NOT taken
//   loadi r7, 0xBB           // r7 = 0xBB  (executes because branch not taken)

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

        // ── Instruction 0 (0x00): loadi r1, 3 ──────────────────────────────
        instr_mem[0]  = 8'h00;   // OPCODE loadi
        instr_mem[1]  = 8'h01;   // RD = r1
        instr_mem[2]  = 8'h00;   // RT ignored
        instr_mem[3]  = 8'h03;   // IMM = 3

        // ── Instruction 1 (0x04): loadi r2, 4 ──────────────────────────────
        instr_mem[4]  = 8'h00;
        instr_mem[5]  = 8'h02;   // RD = r2
        instr_mem[6]  = 8'h00;
        instr_mem[7]  = 8'h04;   // IMM = 4

        // ── Instruction 2 (0x08): loadi r3, 0xFF ────────────────────────────
        instr_mem[8]  = 8'h00;
        instr_mem[9]  = 8'h03;   // RD = r3
        instr_mem[10] = 8'h00;
        instr_mem[11] = 8'hFF;   // IMM = 0xFF

        // ── Instruction 3 (0x0C): mult r4, r1, r2 ───────────────────────────
        // r4 = r1 * r2 = 3 * 4 = 12 = 0x0C
        // Opcode 8'b00001000 = 8'h08
        instr_mem[12] = 8'h08;   // OPCODE mult
        instr_mem[13] = 8'h04;   // RD = r4
        instr_mem[14] = 8'h01;   // RT = r1
        instr_mem[15] = 8'h02;   // RS = r2

        // ── Instruction 4 (0x10): sll r5, r1, 0x02 ─────────────────────────
        // r5 = r1 << 2 = 3 << 2 = 12 = 0x0C
        // Opcode 8'b00001001 = 8'h09
        // RT field carries the source register (r1); IMM field carries shift amount (2)
        instr_mem[16] = 8'h09;   // OPCODE sll
        instr_mem[17] = 8'h05;   // RD = r5
        instr_mem[18] = 8'h01;   // RT = r1  (value to shift, read as REGOUT1)
        instr_mem[19] = 8'h02;   // IMM = 2  (shift amount)

        // ── Instruction 5 (0x14): srl r6, r2, 0x01 ─────────────────────────
        // r6 = r2 >> 1 = 4 >> 1 = 2 (logical, zero fill)
        // Opcode 8'b00001010 = 8'h0A
        instr_mem[20] = 8'h0A;   // OPCODE srl
        instr_mem[21] = 8'h06;   // RD = r6
        instr_mem[22] = 8'h02;   // RT = r2  (value to shift)
        instr_mem[23] = 8'h01;   // IMM = 1  (shift amount)

        // ── Instruction 6 (0x18): sra r7, r3, 0x02 ─────────────────────────
        // r7 = r3 >>> 2 = 0xFF >>> 2 = 0xFF (sign bit = 1, fills in 1s)
        //   0xFF = 11111111b, arithmetic right-shift 2 = 11111111b = 0xFF
        // Opcode 8'b00001011 = 8'h0B
        instr_mem[24] = 8'h0B;   // OPCODE sra
        instr_mem[25] = 8'h07;   // RD = r7
        instr_mem[26] = 8'h03;   // RT = r3  (value = 0xFF)
        instr_mem[27] = 8'h02;   // IMM = 2  (shift amount)

        // ── Instruction 7 (0x1C): loadi r0, 0x81 ────────────────────────────
        // r0 = 0x81 = 10000001b  (used as rotate input)
        instr_mem[28] = 8'h00;
        instr_mem[29] = 8'h00;   // RD = r0
        instr_mem[30] = 8'h00;
        instr_mem[31] = 8'h81;   // IMM = 0x81

        // ── Instruction 8 (0x20): ror r5, r0, 0x01 ──────────────────────────
        // r5 = rotate_right(r0, 1) = rotate_right(0x81, 1)
        //   0x81 = 10000001b, rotate right 1 -> 11000000b = 0xC0
        //   (LSB '1' wraps to MSB)
        // Opcode 8'b00001100 = 8'h0C
        instr_mem[32] = 8'h0C;   // OPCODE ror
        instr_mem[33] = 8'h05;   // RD = r5
        instr_mem[34] = 8'h00;   // RT = r0  (value to rotate)
        instr_mem[35] = 8'h01;   // IMM = 1  (rotate amount)

        // ── Instruction 9 (0x24): loadi r1, 5 ───────────────────────────────
        // Reload r1 = 5 so that r1 != r2 (r2 = 4), making bne TAKEN
        instr_mem[36] = 8'h00;
        instr_mem[37] = 8'h01;   // RD = r1
        instr_mem[38] = 8'h00;
        instr_mem[39] = 8'h05;   // IMM = 5

        // ── Instruction 10 (0x28): bne +1, r1, r2 ───────────────────────────
        // r1 = 5, r2 = 4  →  r1 != r2  → branch TAKEN
        // OFFSET = +1 → skip next instruction
        // Target = (0x28 + 4) + (1 * 4) = 0x30
        // Opcode 8'b00001101 = 8'h0D
        instr_mem[40] = 8'h0D;   // OPCODE bne
        instr_mem[41] = 8'h01;   // OFFSET = +1
        instr_mem[42] = 8'h01;   // RT = r1
        instr_mem[43] = 8'h02;   // RS = r2

        // ── Instruction 11 (0x2C): loadi r6, 0xDE  (SHOULD BE SKIPPED) ──────
        instr_mem[44] = 8'h00;
        instr_mem[45] = 8'h06;   // RD = r6
        instr_mem[46] = 8'h00;
        instr_mem[47] = 8'hDE;   // IMM = 0xDE  (must NOT appear in r6)

        // ── Instruction 12 (0x30): loadi r6, 0xAA ───────────────────────────
        // Execution resumes here after the taken bne above
        instr_mem[48] = 8'h00;
        instr_mem[49] = 8'h06;   // RD = r6
        instr_mem[50] = 8'h00;
        instr_mem[51] = 8'hAA;   // IMM = 0xAA  (r6 should become 0xAA)

        // ── Instruction 13 (0x34): loadi r1, 4 ──────────────────────────────
        // Reload r1 = 4 so that r1 == r2 (r2 = 4), making bne NOT TAKEN
        instr_mem[52] = 8'h00;
        instr_mem[53] = 8'h01;   // RD = r1
        instr_mem[54] = 8'h00;
        instr_mem[55] = 8'h04;   // IMM = 4

        // ── Instruction 14 (0x38): bne +1, r1, r2 ───────────────────────────
        // r1 = 4, r2 = 4  →  r1 == r2  → branch NOT taken
        instr_mem[56] = 8'h0D;   // OPCODE bne
        instr_mem[57] = 8'h01;   // OFFSET = +1
        instr_mem[58] = 8'h01;   // RT = r1
        instr_mem[59] = 8'h02;   // RS = r2

        // ── Instruction 15 (0x3C): loadi r7, 0xBB ───────────────────────────
        // Runs because the preceding bne was NOT taken
        instr_mem[60] = 8'h00;
        instr_mem[61] = 8'h07;   // RD = r7
        instr_mem[62] = 8'h00;
        instr_mem[63] = 8'hBB;   // IMM = 0xBB  (r7 should become 0xBB)

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

        // Run long enough to execute all 16 instructions
        // 16 instructions x 8 ns/cycle = 128 ns + reset overhead (~12 ns)
        // Add margin: 200 ns total
        #200
        $finish;

    end

    // Clock: period = 8 ns  (toggle every 4 ns)
    always
        #4 CLK = ~CLK;

    // ── Expected Results Monitor ─────────────────────────────────────────────
    // Prints register file state at the end of simulation for verification.
    //
    // Expected final register values:
    //   r0 = 0x81  (loadi)
    //   r1 = 0x04  (loadi 4 - last write)
    //   r2 = 0x04  (loadi 4)
    //   r3 = 0xFF  (loadi)
    //   r4 = 0x0C  (mult: 3*4=12)
    //   r5 = 0xC0  (ror: rotate_right(0x81,1) = 0xC0, overwrites sll result)
    //   r6 = 0xAA  (loadi after taken bne)
    //   r7 = 0xBB  (loadi after not-taken bne, overwrites sra result)

    initial
    begin
        // Wait until all 16 instructions have completed
        // Reset ends at ~12 ns; 16 cycles x 8 ns = 128 ns; total ~140 ns
        #150;
        $display("----------------------------------------------");
        $display("Lab 4.5 Extended ISA - Final Register Dump");
        $display("----------------------------------------------");
        $display("r0 = 0x%02h  (expected 0x81)", mycpu.rf.registers[0]);
        $display("r1 = 0x%02h  (expected 0x04)", mycpu.rf.registers[1]);
        $display("r2 = 0x%02h  (expected 0x04)", mycpu.rf.registers[2]);
        $display("r3 = 0x%02h  (expected 0xFF)", mycpu.rf.registers[3]);
        $display("r4 = 0x%02h  (expected 0x0C  - mult 3*4=12)", mycpu.rf.registers[4]);
        $display("r5 = 0x%02h  (expected 0xC0  - ror(0x81,1))", mycpu.rf.registers[5]);
        $display("r6 = 0x%02h  (expected 0xAA  - bne taken, skip 0xDE)", mycpu.rf.registers[6]);
        $display("r7 = 0x%02h  (expected 0xBB  - bne not taken)", mycpu.rf.registers[7]);
        $display("----------------------------------------------");
    end

endmodule
