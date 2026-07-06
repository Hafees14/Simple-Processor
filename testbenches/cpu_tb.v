// Computer Architecture (CO2070) - Lab 03
// Design: Testbench of Integrated CPU of Simple Processor
// Author: Isuru Nawinne
// Group 06 (E/22/014, E/22/035)

`include "cpu.v"

`timescale 1ns/100ps

module cpu_tb;

    reg CLK, RESET;
    wire [31:0] PC;
    wire [31:0] INSTRUCTION;

   
    // SIMPLE Instruction memory (1024 bytes)
    
    reg [7:0] instr_mem [0:1023];

    // Instruction fetch with memory access delay
    assign #2 INSTRUCTION = {
        instr_mem[PC],
        instr_mem[PC+1],
        instr_mem[PC+2],
        instr_mem[PC+3]
    };

    initial
    begin

        // loadi r1,10
        instr_mem[0]  = 8'h00; // OPCODE for loadi
        instr_mem[1]  = 8'h01; // RD = r1
        instr_mem[2]  = 8'h00; // IMMEDIATE = 10
        instr_mem[3]  = 8'h0A; // (hex for 10)

        // loadi r2,5
        instr_mem[4]  = 8'h00; // OPCODE for loadi
        instr_mem[5]  = 8'h02; // RD = r2
        instr_mem[6]  = 8'h00; // IMMEDIATE = 5
        instr_mem[7]  = 8'h05; // (hex for 5)

        // add r3,r1,r2
        instr_mem[8]  = 8'h02; // OPCODE for add
        instr_mem[9]  = 8'h03; // RD = r3
        instr_mem[10] = 8'h01; // RS = r1
        instr_mem[11] = 8'h02; // RT = r2

        // sub r4,r1,r2
        instr_mem[12] = 8'h03; // OPCODE for sub
        instr_mem[13] = 8'h04; // RD = r4
        instr_mem[14] = 8'h01; // RS = r1
        instr_mem[15] = 8'h02; // RT = r2
        instr_mem[15] = 8'h02; // RT = r2 (duplicate instruction to test PC+4 adder running in parallel with mem read)

        // and r5,r1,r2
        instr_mem[16] = 8'h04; // OPCODE for and
        instr_mem[17] = 8'h05; // RD = r5
        instr_mem[18] = 8'h01; // RS = r1
        instr_mem[19] = 8'h02; // RT = r2

        // or r6,r1,r2
        instr_mem[20] = 8'h05; // OPCODE for or
        instr_mem[21] = 8'h06; // RD = r6
        instr_mem[22] = 8'h01; // RS = r1
        instr_mem[23] = 8'h02; // RT = r2

        // mov r7,r1
        instr_mem[24] = 8'h01; // OPCODE for mov
        instr_mem[25] = 8'h07; // RD = r7
        instr_mem[26] = 8'h00; // RS = r0
        instr_mem[27] = 8'h01; // RT = r1

        // loadi r0,255
        instr_mem[28] = 8'h00; // OPCODE for loadi
        instr_mem[29] = 8'h00; // RD = r0
        instr_mem[30] = 8'h00; // IMMEDIATE = 255
        instr_mem[31] = 8'hFF; // (hex for 255)


    end

    /* 
    -----
     CPU
    -----
    */
    cpu mycpu(PC, INSTRUCTION, CLK, RESET);

    initial
    begin

        // generate files needed to plot the waveform using GTKWave
        $dumpfile("cpu_wavedata.vcd");
        $dumpvars(0, cpu_tb);

        CLK = 1'b0;
        RESET = 1'b0;

        // Reset pulse
        #2 RESET = 1'b1;
        #10 RESET = 1'b0;

        // finish simulation after some time
        #160
        $finish;

    end

    // clock signal generation
    always
        #4 CLK = ~CLK;

endmodule
