# Plan B: remote_8008 Extraction

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `projects/b8008_net/` into a fresh standalone repo `~/Development/remote_8008` that consumes the b8008 core via FuseSoC, with all three sim tiers and the LiteX build green before the old tree is deleted.

**Architecture:** Fresh git repo, tracked-files-only import. Top-level Python moves to `soc/`; the VHDL wrapper and the copied monitor ROM live in `src/`. The GHDL netlist is produced by the core repo's `ghdl_synth_verilog` generator (via a small `remote_8008.core` consumer); `sim-core` keeps a `CORE_DIR`-rooted raw-VHDL list because a GHDL testbench cannot consume a netlist.

**Tech Stack:** FuseSoC 2.x, GHDL/Verilator/yosys/nextpnr (oss-cad-suite), LiteX pinned `2026.04`, Python venv.

**Spec:** `intel-8008-vhdl/docs/superpowers/specs/2026-07-10-fusesoc-refactor-design.md`
**Prerequisite:** Plan A complete — read `intel-8008-vhdl/docs/fusesoc.md` for the proven `fusesoc run` incantation and copy-out pattern before Task 3.

## Global Constraints

- `CORE_DIR ?= $(HOME)/Development/intel-8008-vhdl` — the single knob for locating the core repo (Makefile) and its mirror `_CORE_DIR` env fallback in Python.
- LiteX pinned: `LITEX_TAG ?= 2026.04` (already in the Makefile — keep it).
- Source dir is 911MB with 15+ nested git clones — NEVER copy the directory wholesale; only `git ls-files` output.
- The Etherbone plan doc migrates paths-only — it already incorporates both review rounds; no content edits.
- `projects/b8008_net/` is deleted from the core repo ONLY after Task 6's full verification, and that deletion is a user-confirmed step.
- Generator invocation: `top=b8008_net_core`, `extra_files=[src/rom_4kx8_bram.vhdl, src/b8008_net_core.vhdl]` (proven CORE_SRCS order; rom may be dropped from extra_files if elaboration confirms it unused — it must stay in `src/` for sim-core regardless).

---

### Task 1: Repo init + tracked-files import

**Files:**
- Create: `~/Development/remote_8008/` (entire tree)

**Interfaces:**
- Produces: repo with layout `soc/`, `src/`, `sim/`, `firmware/`, `host/`, `docs/`, `Makefile`, `.gitignore`; import commit recording source hash.

- [ ] **Step 1: Init and copy tracked files only**

```bash
mkdir -p ~/Development/remote_8008 && cd ~/Development/remote_8008 && git init
cd ~/Development/intel-8008-vhdl
SRC_HASH=$(git rev-parse --short HEAD)
git ls-files projects/b8008_net | while read f; do
  rel="${f#projects/b8008_net/}"
  mkdir -p ~/Development/remote_8008/"$(dirname "$rel")"
  cp "$f" ~/Development/remote_8008/"$rel"
done
echo "$SRC_HASH"   # note it — used in the commit message and README
```

- [ ] **Step 2: Restructure — top-level Python into `soc/`, monitor ROM into `src/`**

```bash
cd ~/Development/remote_8008
mkdir -p soc src docs/superpowers/plans
mv versa_soc.py b8008_integration.py bench_core.py host_selftest.py test_integration.py soc/
cp ~/Development/intel-8008-vhdl/projects/b8008_monitor/src/rom_4kx8_bram.vhdl src/
cp ~/Development/intel-8008-vhdl/docs/superpowers/plans/2026-07-09-litex-ethernet-monitor.md docs/superpowers/plans/
```

- [ ] **Step 3: `.gitignore`** — vendored LiteX trees and build products. (Intentionally overwrites the `.gitignore` the `git ls-files` loop copied from the source tree — this list supersedes it:)

```gitignore
.venv/
build/
obj_dir/
__pycache__/
*.egg-info/
litex_setup.py
# litex_setup.py-vendored clones (re-created by `make litex-env`)
litex/
litex-boards/
migen/
liteeth/
litedram/
litei2c/
liteiclink/
litejesd204b/
litepcie/
litesata/
litescope/
litesdcard/
litespi/
pythondata-*/
*.log
```

- [ ] **Step 4: Grep for every path assumption the restructure broke** (fix targets live in Tasks 2-3; this step is the inventory)

```bash
cd ~/Development/remote_8008
grep -rn '\.\./\.\.\|b8008_monitor\|bench_core\.py\|b8008_integration\|versa_soc' Makefile soc/ sim/ host/ firmware/ --include='*' | grep -v Binary
```

