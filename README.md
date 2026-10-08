# AMBA APB-to-AXI4-Lite Bridge with UVM Verification

An RTL bridge that translates **APB4** transactions into **AXI4-Lite**
transactions — address, control, data, response, and protocol sequencing
— with a from-scratch **UVM** verification environment: AXI and APB
agents, a reference-model scoreboard, constrained-random testing,
functional coverage, and SystemVerilog assertions.

## Features

- **APB4 slave / AXI4-Lite master bridge**: one APB transfer maps to one
  AXI4-Lite transaction. Handles independent AW/W handshaking, Mealy
  `PREADY` generation (no wasted cycle once the AXI response arrives),
  and back-to-back transfers with no forced idle gap.
- **Reusable UVM environment**: an active APB master agent and a
  *reactive* AXI4-Lite slave agent (the bridge is the AXI master, so the
  TB's AXI driver answers the bridge's requests according to configurable
  response policies — delay, response code, read data — rather than
  originating transactions itself).
- **Reference-model scoreboard**: `apb_axi_ref_model` encodes the
  APB<->AXI translation contract independently of the RTL, and the
  scoreboard checks both directions (APB request -> AXI request, AXI
  response -> APB response) with strict pairing so a dropped or
  duplicated transaction can't hide.
- **Constrained-random testing**: weighted address regions, write-strobe
  patterns, idle gaps, and AXI response/delay distributions, plus
  dedicated error-injection (`ERROR_ONLY`) and wait-state-stress
  (`SLOW`) test modes.
- **Functional coverage** over APB traffic shape and AXI response codes,
  crossed with direction, so error injection reaching the bus (not just
  being configured) is actually measured.
- **SystemVerilog assertions**, bound automatically into every bridge
  instance: APB protocol rules, AXI master-side VALID stability, and a
  single-outstanding-transaction invariant.
- **Synthesis + timing analysis scripts** for Vivado.
- **A cycle-accurate Python model with mutation testing** (see
  `model/`), used to validate the FSM/handshake logic and the
  scoreboard's checking rules independently, since no SystemVerilog
  simulator was available to run the actual RTL/UVM code — see
  "Verification Status" below.

## Repository Layout

```
apb-to-axi-bridge/
├── rtl/
│   ├── apb_if.sv                  # APB4 interface (master/slave modports)
│   ├── axi4_lite_if.sv            # AXI4-Lite interface (master/slave modports)
│   ├── apb_to_axi_bridge.sv       # the bridge FSM/datapath
│   └── apb_to_axi_sva.sv          # assertions, bound into every bridge instance
├── tb/uvm/
│   ├── apb_seq_item.sv / apb_agent.sv        # APB master agent (active)
│   ├── axi_txn.sv / axi_resp_item.sv / axi_agent.sv  # AXI slave agent (reactive)
│   ├── apb_axi_ref_model.sv / apb_axi_scoreboard.sv
│   ├── apb_axi_coverage.sv
│   ├── apb_axi_seq_lib.sv          # directed/random sequences + virtual sequences
│   ├── apb_axi_env.sv
│   ├── apb_axi_tests.sv            # directed / random / error / slow tests
│   ├── apb_axi_tb_pkg.sv
│   └── tb_top.sv
├── model/
│   ├── handshake_cycle_model.py    # cycle-accurate Python mirror of the design + TB
│   └── mutation_check.py           # proves the model's checks can actually fail
├── sim/
│   ├── run_sim.sh                  # Vivado xsim (non-project) flow
│   └── run_questa.do               # ModelSim/Questa flow
├── scripts/synth.tcl               # Vivado out-of-context synthesis + timing reports
├── constraints/apb_to_axi_bridge.xdc
└── docs/
    ├── architecture.md             # FSM, signal mapping, timing diagram, design notes
    └── verification.md             # UVM environment, scoreboard methodology, coverage
```

## Simulating

**Vivado (xsim):**
```bash
chmod +x sim/run_sim.sh
./sim/run_sim.sh                    # UVM_TESTNAME=bridge_directed_test
./sim/run_sim.sh bridge_random_test
./sim/run_sim.sh bridge_error_test
./sim/run_sim.sh bridge_slow_test
```

**ModelSim/Questa:**
```bash
vsim -c -do sim/run_questa.do
```

Watch for `UVM_ERROR` and the closing `SB_SUMMARY` / `COV_SUMMARY` /
`TEST_RESULT` lines. A `waves.vcd` is written every run for waveform-based
debugging in GTKWave or any other VCD viewer.

## Synthesis & Timing Analysis

```bash
vivado -mode batch -source scripts/synth.tcl
```

Produces `reports/utilization.rpt`, `reports/timing_summary.rpt`, and
`reports/timing_worst_paths.rpt`. Default target part is an Arty A7-35T
(`xc7a35ticsg324-1L`) at 100 MHz.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — FSM diagram, APB<->AXI
  signal mapping, timing diagram, design decisions, known limitations.
- [`docs/verification.md`](docs/verification.md) — UVM environment
  structure, the reactive AXI agent's design, the reference-model
  scoreboard's methodology, stimulus/test descriptions, and the coverage
  model.

## Publishing to GitHub

```bash
cd apb-to-axi-bridge
git init
git add .
git commit -m "Initial commit: APB-to-AXI4-Lite bridge with UVM verification"
git branch -M main
git remote add origin https://github.com/<your-username>/<repo-name>.git
git push -u origin main
```

## Verification Status — please read

This RTL and UVM environment were written and reviewed carefully, but
**have not been compiled or run in an actual SystemVerilog/UVM
simulator** — none was available in the environment this repo was
generated in. To get real evidence beyond a read-through, I built a
**cycle-accurate Python model** of the bridge FSM plus the testbench's
driver/monitor/scoreboard timing (`model/handshake_cycle_model.py`) and
ran 9,600 randomized transfers across four response modes (clean,
mixed-error, all-error, slow-slave) with zero deadlocks, protocol
violations, or scoreboard mismatches. A companion **mutation test**
(`model/mutation_check.py`) seeds six specific bugs — PSLVERR ignoring the
AXI response, dropped write strobes, corrupted read data, a wrong latched
address, a swapped read/write direction, and an ignored W handshake — and
confirms the model's checks catch every one, so that clean result isn't
vacuous.

That's real evidence the **handshake logic and checking rules** are
sound. It is **not** a substitute for actually compiling and simulating
the SystemVerilog/UVM code, which can't catch syntax errors, UVM-specific
plumbing mistakes, or anything specific to real simulator semantics.
**Please run `sim/run_sim.sh` (or the Questa flow) yourself** before
treating this as verified, working RTL for your portfolio — and expect to
spend a little time on simulator-specific setup (UVM library flags,
include paths) before the first clean compile.

## License

MIT — see [`LICENSE`](LICENSE).
