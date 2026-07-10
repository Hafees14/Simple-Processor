# Simple-Processor

An 8-bit single-cycle processor built incrementally in Verilog HDL, as part of the CO2070 Computer Architecture course (University of Peradeniya, Department of Computer Engineering).

**Status: In Progress** — Labs 2 to 6 completed. More labs to come.

## Overview

The processor is built step-by-step across a lab series, starting from individual components (ALU, Register File) and growing into a full single-cycle CPU with control logic, flow control instructions, an extended instruction set, and a data memory hierarchy.

Instructions are 32-bit fixed length, encoded as:

| Bits 31–24 | Bits 23–16 | Bits 15–8 | Bits 7–0 |
|---|---|---|---|
| OP-CODE | RD / IMM | RT | RS / IMM |

## Progress So Far

| Lab | Focus | What Was Added |
|---|---|---|
| **Lab 2** | ALU & Register File | 8-bit ALU (add, sub, and, or, mov, loadi functional units) and an 8×8 register file, each tested independently with testbenches |
| **Lab 3** | Integration & Control | Top-level `cpu` module integrating ALU + Register File with control logic and a Program Counter (PC); supports `add`, `sub`, `and`, `or`, `mov`, `loadi` |
| **Lab 4** | Flow Control | Added `j` (jump) and `beq` (branch if equal) support — new branch/jump target adder, ALU `ZERO` flag, and PC control logic |
| **Lab 4.5** *(Bonus)* | Extended ISA | Added `mult`, `sll`, `srl`, `sra`, `ror`, and `bne` instructions, sharing ALU functional units within the existing 3-bit ALUOP encoding |
| **Lab 5** | Data Memory | Added a 256-byte `data_memory` module with `lwd`, `lwi`, `swd`, `swi` instructions (register-direct and immediate addressing), and BUSYWAIT-based CPU stalling |
| **Lab 6** | Data Cache | Added a direct-mapped `dcache` module (8 lines, 4-byte blocks, write-back + write-allocate policy) sitting between the CPU and a new block-based `data_memory`; asynchronous hit detection (`#1` indexing + `#0.9` tag compare, overlapping `#1` data-word select) and a 3-state FSM (`IDLE`, `MEM_WRITE_BACK`, `MEM_READ`) handling dirty write-back, the 1-cycle write-back/fetch gap, and block install on miss |

## Instruction Set (current)

`add`, `sub`, `and`, `or`, `mov`, `loadi`, `j`, `beq`, `mult`, `sll`, `srl`, `sra`, `ror`, `bne`, `lwd`, `lwi`, `swd`, `swi`

*(unchanged from Lab 5 — Lab 6 adds a cache transparently below the existing memory interface; no new instructions were introduced.)*

## Memory Hierarchy (as of Lab 6)

```
CPU  <-->  Data Cache (dcache.v)  <-->  Data Memory (data_memory.v)
       8-bit byte address              6-bit block address
       BUSYWAIT/READ/WRITE              (4-byte blocks)
```

- **Mapping:** direct-mapped, 8 lines, 4-byte blocks — address split as `TAG[7:5] | INDEX[4:2] | OFFSET[1:0]`
- **Write policy:** write-back (dirty blocks flushed only on eviction) + write-allocate (write misses fetch the block before merging)
- **Timing:** `\`timescale 1ns/100ps` used throughout to model the required sub-nanosecond hit latencies (`#0.9`, `#1`, `#1.9`) alongside multi-cycle miss handling
- **Miss penalty:** ~21 cycles on a clean miss, ~42 cycles on a dirty miss (write-back + 1-cycle gap + fetch)

## Repository Structure

```
Simple-Processor/
├── src/                  # Verilog source modules (alu.v, reg_file.v, cpu.v, pc.v, data_memory.v, dcache.v)
├── testbenches/          # Testbenches (reg_file_tb.v, cpu_tb.v, cpu_cache_tb.v, timing_check.v)
├── docs/                 # Lab sheets, reports, block diagrams, timing screenshots, cache-vs-no-cache comparison report
├── .gitignore
└── README.md
```

Each module is overwritten/extended in place as labs progress, so the git commit history itself traces the CPU's evolution lab by lab.

## Tools Used

- **Icarus Verilog (`iverilog`)** — compilation and simulation
- **GTKWave** — waveform visualization for timing verification

## Running Simulations

```bash
# CPU + cache + memory integration test (Lab 6)
iverilog -o cpu_cache_sim testbenches/cpu_cache_tb.v src/*.v
vvp cpu_cache_sim
gtkwave cpu_cache_waves.vcd

# Standalone cache hit-timing check (Lab 6)
iverilog -o timing_sim testbenches/timing_check.v src/dcache.v
vvp timing_sim
```

## Team

Group 06 — University of Peradeniya, Department of Computer Engineering (Batch E22)

---

*More labs coming soon — this README will be updated as the processor grows.*
