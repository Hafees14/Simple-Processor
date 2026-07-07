// Computer Architecture CO2070 - Lab 05
// Design: Testbench – CPU with Data Memory
// Team  : 06
// Members : E/22/014, E/22/035

//  TEST PROGRAM OVERVIEW

//  Program 1 – basic store and load (immediate addressing)
//  ─────────────────────────────────────────────────────
//  loadi r1, 0x42          // r1 = 0x42 = 66d
//  swi   r1, 0x10          // mem[0x10] = 0x42
//  lwi   r2, 0x10          // r2 = mem[0x10] = 0x42  (should match r1)
//  loadi r3, 0x99          // r3 = 0x99
//  swi   r3, 0x20          // mem[0x20] = 0x99
//  lwi   r4, 0x20          // r4 = mem[0x20] = 0x99

//  Program 2 – register-direct store and load (lwd / swd)
//  ──────────────────────────────────────────────────────
//  loadi r5, 0x30          // r5 = 0x30  (address)
//  loadi r6, 0xAB          // r6 = 0xAB  (data to store)
//  swd   r6, r5            // mem[r5=0x30] = r6 = 0xAB
//  lwd   r7, r5            // r7 = mem[r5=0x30] = 0xAB

//  Program 3 – ALU then store result  (add result into memory)
//  ────────────────────────────────────────────────────────────
//  loadi r1, 0x0F          // r1 = 15
//  loadi r2, 0x11          // r2 = 17
//  add   r3, r1, r2        // r3 = 15 + 17 = 32 = 0x20
//  swi   r3, 0x50          // mem[0x50] = 0x20
//  lwi   r0, 0x50          // r0 = mem[0x50] = 0x20  (verify)

//  Program 4 – load, modify, store  (memory data processing loop concept)
//  ────────────────────────────────────────────────────────────────────────
//  loadi r1, 0x01          // r1 = 1
//  swi   r1, 0x60          // mem[0x60] = 1
//  lwi   r2, 0x60          // r2 = 1
//  loadi r3, 0x09          // r3 = 9
//  add   r4, r2, r3        // r4 = r2 + r3 = 10 = 0x0A
//  swi   r4, 0x61          // mem[0x61] = 0x0A
//  lwi   r5, 0x61          // r5 = 0x0A  (verify)
//
// ══════════════════════════════════════════════════════════════════════════════

`include "cpu.v"
`include "data_memory.v"

