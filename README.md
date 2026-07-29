# Simple-Processor

An 8-bit single-cycle processor built incrementally in Verilog HDL, as part of the CO2070 Computer Architecture course (University of Peradeniya, Department of Computer Engineering).

**Status: Complete** — Labs 2 to 7 finished.

## Overview

The processor is built step-by-step across a lab series, starting from individual components (ALU, Register File) and growing into a full single-cycle CPU with control logic, flow control instructions, an extended instruction set, and a two-level memory hierarchy — a write-back data cache and a read-only instruction cache — verified end-to-end with a real Fibonacci-sequence program.

Instructions are 32-bit fixed length, encoded as:

| Bits 31–24 | Bits 23–16 | Bits 15–8 | Bits 7–0 |
|---|---|---|---|
| OP-CODE | RD / IMM | RT | RS / IMM |

## Progress

| Lab | Focus | What Was Added |
|---|---|---|
| **Lab 2** | ALU & Register File | 8-bit ALU (add, sub, and, or, mov, loadi functional units) and an 8×8 register file, each tested independently with testbenches |
| **Lab 3** | Integration & Control | Top-level `cpu` module integrating ALU + Register File with control logic and a Program Counter (PC); supports `add`, `sub`, `and`, `or`, `mov`, `loadi` |
| **Lab 4** | Flow Control | Added `j` (jump) and `beq` (branch if equal) support — new branch/jump target adder, ALU `ZERO` flag, and PC control logic |
| **Lab 4.5** *(Bonus)* | Extended ISA | Added `mult`, `sll`, `srl`, `sra`, `ror`, and `bne` instructions, sharing ALU functional units within the existing 3-bit ALUOP encoding |
| **Lab 5** | Data Memory | Added a 256-byte `data_memory` module with `lwd`, `lwi`, `swd`, `swi` instructions (register-direct and immediate addressing), and BUSYWAIT-based CPU stalling |
| **Lab 6** | Data Cache | Added a direct-mapped `dcache` module (8 lines, 4-byte blocks, write-back + write-allocate policy) sitting between the CPU and a block-based `data_memory`; asynchronous hit detection (`#1` indexing + `#0.9` tag compare, overlapping `#1` data-word select) and a 3-state FSM (`IDLE`, `MEM_WRITE_BACK`, `MEM_READ`) handling dirty write-back, the 1-cycle write-back/fetch gap, and block install on miss |
| **Lab 7** | Instruction Cache | Added a direct-mapped, read-only `icache` module (8 lines, 16-byte blocks, 4 words/block) sitting between the PC and a block-based `instruction_memory`; same asynchronous timing discipline as Lab 6 (`#1` index, `#0.9` tag compare, `#1` word-select). A new `IFETCH_BUSYWAIT` signal jointly gates PC advancement and register-file writes alongside the Lab 6 `MEM_BUSYWAIT`. Verified with a full Fibonacci-sequence program (13 terms, real conditional loop) run through both caches together |

## Instruction Set

`add`, `sub`, `and`, `or`, `mov`, `loadi`, `j`, `beq`, `mult`, `sll`, `srl`, `sra`, `ror`, `bne`, `lwd`, `lwi`, `swd`, `swi`

The ISA has been unchanged since Lab 5 — Labs 6 and 7 add caching transparently below the existing memory interfaces; no new instructions were introduced.

## Memory Hierarchy (final, as of Lab 7)

```
                Instruction Cache (icache.v)  <-->  Instruction Memory (instruction_memory.v)
PC/Fetch  <-->  8 lines, 16-byte blocks             16-byte blocks
                read-only, no write-back

                Data Cache (dcache.v)         <-->  Data Memory (data_memory.v)
CPU       <-->  8 lines, 4-byte blocks               4-byte blocks
                write-back + write-allocate
```

| | Instruction Cache | Data Cache |
|---|---|---|
| **Mapping** | Direct-mapped, 8 lines, 16-byte blocks (4 words/block) — `TAG[9:7] \| INDEX[6:4] \| WORDSEL[3:2]` | Direct-mapped, 8 lines, 4-byte blocks — `TAG[7:5] \| INDEX[4:2] \| OFFSET[1:0]` |
| **Write policy** | Read-only — no dirty bit, missed blocks are simply discarded and re-fetched | Write-back (dirty blocks flushed only on eviction) + write-allocate (write misses fetch the block before merging) |
| **Timing** | `#1` index, `#0.9` tag compare (hit/miss known at `#1.9`), `#1` word-select (word ready at `#2.0`) | Same `#1` / `#0.9` / `#1` structure as the instruction cache |
| **Stall signal** | `IFETCH_BUSYWAIT` — gates PC advancement and register-file writes | `MEM_BUSYWAIT` — gates the same, jointly with `IFETCH_BUSYWAIT` |

`\`timescale 1ns/100ps` is used throughout both caches to model the required sub-nanosecond hit latencies alongside multi-cycle miss handling (write-back + fetch on a dirty data-cache miss; simple re-fetch on an instruction-cache miss).

## Verification Program

Lab 7 is verified with a complete Fibonacci-sequence generator rather than a handful of instructions: it computes fib(0)–fib(12) (0 through 144, the largest value that fits an 8-bit word) using a real conditional loop of 11 iterations, storing every value to data memory through the Lab 6 data cache, then reading the last one back to confirm correctness — exercising the instruction cache, data cache, and full CPU datapath together in one run.

## Repository Structure

```
Simple-Processor/
├── src/                  # Verilog source modules
│   ├── alu.v
│   ├── reg_file.v
│   ├── pc.v
│   ├── cpu.v
│   ├── data_memory.v
│   ├── dcache.v                  # Lab 6
│   ├── instruction_memory.v      # Lab 7
│   ├── icache.v                  # Lab 7
│   └── icache_timing_check.v     # Lab 7 standalone hit-timing check
├── testbenches/          # Testbenches and captured waveforms, by lab
│   ├── alu_tb.v, reg_file_tb.v
│   ├── cpu_tb(L3/L4/L4_5/L5).v
│   ├── cpu_cache_tb(L6).v
│   ├── cpu_icache_fabinocci_tb(L7).v
│   └── *_wavedata*.vcd / *_waves(Lx).vcd
├── docs/                 # Lab sheets, per-lab reports, block diagrams, screenshots
├── .gitignore
└── README.md
```

Each module is overwritten/extended in place as labs progress, so the git commit history itself traces the CPU's evolution lab by lab.

## Tools Used

- **Icarus Verilog (`iverilog`)** — compilation and simulation
- **GTKWave** — waveform visualization for timing verification

## Running Simulations

```bash
# Full CPU + instruction cache + data cache Fibonacci test (Lab 7, final)
iverilog -o cpu_icache_sim "testbenches/cpu_icache_fabinocci_tb(L7).v" src/*.v
vvp cpu_icache_sim
gtkwave "testbenches/cpu_icache_waves(L7).vcd"

# Standalone instruction-cache hit-timing check (Lab 7)
iverilog -o icache_timing_sim src/icache_timing_check.v src/icache.v
vvp icache_timing_sim

# CPU + data cache + memory integration test (Lab 6)
iverilog -o cpu_cache_sim "testbenches/cpu_cache_tb(L6).v" src/*.v
vvp cpu_cache_sim
gtkwave "testbenches/cpu_cache_waves(L6).vcd"
```

## Team

Group 06 — University of Peradeniya, Department of Computer Engineering (Batch E22)
E/22/014 · E/22/034 · E/22/035 · E/22/036
