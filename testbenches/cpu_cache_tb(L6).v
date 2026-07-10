// Computer Architecture CO2070 - Lab 06
// Design: Testbench - CPU with Data Cache and Data Memory
// Team  : 06
// Members : E/22/014, E/22/035

//  TEST PROGRAM OVERVIEW
//
//  Cache geometry: 8 direct-mapped lines, 4-byte blocks.
//  address[7:5]=tag  address[4:2]=index  address[1:0]=offset
//
//  Addresses 0x04 and 0x24 both map to index=1 but have different tags
//  (0 and 1 respectively) - used deliberately to force a dirty eviction.
//
//  loadi r1, 0xAB
//  swi   r1, 0x04     // tag=0,index=1: COLD MISS (write-allocate), then write-hit merge -> mem line1 dirty
//  lwi   r2, 0x04     // same line: HIT -> r2 should = 0xAB
//  loadi r3, 0xCD
//  swi   r3, 0x24     // tag=1,index=1: MISS, evicted line (tag0) is dirty -> writeback + fetch + write-hit merge
//  lwi   r4, 0x24     // same line: HIT -> r4 should = 0xCD
//  lwi   r5, 0x04     // tag=0,index=1 again: MISS again (currently holds tag1, and it's dirty)
//                      // -> writeback tag1's block, fetch tag0's block (which now holds the
//                      //    earlier written-back 0xAB in memory) -> HIT on retry -> r5 should = 0xAB
//                      //    (proves write-back correctly persisted data to memory across two evictions)

`include "cpu.v"
`include "dcache.v"
`include "data_memory.v"


`timescale 1ns/100ps