Expected hits (at minimum): `Makefile` (`ROOT_DIR := ../..`, `MON_DIR`, `$(PY) bench_core.py`, versa target, netlist rule), `soc/b8008_integration.py:35` (`_GHDL_GATES` `../..` path), possibly `soc/versa_soc.py` imports. Record the full list in the task notes.

- [ ] **Step 5: Import commit**

```bash
git add -A
git commit -m "import: b8008_net from intel-8008-vhdl @ <SRC_HASH>

Tracked files only; vendored LiteX trees and build products excluded
(re-created by make litex-env). Layout: top-level python -> soc/,
rom_4kx8_bram.vhdl copied from projects/b8008_monitor/src/."
```

---

### Task 2: README — provenance + condensed work history

**Files:**
- Create: `~/Development/remote_8008/README.md`

- [ ] **Step 1: Write README.md** covering, in order:
  1. **What this is** — LiteX SoC on ECP5-5G Versa wrapping the silicon-validated b8008 core (`greygiant:retro:b8008`, v3.0) with an Etherbone-based network monitor: remote program load, console bridge, run/stop control.
  2. **Provenance** — "Extracted 2026-07-10 from `intel-8008-vhdl` `projects/b8008_net/` @ `<SRC_HASH>` as a fresh repo (history not carried). Development history lives in the source repo's log for that path."
  3. **Condensed work log** — the b8008_net milestones (read them from the migrated plan doc's task list + the source repo's `git log --oneline -- projects/b8008_net` and summarize): stock Versa sanity build, `b8008_net_core` wrapper + GHDL netlist flow, three sim tiers (`sim-core` GHDL boot, `sim-netlist` Verilator gate-level, `sim-bench` Verilator C++ CSR/wishbone bench), Etherbone monitor design (buffer_depth=255; UDP reads are one CSR word per round-trip by design), host package `b8008net` with discovery/console/CLI + pytest suite. Status: pre-hardware — Verilator bench is the gate; hardware bring-up is the plan's final tasks.
  4. **Architecture** — soc/ (LiteX SoC + B8008Core integration), src/ (VHDL wrapper + ROM model), sim/ (three tiers), firmware/ (8008 monitor firmware), host/ (Python client).
  5. **Setup** — `pipx install fusesoc` (pin version from `intel-8008-vhdl/docs/fusesoc.md`), oss-cad-suite, `CORE_DIR` env/make variable pointing at the core repo checkout, `make litex-env` (LiteX pinned `2026.04`).
  6. **Build/test commands** — `make sim-core` / `sim-netlist` / `sim-bench` / `versa` / `pytest host/tests`.
  7. **Plan pointer** — `docs/superpowers/plans/2026-07-09-litex-ethernet-monitor.md` continues here.

- [ ] **Step 2: Commit**

```bash
git add README.md && git commit -m "docs: README with provenance and condensed work history"
```

---

### Task 3: FuseSoC consumption — `remote_8008.core` + Makefile rewire

**Files:**
- Create: `remote_8008.core`
- Modify: `Makefile` (CORE_DIR, SRC_DIR/COMP_DIR/MON_DIR, netlist rule, soc/ paths)
- Modify: `soc/b8008_integration.py:35` (`_GHDL_GATES`)

**Interfaces:**
- Consumes: `greygiant:retro:b8008` core + `ghdl_synth_verilog` generator (Plan A); incantation from `intel-8008-vhdl/docs/fusesoc.md`.
- Produces: `make convert` → `build/b8008_net_core.v` + `build/ghdl_gates.v` (paths sim-netlist/sim-bench/`b8008_integration.py` rely on).

- [ ] **Step 1: Write `remote_8008.core`**

```yaml
CAPI=2:
name: greygiant:retro:remote-8008:0.1
description: LiteX Etherbone monitor SoC around the b8008 core (netlist consumer).
filesets:
  wrapper:
    files:
      - src/rom_4kx8_bram.vhdl
      - src/b8008_net_core.vhdl
    file_type: vhdlSource-2008
generate:
  b8008_net_netlist:
    generator: ghdl_synth_verilog
    parameters:
      top: b8008_net_core
      output: b8008_net_core.v
      extra_files:
        - src/rom_4kx8_bram.vhdl
        - src/b8008_net_core.vhdl
targets:
  default:
    filesets: [wrapper]
    generate: [b8008_net_netlist]
    toplevel: b8008_net_core
```

- [ ] **Step 2: Rewire the Makefile.** Replace the path block and netlist rule:

