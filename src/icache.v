/*
Module  : Instruction Cache
Design  : CO2070 Lab 7 - Direct-Mapped Instruction Cache
Team    : 06
Members : E/22/014, E/22/035

Description:

Direct-mapped, read-only instruction cache sitting between the CPU (program
counter) and the block-based instruction memory. No dirty bit / write-back
logic is needed here (unlike dcache.v in Lab 6) because the CPU never writes
to instruction memory - a missed/evicted block can simply be discarded and
re-fetched later if needed again.

────────────────────────────────────────────────────────────────────────────
 Address breakdown (10-bit CPU-side word address, from PC)
────────────────────────────────────────────────────────────────────────────
    Cache size       = 128 Bytes
    Block size       = 16 Bytes  -> 8 blocks/lines (cache holds 128/16 = 8)
    Instruction word = 4 Bytes   -> 4 words per block

    address[9:7] = TAG    (3 bits)
    address[6:4] = INDEX  (3 bits)  -> 8 cache lines (sets), direct-mapped
    address[3:2] = WORDSEL(2 bits)  -> selects 1 of 4 words within the block
    address[1:0] = always 2'b00 (word-aligned address, per lab spec)

 Each cache line stores:
    - 1 valid bit
    - 3-bit tag
    - 128-bit data block (16 bytes = 4 instruction words)

 Memory-side address is 6 bits = {tag, index}, matching the Lab 7
 instruction_memory's block-addressed (16-byte block) interface.

────────────────────────────────────────────────────────────────────────────
 Timing model (per lab spec) - identical structure to the Lab 6 data cache
────────────────────────────────────────────────────────────────────────────
    - Index extraction (asynchronous read of the indexed line)   : #1
    - Tag comparison (uses the extracted tag/valid)               : #0.9
        => hit/miss status known #1.9 after ADDRESS changes
    - Instruction-word selection from the extracted block
      (overlaps with tag comparison, both start right after
      indexing finishes)                                          : #1
        => selected word ready #2.0 after ADDRESS changes

 This comfortably resolves within the CPU's fetch timing budget, so hits
 never stall the CPU.

────────────────────────────────────────────────────────────────────────────
 Cache controller FSM (Mealy-ish on the miss-detection edge, Moore afterwards)
────────────────────────────────────────────────────────────────────────────
    IDLE:
        - Every cycle, combinationally resolve hit/miss for whatever
          address the PC is currently presenting.
        - On a HIT: de-assert busywait immediately (asynchronously,
          within this same cycle) - no stall.
        - On a MISS: assert mem_read *immediately*, in this same IDLE
          cycle (Mealy output) - required so the block-based
          instruction_memory (which latches `read` on a level-sensitive
          block, then starts its internal multi-cycle transfer on the
          *next* posedge) sees a stable, already-asserted read signal
          before that next clock edge arrives, instead of racing it.
        - Next state: MEM_READ.

    MEM_READ:
        - Holds mem_read=1, mem_address = {tag, index}, busywait=1.
        - Stays here while mem_busywait is high (fetch takes
          16 bytes x 5 cycles/byte = 80 cycles).
        - Once mem_busywait falls: the fetched 128-bit block
          (mem_readinst) is written into the cache line (tag/valid
          updated) synchronously, with a #1 latency, and the FSM
          returns to IDLE. The CPU's original fetch request (still
          being held steady during the stall, since PC is frozen) is
          then naturally re-resolved as an ordinary hit on the next
          IDLE evaluation - #1.9 after the block is installed.

    Total miss penalty: 80 (fetch) + 1 (install/overhead) = 81 cycles,
    matching the lab sheet's stated figure exactly.
*/

