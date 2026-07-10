`include "dcache.v"
`timescale 1ns/100ps

module timing_check;
    reg clock, reset, read, write;
    reg [7:0] address, writedata;
    wire [7:0] readdata;
    wire busywait;
    wire mem_read, mem_write;
    wire [5:0] mem_address;
    wire [31:0] mem_writedata;
    reg [31:0] mem_readdata;
    reg mem_busywait;

    dcache dut(
        .clock(clock), .reset(reset), .read(read), .write(write),
        .address(address), .writedata(writedata), .readdata(readdata), .busywait(busywait),
        .mem_read(mem_read), .mem_write(mem_write), .mem_address(mem_address),
        .mem_writedata(mem_writedata), .mem_readdata(mem_readdata), .mem_busywait(mem_busywait)
    );

    initial clock = 0;
    always #4 clock = ~clock;

    real t_addr_change, t_busywait_fall;

    initial begin
        reset = 1; read = 0; write = 0; address = 0; writedata = 0;
        mem_readdata = 0; mem_busywait = 0;
        @(posedge clock); #1; reset = 0;

        // Prime one line as a valid, dirty entry via a cold miss first
        // (address 0x00: tag=0,index=0,offset=0)
        write = 1; writedata = 8'h11; address = 8'h00;
        @(posedge clock);
        wait (busywait == 0);
        $display("[prime] busywait first fell at t=%0t, state=%b hit=%b", $realtime, dut.state, dut.hit);
        @(posedge clock);
        #3;
        $display("[prime] one cycle later (+3ns settle): t=%0t state=%b hit=%b cache_data0=%h cache_dirty0=%b",
                  $realtime, dut.state, dut.hit, dut.cache_data[0], dut.cache_dirty[0]);
        write = 0;
        @(posedge clock);

        // Now measure a plain HIT's timing: re-present the same address
        // for a READ, and time from the address change to readdata
        // becoming valid (busywait never even rises on a hit, since it's
        // resolved combinationally - so there's no falling edge to catch;
        // readdata settling to the correct value is the real signal).
        @(negedge clock);   // change address safely mid-cycle
        address = 8'h00;
        read = 1;
        t_addr_change = $realtime;
        repeat (25) begin
            #1;
            if (readdata !== 8'hxx)
            begin
                $display("readdata became valid (%h) %0.1f ns after address change", readdata, $realtime - t_addr_change);
                $display("busywait = %b at that point (expected 0 - no stall on a hit)", busywait);
                $finish;
            end
        end
        $display("readdata never resolved within 2.5ns - something is wrong");
        $finish;

        $finish;
    end
endmodule