```make
# Core repo location — the single knob (see README).
CORE_DIR ?= $(HOME)/Development/intel-8008-vhdl

SRC_DIR  := $(CORE_DIR)/src/b8008
COMP_DIR := $(CORE_DIR)/src/components
MON_DIR  := src           # rom_4kx8_bram.vhdl copied in at extraction
```

(`B8008_SRCS` list itself is unchanged — it already uses `$(SRC_DIR)`/`$(COMP_DIR)`. `CORE_SRCS` keeps its five entries; `$(MON_DIR)/rom_4kx8_bram.vhdl` and `src/b8008_net_core.vhdl` now both resolve locally.)

Netlist rule — replace the local `ghdl -a` + `ghdl --synth` recipe with the generator, using the exact incantation `docs/fusesoc.md` proved (template below; adjust flags/copy-out per that doc):

```make
GHDL_GATES  := build/ghdl_gates.v
NETLIST_TOP := b8008_net_core
NETLIST_V   := build/b8008_net_core.v
FUSESOC     ?= fusesoc

# Prereqs keep the OLD rule's core-VHDL sensitivity: a core repo edit must
# regenerate the netlist (core and consumer co-evolve during this phase).
$(NETLIST_V): remote_8008.core $(B8008_SRCS) $(CORE_SRCS)
	@mkdir -p build
	rm -rf build/fusesoc
	$(FUSESOC) --cores-root $(CORE_DIR) --cores-root . \
	    run --setup --build-root build/fusesoc greygiant:retro:remote-8008
	cp "$$(find build/fusesoc -name b8008_net_core.v | head -1)" $(NETLIST_V)
	cp "$$(find build/fusesoc -name ghdl_gates.v | head -1)" $(GHDL_GATES)
	@head -3 $(NETLIST_V)
```

(The `rm -rf build/fusesoc` is required, not hygiene: `--cores-root .` scans the repo recursively, so a previous run's generated `.core` inside `build/fusesoc/` would be rediscovered on the next run — duplicate-VLNV confusion, and the `find | head -1` may grab the stale file.)

Also update every `soc/` reference found in Task 1 Step 4's inventory: `$(PY) bench_core.py` → `$(PY) soc/bench_core.py` (check the run-from-build comment — `bench_core.py` writes into `build/`; keep the cwd behavior identical, adjusting the path it's invoked with, not the cwd), versa target's `versa_soc.py` path likewise.

- [ ] **Step 3: Fix `soc/b8008_integration.py:35`**

```python
_GHDL_GATES = os.path.abspath(os.path.join(_HERE, "..", "build", "ghdl_gates.v"))
```

(`_HERE` is now `soc/`; the gates file is the generator's copy in `build/`. The `core_v="build/b8008_net_core.v"` default already matches the new rule's output.)

- [ ] **Step 4: Run the new netlist rule**

```bash
cd ~/Development/remote_8008 && make convert
head -3 build/b8008_net_core.v
```

Expected: provenance header (`Source: … intel-8008-vhdl @ <hash>, entity b8008_net_core`), file present, `build/ghdl_gates.v` present.

- [ ] **Step 5: Commit**

```bash
git add remote_8008.core Makefile soc/b8008_integration.py
git commit -m "feat: consume b8008 via FuseSoC generator; CORE_DIR-rooted paths"
```

---

### Task 4: Three sim tiers green

**Files:**
- Modify (only if Task 1 Step 4 inventory found stale paths): `Makefile`, `sim/netlist_tb.v` (hardcodes a ROM path relative to repo root — verify it survived the move), `sim/bench_tb.cpp`

- [ ] **Step 1: sim-core**

```bash
make sim-core 2>&1 | tail -5
```

Expected: GHDL analyze of `$(B8008_SRCS) $(CORE_SRCS) $(CORE_TB)` (raw VHDL from `$(CORE_DIR)` + local `src/`), run completes, monitor UART banner assertion passes, exit 0. If analysis fails on a missing file, the `CORE_DIR` rewire missed a path — fix in the Makefile, not by copying files.

- [ ] **Step 2: sim-netlist**

```bash
make sim-netlist 2>&1 | tail -5
```

Expected: Verilator builds `$(NETLIST_V) $(GHDL_GATES) sim/models.v sim/netlist_tb.v`, boot banner decoded, exit 0.

- [ ] **Step 3: sim-bench**

```bash
make sim-bench 2>&1 | tail -5
```