`timescale 1ns/100ps

module icache(
    // CPU-facing interface
    clock,
    reset,
    read,
    address,
    instword,
    busywait,

    // Memory-facing interface (Lab 7 block-based instruction_memory)
    mem_read,
    mem_address,
    mem_readinst,
    mem_busywait
);

    // ── CPU-facing ports ──────────────────────────────────────────────────
    input              clock;
    input              reset;
    input              read;          // 1 whenever the CPU wants to fetch
    input       [9:0]  address;       // word address from the PC
    output reg  [31:0] instword;      // fetched instruction word
    output reg         busywait;      // stall signal to the CPU

    // ── Memory-facing ports ───────────────────────────────────────────────
    output reg         mem_read;
    output reg  [5:0]  mem_address;
    input       [127:0] mem_readinst;
    input              mem_busywait;

    // ── Address breakdown ─────────────────────────────────────────────────
    wire [2:0] tag_in   = address[9:7];   // tag of the incoming request
    wire [2:0] index    = address[6:4];   // selects one of 8 cache lines
    wire [1:0] wordsel  = address[3:2];   // selects 1 of 4 words in the block
    // address[1:0] is always 2'b00 (word-aligned PC) and is not used here.

    // ── Cache storage arrays (8 direct-mapped lines) ──────────────────────
    reg [127:0] cache_data  [0:7];
    reg [2:0]   cache_tag   [0:7];
    reg         cache_valid [0:7];

    // ── Asynchronous indexing (extract the addressed line): #1 latency ───
    reg [127:0] ext_data;
    reg [2:0]   ext_tag;
    reg         ext_valid;

    always @(*)
    begin
        #1;
        ext_data  = cache_data[index];
        ext_tag   = cache_tag[index];
        ext_valid = cache_valid[index];
    end

    // ── Tag comparison / hit detection: further #0.9 latency ─────────────
    // Total latency from ADDRESS change to hit being known: #1 + #0.9 = #1.9
    reg hit;

    always @(*)
    begin
        #0.9;
        hit = ext_valid && (ext_tag == tag_in);
    end

    // ── Instruction-word selection: #1 latency, overlaps tag comparison ──
    // (both start as soon as indexing finishes, i.e. #1 after ADDRESS
    //  changes) -> selected word ready #1 + #1 = #2 after ADDRESS changes
    reg [31:0] selected_word;

    always @(*)
    begin
        #1;
        case (wordsel)
            2'b00: selected_word = ext_data[31:0];
            2'b01: selected_word = ext_data[63:32];
            2'b10: selected_word = ext_data[95:64];
            2'b11: selected_word = ext_data[127:96];
        endcase
    end

    /* ──────────────────────────────────────────────────────────────────
       Cache Controller FSM
       ────────────────────────────────────────────────────────────────── */

    parameter IDLE     = 1'b0,
              MEM_READ = 1'b1;

    reg state, next_state;

    // ── Combinational next-state logic ────────────────────────────────
    always @(*)
    begin
        case (state)

            IDLE:
                if (read && !hit)
                    next_state = MEM_READ;   // miss: go fetch the block
                else
                    next_state = IDLE;

            MEM_READ:
                if (!mem_busywait)
                    next_state = IDLE;       // fetch done -> resolve as a hit
                else
                    next_state = MEM_READ;

            default:
                next_state = IDLE;

        endcase
    end

    // ── Combinational output logic ────────────────────────────────────
    // NOTE: the IDLE case is Mealy-style (depends on read/hit, not just
    // `state`) precisely because mem_read must be asserted "as soon as
    // the miss is detected", i.e. within the very same cycle the miss is
    // first seen in IDLE - not one cycle later, which is what a pure
    // Moore output (driven only by `state`) would give.
    always @(*)
    begin
        case (state)

            IDLE:
            begin
                if (read && !hit)
                begin
                    // Miss: kick off the memory fetch immediately.
                    mem_read    = 1'b1;
                    mem_address = {tag_in, index};
                    busywait    = 1'b1;
                    instword    = 32'dx;
                end
                else if (read)
                begin
                    // Hit: resolve asynchronously, no stall.
                    mem_read    = 1'b0;
                    mem_address = 6'dx;
                    busywait    = 1'b0;
                    instword    = selected_word;
                end
                else
                begin
                    // No fetch request this cycle.
                    mem_read    = 1'b0;
                    mem_address = 6'dx;
                    busywait    = 1'b0;
                    instword    = 32'dx;
                end
            end

            MEM_READ:
            begin
                mem_read    = 1'b1;
                mem_address = {tag_in, index};
                busywait    = 1'b1;
                instword    = 32'dx;
            end

            default:
            begin
                mem_read    = 1'b0;
                mem_address = 6'dx;
                busywait    = 1'b0;
                instword    = 32'dx;
            end

        endcase
    end

    // ── Sequential logic: state register ──────────────────────────────
    // Nonblocking assignment for the same reason documented in dcache.v:
    // the storage-write block below also keys off `state` on this same
    // edge, and must see the pre-edge value regardless of block
    // scheduling order.
    always @(posedge clock)
    begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    /* ──────────────────────────────────────────────────────────────────
       Cache storage writes (the actual datapath, separate from the FSM's
       state register above)
       ────────────────────────────────────────────────────────────────── */

    integer k;

    always @(posedge clock)
    begin
        if (reset)
        begin
            // Invalidate every line on reset.
            for (k = 0; k < 8; k = k + 1)
            begin
                cache_valid[k] = 1'b0;
                cache_tag[k]   = 3'b000;
                cache_data[k]  = 128'b0;
            end
        end
        else if (state == MEM_READ && !mem_busywait)
        begin
            // Fetch just completed: install the new block into the line.
            #1;
            cache_data[index]  = mem_readinst;
            cache_tag[index]   = tag_in;
            cache_valid[index] = 1'b1;
        end
    end

endmodule
