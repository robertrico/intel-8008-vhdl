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
│   ├── b8008_net_core.vhdl # wrapper: b8008 + USART, pure logic, no pads
│   └── sim/                # behavioral RAM/ROM models, testbench only
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

b8008_net_core (25 MHz domain, pure logic):
  b8008 CPU ── USART ── internal tx/rx wires ── LiteX UART (RS232PHY, 115200)
  b8008 memory bus  ──┐
  external ROM bus  ──┤ Migen Memory instances (RAM 8KB dual-port,
                      ┘ monitor ROM 4KB) — all memories SoC-side
```

### Network identity (appliance mode)

- One PHY, one cable. `add_etherbone(phy, with_ethmac=True)` — LiteEth
  hybrid mode: hardware UDP/IP stack for Etherbone plus CPU ethmac on the
  same PHY. Our `versa_soc.py` calls it directly (the stock versa target's
  argparse makes ethernet/etherbone mutually exclusive — that's a CLI
  choice in the target, not a core limitation; don't copy the pattern).
- Hybrid mode requires two MACs (Etherbone MAC ≠ ethmac MAC; LiteX errors
  if equal). RX dispatch is by target MAC.
- **Custom firmware DHCP is mandatory, not a fallback.** Verified: neither
  the LiteEth hardware DHCP core (options 53/61/55 only) nor libliteeth's
  `dhcp.c` (1/3/50/53/54/55) sends hostname option 12, and both are
  one-shot with no lease renewal. Firmware (C over libliteeth, using its
  `dhcp_add_option()` helper) therefore:
  - sends option 12 hostname `b8008` (router device list + local DNS);
  - sets DHCP `chaddr` to the **Etherbone MAC** with the broadcast flag
    set (replies arrive broadcast, so the CPU path still receives them).
    The lease is then bound to the MAC that will answer ARP for the IP —
    no IP-jumping-MACs conflict at the router;
  - writes the leased IP into the Etherbone core's IP CSR;
  - runs a lease-renewal timer (T1/T2) — home-router leases expire (~24h)
    and both stock paths would silently squat on a reassignable address.
- **Etherbone IP CSR is custom wiring**, not a stock flag: `add_etherbone`
  has no dynamic-IP parameter. A `CSRStorage` feeds the UDP/IP core's IP
  input (`convert_ip()` passes Migen Signals through; liteeth's `gen.py`
  `dynamic_params` is precedent). Reset value 0.0.0.0, and the core's ARP
  answering is gated until the CSR is nonzero — never answer for the
  default address on the LAN.
- The CPU is infrastructure only — never in the monitor data path. Once
  the IP CSR is set, console/loader/peek-poke work even with the CPU held.

### VHDL into the LiteX build

- `b8008_net_core.vhdl` is a port of the whole monitor top, not a
  three-block assembly. It contains everything `b8008_monitor_top.vhdl`
  has except PLL (LiteX CRG), pads, debouncers (CSR pulses arrive clean;
  physical buttons debounced outside), and memory arrays (Migen side):
  b8008_top, b8008_usart, debug_clock_control, address_decoder,
  int_button, POR logic, IO-port glue and data-bus mux — all existing
  modules unchanged. Exposes: clk/reset, uart tx/rx, the 8008 RAM memory
  bus, the external ROM bus, control pulse inputs, status and debug
  outputs.
- **Auto-start is kept**: the monitor top's synthetic run/stop press
  ~2 ms after POR release moves into the wrapper. Appliance mode requires
  the monitor to boot and run with no host attached.
- Generic hygiene: every `CLK_FREQ_HZ` generic in the wrapper is
  explicitly `25_000_000` (component defaults are 100 MHz; USART baud
  timing silently breaks otherwise).
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
- Domain crossings, all four, each with its mechanism:
  - (a) async serial between the 25 MHz USART and the sys-domain LiteX
    UART — safe by construction (oversampled serial);
  - (b) the Migen RAM's wishbone port in sys domain, its 8008-facing port
    in the 25 MHz domain — true dual-port BRAM, each port synchronous to
    its own clock;
  - (c) control CSRs sys → 25 MHz: `debug_clock_control` consumes
    single-cycle pulses at 25 MHz (`debug_clock_control.vhdl:30`), so a
    naive sys-domain pulse (13 ns) is missed or double-counted. Mechanism:
    CSRStorage bits are levels; Migen crosses each with MultiReg into the
    `b8008` domain and edge-detects there, feeding the wrapper clean
    single-cycle 25 MHz pulses — same shape as the debouncer outputs the
    monitor top already feeds it;
  - (d) status (`is_running`) 25 MHz → sys: MultiReg 2FF into a CSRStatus.

### Memories live on the Migen side (not in the VHDL)

GHDL's Verilog output is experimental and its dual-port BRAM inference
through yosys has a stack of known failures (ghdl#1069, #2092, #3027,
#2490; yosys#2965, #3400). Failure mode is silent: RAM/ROM degrade to
FFs/LUTs and an 8KB RAM (~65k FFs) or 4KB ROM will not fit the 45F part.
So no memory arrays pass through the ghdl→verilog conversion:

- **8KB RAM:** Migen `Memory` with two ports — port A via
  `get_port(clock_domain="b8008")` wired to the wrapper's exposed memory
  bus, port B as a wishbone slave window (native LiteX, trivially mapped
  to DP16KD).
- **4KB monitor ROM:** Migen `Memory` initialized from the assembled
  monitor image, read port in the `b8008` domain, wired to the wrapper's
  external-ROM bus (the monitor top already supports an external ROM
  interface — same pattern).
- The VHDL core (`b8008_net_core`) is pure logic plus small register
  arrays (register file 7x8, address stack 8x14 — fine as FFs, as today).
- For GHDL simulation, the testbench provides behavioral VHDL RAM/ROM
  models (sim-only, never synthesized).
- Synth report check is mandatory at HW stage 1: expected DP16KD count
  present, FF count sane.
- No arbitration on the RAM. Only hazard is a simultaneous write to the
  same address from both ports; outcome undefined per BRAM semantics.
  Rule: host loads happen with the CPU held (reset or monitor prompt);
  `b8008net load` checks the status CSR and warns if the CPU is running.

### Console path

- The monitor's USART tx/rx become internal wires to a LiteX UART
  (RS232PHY at 115200 in sys domain) with CSR-mapped FIFOs.
- Host reads/writes those CSRs over Etherbone. No monitor ROM or USART
  VHDL changes.
- **FIFO sizing is throughput-critical:** each CSR read is one Etherbone
  UDP round trip (~0.3–1 ms → ~1–3k reads/s ≈ 1–3 kB/s), while the
  monitor transmits at 115200 baud ≈ 11.5 kB/s. The stock 16-deep rx FIFO
  overflows on the first banner burst. Design: `rx_fifo_depth` ≥ 1 KB, and
  `b8008net` reads the rx-level CSR then drains in batched reads.

### Control CSRs

- b8008 reset, run/stop, step-cycle, step-sync, INT: CSR-originated pulses
  (via the CDC mechanism above) OR'd with the debounced physical button
  pulses at the wrapper inputs. Bench buttons keep working; host drives
  the same controls remotely.
- **Run/stop is a toggle** — `debug_clock_control` semantics (proven on
  hardware, not modified): run/stop toggles, step buttons act only while
  stopped, restart injects a reset pulse. Remote imperative `b8008net
  stop`/`run` is therefore **toggle-and-verify**: read `is_running`,
  toggle if it differs from the goal, re-read, retry. Racy only with
  concurrent controllers, which the tool's single-instance lock (see Host
  side) excludes. Decision: host-side toggle-and-verify over adding a
  level input to proven RTL.
- Status CSR: `is_running` (and `triggered`/`next_is_phi*` as available)
  from debug_clock_control, MultiReg'd to sys.
- Debug pin outputs (logic-analyzer bus: cpu_d, s0–s2, sync, phi1/2) stay
  on physical pads as today.

## Host side

### Stack

`b8008net` → `litex_server --udp` (auto-spawned if not running) →
Etherbone/UDP → board.

### Discovery (zero config)

1. Resolve `b8008.lan` / `b8008.local` (router-registered DHCP hostname).
2. Fallback: Etherbone probe sweep of the local /24 (~254 UDP packets,
   milliseconds); the board answers the probe. The sweep speaks Etherbone
   directly (litex's `remote.etherbone` classes standalone) — litex_server
   binds a single IP and can't sweep; it is spawned only after discovery.
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

- **RAM window layout (decided):** one 8008 byte per 32-bit wishbone word
  (8192 words). `peek`/`poke` are single-word, no read-modify-write.
  `load` MUST use `RemoteClient.write(addr, [list])` burst writes (~255
  words per UDP packet → ~33 packets → tens of ms). Naive per-word writes
  are 8192 round trips ≈ 8 s — the trap is documented so nobody falls in.
- `load` replaces `send_hex.py`: no UART in the path, verified by
  read-back (also burst); mismatch reports offset/expected/got, nonzero
  exit.
- CSR addresses come from the LiteX-emitted `csr.csv`; nothing hardcoded.
  On connect, `b8008net` reads the LiteX identifier CSR (build timestamp)
  and warns if it does not match the `csr.csv` on disk — stale-bitstream
  sessions fail loudly, not confusingly.
- Single-instance lock (lockfile): one `b8008net` at a time. The console
  rx FIFO has one consumer and run/stop is toggle-and-verify — concurrent
  instances would steal bytes and race the toggle.

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

Staged; no commit until stage 7 (HW stage 3) passes on the board (hardware-proof rule).
User flashes hardware; assistant builds and hands over commands.

1. **Core sim:** `b8008_net_core` runs adapted monitor boot + interactive
   testbenches, with behavioral VHDL RAM/ROM models in the testbench
   (mirroring the Migen memories' port timing). Full regression
   `run_all_tests.sh` stays green (`src/b8008/` untouched).
2. **Netlist smoke:** converted `b8008_net_core.v` re-simulated once (boot
   banner) to catch ghdl-convert issues before hardware.
3. **Memory-port contract:** one written note in the wrapper defining port
   timing (read latency, write-enable semantics) that both the behavioral
   models and the Migen memories must satisfy — the sim/synth divergence
   risk introduced by moving memories out lives exactly here.
4. **litex_sim (Verilator):** whole SoC minus PHY — validates the console
   CSR path, RAM wishbone window, and control-CSR CDC against the
   converted netlist before any hardware. Cheap stage between GHDL sim
   and HW stage 1.
5. **HW stage 1 — SoC alone (no 8008 core):** DHCP lease acquired, board
   named `b8008` in router list, Etherbone answers on leased IP,
   `litex_cli --regs` works. Synth report checked: expected DP16KD count,
   sane FF count, timing clean. Leave running past lease T1 to observe a
   renewal.
6. **HW stage 2 — full SoC:** `b8008net console` shows monitor banner;
   peek/poke RAM.
7. **HW stage 3 — workflow parity:** mandelbrot, pi, calc loaded via
   `b8008net load`, run via monitor, outputs match serial-era results.

## Risks and the verification spike

Design was verified against LiteX/LiteEth/GHDL sources pre-implementation
(2026-07-09 review): shared-PHY hybrid mode, versa_ecp5 board support, and
both DHCP code paths confirmed real; DHCP path decided (custom firmware,
see Network identity); memories moved out of the VHDL conversion path.

Remaining spike, before RTL work:

1. Install pinned LiteX; build stock versa_ecp5 target as toolchain
   sanity check.
2. Prototype the custom Etherbone-IP CSR wiring (`CSRStorage` →
   UDP/IP core IP input, ARP gate) — the one piece of custom Migen with
   no stock precedent beyond liteeth `gen.py` dynamic_params.
3. Smoke-test `ghdl synth --out=verilog` on the pure-logic wrapper;
   confirm resulting netlist simulates (netlists are unoptimized with
   scrambled names — acceptable, they only feed synthesis).

Other noted risks:
- Probe sweep uses unicast probes (not broadcast), so hardware IP
  filtering is not an issue once the lease is set; board is undiscoverable
  before the first lease — `b8008net` reports "no lease yet, retrying".
- ECP5-5G RGMII IO timing: handled by LiteEth + board file; verify timing
  report at HW stage 1.
- `with_ethmac=True` forces `ETH_PHY_NO_RESET` and bakes related
  constants — harmless, firmware ignores.

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
- Post-review (2026-07-09): all memories (RAM + monitor ROM) moved to
  Migen side — GHDL verilog backend + TDP inference too risky; custom
  firmware DHCP promoted from fallback to mandatory (option 12, chaddr =
  Etherbone MAC + broadcast flag, lease renewal); Etherbone IP CSR
  documented as custom wiring with 0.0.0.0 reset + ARP gate; console rx
  FIFO ≥ 1 KB with batched drains (Etherbone RTT math).
- Post-review pass 2 (2026-07-09, against monitor RTL): control-CSR CDC
  via MultiReg + b8008-domain edge detect; remote run/stop as host-side
  toggle-and-verify (proven debug_clock_control unmodified); wrapper
  scoped as full monitor-top port with auto-start kept; RAM window byte
  per 32-bit word with mandatory burst writes; identifier-CSR staleness
  check; single-instance lock; litex_sim stage before hardware.
