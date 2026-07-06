// Computer Architecture CO2070 - Lab 02 (Part 1)
// Design: 8-bit ALU
// Team : 06
// Members : E/22/014 , E/22/035

`include "alu.v"

module alu_tb;

    // inputs to ALU
    reg [7:0] DATA1;
    reg [7:0] DATA2;
    reg [2:0] SELECT;

    // output from ALU
    wire [7:0] RESULT;


    // instantiate ALU module
    alu myalu(DATA1, DATA2, RESULT, SELECT);


    initial
    begin

        // generate waveform file for GTKWave
        $dumpfile("alu_wavedata.vcd");
        $dumpvars(0, alu_tb);


        //======================================================
        // Test 1 : Forward Operation
        // RESULT = DATA2
        //======================================================

        DATA1 = 8'd10;
        DATA2 = 8'd5;
        SELECT = 3'b000;

        #10;


        //======================================================
        // Test 2 : Addition
        // RESULT = DATA1 + DATA2
        //======================================================

        DATA1 = 8'd20;
        DATA2 = 8'd15;
        SELECT = 3'b001;

        #10;


        //======================================================
        // Test 3 : Bitwise AND
        //======================================================

        DATA1 = 8'b10101010;
        DATA2 = 8'b11001100;
        SELECT = 3'b010;

        #10;


        //======================================================
        // Test 4 : Bitwise OR
        //======================================================

        DATA1 = 8'b10101010;
        DATA2 = 8'b11001100;
        SELECT = 3'b011;

        #10;


        //======================================================
        // Test 5 : Unused SELECT value 100
        //======================================================

        DATA1 = 8'd50;
        DATA2 = 8'd25;
        SELECT = 3'b100;

        #10;


        //======================================================
        // Test 6 : Unused SELECT value 101
        //======================================================

        SELECT = 3'b101;

        #10;


        //======================================================
        // Test 7 : Unused SELECT value 110
        //======================================================

        SELECT = 3'b110;

        #10;


        //======================================================
        // Test 8 : Unused SELECT value 111
        //======================================================

        SELECT = 3'b111;

        #10;


        // finish simulation
        $finish;

    end


    // display values in terminal

    initial
    begin

        $monitor(
            "Time=%0d DATA1=%b DATA2=%b SELECT=%b RESULT=%b",
            $time,
            DATA1,
            DATA2,
            SELECT,
            RESULT
        );

    end

endmodule