Expected: `soc/bench_core.py` emits `build/bench_core.v`, Verilator C++ bench passes (wishbone RAM window, console FIFOs, CDC, stop→restart), exit 0. This needs the LiteX venv — if `$(PY)` is missing run Task 5 Step 1 first, then return here.

- [ ] **Step 4: Commit any path fixes**

```bash
git add -A && git commit -m "fix: path corrections for extracted layout (sim tiers green)"
```

---

### Task 5: LiteX build chain green

- [ ] **Step 1: LiteX env (pinned)**

```bash
make litex-env 2>&1 | tail -2
```

Expected: `litex OK` (tag 2026.04 per Makefile).

- [ ] **Step 2: Stock sanity**

```bash
make stock-sanity 2>&1 | tail -2
```

Expected: `stock sanity OK`.

- [ ] **Step 3: Versa SoC bitstream + firmware.** The bitstream target is `make build` (net Makefile:263, `build: convert firmware` — it runs `versa_soc.py` by path, so verify the Task 3 rewire changed that invocation to `soc/versa_soc.py`):

```bash
make build 2>&1 | tail -5
ls build/versa/gateware/versa_soc.bit
test -f firmware/build/firmware.bin && echo firmware OK
```

Expected: bitstream file exists; `firmware OK` (the `firmware` target at Makefile:240 ran as a `build` prerequisite).

- [ ] **Step 4: Host test suite**

```bash
.venv/bin/python -m pytest host/tests -q 2>&1 | tail -3
```

Expected: all pass.

- [ ] **Step 5: Commit anything the build chain needed**

```bash
git add -A && git commit -m "build: LiteX chain green in extracted repo"
```

---

### Task 6: Plan-doc path migration + core-repo cleanup

**Files:**
- Modify: `~/Development/remote_8008/docs/superpowers/plans/2026-07-09-litex-ethernet-monitor.md` (paths only)
- Delete (core repo): `projects/b8008_net/`
- Create (core repo): `projects/b8008_net/README.md` → replaced by stub `projects/README-b8008_net-moved.md`
- Modify (core repo): `docs/superpowers/plans/2026-07-09-litex-ethernet-monitor.md` → delete (moved)

- [ ] **Step 1: Path-only edits to the migrated plan doc.** `grep -n 'projects/b8008_net\|\.\./\.\.' docs/superpowers/plans/2026-07-09-litex-ethernet-monitor.md` and rewrite each hit for the new layout (`projects/b8008_net/x` → `x`, top-level python → `soc/`). **No content edits** — the doc already incorporates both review rounds.

```bash
git add docs/ && git commit -m "docs: migrate Etherbone plan, paths updated for new layout"
```

- [ ] **Step 2: VERIFICATION GATE before any deletion** — all of the following, fresh:

```bash
cd ~/Development/remote_8008
make convert && make sim-core && make sim-netlist && make sim-bench
.venv/bin/python -m pytest host/tests -q
make build 2>&1 | tail -3
ls build/versa/gateware/versa_soc.bit
```

All green or STOP.

- [ ] **Step 3: USER CONFIRMATION — destructive.** Present the gate results and ask the user to confirm deleting `projects/b8008_net/` (911MB, includes their vendored LiteX clones) from `intel-8008-vhdl`. Do not proceed without an explicit yes.

- [ ] **Step 4: Delete and stub (after confirmation)**

```bash
cd ~/Development/intel-8008-vhdl
git rm -r --cached projects/b8008_net 2>/dev/null; git rm -r projects/b8008_net
rm -rf projects/b8008_net    # clears untracked vendored clones the git rm left
git rm docs/superpowers/plans/2026-07-09-litex-ethernet-monitor.md
cat > projects/README-b8008_net-moved.md <<'EOF'
# b8008_net has moved

Extracted 2026-07-10 to its own repository: `~/Development/remote_8008`
(LiteX Etherbone monitor SoC). It consumes this repo's b8008 core via
FuseSoC (`greygiant:retro:b8008`). The Etherbone plan doc moved with it.
EOF
git add projects/README-b8008_net-moved.md
git commit -m "refactor: b8008_net extracted to remote_8008 repo"
```

Also remove any `b8008_net` mentions from the root Makefile help text (`grep -n b8008_net Makefile`).

---

## Verification (spec §4, remote_8008)

- [ ] `sim-core`, `sim-netlist`, `sim-bench` green (Task 4, re-proven Task 6 Step 2).
- [ ] Versa bitstream builds; firmware builds; pytest green (Task 5).
- [ ] Core repo still green after deletion: `cd ~/Development/intel-8008-vhdl && make test-b8008-top`.
