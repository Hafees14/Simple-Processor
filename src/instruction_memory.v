/*
Module	: 256x8-bit instruction memory (16-Byte blocks)
Author	: Isuru Nawinne
Date		: 10/06/2020
Modified: Team 06 (E/22/014, E/22/035) - Lab 7 Fibonacci test program

Description	:

This file presents a primitive instruction memory module for CO2070 Lab 7.
This memory allows instructions to be read as 16-Byte blocks.

────────────────────────────────────────────────────────────────────────────
 TEST PROGRAM: Fibonacci sequence generator (per instructor's request for a
 complete, realistic program rather than a handful of instructions)
────────────────────────────────────────────────────────────────────────────

 Computes the first 13 Fibonacci numbers (fib(0)..fib(12): 0,1,1,2,3,5,8,13,
 21,34,55,89,144 - the largest that still fits in an 8-bit data word) and
 stores every one of them to data memory (through the Lab 6 data cache),
 then reads the last one back to confirm correctness, using a real
 conditional loop (11 iterations) rather than straight-line code.

 Registers used:
   r0 = fib(n-2)  (running "previous" value)
   r1 = fib(n-1)  (running "current" value)
   r2 = fib(n)    (newly computed value, scratch)
   r3 = loop counter (counts down from 11 to 0)
   r4 = data-memory write pointer (address of the next fib value to store)
   r5 = constant 1  (decrement / increment step)
   r6 = constant 0  (loop-exit comparison target)
   r7 = verification register (holds fib(12) read back at the end)

 Assembly:
   ; ── setup (words 0-7, blocks 0-1) ──────────────────────────────────
   word0  loadi r0, 0          ; fib(0) = 0
   word1  loadi r1, 1          ; fib(1) = 1
   word2  loadi r4, 2          ; next store address = 2
   word3  loadi r5, 1          ; constant 1
   word4  loadi r6, 0          ; constant 0
   word5  loadi r3, 11         ; loop 11 times -> generates fib(2)..fib(12)
   word6  swi   r0, 0x00       ; mem[0] = fib(0)
   word7  swi   r1, 0x01       ; mem[1] = fib(1)

   ; ── loop body (words 8-14, blocks 2-3) ─────────────────────────────
   LOOP:
   word8  add   r2, r0, r1     ; r2 = r0 + r1        (next fib number)
   word9  swd   r2, r4         ; mem[r4] = r2         (store it)
   word10 mov   r0, r1         ; r0 = r1              (shift window)
   word11 mov   r1, r2         ; r1 = r2
   word12 add   r4, r4, r5     ; r4 = r4 + 1           (next address)
   word13 sub   r3, r3, r5     ; r3 = r3 - 1           (decrement counter)
   word14 bne   LOOP, r3, r6   ; loop again while r3 != 0

   ; ── verification tail (words 15-16, blocks 3-4) ────────────────────
   word15 lwi   r7, 0x0C       ; r7 = mem[12]  (should be fib(12) = 144)
   word16 j     -1             ; halt (infinite self-jump)

 This exercises FIVE cache blocks (indices 0-4), a genuine data-dependent
 loop executed 11 times (crossing the block-2/block-3 boundary on every
 single iteration), real arithmetic (add/sub/mov), a conditional branch
 (bne) whose condition changes every iteration, and both register-direct
 (swd) and immediate (swi/lwi) data-memory addressing - i.e. a complete,
 representative program, not a toy sequence.
*/

module instruction_memory(
	clock,
	read,
    address,
    readinst,
	busywait
);
input				clock;
input				read;
input[5:0]			address;
output reg [127:0]	readinst;
output	reg			busywait;

reg readaccess;

//Declare memory array 1024x8-bits 
reg [7:0] memory_array [1023:0];

