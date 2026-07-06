# Simple-Processor

An 8-bit single-cycle processor built incrementally in Verilog HDL, as part of the CO2070 Computer Architecture course (University of Peradeniya, Department of Computer Engineering).

**Status: In Progress** — Labs 2 to 5 completed. More labs to come.

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

## Instruction Set (current)

`add`, `sub`, `and`, `or`, `mov`, `loadi`, `j`, `beq`, `mult`, `sll`, `srl`, `sra`, `ror`, `bne`, `lwd`, `lwi`, `swd`, `swi`

## Repository Structure

```
Simple-Processor/
├── src/                  # Verilog source modules (alu.v, reg_file.v, cpu.v, pc.v, data_memory.v)
├── testbenches/          # Testbenches (reg_file_tb.v, cpu_tb.v)
├── docs/                 # Lab sheets, reports, block diagrams, timing screenshots
├── .gitignore
└── README.md
```

Each module is overwritten/extended in place as labs progress, so the git commit history itself traces the CPU's evolution lab by lab.

## Tools Used

- **Icarus Verilog (`iverilog`)** — compilation and simulation
- **GTKWave** — waveform visualization for timing verification

## Running Simulations

```bash
iverilog -o cpu_sim testbenches/cpu_tb.v src/*.v
vvp cpu_sim
gtkwave cpu_lab5_waves.vcd   # or the relevant .vcd file
```

## Team

Group 06 — University of Peradeniya, Department of Computer Engineering (Batch E22)

---

*More labs coming soon — this README will be updated as the processor grows.*