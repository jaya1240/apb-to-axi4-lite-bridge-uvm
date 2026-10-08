# Verification

## Environment

```
tb_top
 ├─ apb_if / axi4_lite_if           (two protocol interfaces)
 ├─ apb_to_axi_bridge (DUT)         (bound with apb_to_axi_sva assertions)
 └─ apb_axi_env
     ├─ apb_agent                    APB *master* (active)
     │   ├─ apb_sequencer
     │   ├─ apb_driver               SETUP/ACCESS phase driver, honors wait states
     │   └─ apb_monitor              reconstructs transfers, measures wait states + idle gaps
     ├─ axi_agent                    AXI4-Lite *slave* (reactive responder)
     │   ├─ axi_sequencer            supplies *response policies*
     │   ├─ axi_driver               waits for the bridge's request, answers per policy
     │   └─ axi_monitor              reconstructs AW+W+B / AR+R transactions
     ├─ apb_axi_scoreboard           correlates APB <-> AXI 1:1, checks via the ref model
     │   └─ apb_axi_ref_model        translation contract (forward + return direction)
     ├─ apb_axi_coverage             functional coverage (APB side + AXI side)
     └─ bridge_virtual_sequencer     coordinates the two agents' sequences
```

### Why the AXI agent is reactive

The bridge is the AXI **master**: *it* originates addresses and write data.
So the testbench's AXI agent can't "send transactions" in the usual
sense. Instead, its sequences generate **response policies**
(`axi_resp_item`): how many cycles to delay each ready/valid, which
response code to return (OKAY / SLVERR / DECERR), and what read data to
hand back. The driver waits for a request from the bridge, pulls one
policy item, and answers accordingly. This is the standard pattern for
verifying a bus-master DUT against a UVM-modeled slave.

## Reference Model and Scoreboard

`apb_axi_ref_model` encodes the translation contract directly from the
protocol mapping (not from the RTL):

- **Forward:** an APB request must appear on AXI with the same direction
  and address; writes carry `PWDATA` -> `WDATA` and `PSTRB` -> `WSTRB`.
- **Return:** `PSLVERR` must be asserted exactly when the AXI response is
  not OKAY; on OKAY reads `PRDATA` must equal `RDATA` (not compared on
  error, since `PRDATA` is undefined then).

The scoreboard receives completed transfers from both monitors. The two
monitors publish on the same clock edge (`PREADY` completes together with
the AXI response handshake), so it queues each stream and compares
whenever both have an entry, independent of which `write()` is called
first. Leftover entries at end of test are flagged (`SB_UNMATCHED`), so a
dropped or duplicated transaction can't hide.

## Stimulus

| Sequence                | What it does |
|-------------------------|--------------|
| `apb_directed_seq`      | write/read-back, partial and all-zero strobes, back-to-back writes/reads/alternating with no idle gap, address extremes (`0x0` and `0xFFFF_FFFC`), long idle gap |
| `apb_random_seq`        | constrained-random: word-aligned addresses weighted across low/mid/high regions; `PSTRB` weighted toward full with partial and zero mixed in (reads always 0, per APB4); idle gap weighted toward back-to-back |
| `axi_resp_seq` (modes)  | `OKAY_ONLY` (zero delay), `ERROR_ONLY` (SLVERR/DECERR), `MIXED` (80/10/10 OKAY/SLVERR/DECERR, random delays on every handshake), `SLOW` (5-15 cycle delays everywhere) |

Virtual sequences pair an APB stimulus with an AXI response mode and run
the AXI policy generator in the background while the APB sequence runs in
the foreground.

## Tests

| Test                    | APB stimulus | AXI slave behavior | Focus |
|-------------------------|--------------|--------------------|-------|
| `bridge_directed_test`  | directed     | clean, zero-delay  | basic correctness, strobes, back-to-back, address extremes |
| `bridge_random_test`    | 300 random   | mixed responses, random delays | constrained-random regression |
| `bridge_error_test`     | 100 random   | every response is SLVERR/DECERR | error propagation to `PSLVERR` |
| `bridge_slow_test`      | 60 random    | 5-15 cycle delays  | APB wait-state handling |

## Assertions (`rtl/apb_to_axi_sva.sv`, bound into the bridge)

- **APB:** `PENABLE` never rises without `PSEL`; address/`PWRITE` stay
  stable through the access phase until `PREADY`; the setup phase lasts
  exactly one cycle.
- **AXI4-Lite (master side):** `AWVALID`, `WVALID`, `ARVALID` stay
  asserted until their `READY`.
- **Bridge invariant:** a write and a read are never active on the AXI
  side at the same time (single-outstanding).

## Functional Coverage

- **`cg_apb`** (per transfer): direction, address region, write-strobe
  pattern (full / none / partial), `PSLVERR`, observed wait states (short
  / medium / long / huge), idle gap (back-to-back / short / long), with
  crosses direction x error, direction x idle gap, direction x address
  region.
- **`cg_axi`** (per transaction): direction x response code (OKAY /
  SLVERR / DECERR), measured from what actually appeared on the bus, so
  it confirms error injection reached the DUT rather than merely being
  configured.

## Running

```bash
./sim/run_sim.sh                     # bridge_directed_test
./sim/run_sim.sh bridge_random_test
./sim/run_sim.sh bridge_error_test
./sim/run_sim.sh bridge_slow_test
```

Watch for `UVM_ERROR` (scoreboard mismatch, unmatched transactions, or a
failed assertion) and the closing `SB_SUMMARY` / `COV_SUMMARY` /
`TEST_RESULT` lines. `waves.vcd` is written on every run for
waveform-based debugging.

## Verification Status (please read)

The RTL and UVM environment here were written and hand-reviewed, but **have
not been compiled or run in a SystemVerilog/UVM simulator** — none was
available where this repo was generated. What *was* done instead:

- A structural check of all `.sv` files (balanced `begin/end`,
  `class/endclass`, etc.).
- A **cycle-accurate Python model** (`model/handshake_cycle_model.py`) that
  mirrors the bridge FSM and the testbench's driver / monitor / scoreboard
  timing (same pre-edge sampling and non-blocking-drive conventions). It
  ran 9,600 random transfers across fast / mixed-error / error-only /
  slow-slave modes with no deadlocks, protocol violations, or scoreboard
  mismatches.
- A **mutation check** (`model/mutation_check.py`) that seeds six bugs
  (PSLVERR ignoring the response, dropped strobes, corrupted read data,
  wrong address, swapped direction, ignored W handshake) and confirms
  the model flags every one, so the clean pass above isn't vacuous.

That validates the handshake logic and the checking rules, not the SV
syntax or UVM plumbing. **Run `sim/run_sim.sh` (or the Questa flow)
yourself before treating this as verified.** Expect to spend a little
time on simulator-specific compile issues (UVM library flags, include
paths) before the first clean run — treat any `UVM_ERROR` after that as a
real finding.