//Initialize instruction memory
initial
begin
	busywait = 0;
	readaccess = 0;

    // ── Block 0 (words 0-3, bytes 0x00-0x0F) ──────────────────────────────
    {memory_array[10'd3],  memory_array[10'd2],  memory_array[10'd1],  memory_array[10'd0]}  = 32'h00_00_00_00; // loadi r0, 0
    {memory_array[10'd7],  memory_array[10'd6],  memory_array[10'd5],  memory_array[10'd4]}  = 32'h00_01_00_01; // loadi r1, 1
    {memory_array[10'd11], memory_array[10'd10], memory_array[10'd9],  memory_array[10'd8]}  = 32'h00_04_00_02; // loadi r4, 2
    {memory_array[10'd15], memory_array[10'd14], memory_array[10'd13], memory_array[10'd12]} = 32'h00_05_00_01; // loadi r5, 1

    // ── Block 1 (words 4-7, bytes 0x10-0x1F) ──────────────────────────────
    {memory_array[10'd19], memory_array[10'd18], memory_array[10'd17], memory_array[10'd16]} = 32'h00_06_00_00; // loadi r6, 0
    {memory_array[10'd23], memory_array[10'd22], memory_array[10'd21], memory_array[10'd20]} = 32'h00_03_00_0B; // loadi r3, 11
    {memory_array[10'd27], memory_array[10'd26], memory_array[10'd25], memory_array[10'd24]} = 32'h13_00_00_00; // swi r0, 0x00
    {memory_array[10'd31], memory_array[10'd30], memory_array[10'd29], memory_array[10'd28]} = 32'h13_00_01_01; // swi r1, 0x01

    // ── Block 2 (words 8-11, bytes 0x20-0x2F) - LOOP body, part A ─────────
    {memory_array[10'd35], memory_array[10'd34], memory_array[10'd33], memory_array[10'd32]} = 32'h02_02_00_01; // add r2,r0,r1
    {memory_array[10'd39], memory_array[10'd38], memory_array[10'd37], memory_array[10'd36]} = 32'h12_00_02_04; // swd r2,r4
    {memory_array[10'd43], memory_array[10'd42], memory_array[10'd41], memory_array[10'd40]} = 32'h01_00_00_01; // mov r0,r1
    {memory_array[10'd47], memory_array[10'd46], memory_array[10'd45], memory_array[10'd44]} = 32'h01_01_00_02; // mov r1,r2

    // ── Block 3 (words 12-15, bytes 0x30-0x3F) - LOOP body, part B + tail ─
    {memory_array[10'd51], memory_array[10'd50], memory_array[10'd49], memory_array[10'd48]} = 32'h02_04_04_05; // add r4,r4,r5
    {memory_array[10'd55], memory_array[10'd54], memory_array[10'd53], memory_array[10'd52]} = 32'h03_03_03_05; // sub r3,r3,r5
    {memory_array[10'd59], memory_array[10'd58], memory_array[10'd57], memory_array[10'd56]} = 32'h0D_F9_03_06; // bne -7,r3,r6  (-> word8)
    {memory_array[10'd63], memory_array[10'd62], memory_array[10'd61], memory_array[10'd60]} = 32'h11_07_00_0C; // lwi r7, 0x0C

    // ── Block 4 (word 16, bytes 0x40-0x4F) - halt ─────────────────────────
    {memory_array[10'd67], memory_array[10'd66], memory_array[10'd65], memory_array[10'd64]} = 32'h06_FF_00_00; // j -1 (halt)
end

//Detecting an incoming memory access
always @(read)
begin
    busywait = (read)? 1 : 0;
    readaccess = (read)? 1 : 0;
end

//Reading
always @(posedge clock)
begin
	if(readaccess)
	begin
		readinst[7:0]     = #40 memory_array[{address,4'b0000}];
		readinst[15:8]    = #40 memory_array[{address,4'b0001}];
		readinst[23:16]   = #40 memory_array[{address,4'b0010}];
		readinst[31:24]   = #40 memory_array[{address,4'b0011}];
		readinst[39:32]   = #40 memory_array[{address,4'b0100}];
		readinst[47:40]   = #40 memory_array[{address,4'b0101}];
		readinst[55:48]   = #40 memory_array[{address,4'b0110}];
		readinst[63:56]   = #40 memory_array[{address,4'b0111}];
		readinst[71:64]   = #40 memory_array[{address,4'b1000}];
		readinst[79:72]   = #40 memory_array[{address,4'b1001}];
		readinst[87:80]   = #40 memory_array[{address,4'b1010}];
		readinst[95:88]   = #40 memory_array[{address,4'b1011}];
		readinst[103:96]  = #40 memory_array[{address,4'b1100}];
		readinst[111:104] = #40 memory_array[{address,4'b1101}];
		readinst[119:112] = #40 memory_array[{address,4'b1110}];
		readinst[127:120] = #40 memory_array[{address,4'b1111}];
		busywait = 0;
		readaccess = 0;
	end
end
 
endmodule
