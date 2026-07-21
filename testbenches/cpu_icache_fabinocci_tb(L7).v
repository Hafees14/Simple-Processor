// Computer Architecture CO2070 - Lab 07
// Design: Testbench - CPU with full memory hierarchy running a complete
//         Fibonacci-sequence program (per instructor's request for a
//         complete program rather than a couple of instructions).
// Team  : 06
// Members : E/22/014, E/22/035

// See instruction_memory.v for the full program listing and rationale.
//
// What this testbench verifies:
//   1. Instruction-cache misses occur only at block boundaries (5 cold
//      misses total: blocks/indices 0,1,2,3,4), never inside a block.
//   2. The loop (words 8-14) executes 11 times, crossing the block-2 /
//      block-3 boundary on every single iteration - after the first
//      iteration warms both blocks, all 10 remaining iterations produce
//      ZERO additional instruction-cache misses (checked via miss_count).
//   3. The computed Fibonacci sequence is arithmetically correct:
//      final r0=89, r1=144 (the last two numbers generated), and r7=144
//      (fib(12), read back from data memory through the data cache with
//      lwi, proving the data cache holds the correct value even though
//      it was never written back to main memory - still dirty/cached).
//   4. The data cache (Lab 6) and instruction cache (Lab 7) operate
//      correctly and simultaneously throughout.

`include "cpu.v"
`include "icache.v"
`include "instruction_memory.v"
`include "dcache.v"
`include "data_memory.v"

`timescale 1ns/100ps