`timescale 1ns/100ps

module cpu_tb;

    // ── DUT Interface Signals ─────────────────────────────────────────────────

    reg         CLK;
    reg         RESET;
    wire [31:0] PC;
    wire [31:0] INSTRUCTION;

    // Data memory interface wires between CPU and data memory
    wire        MEM_READ;
    wire        MEM_WRITE;
    wire [7:0]  MEM_ADDRESS;
    wire [7:0]  MEM_WRITEDATA;
    wire [7:0]  MEM_READDATA;
    wire        MEM_BUSYWAIT;

    // Instruction Memory 
    // 1 KB byte-addressed array (holds up to 256 × 32-bit instructions)
    // Read asynchronously with #2 latency (simulates instruction memory delay)

    reg [7:0] instr_mem [0:1023];

    assign #2 INSTRUCTION = {
        instr_mem[PC],
        instr_mem[PC + 1],
        instr_mem[PC + 2],
        instr_mem[PC + 3]
    };

    //  DUT Instantiation 

    cpu dut(
        .PC           (PC),
        .INSTRUCTION  (INSTRUCTION),
        .CLK          (CLK),
        .RESET        (RESET),
        .MEM_READ     (MEM_READ),
        .MEM_WRITE    (MEM_WRITE),
        .MEM_ADDRESS  (MEM_ADDRESS),
        .MEM_WRITEDATA(MEM_WRITEDATA),
        .MEM_READDATA (MEM_READDATA),
        .MEM_BUSYWAIT (MEM_BUSYWAIT)
    );

    // Data Memory Instantiation

    data_memory dmem(
        .clock     (CLK),
        .reset     (RESET),
        .read      (MEM_READ),
        .write     (MEM_WRITE),
        .address   (MEM_ADDRESS),
        .writedata (MEM_WRITEDATA),
        .readdata  (MEM_READDATA),
        .busywait  (MEM_BUSYWAIT)
    );

    // Clock Generation
    // Period = 8 time units (matches the Lab 3/4/5 timing model)

    initial  CLK = 1'b0;
    always   #4 CLK = ~CLK;

    //  Instruction Memory Initialisation
    
    //  Instruction format (big-endian, 4 bytes per instruction):
    //    Byte 0 [31:24] = OPCODE
    //    Byte 1 [23:16] = RD / OFFSET
    //    Byte 2 [15:8]  = RT
    //    Byte 3 [7:0]   = RS / IMM
    
    //  Helper macros (implemented as tasks below):
    //    LOADI  RD  IMM        → 8'h00  RD  0   IMM
    //    MOV    RD  RT         → 8'h01  RD  0   RT
    //    ADD    RD  RT  RS     → 8'h02  RD  RT  RS
    //    SUB    RD  RT  RS     → 8'h03  RD  RT  RS
    //    AND    RD  RT  RS     → 8'h04  RD  RT  RS
    //    OR     RD  RT  RS     → 8'h05  RD  RT  RS
    //    J      OFFSET         → 8'h06  OFFSET 0 0
    //    BEQ    OFF  RT  RS    → 8'h07  OFF  RT  RS
    //    LWD    RD  RS         → 8'h10  RD  0   RS
    //    LWI    RD  IMM        → 8'h11  RD  0   IMM
    //    SWD    RT  RS         → 8'h12  0   RT  RS
    //    SWI    RT  IMM        → 8'h13  0   RT  IMM

    integer idx;   // byte index into instr_mem used by load_instr task

    // Task: place one 32-bit instruction into instr_mem at byte address ADDR 

    task load_instr;
        input [9:0]  addr;    // byte address (multiple of 4)
        input [7:0]  b0;      // OPCODE
        input [7:0]  b1;      // RD / OFFSET
        input [7:0]  b2;      // RT
        input [7:0]  b3;      // RS / IMM
        begin
            instr_mem[addr]   = b0;
            instr_mem[addr+1] = b1;
            instr_mem[addr+2] = b2;
            instr_mem[addr+3] = b3;
        end
    endtask

    // Task: check an actual value against expected and print PASS/FAIL

    task check_reg;
        input [127:0] name;
        input [2:0]   regnum;
        input [7:0]   expected;
        begin
            if (dut.rf.registers[regnum] !== expected)
                $display("    FAIL: %0s = 0x%h, expected 0x%h", name, dut.rf.registers[regnum], expected);
            else
                $display("    PASS: %0s = 0x%h", name, dut.rf.registers[regnum]);
        end
    endtask

    task check_mem;
        input [127:0] name;
        input [7:0]   addr;
        input [7:0]   expected;
        begin
            if (dmem.memory_array[addr] !== expected)
                $display("    FAIL: %0s = 0x%h, expected 0x%h", name, dmem.memory_array[addr], expected);
            else
                $display("    PASS: %0s = 0x%h", name, dmem.memory_array[addr]);
        end
    endtask

    //  Test: initialise instruction memory then reset and run

    initial
    begin

        // Zero-fill instruction memory 
        for (idx = 0; idx < 1024; idx = idx + 1)
            instr_mem[idx] = 8'h00;

        //  PROGRAM 1 – Immediate addressing: swi / lwi
        //
        //  Expected final state:
        //    r1 = 0x42 ,  r2 = 0x42   (mem[0x10] = 0x42)
        //    r3 = 0x99 ,  r4 = 0x99   (mem[0x20] = 0x99)

        // Instruction 0 (byte 0x000): loadi r1, 0x42
        //   OPCODE=0x00  RD=1  RT=0  IMM=0x42
        load_instr(10'h000,  8'h00,  8'h01,  8'h00,  8'h42);

        // Instruction 1 (byte 0x004): swi r1, 0x10
        //   Store RT=r1 to mem[IMM=0x10]
        //   OPCODE=0x13  RD=ignored=0  RT=1  IMM=0x10
        load_instr(10'h004,  8'h13,  8'h00,  8'h01,  8'h10);

        // Instruction 2 (byte 0x008): lwi r2, 0x10
        //   Load mem[IMM=0x10] into RD=r2
        //   OPCODE=0x11  RD=2  RT=0  IMM=0x10
        load_instr(10'h008,  8'h11,  8'h02,  8'h00,  8'h10);

        // Instruction 3 (byte 0x00C): loadi r3, 0x99
        load_instr(10'h00C,  8'h00,  8'h03,  8'h00,  8'h99);

        // Instruction 4 (byte 0x010): swi r3, 0x20
        //   OPCODE=0x13  RD=0  RT=3  IMM=0x20
        load_instr(10'h010,  8'h13,  8'h00,  8'h03,  8'h20);

        // Instruction 5 (byte 0x014): lwi r4, 0x20
        //   OPCODE=0x11  RD=4  RT=0  IMM=0x20
        load_instr(10'h014,  8'h11,  8'h04,  8'h00,  8'h20);

        //  PROGRAM 2 – Register-direct addressing: swd / lwd
        //
        //  Expected final state:
        //    r5 = 0x30  (address),  r6 = 0xAB  (data stored)
        //    r7 = 0xAB  (loaded back from mem[0x30])

        // Instruction 6 (byte 0x018): loadi r5, 0x30   (address to use)
        load_instr(10'h018,  8'h00,  8'h05,  8'h00,  8'h30);

        // Instruction 7 (byte 0x01C): loadi r6, 0xAB   (data to store)
        load_instr(10'h01C,  8'h00,  8'h06,  8'h00,  8'hAB);

        // Instruction 8 (byte 0x020): swd r6, r5
        //   mem[RS=r5=0x30] = RT=r6=0xAB
        //   OPCODE=0x12  RD=0  RT=6  RS=5
        load_instr(10'h020,  8'h12,  8'h00,  8'h06,  8'h05);

        // Instruction 9 (byte 0x024): lwd r7, r5
        //   RD=r7 = mem[RS=r5=0x30]
        //   OPCODE=0x10  RD=7  RT=0  RS=5
        load_instr(10'h024,  8'h10,  8'h07,  8'h00,  8'h05);

        //  PROGRAM 3 – ALU result stored to memory and verified
        //
        //  r1=15, r2=17, r3=r1+r2=32=0x20, mem[0x50]=0x20, r0=0x20

        // Instruction 10 (byte 0x028): loadi r1, 0x0F
        load_instr(10'h028,  8'h00,  8'h01,  8'h00,  8'h0F);

        // Instruction 11 (byte 0x02C): loadi r2, 0x11
        load_instr(10'h02C,  8'h00,  8'h02,  8'h00,  8'h11);

        // Instruction 12 (byte 0x030): add r3, r1, r2
        //   OPCODE=0x02  RD=3  RT=1  RS=2
        load_instr(10'h030,  8'h02,  8'h03,  8'h01,  8'h02);

        // Instruction 13 (byte 0x034): swi r3, 0x50
        //   mem[0x50] = r3 = 0x20
        //   OPCODE=0x13  RD=0  RT=3  IMM=0x50
        load_instr(10'h034,  8'h13,  8'h00,  8'h03,  8'h50);

        // Instruction 14 (byte 0x038): lwi r0, 0x50
        //   r0 = mem[0x50] = 0x20
        //   OPCODE=0x11  RD=0  RT=0  IMM=0x50
        load_instr(10'h038,  8'h11,  8'h00,  8'h00,  8'h50);

        //  PROGRAM 4 – Load / modify / store pattern
        //
        //  mem[0x60]=1, load it, add 9 to get 10=0x0A, store to mem[0x61], verify

        // Instruction 15 (byte 0x03C): loadi r1, 0x01
        load_instr(10'h03C,  8'h00,  8'h01,  8'h00,  8'h01);

        // Instruction 16 (byte 0x040): swi r1, 0x60
        //   mem[0x60] = 1
        //   OPCODE=0x13  RD=0  RT=1  IMM=0x60
        load_instr(10'h040,  8'h13,  8'h00,  8'h01,  8'h60);

        // Instruction 17 (byte 0x044): lwi r2, 0x60
        //   r2 = mem[0x60] = 1
        //   OPCODE=0x11  RD=2  RT=0  IMM=0x60
        load_instr(10'h044,  8'h11,  8'h02,  8'h00,  8'h60);

        // Instruction 18 (byte 0x048): loadi r3, 0x09
        load_instr(10'h048,  8'h00,  8'h03,  8'h00,  8'h09);

        // Instruction 19 (byte 0x04C): add r4, r2, r3
        //   r4 = r2 + r3 = 1 + 9 = 10 = 0x0A
        //   OPCODE=0x02  RD=4  RT=2  RS=3
        load_instr(10'h04C,  8'h02,  8'h04,  8'h02,  8'h03);

        // Instruction 20 (byte 0x050): swi r4, 0x61
        //   mem[0x61] = r4 = 0x0A
        //   OPCODE=0x13  RD=0  RT=4  IMM=0x61
        load_instr(10'h050,  8'h13,  8'h00,  8'h04,  8'h61);

        // Instruction 21 (byte 0x054): lwi r5, 0x61
        //   r5 = mem[0x61] = 0x0A
        //   OPCODE=0x11  RD=5  RT=0  IMM=0x61
        load_instr(10'h054,  8'h11,  8'h05,  8'h00,  8'h61);

        // ── End of programs: infinite loop (j -1) ─────────────────────────
        // Instruction 22 (byte 0x058): j -1
        //   OFFSET = 0xFF = -1 → PC stays at same instruction (infinite loop)
        load_instr(10'h058,  8'h06,  8'hFF,  8'h00,  8'h00);


        // Reset and run
        RESET = 1'b1;
        @(posedge CLK);
        #1;
        RESET = 1'b0;

        // ── Program 1: swi r1, 0x10 ───────────────────────────────────────
        // Wait for loadi r1 (1 cycle) + swi (6 cycles) = 7 cycles
        repeat(7) @(posedge CLK);
        $display("[TIME=%0t] INSTR 1 DONE: swi r1(=0x42), addr=0x10 --> mem[0x10] should = 0x42", $time);
        #5;
        check_mem("mem[0x10]", 8'h10, 8'h42);

        // ── Program 1: lwi r2, 0x10 ───────────────────────────────────────
        repeat(6) @(posedge CLK);
        $display("[TIME=%0t] INSTR 2 DONE: lwi r2, addr=0x10 --> r2 should = 0x42", $time);
        #5;
        check_reg("r2", 3'd2, 8'h42);

        // ── Program 1: loadi r3 + swi r3, 0x20 ───────────────────────────
        repeat(7) @(posedge CLK);
        $display("[TIME=%0t] INSTR 4 DONE: swi r3(=0x99), addr=0x20 --> mem[0x20] should = 0x99", $time);
        #5;
        check_mem("mem[0x20]", 8'h20, 8'h99);

        // ── Program 1: lwi r4, 0x20 ───────────────────────────────────────
        repeat(6) @(posedge CLK);
        $display("[TIME=%0t] INSTR 5 DONE: lwi r4, addr=0x20 --> r4 should = 0x99", $time);
        #5;
        check_reg("r4", 3'd4, 8'h99);

        // ── Program 2: loadi r5 + loadi r6 + swd r6,r5 ───────────────────
        repeat(8) @(posedge CLK);
        $display("[TIME=%0t] INSTR 8 DONE: swd r6(=0xAB), r5(=0x30) --> mem[0x30] should = 0xAB", $time);
        #5;
        check_mem("mem[0x30]", 8'h30, 8'hAB);

        // ── Program 2: lwd r7, r5 ─────────────────────────────────────────
        repeat(6) @(posedge CLK);
        $display("[TIME=%0t] INSTR 9 DONE: lwd r7, r5(=0x30) --> r7 should = 0xAB", $time);
        #5;
        check_reg("r7", 3'd7, 8'hAB);

        // ── Program 3: loadi r1 + loadi r2 + add r3 + swi r3,0x50 ────────
        repeat(10) @(posedge CLK);
        $display("[TIME=%0t] INSTR 13 DONE: swi r3(=0x20), addr=0x50 --> mem[0x50] should = 0x20", $time);
        #5;
        check_mem("mem[0x50]", 8'h50, 8'h20);

        // ── Program 3: lwi r0, 0x50 ───────────────────────────────────────
        repeat(6) @(posedge CLK);
        $display("[TIME=%0t] INSTR 14 DONE: lwi r0, addr=0x50 --> r0 should = 0x20", $time);
        #5;
        check_reg("r0", 3'd0, 8'h20);

        // ── Program 4: loadi r1 + swi r1,0x60 ────────────────────────────
        repeat(7) @(posedge CLK);
        $display("[TIME=%0t] INSTR 16 DONE: swi r1(=0x01), addr=0x60 --> mem[0x60] should = 0x01", $time);
        #5;
        check_mem("mem[0x60]", 8'h60, 8'h01);

        // ── Program 4: lwi r2, 0x60 ───────────────────────────────────────
        repeat(6) @(posedge CLK);
        $display("[TIME=%0t] INSTR 17 DONE: lwi r2, addr=0x60 --> r2 should = 0x01", $time);
        #5;
        check_reg("r2", 3'd2, 8'h01);

        // ── Program 4: loadi r3 + add r4 + swi r4,0x61 ───────────────────
        repeat(9) @(posedge CLK);
        $display("[TIME=%0t] INSTR 20 DONE: swi r4(=0x0A), addr=0x61 --> mem[0x61] should = 0x0A", $time);
        #5;
        check_mem("mem[0x61]", 8'h61, 8'h0A);

        // ── Program 4: lwi r5, 0x61 ───────────────────────────────────────
        repeat(6) @(posedge CLK);
        $display("[TIME=%0t] INSTR 21 DONE: lwi r5, addr=0x61 --> r5 should = 0x0A", $time);
        #5;
        check_reg("r5", 3'd5, 8'h0A);

        $display("----------------------------------------------------");
        $display("Simulation complete. Check waveform for verification.");
        $display("Expected results:");
        $display("  Program 1 (imm addressing) - r1=0x42 r2=0x42 r3=0x99 r4=0x99");
        $display("  Program 2 (reg-direct)     - r5=0x30 r6=0xAB r7=0xAB");
        $display("  Program 3 (ALU->mem)       - r1=0x0F r2=0x11 r3=0x20  r0=0x20");
        $display("  Program 4 (ld/mod/st)      - r2=0x01 r3=0x09 r4=0x0A r5=0x0A");
        $display("----------------------------------------------------");

        $finish;
    end

    // ── VCD Waveform Dump ─────────────────────────────────────────────────────

    initial
    begin
        $dumpfile("cpu_lab5_waves.vcd");
        $dumpvars(0, cpu_tb);
    end

endmodule