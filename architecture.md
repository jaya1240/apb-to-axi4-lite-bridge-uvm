# Architecture

## Role of the Bridge

```
   APB master                 apb_to_axi_bridge                  AXI4-Lite slave
 (CPU / debug port) --APB--> [ APB slave | AXI master ] --AXI4-Lite--> (register block,
                                                                        interconnect, ...)
```

The bridge is an **APB4 slave** on one side and an **AXI4-Lite master** on
the other. An APB transfer has no bursts, so each APB transfer maps to
exactly one AXI4-Lite transaction: there's no splitting or merging, only
protocol sequencing and signal translation.

## Signal Mapping

| APB4                  | AXI4-Lite                         | Notes |
|-----------------------|-----------------------------------|-------|
| `PADDR`               | `AWADDR` (write) / `ARADDR` (read)| passes through unchanged |
| `PWRITE`              | selects write vs. read channels   | |
| `PWDATA`              | `WDATA`                           | writes only |
| `PSTRB`               | `WSTRB`                           | writes only; APB4 requires `PSTRB`=0 on reads |
| `PRDATA`              | `RDATA`                           | reads only |
| `PSLVERR`             | `BRESP` / `RRESP` != `OKAY`       | `SLVERR` and `DECERR` both raise `PSLVERR` |
| `PREADY`              | response handshake completing     | wait states = time the AXI slave takes |

`PPROT` / `AWPROT` / `ARPROT` are not modeled (see Limitations).

## FSM

```
                       PSEL & !PENABLE (SETUP), PWRITE=1
              +-------------------------------------------+
              |                                           v
         +--------+                                  +----------+
   +---->|  IDLE  |                                  |AXI_WRITE |  AWVALID/WVALID, each
   |     +--------+                                  +----------+  dropped on its own handshake
   |          |  PSEL & !PENABLE, PWRITE=0                 | both AW and W accepted
   |          v                                            v
   |     +----------+                                  +----------+
   |     | AXI_READ |  ARVALID until ARREADY           |AXI_BRESP |  BREADY=1, PREADY=BVALID
   |     +----------+                                  +----------+
   |          | AR accepted                                | BVALID&BREADY
   |          v                                            |
   |     +----------+                                       |
   |     |AXI_RRESP |  RREADY=1, PREADY=RVALID              |
   |     +----------+                                       |
   |          | RVALID&RREADY                               |
   +----------+---------------------------------------------+
```

Design decisions worth knowing:

- **Latch at SETUP, not ACCESS.** `PADDR`/`PWRITE`/`PWDATA`/`PSTRB` are
  latched when the bridge sees the SETUP phase (`PSEL` high, `PENABLE`
  low). Those values are already stable then, so the AXI request can be
  issued a cycle earlier, and the bridge never re-samples the APB bus
  afterwards, so it doesn't matter what the master does with those
  signals once latched.
- **Mealy `PREADY`.** `PREADY` (and `PRDATA`/`PSLVERR`) is a combinational
  function of the state and the AXI response, so the APB access phase
  completes on the *same* clock edge as the AXI response handshake. No
  extra "complete" state, no wasted cycle.
- **Independent AW / W handshakes.** AXI allows the write-address and
  write-data channels to be accepted on different cycles. The bridge
  tracks each with its own done flag (`aw_done_q`, `w_done_q`) and only
  advances once both have completed, dropping each `VALID` as soon as its
  own handshake finishes.
- **Back-to-back transfers.** The FSM returns to `IDLE` on the same edge
  the previous transfer completes, so a following SETUP phase on the very
  next cycle is accepted with no idle gap.
- **Single outstanding.** APB never has more than one transfer in flight,
  so the bridge never has more than one AXI transaction in flight (an SVA
  property asserts a write and a read are never active together).
- **`PRDATA` on error.** The bridge simply passes `RDATA` through even when
  `PSLVERR` is asserted. Per the APB spec `PRDATA` is undefined on an error
  response, so the verification environment doesn't compare it then.

## Timing: single write, zero-wait AXI slave

```
clk      : _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
PSEL     : ____/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\___
PENABLE  : ________/‾‾‾‾‾‾‾‾‾‾‾‾\___
                 SETUP   ACCESS...
state    : IDLE | WRITE | BRESP | IDLE
AWVALID  :        /‾‾‾‾‾\
AWREADY  :               /‾\           (slave answers a cycle later)
BVALID   :                  /‾‾\
PREADY   :                  /‾‾\       (same cycle as BVALID: Mealy)
```

(Exact cycle counts depend on the slave's delays; the testbench's
reactive AXI driver randomizes them.)

## Timing / Synthesis

Single clock (`clk`), single active-low asynchronous reset (`rstn`), fully
synchronous otherwise, so no gated clocks or combinational loops.
`constraints/apb_to_axi_bridge.xdc` constrains a 100 MHz clock and
false-paths the async reset. `scripts/synth.tcl` runs out-of-context Vivado
synthesis and writes utilization + timing reports.

## Limitations

- AXI4-**Lite** only: no bursts, IDs, or exclusive accesses. (APB has none
  of these either, so this is the natural mapping.)
- `PPROT` / `AxPROT` and `PWAKEUP`/user signals are not modeled.
- No timeout: if the AXI slave never responds, the bridge waits forever
  (a production bridge would typically add a watchdog that returns
  `PSLVERR`).
- Reset asserted mid-transfer returns the FSM to `IDLE` (asynchronous
  reset), but that scenario is not part of the current test suite.
