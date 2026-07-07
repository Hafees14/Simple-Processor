// Computer Architecture CO2070 - Lab 05
// Testbench - Fibonacci Program
// Team : 06


`include "cpu.v"
`include "data_memory.v"

`timescale 1ns/100ps


module cpu_tb;


    //====================================================
    // CPU CONNECTIONS
    //====================================================

    reg CLK;
    reg RESET;

    wire [31:0] PC;
    wire [31:0] INSTRUCTION;


    // Data memory interface

    wire MEM_READ;
    wire MEM_WRITE;

    wire [7:0] MEM_ADDRESS;
    wire [7:0] MEM_WRITEDATA;
    wire [7:0] MEM_READDATA;

    wire MEM_BUSYWAIT;



    //====================================================
    // INSTRUCTION MEMORY
    //====================================================

    reg [7:0] instr_mem [0:1023];


    assign #2 INSTRUCTION =
    {
        instr_mem[PC],
        instr_mem[PC+1],
        instr_mem[PC+2],
        instr_mem[PC+3]
    };



    //====================================================
    // CPU INSTANCE
    //====================================================

    cpu dut
    (
        .PC(PC),
        .INSTRUCTION(INSTRUCTION),

        .CLK(CLK),
        .RESET(RESET),

        .MEM_READ(MEM_READ),
        .MEM_WRITE(MEM_WRITE),

        .MEM_ADDRESS(MEM_ADDRESS),
        .MEM_WRITEDATA(MEM_WRITEDATA),
        .MEM_READDATA(MEM_READDATA),

        .MEM_BUSYWAIT(MEM_BUSYWAIT)
    );




    //====================================================
    // DATA MEMORY INSTANCE
    //====================================================

    data_memory dmem
    (
        .clock(CLK),
        .reset(RESET),

        .read(MEM_READ),
        .write(MEM_WRITE),

        .address(MEM_ADDRESS),
        .writedata(MEM_WRITEDATA),
        .readdata(MEM_READDATA),

        .busywait(MEM_BUSYWAIT)
    );




    //====================================================
    // CLOCK
    //====================================================

    initial
        CLK = 0;

    always
        #4 CLK = ~CLK;




    //====================================================
    // LOAD INSTRUCTION TASK
    //====================================================

    task load_instr;

        input [9:0] addr;

        input [7:0] b0;
        input [7:0] b1;
        input [7:0] b2;
        input [7:0] b3;


        begin

            instr_mem[addr]   = b0;
            instr_mem[addr+1] = b1;
            instr_mem[addr+2] = b2;
            instr_mem[addr+3] = b3;

        end

    endtask




    integer i;



    //====================================================
    // PROGRAM LOADING
    //====================================================


    initial
    begin


        // Clear instruction memory

        for(i=0;i<1024;i=i+1)
            instr_mem[i]=8'h00;



        /*
        
        Fibonacci Program

        r0 = previous value
        r1 = current value
        r3 = counter
        r4 = increment
        r5 = limit
        r6 = memory address


        Memory:

        mem[0] = 0
        mem[1] = 1
        mem[2] = 1
        mem[3] = 2
        ...

        */



        // r0 = 0
        load_instr(
        10'h000,
        8'h00,8'h00,8'h00,8'h00);


        // r1 = 1
        load_instr(
        10'h004,
        8'h00,8'h01,8'h00,8'h01);


        // r3 = 2 counter  <-- FIX HERE
        load_instr(
        10'h008,
        8'h00,8'h03,8'h00,8'h02);


        // r4 = 1
        load_instr(
        10'h00C,
        8'h00,8'h04,8'h00,8'h01);


        // r5 = 8 limit
        load_instr(
        10'h010,
        8'h00,8'h05,8'h00,8'h08);


        // r6 = 0 memory address
        load_instr(
        10'h014,
        8'h00,8'h06,8'h00,8'h00);



        // store r0 -> mem[r6]

        load_instr(
        10'h018,
        8'h12,8'h00,8'h00,8'h06);



        // r6++

        load_instr(
        10'h01C,
        8'h02,8'h06,8'h06,8'h04);



        // store r1

        load_instr(
        10'h020,
        8'h12,8'h00,8'h01,8'h06);



        // r6++

        load_instr(
        10'h024,
        8'h02,8'h06,8'h06,8'h04);




        //============================
        // LOOP START 0x028
        //============================


        // r2=r0+r1

        load_instr(
        10'h028,
        8'h02,8'h02,8'h00,8'h01);



        // store r2

        load_instr(
        10'h02C,
        8'h12,8'h00,8'h02,8'h06);



        // r6++

        load_instr(
        10'h030,
        8'h02,8'h06,8'h06,8'h04);



        // r0=r1

        load_instr(
        10'h034,
        8'h01,8'h00,8'h00,8'h01);



        // r1=r2

        load_instr(
        10'h038,
        8'h01,8'h01,8'h00,8'h02);



        // counter++

        load_instr(
        10'h03C,
        8'h02,8'h03,8'h03,8'h04);



        // if counter==limit END

        load_instr(
        10'h040,
        8'h07,8'h01,8'h03,8'h05);



        // jump LOOP
        // offset = -7 instructions

        load_instr(
        10'h044,
        8'h06,8'hF8,8'h00,8'h00);

        

        // END infinite loop

        load_instr(
        10'h048,
        8'h06,8'h00,8'h00,8'h00);




        // RESET

        RESET=1;

        #10;

        RESET=0;



        // run

        #1000;




        $display("");
        $display("------------------------------");
        $display(" Fibonacci Numbers ");
        $display("------------------------------");


        $display("%d",dmem.memory_array[0]);
        $display("%d",dmem.memory_array[1]);
        $display("%d",dmem.memory_array[2]);
        $display("%d",dmem.memory_array[3]);
        $display("%d",dmem.memory_array[4]);
        $display("%d",dmem.memory_array[5]);
        $display("%d",dmem.memory_array[6]);
        $display("%d",dmem.memory_array[7]);


        $finish;


    end




    //====================================================
    // WAVEFORM
    //====================================================


    initial
    begin

        $dumpfile("cpu_lab5_waves.vcd");

        $dumpvars(0,cpu_tb);

    end




endmodule