module cpu_icache_tb;

    reg         CLK;
    reg         RESET;
    wire [31:0] PC;
    wire [31:0] INSTRUCTION;

    // ── CPU <-> Instruction Cache ──────────────────────────────────────────
    wire         IFETCH_READ;
    wire [9:0]   IFETCH_ADDRESS;
    wire [31:0]  IFETCH_INSTWORD;
    wire         IFETCH_BUSYWAIT;

    // ── Instruction Cache <-> Instruction Memory ───────────────────────────
    wire         IMEM_READ;
    wire [5:0]   IMEM_ADDRESS;
    wire [127:0] IMEM_READINST;
    wire         IMEM_BUSYWAIT;

    // ── CPU <-> Data Cache (unchanged from Lab 6) ──────────────────────────
    wire        MEM_READ;
    wire        MEM_WRITE;
    wire [7:0]  MEM_ADDRESS;
    wire [7:0]  MEM_WRITEDATA;
    wire [7:0]  MEM_READDATA;
    wire        MEM_BUSYWAIT;

    // ── Data Cache <-> Data Memory (unchanged from Lab 6) ──────────────────
    wire          DMEM_READ;
    wire          DMEM_WRITE;
    wire [5:0]    DMEM_ADDRESS;
    wire [31:0]   DMEM_WRITEDATA;
    wire [31:0]   DMEM_READDATA;
    wire          DMEM_BUSYWAIT;

    assign IFETCH_READ    = 1'b1;
    assign IFETCH_ADDRESS = PC[9:0];
    assign INSTRUCTION    = IFETCH_INSTWORD;

    // ── Register-file waveform taps ─────────────────────────────────────────
    // dut.rf.registers is a memory array (reg [7:0] registers[0:7]) and
    // Icarus's $dumpvars does not expose individual memory-array elements
    // as separate VCD signals. These wires re-expose each register as an
    // ordinary top-level signal so they show up in GTKWave's signal list
    // (under the cpu_icache_tb top scope) and get written to the .vcd
    // like any other wire. Right-click -> Data Format -> Decimal in
    // GTKWave to view them as plain numbers instead of binary/hex.
    wire [7:0] R0 = dut.rf.registers[0];
    wire [7:0] R1 = dut.rf.registers[1];
    wire [7:0] R2 = dut.rf.registers[2];
    wire [7:0] R3 = dut.rf.registers[3];
    wire [7:0] R4 = dut.rf.registers[4];
    wire [7:0] R5 = dut.rf.registers[5];
    wire [7:0] R6 = dut.rf.registers[6];
    wire [7:0] R7 = dut.rf.registers[7];

    cpu dut(
        .PC              (PC),
        .INSTRUCTION     (INSTRUCTION),
        .CLK             (CLK),
        .RESET           (RESET),
        .MEM_READ        (MEM_READ),
        .MEM_WRITE       (MEM_WRITE),
        .MEM_ADDRESS     (MEM_ADDRESS),
        .MEM_WRITEDATA   (MEM_WRITEDATA),
        .MEM_READDATA    (MEM_READDATA),
        .MEM_BUSYWAIT    (MEM_BUSYWAIT),
        .IFETCH_BUSYWAIT (IFETCH_BUSYWAIT)
    );

    icache icache_dut(
        .clock        (CLK),
        .reset        (RESET),
        .read         (IFETCH_READ),
        .address      (IFETCH_ADDRESS),
        .instword     (IFETCH_INSTWORD),
        .busywait     (IFETCH_BUSYWAIT),
        .mem_read     (IMEM_READ),
        .mem_address  (IMEM_ADDRESS),
        .mem_readinst (IMEM_READINST),
        .mem_busywait (IMEM_BUSYWAIT)
    );

    instruction_memory imem(
        .clock    (CLK),
        .read     (IMEM_READ),
        .address  (IMEM_ADDRESS),
        .readinst (IMEM_READINST),
        .busywait (IMEM_BUSYWAIT)
    );

    dcache dcache_dut(
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

    // ── Instrumentation: count instruction-cache misses ────────────────────
    integer miss_count;
    reg     prev_in_mem_read;

    initial begin
        miss_count = 0;
        prev_in_mem_read = 1'b0;
    end

    always @(posedge CLK) begin
        if (icache_dut.state == icache_dut.MEM_READ && !prev_in_mem_read) begin
            miss_count = miss_count + 1;
            $display("    [MISS #%0d] at time=%0t  PC=%h  tag_in=%b index=%b",
                miss_count, $time, PC, icache_dut.tag_in, icache_dut.index);
        end
        prev_in_mem_read <= (icache_dut.state == icache_dut.MEM_READ);
    end

    // ── Instrumentation: count loop iterations (word 8 re-fetched) ─────────
    integer loop_count;
    initial loop_count = 0;
    always @(posedge CLK) begin
        if (PC == 32'h00000020 && !IFETCH_BUSYWAIT)
            loop_count = loop_count + 1;
    end

    task check_reg;
        input [8*48-1:0] name;
        input [2:0]   regnum;
        input [7:0]   expected;
        begin
            if (dut.rf.registers[regnum] !== expected)
                $display("    FAIL: %0s = 0x%h (%0d), expected 0x%h (%0d)", name, dut.rf.registers[regnum], dut.rf.registers[regnum], expected, expected);
            else
                $display("    PASS: %0s = 0x%h (%0d)", name, dut.rf.registers[regnum], dut.rf.registers[regnum]);
        end
    endtask

    task check_misses;
        input [8*48-1:0] label;
        input integer expected;
        begin
            if (miss_count !== expected)
                $display("    FAIL: %0s -> miss_count = %0d, expected %0d", label, miss_count, expected);
            else
                $display("    PASS: %0s -> miss_count = %0d", label, miss_count);
        end
    endtask

    initial begin
        RESET = 1'b1;
        @(posedge CLK); #1;
        RESET = 1'b0;

        // Generous margin: 5 misses x 81 cycles + 11 loop iterations x
        // (6 instructions/iter, all hits after warm-up) + setup/tail.
        repeat(900) @(posedge CLK); #5;

        $display("==================== PROGRAM COMPLETE ====================");
        $display("Loop body (word 8, address 0x20) was fetched %0d times (expect 11)", loop_count);

        check_misses("cold misses across all 5 code blocks", 5);
        check_reg("r0 (second-to-last fib = 89)",  3'd0, 8'd89);
        check_reg("r1 (last fib generated = 144)", 3'd1, 8'd144);
        check_reg("r3 (loop counter, must reach 0)", 3'd3, 8'd0);
        check_reg("r7 (readback of mem[12] via lwi = fib(12) = 144)", 3'd7, 8'd144);

        if (loop_count !== 11)
            $display("    FAIL: loop executed %0d times, expected 11", loop_count);
        else
            $display("    PASS: loop executed exactly 11 times");

        $display("----------------------------------------------------");
        $display("Simulation complete. Total instruction-cache misses: %0d", miss_count);
        $finish;
    end

    initial begin
        $dumpfile("cpu_icache_waves.vcd");
        $dumpvars(0, cpu_icache_tb);
    end

endmodule
