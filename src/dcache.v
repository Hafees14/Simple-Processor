/*
Module  : Data Cache
Design  : CO2070 Lab 6 - Direct-Mapped Data Cache
Team    : 06
Members : E/22/014, E/22/035

Description:

Direct-mapped, write-back, write-allocate data cache sitting between the CPU
and the (block-based) data memory. Presents the same byte-addressed
interface to the CPU that the plain data_memory module did in Lab 5, and
talks to the Lab 6 block-based data_memory on the other side.

────────────────────────────────────────────────────────────────────────────
 Address breakdown (8-bit CPU-side address)
────────────────────────────────────────────────────────────────────────────
    address[7:5] = TAG    (3 bits)
    address[4:2] = INDEX  (3 bits)  -> 8 cache lines (sets), direct-mapped
    address[1:0] = OFFSET (2 bits)  -> selects 1 of 4 bytes within the block

 Each cache line stores:
    - 1 valid bit
    - 1 dirty bit
    - 3-bit tag
    - 32-bit data block (4 bytes)

 Memory-side address is 6 bits = {tag, index}, matching the Lab 6
 data_memory's block-addressed (4-byte block) interface.

────────────────────────────────────────────────────────────────────────────
 Timing model (per lab spec)
────────────────────────────────────────────────────────────────────────────
    - Index extraction (asynchronous read of the indexed line)   : #1
    - Tag comparison (uses the extracted tag/valid)               : #0.9
        => hit/miss status known #1.9 after ADDRESS changes
    - Data-word selection from the extracted block (overlaps
      with tag comparison, both start right after indexing)       : #1
        => selected word ready #2.0 after ADDRESS changes
    - Write-hit: writing CPU data into the block                  : #1,
      applied synchronously (posedge clock) since it depends on
      the (already-resolved) hit status - cannot overlap with the
      tag comparison that produced that hit status.
    - Cache-line update after a block fetch from memory           : #1,
      applied synchronously at the edge the fetch completes.

 All of this comfortably resolves within the #2/#3 time-unit budget the
 CPU allows for a hit (lwd/swd have #2, lwi/swi have #3), so hits never
 stall the CPU.
────────────────────────────────────────────────────────────────────────────
 Cache controller FSM (Mealy-ish on the miss-detection edge, Moore afterwards)
────────────────────────────────────────────────────────────────────────────
    IDLE:
        - Every cycle, combinationally resolve hit/miss for whatever
          address is currently presented.
        - On a HIT (read or write): de-assert busywait immediately
          (asynchronously, within this same cycle) - no stall.
        - On a MISS: assert the appropriate memory control signal
          (mem_read if the evicted line isn't dirty, mem_write if it is)
          *immediately*, in this same IDLE cycle (Mealy output) - this is
          required so that the Lab-6 data_memory (which latches
          read/write on a level-sensitive block, then starts its
          internal multi-cycle transfer on the *next* posedge) sees a
          stable, already-asserted read/write signal *before* that next
          clock edge arrives, instead of racing it.
        - Next state: MEM_READ if evicted line clean, MEM_WRITE_BACK if dirty.

    MEM_WRITE_BACK:
        - Holds mem_write=1, mem_address = {old tag, index},
          mem_writedata = old (dirty) block, busywait=1.
        - Stays here while mem_busywait is high.
        - Once mem_busywait falls: move to MEM_READ. Note this is a plain
          Moore transition (mem_read only becomes 1 once we are actually
          *in* MEM_READ) - this naturally creates exactly the 1-cycle gap
          the spec calls for between write-back completing and the read
          starting, because the newly-entered MEM_READ state's mem_read
          output needs a full cycle to propagate through data_memory's
          own level-sensitive read/write detector before its internal
          posedge-triggered transfer logic will see it.

    MEM_READ:
        - Holds mem_read=1, mem_address = {new tag, index}, busywait=1.
        - Stays here while mem_busywait is high.
        - Once mem_busywait falls: the fetched 32-bit block (mem_readdata)
          is written into the cache line (tag/valid/dirty updated,
          dirty cleared) synchronously, with a #1 latency, and the FSM
          returns to IDLE. The CPU's original request (still being held
          steady during the stall) is then naturally re-resolved as an
          ordinary hit on the next IDLE evaluation.
*/

