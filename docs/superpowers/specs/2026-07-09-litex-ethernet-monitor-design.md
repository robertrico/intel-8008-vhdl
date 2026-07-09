# b8008 Monitor over Ethernet — LiteX SoC Design

**Date:** 2026-07-09
**Status:** Approved design, pre-implementation
**Board:** Lattice ECP5-5G Versa (LFE5UM5G-45F), Marvell 88E1512 RGMII PHYs

## Goal

Run the b8008 monitor over the network instead of serial. The board behaves
like a normal network appliance: plug in an Ethernet cable, it acquires a
DHCP lease, shows up in the router's device list as `b8008`, and the host
tool finds it with zero configuration. Over that link: interactive monitor
console, program loading at wire speed, and direct peek/poke of 8008 RAM.

## Scope

In scope:
- Interactive monitor console over Ethernet (replaces serial terminal).
- Program loading (replaces `send_hex.py` + UART pacing entirely).
- Direct host access to 8008 RAM (read/write while CPU runs or is held).
- DHCP appliance behavior with hostname registration.
- `b8008net` host CLI.

Out of scope (future work, explicitly deferred):
- Web/xterm.js demo layer with ngrok and multi-visitor locking. The board
  design below is sufficient for it; the demo layer is host-side only and
  will be designed separately.
- Serial UART fallback path (monitor project `projects/b8008_monitor/`
  remains untouched and keeps working over serial as-is).
- mDNS responder (`b8008.local` from the board itself) — firmware can add
  it later; discovery does not depend on it.

## Architecture

LiteX owns the FPGA top level. The b8008 and its monitor become a core
inside a LiteX SoC. New project directory; the existing serial monitor
project is not modified.

```
projects/b8008_net/
├── versa_soc.py            # LiteX top (based on litex-boards versa_ecp5)
├── src/
│   ├── b8008_net_core.vhdl # wrapper: b8008 + USART + dual-port RAM, no pads
│   └── ram_dp_sync.vhdl    # true dual-port 8KB BRAM
├── firmware/               # VexRiscv DHCP/identity firmware (C)
├── host/b8008net           # Python CLI
└── Makefile                # ghdl-convert + litex build + prog targets
```

### Block diagram

```
PHY0 (RGMII) ── LiteEth ──┬── Etherbone ── wishbone ─┬─ 8008 RAM port B
                          │                          ├─ console UART CSRs
                          │                          └─ control CSRs
                          └── ethmac ── VexRiscv + firmware
                                        (DHCP, hostname, IP-to-CSR)

PHY1: unused (free for future experiments)

b8008_net_core (25 MHz domain):
  b8008 CPU ── USART ── internal tx/rx wires ── LiteX UART (RS232PHY, 115200)
  b8008 memory bus ── ram_dp_sync port A
```

### Network identity (appliance mode)

- One PHY, one cable. LiteEth hardware UDP/IP stack shared between
  Etherbone and the CPU's ethmac (`add_ethernet` + `add_etherbone` on the
  same PHY, `eth_dynamic_ip`).
- VexRiscv firmware at boot: runs DHCP with hostname option `b8008`
  (so home routers list the device by name and typically register it in
  local DNS automatically), then writes the leased IP into the Etherbone
  UDP/IP core's CSRs. Etherbone answers on the leased address from then on.
- The CPU is infrastructure only — never in the monitor data path. If it
  is held in reset, console/loader/peek-poke still work once an IP is set.
- Firmware is small (~100 lines of C over libliteeth), stored in on-chip
  ROM, and is also the fallback if any stock LiteX DHCP path has gaps: the
  CPU can implement whatever the appliance UX requires.

### VHDL into the LiteX build

- `b8008_net_core.vhdl` wraps the existing `src/b8008/` modules (all
  unchanged) plus USART plus `ram_dp_sync`, exposing: clk/reset, uart
  tx/rx, RAM port B, control inputs, debug outputs.
- A Makefile step converts it once per build with
  `ghdl synth --out=verilog` → `b8008_net_core.v`. LiteX includes the
  generated Verilog as a source and instantiates it. Deterministic; no
  ghdl-yosys-plugin inside LiteX's build.
- LiteX drives the same oss-cad-suite yosys/nextpnr-ecp5/ecppack already
  in use.

### Clocking

- LiteX CRG generates sys_clk (75–100 MHz, spike decides exact) and a
  25 MHz `b8008` clock domain (replaces `pll_25mhz`).
- RGMII 125 MHz domains are handled by LiteEth and the board file.
- The only domain crossings: (a) async serial between the 25 MHz USART and
  the sys-domain LiteX UART — safe by construction (oversampled serial);
  (b) `ram_dp_sync` port B in sys domain, port A in 25 MHz domain — true
  dual-port BRAM, each port synchronous to its own clock.

### Dual-port RAM

- `ram_dp_sync.vhdl`: 8KB true dual-port BRAM in b8008 module style
  (simple, dumb, own testbench).
- Port A: the 8008's memory port, exact current `ram_sync` behavior.
- Port B: synchronous read/write, wrapped by a ~20-line Migen shim into a
  wishbone slave window in the SoC address map.
- No arbitration needed. Only hazard is a simultaneous write to the same
  address from both ports; outcome is undefined per BRAM semantics. Rule:
  host loads happen with the CPU held (reset or monitor prompt); `b8008net
  load` checks the status CSR and warns if the CPU is running.

