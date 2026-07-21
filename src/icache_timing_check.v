// Computer Architecture CO2070 - Lab 07
// Standalone timing check: verifies the instruction cache resolves a HIT
// within the required #1.9 / #2.0 time-unit budget (mirrors timing_check.v
// from Lab 6, adapted for the instruction cache's word/block sizes).

`include "icache.v"

`timescale 1ns/100ps

module icache_timing_check;

    reg         clock, reset, read;
    reg  [9:0]  address;
    wire [31:0] instword;
    wire        busywait;

    reg         mem_busywait;
    reg  [127:0] mem_readinst;
    wire        mem_read;
    wire [5:0]  mem_address;

    icache dut(
        .clock(clock), .reset(reset), .read(read), .address(address),
        .instword(instword), .busywait(busywait),
        .mem_read(mem_read), .mem_address(mem_address),
        .mem_readinst(mem_readinst), .mem_busywait(mem_busywait)
    );

    initial clock = 0;
    always #4 clock = ~clock;

    initial begin
        reset = 1; read = 0; address = 10'd0;
        mem_busywait = 0; mem_readinst = 128'h0;
        @(posedge clock); #1; reset = 0;

        // ── Prime the cache: force a known block into line 0 (tag=0) ──────
        // Directly load the storage arrays (bypassing timing) purely to set
        // up a HIT scenario for the measurement below - this is test setup,
        // not something the RTL itself does out-of-band.
        dut.cache_data[0]  = {96'd0, 32'h000000AA}; // word0 (bits [31:0]) of the block = 0x000000AA
        dut.cache_tag[0]   = 3'b000;
        dut.cache_valid[0] = 1'b1;

        @(posedge clock);
        #3; // let setup settle well clear of any clock edge

        // ── Now issue a read that should HIT immediately ───────────────────
        read = 1;
        address = 10'b000_000_00_00;   // tag=000, index=000, wordsel=00
        $display("[prime] issuing read at t=%0t", $time);

        #1.9;
        $display("[check] t=%0t : hit-detection window elapsed, busywait=%b (expect 0)", $time, busywait);

        #0.1; // reach the #2.0 mark
        $display("[check] t=%0t : instword=%h (expect 000000AA), busywait=%b (expect 0)", $time, instword, busywait);

        if (busywait !== 1'b0)
            $display("    FAIL: busywait should be 0 on a hit (no stall)");
        else
            $display("    PASS: busywait = 0 on hit (CPU not stalled)");

        if (instword !== 32'h000000AA)
            $display("    FAIL: instword = %h, expected 000000AA", instword);
        else
            $display("    PASS: instword = 000000AA, resolved within #2 time units");

        #10;
        $display("----------------------------------------------------");
        $display("Timing check complete.");
        $finish;
    end

endmodule