`timescale 1ns/100ps

module dcache(
    // CPU-facing interface (identical shape to the Lab 5 data_memory)
    clock,
    reset,
    read,
    write,
    address,
    writedata,
    readdata,
    busywait,

    // Memory-facing interface (Lab 6 block-based data_memory)
    mem_read,
    mem_write,
    mem_address,
    mem_writedata,
    mem_readdata,
    mem_busywait
);

    // ── CPU-facing ports ──────────────────────────────────────────────────
    input             clock;
    input             reset;
    input             read;
    input             write;
    input      [7:0]  address;
    input      [7:0]  writedata;
    output reg [7:0]  readdata;
    output reg        busywait;

    // ── Memory-facing ports ───────────────────────────────────────────────
    output reg        mem_read;
    output reg        mem_write;
    output reg [5:0]  mem_address;
    output reg [31:0] mem_writedata;
    input      [31:0] mem_readdata;
    input             mem_busywait;

    // ── Address breakdown ─────────────────────────────────────────────────
    wire [2:0] tag_in  = address[7:5];   // tag of the incoming request
    wire [2:0] index   = address[4:2];   // selects one of 8 cache lines
    wire [1:0] offset  = address[1:0];   // selects 1 of 4 bytes in the block

    // ── Cache storage arrays (8 direct-mapped lines) ──────────────────────
    reg [31:0] cache_data  [0:7];
    reg [2:0]  cache_tag   [0:7];
    reg        cache_valid [0:7];
    reg        cache_dirty [0:7];

    // ── Asynchronous indexing (extract the addressed line): #1 latency ───
    reg [31:0] ext_data;
    reg [2:0]  ext_tag;
    reg        ext_valid;
    reg        ext_dirty;

    always @(*)
    begin
        #1;
        ext_data  = cache_data[index];
        ext_tag   = cache_tag[index];
        ext_valid = cache_valid[index];
        ext_dirty = cache_dirty[index];
    end

    // ── Tag comparison / hit detection: further #0.9 latency ─────────────
    // Total latency from ADDRESS change to hit being known: #1 + #0.9 = #1.9
    reg hit;
    reg dirty;   // dirty bit of the line currently occupying this index
                 // (relevant when we are about to evict it on a miss)

    always @(*)
    begin
        #0.9;
        hit   = ext_valid && (ext_tag == tag_in);
        dirty = ext_dirty;
    end

    // ── Data-word selection: #1 latency, overlaps with tag comparison ────
    // (both start as soon as indexing finishes, i.e. #1 after ADDRESS
    //  changes) -> selected word ready #1 + #1 = #2 after ADDRESS changes
    reg [7:0] selected_word;

    always @(*)
    begin
        #1;
        case (offset)
            2'b00: selected_word = ext_data[7:0];
            2'b01: selected_word = ext_data[15:8];
            2'b10: selected_word = ext_data[23:16];
            2'b11: selected_word = ext_data[31:24];
        endcase
    end

    /* ──────────────────────────────────────────────────────────────────
       Cache Controller FSM
       ────────────────────────────────────────────────────────────────── */

    parameter IDLE           = 2'b00,
              MEM_READ       = 2'b01,
              MEM_WRITE_BACK = 2'b10;

    reg [1:0] state, next_state;

    // ── Combinational next-state logic ────────────────────────────────
    always @(*)
    begin
        case (state)

            IDLE:
                if ((read || write) && !hit)
                begin
                    if (!dirty)
                        next_state = MEM_READ;        // clean line: fetch directly
                    else
                        next_state = MEM_WRITE_BACK;  // dirty line: evict first
                end
                else
                    next_state = IDLE;

            MEM_WRITE_BACK:
                if (!mem_busywait)
                    next_state = MEM_READ;   // write-back done -> go fetch
                                              // (the 1-cycle gap falls out
                                              //  naturally, see header note)
                else
                    next_state = MEM_WRITE_BACK;

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
    // NOTE: the IDLE case is Mealy-style (depends on read/write/hit/dirty,
    // not just `state`) precisely because the memory READ/WRITE signal
    // must be asserted "as soon as the miss is detected", i.e. within the
    // very same cycle the miss is first seen in IDLE - not one cycle
    // later, which is what a pure Moore output (driven only by `state`)
    // would give.
    always @(*)
    begin
        case (state)

            IDLE:
            begin
                if ((read || write) && !hit)
                begin
                    // Miss: kick off the memory access immediately.
                    if (!dirty)
                    begin
                        mem_read      = 1'b1;
                        mem_write     = 1'b0;
                        mem_address   = {tag_in, index};   // fetch the NEW block
                        mem_writedata = 32'dx;
                    end
                    else
                    begin
                        mem_read      = 1'b0;
                        mem_write     = 1'b1;
                        mem_address   = {ext_tag, index};  // evict the OLD block
                        mem_writedata = ext_data;
                    end
                    busywait = 1'b1;
                    readdata = 8'dx;
                end
                else if (read || write)
                begin
                    // Hit: resolve asynchronously, no stall.
                    mem_read      = 1'b0;
                    mem_write     = 1'b0;
                    mem_address   = 6'dx;
                    mem_writedata = 32'dx;
                    busywait      = 1'b0;
                    readdata      = read ? selected_word : 8'dx;
                end
                else
                begin
                    // No request this cycle.
                    mem_read      = 1'b0;
                    mem_write     = 1'b0;
                    mem_address   = 6'dx;
                    mem_writedata = 32'dx;
                    busywait      = 1'b0;
                    readdata      = 8'dx;
                end
            end

            MEM_WRITE_BACK:
            begin
                mem_read      = 1'b0;
                mem_write     = 1'b1;
                mem_address   = {ext_tag, index};
                mem_writedata = ext_data;
                busywait      = 1'b1;
                readdata      = 8'dx;
            end

            MEM_READ:
            begin
                mem_read      = 1'b1;
                mem_write     = 1'b0;
                mem_address   = {tag_in, index};
                mem_writedata = 32'dx;
                busywait      = 1'b1;
                readdata      = 8'dx;
            end

            default:
            begin
                mem_read      = 1'b0;
                mem_write     = 1'b0;
                mem_address   = 6'dx;
                mem_writedata = 32'dx;
                busywait      = 1'b0;
                readdata      = 8'dx;
            end

        endcase
    end

    // ── Sequential logic: state register ──────────────────────────────
    // NOTE: uses a NONBLOCKING assignment deliberately. There is a second,
    // separate always @(posedge clock) block below (the cache storage
    // writes) that checks the value of `state` at this same edge to decide
    // whether a just-completed fetch should be installed into the cache
    // line. If `state` were updated here with a blocking assignment, that
    // second block could race against this one and see the *already
    // updated* state (whichever block Verilog happens to run first),
    // silently causing it to never fire and the fetched block to never
    // get installed. Nonblocking assignment guarantees every block
    // triggered by this same edge reads the old value of `state`,
    // regardless of scheduling order.
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
                cache_dirty[k] = 1'b0;
                cache_tag[k]   = 3'b000;
                cache_data[k]  = 32'b0;
            end
        end
        else if (state == IDLE && write && hit)
        begin
            // Write-hit: merge the CPU's byte into the block, mark dirty.
            // (Cannot overlap with tag comparison - only fires once hit
            //  is already known, and takes effect at the *next* edge,
            //  i.e. right here, synchronously.)
            #1;
            case (offset)
                2'b00: cache_data[index][7:0]   = writedata;
                2'b01: cache_data[index][15:8]  = writedata;
                2'b10: cache_data[index][23:16] = writedata;
                2'b11: cache_data[index][31:24] = writedata;
            endcase
            cache_dirty[index] = 1'b1;
            // valid/tag unchanged - this line was already a hit.
        end
        else if (state == MEM_READ && !mem_busywait)
        begin
            // Fetch just completed: install the new block into the line.
            #1;
            cache_data[index]  = mem_readdata;
            cache_tag[index]   = tag_in;
            cache_valid[index] = 1'b1;
            cache_dirty[index] = 1'b0;   // freshly fetched from memory: clean
        end
    end

endmodule