module cpu_cache_tb;

    reg         CLK;
    reg         RESET;
    wire [31:0] PC;
    wire [31:0] INSTRUCTION;

    // CPU <-> Cache (identical shape to Lab 5's CPU <-> memory interface)
    wire        MEM_READ;
    wire        MEM_WRITE;
    wire [7:0]  MEM_ADDRESS;
    wire [7:0]  MEM_WRITEDATA;
    wire [7:0]  MEM_READDATA;
    wire        MEM_BUSYWAIT;

    // Cache <-> Data Memory (block-based, Lab 6)
    // Memory transfers one 4-byte block = 32 bits
    wire          DMEM_READ;
    wire          DMEM_WRITE;
    wire [5:0]    DMEM_ADDRESS;
    wire [31:0]   DMEM_WRITEDATA;
    wire [31:0]   DMEM_READDATA;
    wire          DMEM_BUSYWAIT;

    reg [7:0] instr_mem [0:1023];

    assign #2 INSTRUCTION = {
        instr_mem[PC], instr_mem[PC+1], instr_mem[PC+2], instr_mem[PC+3]
    };

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

    dcache cache(
        .clock         (CLK),
        .reset         (RESET),
        .read          (MEM_READ),
        .write         (MEM_WRITE),
        .address       (MEM_ADDRESS),
        .writedata     (MEM_WRITEDATA),
        .readdata      (MEM_READDATA),
        .busywait      (MEM_BUSYWAIT),

        .mem_read      (DMEM_READ),
        .mem_write     (DMEM_WRITE),
        .mem_address   (DMEM_ADDRESS),
        .mem_writedata (DMEM_WRITEDATA),
        .mem_readdata  (DMEM_READDATA),
        .mem_busywait  (DMEM_BUSYWAIT)
    );

    data_memory dmem(
        .clock     (CLK),
        .reset     (RESET),
        .read      (DMEM_READ),
        .write     (DMEM_WRITE),
        .address   (DMEM_ADDRESS),
        .writedata (DMEM_WRITEDATA),
        .readdata  (DMEM_READDATA),
        .busywait  (DMEM_BUSYWAIT)
    );

    initial CLK = 1'b0;
    always  #4 CLK = ~CLK;

    integer idx;

    task load_instr;
        input [9:0] addr; input [7:0] b0,b1,b2,b3;
        begin
            instr_mem[addr]=b0; instr_mem[addr+1]=b1; instr_mem[addr+2]=b2; instr_mem[addr+3]=b3;
        end
    endtask

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

    initial
    begin
        for (idx = 0; idx < 1024; idx = idx + 1)
            instr_mem[idx] = 8'h00;

        // loadi r1, 0xAB
        load_instr(10'h000, 8'h00,8'h01,8'h00,8'hAB);
        // swi r1, 0x04   (tag=0, index=1, offset=0) -- cold miss, write-allocate
        load_instr(10'h004, 8'h13,8'h00,8'h01,8'h04);
        // lwi r2, 0x04   -- should hit
        load_instr(10'h008, 8'h11,8'h02,8'h00,8'h04);
        // loadi r3, 0xCD
        load_instr(10'h00C, 8'h00,8'h03,8'h00,8'hCD);
        // swi r3, 0x24   (tag=1, index=1, offset=0) -- miss, evicts dirty tag-0 line
        load_instr(10'h010, 8'h13,8'h00,8'h03,8'h24);
        // lwi r4, 0x24   -- should hit
        load_instr(10'h014, 8'h11,8'h04,8'h00,8'h24);
        // lwi r5, 0x04   -- miss again (evicts dirty tag-1 line), refetches tag-0's
        //                   block which now holds the earlier written-back 0xAB
        load_instr(10'h018, 8'h11,8'h05,8'h00,8'h04);
        // j -1 (infinite loop / end of program)
        load_instr(10'h01C, 8'h06,8'hFF,8'h00,8'h00);

        RESET = 1'b1;
        @(posedge CLK);
        #1;
        RESET = 1'b0;

        // Generous, safety-margin waits (misses can take dozens of cycles;
        // we just wait long enough for each instruction to definitely be
        // done rather than hand-computing exact miss-penalty cycle counts).

        repeat(10)  @(posedge CLK); #5;
        $display("[after swi r1,0x04 - cold miss + write-allocate]");
        // (no CPU-visible register to check here; memory-side check below)

        repeat(60) @(posedge CLK); #5;
        $display("[after lwi r2,0x04 - should be a hit]");
        check_reg("r2", 3'd2, 8'hAB);

        repeat(10) @(posedge CLK); #5;
        $display("[after loadi r3 - no cache interaction]");

        repeat(90) @(posedge CLK); #5;
        $display("[after swi r3,0x24 - miss, evicts dirty tag-0 line]");

        repeat(60) @(posedge CLK); #5;
        $display("[after lwi r4,0x24 - should be a hit]");
        check_reg("r4", 3'd4, 8'hCD);

        repeat(90) @(posedge CLK); #5;
        $display("[after lwi r5,0x04 - miss again, evicts dirty tag-1 line, refetches tag-0]");
        check_reg("r5", 3'd5, 8'hAB);

        // Direct check of memory contents, confirming write-back actually
        // persisted both evicted dirty blocks correctly.
        $display("[memory contents after both evictions]");
        if (dmem.memory_array[8'h04] !== 8'hAB)
            $display("    FAIL: mem[0x04] = %h, expected AB (tag-0 block's write-back)", dmem.memory_array[8'h04]);
        else
            $display("    PASS: mem[0x04] = AB (tag-0 block correctly written back)");

        if (dmem.memory_array[8'h24] !== 8'hCD)
            $display("    FAIL: mem[0x24] = %h, expected CD (tag-1 block's write-back)", dmem.memory_array[8'h24]);
        else
            $display("    PASS: mem[0x24] = CD (tag-1 block correctly written back)");

        $display("----------------------------------------------------");
        $display("Simulation complete.");
        $finish;
    end

    initial
    begin
        $dumpfile("cpu_cache_waves.vcd");
        $dumpvars(0, cpu_cache_tb);
    end

endmodule
