# b8008 Monitor over Ethernet (LiteX SoC) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Versa ECP5 board becomes a network appliance: plug in Ethernet, it DHCPs as `b8008`, and the `b8008net` CLI gives an interactive monitor console, wire-speed program loading, and live peek/poke of 8008 RAM — replacing the serial workflow.

**Architecture:** LiteX owns the FPGA top. The existing b8008 monitor design becomes a pure-logic VHDL core (`b8008_net_core`) converted to Verilog and instantiated in a LiteX SoC. All memories (8KB RAM, 4KB monitor ROM) are Migen `Memory` instances. One PHY carries both a hardware Etherbone endpoint (console/loader/peek-poke via wishbone+CSRs) and a VexRiscv ethmac whose only job is firmware DHCP (hostname option 12, lease renewal, writes leased IP into the Etherbone core's IP CSR).

**Tech Stack:** LiteX + LiteEth + VexRiscv (pinned release), GHDL/yosys/nextpnr-ecp5 from oss-cad-suite, GHDL `synth --out=verilog` for VHDL→Verilog, Verilator via litex_sim, Python 3 host tool.

**Spec:** `docs/superpowers/specs/2026-07-09-litex-ethernet-monitor-design.md` — read it before starting any task.

## Global Constraints

- Existing repo rules apply (CLAUDE.md): never run GHDL directly for the b8008 projects — existing sims go through `make`; new `projects/b8008_net/` targets follow the same pattern via `projects/project.mk` conventions where applicable.
- `projects/b8008_monitor/` is NOT modified by any task. `src/b8008/b8008_top.vhdl` is modified once (Task 3), backward-compatibly; the full regression `./test_programs/verification_scripts/run_all_tests.sh` must stay green after it.
- All `CLK_FREQ_HZ` generics in new VHDL are explicitly `25_000_000` (defaults are 100 MHz; USART baud silently breaks otherwise).
- Commit per task when that task's own validation passes. **No commit message may claim hardware-proven behavior before Task 15.** Hardware flashing is done by the user; tasks 13–15 hand over commands and wait (see memory: user flashes, user triggers hardware-validation commits).
- MAC/IP constants: Etherbone MAC `0x10e2d5000001`, ethmac (CPU) MAC `0x10e2d5000002`, Etherbone UDP port `1234`, Etherbone IP CSR reset `0.0.0.0`. DHCP hostname `b8008`.
- LiteX pinned: `LITEX_TAG` Makefile variable, set in Task 1 to the newest release tag found via `git ls-remote --tags https://github.com/enjoy-digital/litex.git`.
- Python for `b8008net` lives in the LiteX venv (`projects/b8008_net/.venv`); tests run with that venv's `python -m pytest`.

## File Map

| Path | Responsibility |
|---|---|
| `projects/b8008_net/Makefile` | litex-env, convert, build, sim, firmware, prog targets |
| `projects/b8008_net/versa_soc.py` | LiteX target: CRG, PHY, CPU, etherbone, identifier |
| `projects/b8008_net/b8008_integration.py` | `B8008Core` Migen module: Instance, memories, wishbone shim, console bridge, control-CSR CDC |
| `projects/b8008_net/src/b8008_net_core.vhdl` | Pure-logic port of the monitor top (VHDL) |
| `projects/b8008_net/sim/b8008_net_core_tb.vhdl` | GHDL boot-banner testbench (uses ram_sync/rom_4kx8_bram as behavioral models) |
| `projects/b8008_net/sim/netlist_tb.v` + `sim/models.v` | iverilog smoke test of the converted netlist |
| `projects/b8008_net/sim_soc.py` | litex_sim (Verilator) SoC for end-to-end pre-hardware validation |
| `projects/b8008_net/firmware/main.c`, `firmware/dhcp8008.c/.h` | DHCP + IP-CSR firmware |
| `projects/b8008_net/host/` | `b8008net` package + pytest suite |
| `src/b8008/b8008_top.vhdl` | + `EXTERNAL_RAM` generic and external RAM bus (defaults preserve today's behavior) |

---

### Task 1: LiteX environment

**Files:**
- Create: `projects/b8008_net/Makefile`
- Create: `projects/b8008_net/.gitignore` (`.venv/`, `build/`, `*.v` generated, `__pycache__/`)

**Interfaces:**
- Produces: `make litex-env` (idempotent), `$(VENV)/bin/python` with litex/liteeth/litex-boards importable, `LITEX_TAG` pinned.

- [ ] **Step 1: Find newest LiteX release tag**

Run: `git ls-remote --tags https://github.com/enjoy-digital/litex.git | grep -o 'refs/tags/20[0-9.]*$' | sort -V | tail -3`
Pick the newest plain-release tag; it becomes `LITEX_TAG` below.

- [ ] **Step 2: Write the Makefile (env portion)**

```make
# projects/b8008_net/Makefile
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

OSS_CAD_SUITE ?= $(HOME)/oss-cad-suite/bin
GHDL ?= $(OSS_CAD_SUITE)/ghdl
export PATH := $(OSS_CAD_SUITE):$(PATH)

LITEX_TAG ?= <tag from Step 1>
VENV := .venv
PY := $(VENV)/bin/python

.PHONY: litex-env
litex-env:
	test -d $(VENV) || python3 -m venv $(VENV)
	$(PY) -m pip install --upgrade pip meson ninja
	test -f litex_setup.py || curl -fsSL -o litex_setup.py \
	  https://raw.githubusercontent.com/enjoy-digital/litex/master/litex_setup.py
	cd $(VENV) && ../$(PY) ../litex_setup.py --init --install --tag=$(LITEX_TAG) --config=standard
	$(PY) -c "import litex, liteeth, litex_boards; print('litex OK')"
```

(litex_setup `--config=standard` includes liteeth, litex-boards, and the RISC-V toolchain pointers; if the chosen tag names the flag differently, follow `python litex_setup.py --help` — the deliverable is the Step 4 check passing.)

- [ ] **Step 3: Run it**

Run: `cd projects/b8008_net && make litex-env`
Expected: ends with `litex OK`.

- [ ] **Step 4: Toolchain sanity — build stock versa target to a bitstream**

Run: `cd projects/b8008_net && $(pwd)/.venv/bin/python -m litex_boards.targets.lattice_ecp5_versa --device=LFE5UM5G --build --output-dir build/stock_sanity`
(Exact module name: `ls .venv/**/litex_boards/targets/ | grep -i versa` first; use what exists.)
Expected: `build/stock_sanity/gateware/*.bit` exists. This proves yosys/nextpnr/ecppack wiring end-to-end.

- [ ] **Step 5: Check RISC-V cross-compiler**

Run: `riscv64-unknown-elf-gcc --version || riscv-none-elf-gcc --version`
If absent: `brew tap riscv-software-src/riscv && brew install riscv-tools` (or the litex_setup `--gcc=riscv` path). Record which compiler name worked — Task 8 needs it.

- [ ] **Step 6: Commit**

```bash
git add projects/b8008_net/Makefile projects/b8008_net/.gitignore
git commit -m "b8008_net: LiteX environment, pinned tag, stock versa sanity build"
```

---

### Task 2: Spike — dynamic-IP Etherbone elaborates

Proves the one custom mechanism with no stock precedent: a `CSRStorage`-driven IP on the Etherbone UDP/IP core, in hybrid (`with_ethmac=True`) mode.

**Files:**
- Create: `projects/b8008_net/spike_dynamic_ip.py` (deleted at end of task — spike, not product)

**Interfaces:**
- Produces: the working invocation pattern (recorded as a comment block in `versa_soc.py` later); confirmation that `soc.add_etherbone(..., ip_address=<Signal>, with_ethmac=True)` elaborates, or the fallback wiring if it does not.

- [ ] **Step 1: Write the spike**

```python
# spike_dynamic_ip.py — throwaway: does dynamic-IP etherbone elaborate?
from migen import Signal
from litex_boards.targets import lattice_ecp5_versa as versa  # adjust to actual module name from Task 1
from litex.soc.interconnect.csr import CSRStorage, AutoCSR

class _EbIP(AutoCSR):
    def __init__(self):
        self.ip = CSRStorage(32, reset=0)

def main():
    soc = versa.BaseSoC(device="LFE5UM5G", cpu_type="vexriscv", cpu_variant="minimal",
                        with_ethernet=False, with_etherbone=False)
    soc.submodules.eb_ip = _EbIP()
    phy = soc.platform.request("eth_clocks", 0), soc.platform.request("eth", 0)
    from liteeth.phy.ecp5rgmii import LiteEthPHYRGMII
    soc.submodules.ethphy = LiteEthPHYRGMII(*phy, tx_delay=0e-9)
    soc.add_etherbone(phy=soc.ethphy,
                      mac_address=0x10e2d5000001,
                      ip_address=soc.eb_ip.ip.storage,   # <-- the experiment
                      udp_port=1234,
                      with_ethmac=True,
                      ethmac_address=0x10e2d5000002,
                      ethmac_local_ip="0.0.0.0",
                      ethmac_remote_ip="0.0.0.0")
    soc.finalize()
    print("ELABORATED OK")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run, iterate against actual API**

Run: `cd projects/b8008_net && .venv/bin/python spike_dynamic_ip.py`
Expected: `ELABORATED OK`. If `add_etherbone` rejects a Signal or a kwarg name differs, read `.venv/**/litex/soc/integration/soc.py` `add_etherbone` (~line 2615 per review) and either (a) fix kwarg names, or (b) fall back to hand-instantiating `LiteEthUDPIPCore(ip_address=<Signal>)` + `LiteEthEtherbone` exactly as `add_etherbone` does internally, with the Signal substituted. Keep iterating until ELABORATED OK.

- [ ] **Step 3: Also verify verilog generation**

Add `from litex.build.generic_platform import *` build call or simply run the target with `--no-compile-gateware` equivalent: `soc.build(run=False)` after finalize. Expected: `build/**/top.v` written, contains the eb_ip CSR.

- [ ] **Step 4: Record findings, delete spike, commit note**

Paste the final working invocation into a comment at the top of a new empty `projects/b8008_net/versa_soc.py` (filled in Task 7). `rm spike_dynamic_ip.py`.

```bash
git add projects/b8008_net/versa_soc.py
git commit -m "b8008_net: spike result - dynamic-IP etherbone invocation recorded"
```

---

### Task 3: `b8008_top` external-RAM option

Backward-compatible: `EXTERNAL_RAM => false` (default) keeps the internal `ram_sync`; nothing else changes. Test is an equivalence sim: same program, internal vs external RAM, same result.

**Files:**
- Modify: `src/b8008/b8008_top.vhdl`
- Create: `sim/b8008/b8008_top_extram_tb.vhdl`
- Modify: root `Makefile` (add `test-b8008-extram` target following the existing test-target pattern)

**Interfaces:**
- Produces (new optional ports on `b8008_top`, all in the `clk_in` domain):

```vhdl
generic ( ...existing...; EXTERNAL_RAM : boolean := false );
port ( ...existing...;
    ram_ext_addr  : out std_logic_vector(13 downto 0);         -- latched address, low RAM_ADDR_BITS valid
    ram_ext_wdata : out std_logic_vector(7 downto 0);
    ram_ext_rdata : in  std_logic_vector(7 downto 0) := x"00"; -- must be a 1-cycle synchronous read of ram_ext_addr
    ram_ext_rw_n  : out std_logic;                              -- 0 = write (ram_sync semantics)
    ram_ext_cs_n  : out std_logic );                            -- 0 = selected
```

Memory-port contract (verbatim into a comment above the ports — the Migen RAM and every behavioral model must satisfy it): *external RAM behaves exactly like `ram_sync`: on every rising `clk_in` edge, `ram_ext_rdata` becomes the registered read of `ram_ext_addr` (one-cycle latency, no CS gating on reads); a write occurs on the edge when `ram_ext_cs_n='0'` and `ram_ext_rw_n='0'`.*

- [ ] **Step 1: Write the failing equivalence testbench**

`sim/b8008/b8008_top_extram_tb.vhdl`: instantiate two `b8008_top` — A with defaults, B with `EXTERNAL_RAM => true` plus an external `ram_sync` (ADDR_BITS => RAM_ADDR_BITS) wired per the contract. Drive both with the same clock/reset/interrupt bootstrap sequence the existing `sim/b8008` top-level TB uses (copy its stimulus process). Run a RAM-exercising program: reuse `test_programs` `ram_test` image via `RAM_INIT_FILE`/ROM path exactly as the existing top TB does. Assert every 100 µs that `ram_byte_0`, `debug_reg_a`, and `debug_pc` of A and B are equal; report FAIL on mismatch, PASS at end.

- [ ] **Step 2: Add make target + run to verify it fails**

Root `Makefile`: copy the `test-b8008-top` recipe shape into `test-b8008-extram` (analyze `sim/b8008/b8008_top_extram_tb.vhdl`, elaborate `b8008_top_extram_tb`, run).
Run: `make test-b8008-extram`
Expected: FAIL — analysis error (`EXTERNAL_RAM` and `ram_ext_*` don't exist yet).

- [ ] **Step 3: Implement in `b8008_top.vhdl`**

At the `u_ram` site (line ~400):

```vhdl
gen_ram_internal : if not EXTERNAL_RAM generate
    u_ram : ram_sync
        generic map (ADDR_BITS => RAM_ADDR_BITS, INIT_FILE => RAM_INIT_FILE)
        port map (CLK => clk_in,
                  ADDR => latched_address(RAM_ADDR_BITS-1 downto 0),
                  DATA_IN => ram_data_in, DATA_OUT => ram_data_out,
                  RW_N => ram_rw_n, CS_N => ram_cs_n);
end generate;
gen_ram_external : if EXTERNAL_RAM generate
    ram_data_out <= ram_ext_rdata;
end generate;

ram_ext_addr  <= (others => '0') when not EXTERNAL_RAM
                 else std_logic_vector(resize(unsigned(latched_address(RAM_ADDR_BITS-1 downto 0)), 14));
ram_ext_wdata <= ram_data_in;
ram_ext_rw_n  <= ram_rw_n;
ram_ext_cs_n  <= ram_cs_n;
```

(If the `when ... else` on a boolean generic trips GHDL, move the assignments inside the two generates — same effect.)

- [ ] **Step 4: Run new test + full regression**

Run: `make test-b8008-extram` → PASS.
Run: `./test_programs/verification_scripts/run_all_tests.sh` → all PASS (defaults untouched).

- [ ] **Step 5: Commit**

```bash
git add src/b8008/b8008_top.vhdl sim/b8008/b8008_top_extram_tb.vhdl Makefile
git commit -m "b8008_top: optional external RAM bus (EXTERNAL_RAM generic), equivalence-tested"
```

---

### Task 4: `b8008_net_core` wrapper + GHDL boot testbench

Port of `projects/b8008_monitor/src/b8008_monitor_top.vhdl` with: no PLL, no pads, no debouncers, no memories, DIP-switch features replaced by ports.

**Files:**
- Create: `projects/b8008_net/src/b8008_net_core.vhdl`
- Create: `projects/b8008_net/sim/b8008_net_core_tb.vhdl`
- Modify: `projects/b8008_net/Makefile` (add `sim-core` target; GHDL flags copied from `projects/project.mk`: `--std=08 --work=work`)

**Interfaces:**
- Produces the entity every later task instantiates:

```vhdl
entity b8008_net_core is
    port (
        clk  : in std_logic;   -- 25 MHz (LiteX "b8008" clock domain)
        rst  : in std_logic;   -- active-high, synchronous, from LiteX CRG
        -- console serial (internal wires to LiteX console bridge)
        uart_tx : out std_logic;
        uart_rx : in  std_logic;
        -- control pulses: single-cycle, clk domain, already synchronized
        ctl_run_stop   : in std_logic;
        ctl_step_cycle : in std_logic;
        ctl_step_sync  : in std_logic;
        ctl_int        : in std_logic;   -- one interrupt request
        ctl_int_vector : in std_logic_vector(2 downto 0);  -- stable level
        -- status (clk domain; LiteX side synchronizes)
        sts_is_running : out std_logic;
        sts_triggered  : out std_logic;
        sts_tx_busy    : out std_logic;
        -- external RAM bus (contract: see b8008_top ram_ext_* comment)
        ram_addr  : out std_logic_vector(12 downto 0);
        ram_wdata : out std_logic_vector(7 downto 0);
        ram_rdata : in  std_logic_vector(7 downto 0);
        ram_rw_n  : out std_logic;
        ram_cs_n  : out std_logic;
        -- external ROM bus (contract: 1-cycle synchronous read, no gating)
        rom_addr : out std_logic_vector(11 downto 0);
        rom_data : in  std_logic_vector(7 downto 0);
        -- logic-analyzer debug (straight to pads at SoC level)
        dbg_d    : out std_logic_vector(7 downto 0);
        dbg_s0   : out std_logic; dbg_s1 : out std_logic; dbg_s2 : out std_logic;
        dbg_sync : out std_logic; dbg_phi1 : out std_logic; dbg_phi2 : out std_logic;
        dbg_int  : out std_logic
    );
end entity;
```

- [ ] **Step 1: Write the failing boot testbench**

`sim/b8008_net_core_tb.vhdl`: instantiate `b8008_net_core`; connect `ram_sync` (ADDR_BITS=>13) to the RAM bus and `rom_4kx8_bram` (its `ADDR`/`DATA_OUT`/`CS_N=>'0'` port map exactly as the monitor top's `gen_internal_rom`) to the ROM bus — these ARE the behavioral models, contract-conformant by construction. ROM content: `projects/b8008_monitor/src/rom_baked.mem` via the same mechanism `rom_4kx8_bram` uses today (check its generic/init; mirror the monitor project's sim setup in `projects/b8008_monitor/sim/monitor_boot_tb.vhdl` — copy its UART-decode procedure verbatim). Drive `clk` at 25 MHz, pulse `rst`, hold ctl inputs at '0' (auto-start must boot it — that's the test). Decode `uart_tx` at 115200 and assert the monitor banner string arrives (same string `monitor_boot_tb` checks). PASS/FAIL report.

- [ ] **Step 2: Add `sim-core` target, run, verify fail**

Makefile target analyzes: all of `src/b8008/*.vhdl`, `src/components/rom_4kx8.vhdl` equivalents used by the monitor sim (copy the analyze list from `projects/b8008_monitor/Makefile`), then `src/b8008_net_core.vhdl`, then the TB.
Run: `cd projects/b8008_net && make sim-core`
Expected: FAIL — `b8008_net_core` not found.

- [ ] **Step 3: Write the wrapper**

Start from a copy of `b8008_monitor_top.vhdl`. Deltas:
1. Entity → the Interfaces block above.
2. Delete: `u_pll` (clk is already 25 MHz; `pll_locked` → `not rst`), all three debouncers, `gen_internal_rom` (keep only the external path: `rom_d_cpu <= rom_data; rom_addr <= rom_a_int(11 downto 0)`), LED muxes, rolling-fetch capture, `cpu_*` pad wiring (replace with `dbg_*` assignments), `u_int_button` and the sw(5)/sw(7) logic, ready-hold sw(6) logic (`ready_in => '1'` constant), reset-sync from sw(0) (`reset_sw <= '0'`).
3. POR: keep the counter process, replace `pll_locked = '0'` condition with `rst = '1'`.
4. Auto-start: keep verbatim (2 ms synthetic press).
5. Bootstrap FSM, vec latch: keep verbatim, except vec latch's button branch becomes `elsif int_req_latch = '1' then cpu_int_vec <= ctl_int_vector;`.
6. New interrupt request latch replacing int_button:

```vhdl
int_latch : process(clk)
begin
    if rising_edge(clk) then
        if reset_int = '1' or bootstrap_done = '0' then
            int_req_latch <= '0';
        elsif ctl_int = '1' then
            int_req_latch <= '1';
        elsif t1i_ack_sig = '1' then
            int_req_latch <= '0';
        end if;
    end if;
end process;
```
`interrupt => bootstrap_int or int_req_latch`.
7. `u_debug_clk` port map: `btn_run_stop => ctl_run_stop or auto_start_pulse`, `btn_step_cycle => ctl_step_cycle`, `btn_step_sync => ctl_step_sync`, `bootstrap_done => bootstrap_done` (hardware-break switch gone — break disabled, i.e. the old sw(1)-off behavior).
8. `u_system : b8008_top` generic map: `CLK_FREQ_HZ => 25_000_000, EXTERNAL_RAM => true` plus the monitor's existing ROM/RAM map generics copied verbatim from its instantiation; wire `ram_ext_addr(12 downto 0) → ram_addr`, `ram_ext_wdata → ram_wdata`, `ram_ext_rdata ← ram_rdata`, `ram_ext_rw_n → ram_rw_n`, `ram_ext_cs_n → ram_cs_n`.
9. `u_uart : b8008_usart` kept verbatim (25 MHz generic already explicit).
10. Status: `sts_is_running <= dbg_is_running; sts_triggered <= dbg_triggered; sts_tx_busy <= uart_tx_busy;`

- [ ] **Step 4: Run to pass**

Run: `cd projects/b8008_net && make sim-core`
Expected: PASS — banner decoded, headless auto-start proven.

- [ ] **Step 5: Commit**

```bash
git add projects/b8008_net/src/b8008_net_core.vhdl projects/b8008_net/sim/b8008_net_core_tb.vhdl projects/b8008_net/Makefile
git commit -m "b8008_net: pure-logic core wrapper boots monitor headless in sim"
```

---

### Task 5: Netlist conversion + iverilog smoke

**Files:**
- Create: `projects/b8008_net/sim/netlist_tb.v`, `projects/b8008_net/sim/models.v`
- Modify: `projects/b8008_net/Makefile` (`convert`, `sim-netlist` targets)

**Interfaces:**
- Produces: `build/b8008_net_core.v` — the only VHDL-derived artifact later tasks consume; module name `b8008_net_core`, ports exactly as Task 4.

- [ ] **Step 1: `convert` target**

```make
CORE_SRCS := $(wildcard ../../src/b8008/*.vhdl) src/b8008_net_core.vhdl
build/b8008_net_core.v: $(CORE_SRCS)
	mkdir -p build
	cd build && $(GHDL) -a --std=08 --work=work $(addprefix ../,$(CORE_SRCS))
	cd build && $(GHDL) synth --std=08 --work=work --out=verilog b8008_net_core > b8008_net_core.v
convert: build/b8008_net_core.v
```
(`b8008_usart` lives outside `src/b8008/` — add its actual path from the monitor Makefile's analyze list to `CORE_SRCS`.)

- [ ] **Step 2: Run, inspect**

Run: `make convert`
Expected: `build/b8008_net_core.v` exists; `grep -c "module" build/b8008_net_core.v` > 1; **no empty module bodies for known units** (spot-check: `grep -A2 "module .*alu"` shows logic — ghdl#2092 guard).

- [ ] **Step 3: Write verilog models + TB, run smoke**

`sim/models.v`: 8KB RAM and 4KB ROM in verilog implementing the memory-port contract (sync read every posedge, RAM write on `!cs_n && !rw_n`; ROM `$readmemh` from `rom_baked.mem` path passed via parameter). `sim/netlist_tb.v`: clock 25 MHz, reset pulse, UART RX decoder at 115200 collecting bytes into a buffer; after 60 ms sim time, `$display` PASS if buffer contains the banner substring (same string as Task 4), else FAIL.
Run: `make sim-netlist` (target: `iverilog -g2012 -o build/netlist_tb build/b8008_net_core.v sim/models.v sim/netlist_tb.v && vvp build/netlist_tb`)
Expected: PASS. If iverilog chokes on GHDL's output constructs, substitute `verilator --binary` for iverilog in the target — either simulator satisfies the task.

- [ ] **Step 4: Commit**

```bash
git add projects/b8008_net/sim/netlist_tb.v projects/b8008_net/sim/models.v projects/b8008_net/Makefile
git commit -m "b8008_net: ghdl->verilog conversion verified by netlist boot sim"
```

---

### Task 6: `B8008Core` Migen integration module

**Files:**
- Create: `projects/b8008_net/b8008_integration.py`
- Create: `projects/b8008_net/test_integration.py` (elaboration unit test)

**Interfaces:**
- Consumes: `build/b8008_net_core.v` (Task 5), port names from Task 4.
- Produces: `class B8008Core(LiteXModule)` with: `.bus_ram` (wishbone.Interface, slave, 8192×32-bit words, byte per word), CSRs `ctl` (fields `run_stop, step_cycle, step_sync, int_req, int_vector[3]`), `status` (fields `is_running, triggered, tx_busy`), `console` sub-CSRs (`rxtx` 8-bit read-pop/write-push, `rxlevel`, `txfull`, `rxempty`), constructor `B8008Core(platform, core_v="build/b8008_net_core.v", rom_init=<list[int] 4096>)`. Requires clock domain `"b8008"` to exist.

- [ ] **Step 1: Write the failing elaboration test**

```python
# test_integration.py
from migen import *
from litex.gen import LiteXModule

def test_elaborates(tmp_path):
    from b8008_integration import B8008Core
    from litex.build.generic_platform import Pins
    from litex.build.lattice import LatticeECP5Platform
    # minimal fake platform good enough for finalization
    class P(LatticeECP5Platform):
        default_clk_name = "clk"
        def __init__(self):
            super().__init__("LFE5UM5G-45F-8BG381C", [("clk", 0, Pins("P3"))], toolchain="trellis")
    class Top(LiteXModule):
        def __init__(self, platform):
            self.cd_sys = ClockDomain()
            self.cd_b8008 = ClockDomain()
            self.core = B8008Core(platform, rom_init=[0]*4096)
    top = Top(P())
    from migen.fhdl.verilog import convert
    v = str(convert(top, ios=set()))
    assert "b8008_net_core" in v

def test_rom_init_loader():
    from b8008_integration import load_mem_file
    words = load_mem_file("../b8008_monitor/src/rom_baked.mem")
    assert len(words) == 4096 and all(0 <= w < 256 for w in words)
```

Run: `.venv/bin/python -m pytest test_integration.py -v` → FAIL (module missing).

- [ ] **Step 2: Implement `b8008_integration.py`**

```python
from migen import *
from migen.genlib.cdc import MultiReg, PulseSynchronizer
from litex.gen import LiteXModule
from litex.soc.interconnect import wishbone, stream
from litex.soc.interconnect.csr import CSRStorage, CSRStatus, CSR, CSRField, AutoCSR

def load_mem_file(path):
    return [int(l.strip(), 16) for l in open(path) if l.strip()]

class B8008Core(LiteXModule, AutoCSR):
    def __init__(self, platform, core_v="build/b8008_net_core.v", rom_init=None):
        # ---- control CSRs (sys domain) -> pulses in b8008 domain -------
        self.ctl = CSRStorage(fields=[
            CSRField("run_stop",   size=1, pulse=True),
            CSRField("step_cycle", size=1, pulse=True),
            CSRField("step_sync",  size=1, pulse=True),
            CSRField("int_req",    size=1, pulse=True),
            CSRField("int_vector", size=3)])
        ctl_pulses = {}
        for name in ["run_stop", "step_cycle", "step_sync", "int_req"]:
            ps = PulseSynchronizer("sys", "b8008")
            self.submodules += ps
            self.comb += ps.i.eq(getattr(self.ctl.fields, name))
            ctl_pulses[name] = ps.o
        int_vec_b = Signal(3)
        self.specials += MultiReg(self.ctl.fields.int_vector, int_vec_b, "b8008")
        # ---- status b8008 -> sys ---------------------------------------
        is_running_b, triggered_b, tx_busy_b = Signal(), Signal(), Signal()
        self.status = CSRStatus(fields=[
            CSRField("is_running", size=1), CSRField("triggered", size=1),
            CSRField("tx_busy", size=1)])
        self.specials += [
            MultiReg(is_running_b, self.status.fields.is_running),
            MultiReg(triggered_b,  self.status.fields.triggered),
            MultiReg(tx_busy_b,    self.status.fields.tx_busy)]
        # ---- RAM: 8KB dual-port, byte per 32-bit wishbone word ---------
        ram = Memory(8, 8192)
        pa = ram.get_port(write_capable=True, clock_domain="b8008")
        pb = ram.get_port(write_capable=True, clock_domain="sys")
        self.specials += ram, pa, pb
        self.bus_ram = wishbone.Interface(data_width=32, adr_width=30)
        self.sync += self.bus_ram.ack.eq(self.bus_ram.cyc & self.bus_ram.stb & ~self.bus_ram.ack)
        self.comb += [
            pb.adr.eq(self.bus_ram.adr[:13]),
            pb.dat_w.eq(self.bus_ram.dat_w[:8]),
            pb.we.eq(self.bus_ram.cyc & self.bus_ram.stb & ~self.bus_ram.ack
                     & self.bus_ram.we & self.bus_ram.sel[0]),
            self.bus_ram.dat_r.eq(pb.dat_r)]
        # ---- ROM: 4KB, b8008-domain read port ---------------------------
        rom = Memory(8, 4096, init=rom_init or [0]*4096)
        pr = rom.get_port(clock_domain="b8008")
        self.specials += rom, pr
        # ---- console bridge: RS232-level serial <-> CSR FIFOs ----------
        #   Mirrors litex.soc.cores.uart mechanism (read .venv/**/uart.py):
        #   RS232PHY in sys domain on internal pads; SyncFIFO rx depth 4096,
        #   tx depth 256; CSR rxtx pops rx on read / pushes tx on write;
        #   CSRStatus rxlevel <- rx_fifo.level, txfull, rxempty.
        from litex.soc.cores.uart import RS232PHY
        pads = Record([("tx", 1), ("rx", 1)])
        self.submodules.phy = RS232PHY(pads, clk_freq=platform.sys_clk_freq
                                       if hasattr(platform, "sys_clk_freq") else 75_000_000,
                                       baudrate=115200)
        rx_fifo = stream.SyncFIFO([("data", 8)], 4096)
        tx_fifo = stream.SyncFIFO([("data", 8)], 256)
        self.submodules += rx_fifo, tx_fifo
        self._rxtx    = CSR(8, name="rxtx")
        self._rxlevel = CSRStatus(13, name="rxlevel")
        self._txfull  = CSRStatus(name="txfull")
        self._rxempty = CSRStatus(name="rxempty")
        self.comb += [
            self.phy.source.connect(rx_fifo.sink),
            tx_fifo.source.connect(self.phy.sink),
            self._rxtx.w.eq(rx_fifo.source.data),
            rx_fifo.source.ready.eq(self._rxtx.we_r if hasattr(self._rxtx, "we_r") else self._rxtx.we),
            tx_fifo.sink.data.eq(self._rxtx.r),
            tx_fifo.sink.valid.eq(self._rxtx.re),
            self._rxlevel.status.eq(rx_fifo.level),
            self._txfull.status.eq(~tx_fifo.sink.ready),
            self._rxempty.status.eq(~rx_fifo.source.valid)]
        # NOTE: the exact pop/push strobes (re vs we naming) MUST be copied
        # from the installed litex uart.py — assert against it in Step 3.
        # ---- the VHDL core ----------------------------------------------
        platform.add_source(core_v)
        self.specials += Instance("b8008_net_core",
            i_clk=ClockSignal("b8008"), i_rst=ResetSignal("b8008"),
            o_uart_tx=pads.rx,  # core TX -> bridge RX
            i_uart_rx=pads.tx,  # bridge TX -> core RX
            i_ctl_run_stop=ctl_pulses["run_stop"],
            i_ctl_step_cycle=ctl_pulses["step_cycle"],
            i_ctl_step_sync=ctl_pulses["step_sync"],
            i_ctl_int=ctl_pulses["int_req"],
            i_ctl_int_vector=int_vec_b,
            o_sts_is_running=is_running_b, o_sts_triggered=triggered_b,
            o_sts_tx_busy=tx_busy_b,
            o_ram_addr=pa.adr, o_ram_wdata=pa.dat_w, i_ram_rdata=pa.dat_r,
            o_ram_rw_n=Signal(name="ram_rw_n_w"), o_ram_cs_n=Signal(name="ram_cs_n_w"),
            o_rom_addr=pr.adr, i_rom_data=pr.dat_r,
            o_dbg_d=Signal(8), o_dbg_s0=Signal(), o_dbg_s1=Signal(), o_dbg_s2=Signal(),
            o_dbg_sync=Signal(), o_dbg_phi1=Signal(), o_dbg_phi2=Signal(), o_dbg_int=Signal())
        # pa.we from rw_n/cs_n: route the two Signal()s above into named
        # signals and: self.comb += pa.we.eq(~cs_n & ~rw_n)
```

Clean up the last comment into real code (named `ram_rw_n`/`ram_cs_n` Signals + the `pa.we` comb). Expose debug signals as attributes (`self.dbg = Record(...)`) so `versa_soc.py` can route them to pads.

- [ ] **Step 3: Verify CSR pop/push strobes against installed LiteX**

Read `.venv/**/litex/soc/cores/uart.py` `UART.__init__` — copy its exact `rxtx`/fifo strobe wiring (`self._rxtx.re`/`.we` semantics) into the bridge; the comment in Step 2 marks the spot. This is a correctness-critical detail that varies by LiteX version.

- [ ] **Step 4: Run tests to pass, commit**

Run: `.venv/bin/python -m pytest test_integration.py -v` → 2 PASS.

```bash
git add projects/b8008_net/b8008_integration.py projects/b8008_net/test_integration.py
git commit -m "b8008_net: B8008Core Migen integration - memories, console bridge, control CDC"
```

---

### Task 7: `versa_soc.py` — full SoC builds to bitstream

**Files:**
- Modify: `projects/b8008_net/versa_soc.py` (has the Task 2 invocation comment)
- Modify: `projects/b8008_net/Makefile` (`build`, `prog`, `check-synth` targets)

**Interfaces:**
- Consumes: `B8008Core` (Task 6), spike invocation (Task 2).
- Produces: `build/versa/gateware/versa_soc.bit`, `build/versa/csr.csv`; CSR names `b8008_ctl`, `b8008_status`, `b8008_rxtx`, `b8008_rxlevel`, `b8008_txfull`, `b8008_rxempty`, `eb_ip_ip`, `identifier_*`; mem region `b8008_ram` (origin recorded in csr.csv). These names are the host-tool contract.

- [ ] **Step 1: Write the target**

Based on the stock versa target (Task 1 module) with these deltas:
1. CRG: extend the stock `_CRG` — add `self.cd_b8008 = ClockDomain()` and `pll.create_clkout(self.cd_b8008, 25e6)`; keep sys at the stock 75 MHz.
2. `SoCCore` args: `cpu_type="vexriscv", cpu_variant="minimal", integrated_rom_size=0x8000, integrated_sram_size=0x2000, uart_name="stub", ident="b8008_net", ident_version=True, timer=True` (identifier CSR is the staleness check hook).
3. `self.submodules.eb_ip = ...` + `add_etherbone(...)` exactly per the Task 2 spike result (Signal-driven IP, `with_ethmac=True`, both MACs from Global Constraints).
4. `self.submodules.b8008 = B8008Core(platform, rom_init=load_mem_file("../b8008_monitor/src/rom_baked.mem"))`; `self.bus.add_slave("b8008_ram", self.b8008.bus_ram, SoCRegion(origin=0x9000_0000, size=0x10000, cached=False))`.
5. Route `self.b8008.dbg` record to the X3 expansion pads: add a platform extension with the same sites the monitor LPF uses for `cpu_d[0..7]`, `cpu_s0..2`, `cpu_sync`, `cpu_phi1/2`, `cpu_int` (copy sites from `projects/b8008_monitor/constraints/b8008_monitor.lpf`).
6. `--build` CLI via `LiteXArgumentParser` as in the stock target; also emit `csr.csv` (`--csr-csv build/versa/csr.csv`).

- [ ] **Step 2: Makefile targets**

```make
build: convert firmware
	$(PY) versa_soc.py --build --output-dir build/versa --csr-csv build/versa/csr.csv \
	    --integrated-rom-init firmware/build/firmware.bin
prog:
	$(OSS_CAD_SUITE)/openFPGALoader -b versa build/versa/gateware/versa_soc.bit
check-synth:
	@grep -E "DP16KD" build/versa/gateware/*_synth* | head; \
	 echo "expect >= 8 DP16KD (8KB RAM=4..8, ROM=2..4, + SoC)"
```
(Until Task 8 exists, temporarily build with `--integrated-rom-init` omitted.)

- [ ] **Step 3: Build**

Run: `make build` (expect 10–30 min first time)
Expected: bitstream + csr.csv exist; `grep b8008_rxtx build/versa/csr.csv` hits; `grep b8008_ram build/versa/csr.csv` shows origin 0x90000000; `make check-synth` shows DP16KD count ≥ expected and total FF count < 20k (if FFs ≈ 65k+, BRAM inference failed — stop, fix before proceeding); timing report shows all domains met.

- [ ] **Step 4: Commit**

```bash
git add projects/b8008_net/versa_soc.py projects/b8008_net/Makefile
git commit -m "b8008_net: full SoC builds - etherbone + vexriscv + b8008 core, timing met"
```

---

### Task 8: DHCP/identity firmware

**Files:**
- Create: `projects/b8008_net/firmware/main.c`, `firmware/dhcp8008.c`, `firmware/dhcp8008.h`, `firmware/Makefile` (scaffold: `.venv/bin/litex_bare_metal_demo --build-path=build/versa` generates a working app skeleton — copy its Makefile/linker setup, replace main.c)
- Create: `projects/b8008_net/firmware/test_dhcp_host.c` (host-cc unit test of packet builder)

**Interfaces:**
- Consumes: CSR accessors from `build/versa/generated/csr.h` (notably `eb_ip_ip_write()`); libliteeth (`udp.c/microudp`) from the LiteX tree.
- Produces: `firmware/build/firmware.bin` for `--integrated-rom-init`.

- [ ] **Step 1: Host-testable DHCP packet builder first**

`dhcp8008.c`: `int dhcp_build_discover(uint8_t *buf, const uint8_t chaddr[6], uint32_t xid)` and `dhcp_build_request(...)` — construct BOOTP+options: op=1, **flags=0x8000 (broadcast)**, **chaddr = Etherbone MAC**, options: 53 (DISCOVER/REQUEST), 55 (1,3,6), **12 = "b8008"**, 61 = chaddr, 255. Plus `int dhcp_parse_offer(const uint8_t *buf, int len, uint32_t xid, uint32_t *ip, uint32_t *server, uint32_t *lease_secs)`.
`test_dhcp_host.c`: builds a DISCOVER, asserts flags==0x8000, chaddr matches, option 12 present with "b8008", option list terminated; parses a canned OFFER byte array and asserts ip/lease extraction.
Run: `cc -o /tmp/t firmware/dhcp8008.c firmware/test_dhcp_host.c && /tmp/t` → prints `ALL PASS`. (Write test first; watch it fail to link; implement; pass.)

- [ ] **Step 2: `main.c`**

Logic (uses libliteeth's raw send/receive around the builder — mirror how `bios/cmds/cmd_liteeth` and `libliteeth/dhcp.c` drive microudp; DHCP is UDP 68→67 broadcast):

```c
for (;;) {
    if (!leased || elapsed >= lease_secs/2) {
        if (dhcp_run(&ip, &lease_secs)) {      // DISCOVER->OFFER->REQUEST->ACK, 5 tries
            eb_ip_ip_write(ip);                 // etherbone answers on leased IP
            leased = 1; elapsed = 0;
        }
    }
    msleep(1000); elapsed++;
}
```

- [ ] **Step 3: Build firmware + full bitstream**

Run: `cd firmware && make` → `firmware/build/firmware.bin`. Then `cd .. && make build` (now with rom-init).
Expected: clean build, bitstream regenerated.

- [ ] **Step 4: Commit**

```bash
git add projects/b8008_net/firmware
git commit -m "b8008_net: DHCP firmware - option-12 hostname, etherbone-MAC chaddr, renewal"
```

---

### Task 9: litex_sim end-to-end (pre-hardware gate)

**Files:**
- Create: `projects/b8008_net/sim_soc.py`
- Modify: `projects/b8008_net/Makefile` (`sim-soc` target)
- Create: `projects/b8008_net/host_selftest.py` (scripted RemoteClient checks, reused later)

**Interfaces:**
- Consumes: converted netlist, `B8008Core`.
- Produces: proof the console CSR path, RAM window, and control CSRs work over Etherbone before any hardware.

- [ ] **Step 1: sim SoC**

`sim_soc.py`: LiteX sim platform (`litex.build.sim`), pattern-match `litex/tools/litex_sim.py`: SimPHY ethernet model with `--with-etherbone`, **static** `ip_address="192.168.1.51"` (no Signal, no CPU — firmware/DHCP is out of sim scope, noted in spec), plus `B8008Core` with the same rom_init. `b8008` clock domain: in sim, drive it from sys clock divided by 3 via a simple counter CE domain — or run `b8008` = sys (25 MHz sys in sim) — pick sys=25 MHz for the sim SoC so both domains are one clock; CDC correctness was reviewed structurally and litex_sim's value here is the CSR/wishbone/netlist plumbing.

- [ ] **Step 2: scripted checks**

`host_selftest.py` (argparse `--csr build/sim/csr.csv`):
1. RemoteClient connect; read identifier string; print.
2. RAM window: write bytes 0..255 at word offsets 0..255 (burst), read back (burst), assert equal.
3. Console: poll `b8008_rxlevel` until > 0 (auto-start banner), drain, assert banner substring present, print it.
4. Type `H\r` (or the monitor's help/command from `b8008_monitor.asm` — check its command table) via `rxtx` writes; assert response arrives.
Exit 0 on all-pass.

- [ ] **Step 3: Run**

Terminal A: `make sim-soc` (runs Verilator sim with etherbone on tap/udp per litex_sim conventions).
Terminal B: `.venv/bin/litex_server --udp --udp-ip=192.168.1.51` then `.venv/bin/python host_selftest.py --csr build/sim/csr.csv`.
Expected: `ALL PASS` including printed monitor banner. Iterate here until it does — this is the cheap place to debug.

- [ ] **Step 4: Commit**

```bash
git add projects/b8008_net/sim_soc.py projects/b8008_net/host_selftest.py projects/b8008_net/Makefile
git commit -m "b8008_net: litex_sim end-to-end - banner, RAM window, console over etherbone"
```

---

### Task 10: `b8008net` skeleton — discovery, lock, connection

**Files:**
- Create: `projects/b8008_net/host/pyproject.toml` (name `b8008net`, console-script `b8008net = b8008net.cli:main`)
- Create: `projects/b8008_net/host/b8008net/{__init__.py,cli.py,discovery.py,board.py}`
- Create: `projects/b8008_net/host/tests/test_discovery.py`

**Interfaces:**
- Produces: `Board` class: `Board.connect(csr_csv, host=None) -> Board` (spawns/finds litex_server, identifier check, lockfile at `~/.b8008net.lock`), `.read(addr, n=1, same_addr=False)`, `.write(addr, values)`, `.regs` (RemoteClient regs), `.ram_base` (from csr.csv `b8008_ram`). `discover() -> str|None`: tries cached `~/.b8008net_host`, then `b8008.lan`/`b8008.local` DNS, then probe sweep.

- [ ] **Step 1: Failing tests**

`test_discovery.py`:
- `test_sweep_builds_probe()`: `probe_packet()` returns bytes beginning with Etherbone magic `0x4e6f` and probe flag set (build via `litex.tools.remote.etherbone.EtherbonePacket` with `pf=1`; assert against its own parser round-trip).
- `test_sweep_candidates()`: `subnet_candidates("192.168.7.23", "255.255.255.0")` yields 253 addresses excluding self/network/broadcast.
- `test_cache_roundtrip(tmp_path)`: `save_cache/load_cache`.
- `test_lock_excludes(tmp_path)`: acquiring lock twice raises `BoardBusy`.
Run: `.venv/bin/python -m pytest host/tests -v` → FAIL (module missing).

- [ ] **Step 2: Implement**

`discovery.py`: the four functions; sweep = UDP socket, send probe to each candidate:1234, `select` 0.5 s window, first responder wins. `board.py`: lockfile via `fcntl.flock`; spawn `litex_server --udp --udp-ip <host>` as subprocess if port 1234 TCP not already listening; RemoteClient; identifier read (`identifier_mem` chars) printed and compared with csr.csv timestamp — mismatch prints a loud warning. `read(..., same_addr=True)` builds an `EtherboneReads` record with a repeated address list for FIFO draining (fallback: loop of single reads if the server rejects it — try once, remember).

- [ ] **Step 3: Pass + live check against litex_sim**

Run: pytest → PASS. Then with Task 9's sim still available: `b8008net --csr build/sim/csr.csv --host 192.168.1.51 status` prints identifier + is_running. (Add the thin `cli.py` with `status` subcommand now.)

- [ ] **Step 4: Commit**

```bash
git add projects/b8008_net/host
git commit -m "b8008net: discovery (dns+probe-sweep+cache), lockfile, board connection, status"
```

---

### Task 11: `b8008net console`

**Files:**
- Create: `projects/b8008_net/host/b8008net/console.py`
- Modify: `projects/b8008_net/host/b8008net/cli.py`
- Create: `projects/b8008_net/host/tests/test_console.py`

**Interfaces:**
- Consumes: `Board` (`.regs.b8008_rxtx/rxlevel/txfull/rxempty`).
- Produces: `console_loop(board, stdin, stdout)` — raw-tty interactive session; Ctrl-] exits.

- [ ] **Step 1: Failing test with a fake board**

`test_console.py`: `FakeBoard` with scripted rxlevel/rxtx values; assert `drain(board)` returns exactly the scripted bytes using batched reads (rxlevel consulted, ≤256 per batch); assert `send(board, b"G 2000\r")` writes each byte and respects a scripted `txfull=1` stall.
Run → FAIL.

- [ ] **Step 2: Implement**

`drain()`: read rxlevel; if 0 return; `board.read(rxtx_addr, n=min(level,256), same_addr=True)`; bytes out. `send()`: per byte, spin on txfull (with 1 ms sleep), write rxtx. `console_loop()`: `termios` raw mode, select on stdin, 10 ms poll cadence, drain→stdout, stdin→send.

- [ ] **Step 3: Pass tests; live smoke on litex_sim**

pytest PASS; then `b8008net --csr build/sim/csr.csv --host 192.168.1.51 console` shows banner, monitor responds to typed commands.

- [ ] **Step 4: Commit**

```bash
git add projects/b8008_net/host
git commit -m "b8008net: interactive console with batched fifo drains"
```

---

### Task 12: `b8008net` load / peek / poke / run / reset / step

**Files:**
- Create: `projects/b8008_net/host/b8008net/{hexfile.py,commands.py}`
- Modify: `projects/b8008_net/host/b8008net/cli.py`
- Create: `projects/b8008_net/host/tests/{test_hexfile.py,test_commands.py}`

**Interfaces:**
- Consumes: `Board`, `console.send/drain`, monitor `G`/`L` semantics from `projects/b8008_monitor/b8008_monitor.asm` and the existing `send_hex.py` (read both first — the hex format is whatever `p2hex` emits and `send_hex.py` already parses; mirror it).
- Produces: CLI subcommands `load FILE`, `peek ADDR [LEN]`, `poke ADDR BYTE...`, `run ADDR`, `reset`, `stop`, `step [sync]`.

- [ ] **Step 1: Failing tests**

`test_hexfile.py`: parse a 3-record Intel-HEX literal (embedded in the test) → `{addr: bytes}` segments; checksum error raises.
`test_commands.py` (FakeBoard): `load` writes segments to `ram_base + 4*(addr-0x2000)` as bursts, reads back, raises `VerifyError` with offset on injected mismatch; `load` refuses (without `--force`) when `status.is_running=1`; `run 0x2000` sends `G 2000\r` via console; `stop` toggles: fake `is_running=1`, expect one ctl.run_stop pulse then status re-read; addresses below 0x2000/above 0x3FFF raise.
Run → FAIL.

- [ ] **Step 2: Implement + pass**

`commands.py` implements against `Board` + console helpers; `peek` prints canonical hexdump. RAM mapping: `word_addr = ram_base + 4*(a8008 - 0x2000)`; reject out-of-range. `stop`/`run-state`: toggle-and-verify loop (max 3 attempts, then error).

- [ ] **Step 3: Live smoke on litex_sim**

`b8008net ... load ../../test_programs/<small>.hex` (assemble one first via the monitor project's flow: `cd ../b8008_monitor && make assemble PROG=...` — use an existing RAM-targeted program from the L/G workflow), `peek 2000 32`, `run 2000`, console shows program output.

- [ ] **Step 4: Commit**

```bash
git add projects/b8008_net/host
git commit -m "b8008net: load/peek/poke/run/reset/step with read-back verify"
```

---

### Task 13: HW stage 1 — SoC alone on the board (USER IN LOOP)

No new code. Hand the user: `make build && make prog` (or the .bit path for their flashing flow). Then verify together:

- [ ] Board requests DHCP; router device list shows **b8008**; note the leased IP.
- [ ] `b8008net status` finds the board via discovery (no IP typed) — identifier string matches this build.
- [ ] `.venv/bin/litex_cli --udp --udp-ip <leased> --regs` dumps CSRs.
- [ ] `make check-synth` numbers recorded: DP16KD count as expected, FFs sane, timing met.
- [ ] Leave powered past lease T1 (≥ half lease time): renewal observed (router lease timer refreshes; board stays reachable).
- [ ] Any failure: debug before proceeding; commits allowed for fixes but messages say "sim-proven" only.

---

### Task 14: HW stage 2 — full monitor over the network (USER IN LOOP)

- [ ] `b8008net console` → monitor banner appears (headless auto-start on real silicon).
- [ ] Monitor commands work interactively (whatever `b8008_monitor.asm` supports — same session quality as serial).
- [ ] `b8008net peek 2000 64` / `poke` round-trip while CPU at prompt.
- [ ] `b8008net stop` / `step` / `reset` behave (toggle-and-verify converges); physical buttons still work.

---

### Task 15: HW stage 3 — workflow parity, docs, final gate (USER IN LOOP)

- [ ] `b8008net load` + `run` for **mandelbrot, pi, calc** — outputs match the serial-era results (compare against the validated runs recorded in project memory / prior sessions).
- [ ] Write `projects/b8008_net/README.md`: what it is, one-time setup (`make litex-env`), build/flash, `b8008net` usage, discovery behavior, demo-layer future note.
- [ ] Update root `README.md` with a short b8008_net section.
- [ ] Final commits (user-triggered): docs + any held fixes, messages may now say hardware-validated.

```bash
git add projects/b8008_net/README.md README.md
git commit -m "b8008_net: hardware-validated - monitor over Ethernet (console, load, peek/poke)"
```

---

## Self-Review Notes (kept for executors)

- Spec coverage: appliance DHCP (T8), hostname (T8), Etherbone dynamic IP + ARP-by-zero (T2/T7/T8), memories Migen-side + DP16KD check (T6/T7), console FIFO 4096 + batched drains (T6/T11), control CDC + toggle-and-verify (T6/T12), wrapper full scope + auto-start (T4), b8008_top external RAM — spec's "modules unchanged" amended by design here, backward-compatible + regression-gated (T3), identifier staleness (T10), lockfile (T10), burst load + verify (T12), litex_sim stage (T9), staged HW gates (T13–15).
- Known version-sensitive spots are marked in-task with "read the installed source" directives (litex uart strobes T6/S3, add_etherbone kwargs T2/S2, litex_setup flags T1/S2) — these are deliberate: the pinned tree is the source of truth, not this document.
