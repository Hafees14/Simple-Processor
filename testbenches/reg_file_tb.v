// Computer Architecture CO2070 - Lab 02
// Design: Register File of Simple Processor
// Team : 06
// Members : E/22/014 , E/22/035

// Register File Module

`include "reg_file.v"

module reg_file_tb;
    
    reg [7:0] WRITEDATA;
    reg [2:0] WRITEREG, READREG1, READREG2;
    reg CLK, RESET, WRITEENABLE; 
    
    wire [7:0] REGOUT1, REGOUT2;
    
    
    // Instantiate Register File

    reg_file myregfile(
        WRITEDATA,
        REGOUT1,
        REGOUT2,
        WRITEREG,
        READREG1,
        READREG2,
        WRITEENABLE,
        CLK,
        RESET
    );
       
       
    // Apply Input Signals

    initial
    begin

        // initial clock value
        CLK = 1'b1;
        
        
        // generate waveform file for GTKWave
        $dumpfile("reg_file_wavedata.vcd");
        $dumpvars(0, reg_file_tb);
        
        
        // initial values

        RESET = 1'b0;
        WRITEENABLE = 1'b0;
        
        
        // Reset register file

        #4
        RESET = 1'b1;

        READREG1 = 3'd0;
        READREG2 = 3'd4;
        
        
        // Stop reset

        #6
        RESET = 1'b0;
        
        
        // Write value 95 into register 2

        #2

        WRITEREG = 3'd2;
        WRITEDATA = 8'd95;
        WRITEENABLE = 1'b1;
        
        
        // Disable writing

        #7
        WRITEENABLE = 1'b0;
        
        
        // Read register 2

        #1
        READREG1 = 3'd2;
        
        
        // Write value 28 into register 1

        #7

        WRITEREG = 3'd1;
        WRITEDATA = 8'd28;
        WRITEENABLE = 1'b1;

        READREG1 = 3'd1;
        
        
        // Disable writing

        #8
        WRITEENABLE = 1'b0;
        
        
        // Write value 6 into register 4

        #8

        WRITEREG = 3'd4;
        WRITEDATA = 8'd6;
        WRITEENABLE = 1'b1;
        
        
        // Change register 4 value to 15

        #8

        WRITEDATA = 8'd15;
        WRITEENABLE = 1'b1;
        
        
        // Disable writing

        #10
        WRITEENABLE = 1'b0;
        
        
        // Write value 50 into register 7

        #6

        WRITEREG = 3'd7;
        WRITEDATA = 8'd50;
        WRITEENABLE = 1'b1;
        
        
        // Disable writing

        #5
        WRITEENABLE = 1'b0;
        
        
        // Finish simulation

        #10
        $finish;

    end
    
    
    // Clock Generation
    // clock changes every 4 time units

    always
        #4 CLK = ~CLK;


    // Display values in terminal

    initial
    begin

        $monitor(
            "Time=%0d CLK=%b RESET=%b WRITE=%b WRITEREG=%0d WRITEDATA=%0d READREG1=%0d REGOUT1=%0d READREG2=%0d REGOUT2=%0d",
            $time,
            CLK,
            RESET,
            WRITEENABLE,
            WRITEREG,
            WRITEDATA,
            READREG1,
            REGOUT1,
            READREG2,
            REGOUT2
        );

    end


endmodule