### Console path

- The monitor's USART tx/rx become internal wires to a LiteX UART
  (RS232PHY at 115200 in sys domain) with CSR-mapped FIFOs.
- Host reads/writes those CSRs over Etherbone. No monitor ROM or USART
  VHDL changes.

### Control CSRs

- b8008 reset, run/stop, step-cycle, step-sync, INT: CSR bits OR'd with
  the existing physical buttons. Bench buttons keep working; host can
  drive the same controls remotely.
- Status CSR: CPU run/stop state (from debug_clock_control).
- Debug pin outputs (logic-analyzer bus: cpu_d, s0–s2, sync, phi1/2) stay
  on physical pads as today.

## Host side

### Stack

`b8008net` → `litex_server --udp` (auto-spawned if not running) →
Etherbone/UDP → board.

### Discovery (zero config)

1. Resolve `b8008.lan` / `b8008.local` (router-registered DHCP hostname).
2. Fallback: Etherbone probe sweep of the local /24 (~254 UDP packets,
   milliseconds); the board answers the probe.
3. Cache the last-known address; re-discover only when unreachable.

No IP is ever typed or stored in project config.

### `b8008net` commands

```
b8008net console            # interactive monitor session (raw tty)
b8008net load prog.hex      # parse hex → wishbone writes → read-back verify
b8008net run <addr>         # G command via console (monitor stays in charge)
b8008net peek <addr> [len]  # hex dump of 8008 RAM
b8008net poke <addr> <bytes>
b8008net reset|stop|step    # control CSRs
b8008net status             # discovery result, link, CPU state
```

- `load` replaces `send_hex.py`: no UART in the path, 8KB in milliseconds,
  verified by read-back; mismatch reports offset/expected/got, nonzero exit.
- CSR addresses come from the LiteX-emitted `csr.csv`; nothing hardcoded.

### LiteX installation

Repo-local venv (`projects/b8008_net/.venv`) via `litex_setup.py`, pinned
to a release tag. `make litex-env` sets it up once.

## Error handling

- Etherbone/UDP: RemoteClient timeout + retry; `b8008net` wraps failures
  with actionable messages (unreachable → re-run discovery → check cable).
- Console: rx FIFO + flags; poll loop orders of magnitude faster than
  115200 byte rate, no silent loss.
- Loads: read-back verify always; CPU-running warning via status CSR.
- DHCP not yet leased (first seconds after plug-in): discovery reports
  "no lease yet, retrying".

## Testing

Staged; no commit until stage 6 passes on the board (hardware-proof rule).
User flashes hardware; assistant builds and hands over commands.

1. **Module sim:** `ram_dp_sync` GHDL testbench (both ports, simultaneous
   access), existing style + make target.
2. **Core sim:** `b8008_net_core` runs adapted monitor boot + interactive
   testbenches. Full regression `run_all_tests.sh` stays green
   (`src/b8008/` untouched).
3. **Netlist smoke:** converted `b8008_net_core.v` re-simulated once (boot
   banner) to catch ghdl-convert issues before hardware.
4. **HW stage 1 — SoC alone (no 8008 core):** DHCP lease acquired, board
   named `b8008` in router list, Etherbone answers on leased IP,
   `litex_cli --regs` works.
5. **HW stage 2 — full SoC:** `b8008net console` shows monitor banner;
   peek/poke RAM.
6. **HW stage 3 — workflow parity:** mandelbrot, pi, calc loaded via
   `b8008net load`, run via monitor, outputs match serial-era results.

## Risks and the verification spike

First implementation task is a spike, before any RTL work:

1. Install LiteX; confirm the cleanest supported path for
   dynamic-IP Etherbone on a shared PHY. Candidates, in preference order:
   BIOS/firmware DHCP + CSR-writable Etherbone IP (`eth_dynamic_ip`);
   LiteEth hardware DHCP core; custom firmware DHCP over libliteeth.
   All converge on the same UX; spike picks the least custom one.
2. Confirm whether the chosen DHCP path sends hostname option 12
   (`b8008`); if not, firmware adds it.
3. Confirm litex-boards `versa_ecp5` (5G variant) exposes the PHY used.
4. Smoke-test `ghdl synth --out=verilog` on a trivial b8008 module before
   committing to the conversion flow.

Other noted risks:
- Etherbone probe response to subnet sweep (unicast probes, not broadcast,
  so hardware IP filtering is not an issue once the lease is set).
- ECP5-5G RGMII IO timing: handled by LiteEth + board file; verify timing
  report at HW stage 1.

## Decision log

- LiteX owns the top level (vs. embedding a generated core in the VHDL
  top): user choice, full LiteX ecosystem desired.
- VexRiscv kept, with a concrete job: DHCP/identity engine for appliance
  behavior. Not in the monitor data path.
- One PHY shared (vs. two-PHY split): appliance UX wants one cable and a
  single DHCP identity; the earlier two-PHY split assumed a static
  Etherbone IP, which was rejected (busy home network, no manual IP
  management, no router configuration).
- Static IP rejected: user requires plug-in-like-a-regular-device.
- Host UX: single `b8008net` CLI (vs. telnet bridge or raw litex tools).
- Demo/web layer deferred by user to keep scope contained.
