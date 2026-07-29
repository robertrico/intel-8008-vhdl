# FuseSoC Adoption + remote_8008 Extraction — Design

**Date:** 2026-07-10
**Status:** Approved pending user spec review
**Scope:** Three repos — `intel-8008-vhdl` (core), `remote_8008` (new), `project_byte_hamr`

## Goals

1. Package the b8008 core as a FuseSoC core so other HDL projects can depend on it.
2. Extract the LiteX project (`projects/b8008_net/`) into its own repository, `remote_8008` — it is misplaced inside the core repo.
3. Let Byte Hamr's `b8008_hamr` design consume the core via FuseSoC without turning the rest of Byte Hamr into a FuseSoC project.
4. Keep all existing Makefile workflows functional throughout.

## Non-goals (this phase)

- Full FuseSoC/edalize build flows in the core repo (sim targets, synth/pnr/bit). That is the explicit **next** phase — see Migration Ladder.
- Any FuseSoC adoption in Byte Hamr beyond the single `b8008_hamr` design.
- Restructuring Byte Hamr's tooling toward a standard layout (acknowledged as valuable; future, separate effort).
- `.core` files for `s8008` / `v8008` (deprecated attempts; untouched).
- Migrating software/assembler targets (ASL, Merlin32, ProDOS disks, ESP32) into FuseSoC. Never — those stay in make.

## Decisions (settled during brainstorming)

| Decision | Choice |
|---|---|
| FuseSoC depth in core repo | Packaging + netlist generator now; full edalize flows after this phase proves out (clean #1→#2 upgrade path) |
| Cores packaged | `b8008` only — rtl fileset (incl. `phase_clocks`), `debug-io` fileset (`debug_clock_control`, `usart`, `b8008_usart`), `synth-helpers` (`ghdl_gates.v`) |
| Byte Hamr ingestion | FuseSoC dependency, scoped to the `b8008_hamr` design only |
| remote_8008 history | Fresh repo, single import commit; README carries provenance + condensed work history |
| VLNV | `greygiant:retro:b8008` — version tracks VERSIONS.md (currently `3.0`) |
| Hosting | Local-only git first; GitHub later |
| LiteX role | Quarantined in remote_8008; composes with FuseSoC (LiteX builds the SoC, FuseSoC supplies the core). No LiteX elsewhere |

## Prerequisites

- `fusesoc` is not installed on the dev machine. Install via `pipx install fusesoc` (2.x); pin the version in each repo's README/docs.
- LiteX pinned to a release tag in remote_8008 (`litex_setup.py --tag`), not master.
- oss-cad-suite remains the toolchain everywhere. FuseSoC orchestrates; it does not replace tools.

## Section 1 — Core repo (`intel-8008-vhdl`)

### `b8008.core` (CAPI2, repo root)

- VLNV `greygiant:retro:b8008:3.0`.
- `rtl` fileset: the **27 ordered VHDL files from `projects/project.mk` `B8008_SRCS`** —
  this list includes `ram_sync.vhdl`, `address_decoder.vhdl`, and `b8008_top.vhdl` and is
  the list that produced Byte Hamr's vendored netlist. (The root Makefile's 24-file
  `B8008_SRCS` stops at `b8008.vhdl` and its synth rule elaborates entity `b8008`, not
  `b8008_top` — building `b8008_top` from that list fails elaboration. Do not use it.)
  FuseSoC preserves fileset order, so GHDL analysis order survives.
- `debug-io` fileset: `src/b8008/debug_clock_control.vhdl`, `src/components/usart.vhdl`,
  `src/components/b8008_usart.vhdl` — core-adjacent peripherals not in any `B8008_SRCS`
  list, but required by remote_8008's `b8008_net_core` wrapper (net Makefile
  `CORE_SRCS`). Without packaging these, the wrapper's `../..` paths die at extraction
  and Plan B is blocked.
- `synth-helpers` fileset: `src/synth/ghdl_gates.v` — required by consumers of the GHDL-synthesized netlist (implements the multiplexed-DFF primitives GHDL emits).
- Tool options recorded in the core file: GHDL `--std=08`.

### `ghdl-synth-verilog` generator

A FuseSoC generator shipped by the core repo, wrapping the existing
`ghdl --synth --std=08 --out=verilog` flow (the same command that produced Byte Hamr's
vendored `b8008_core.v`).

- **Parameters:** top entity (default `b8008_top`), generics (`CLK_FREQ_HZ`, memory-map
  personality), output file name, and **`extra_files`** — additional VHDL sources
  analyzed after the core fileset. `extra_files` is what lets remote_8008 synthesize its
  project-local wrapper entity (`b8008_net_core`) through the same generator (see §2).
- **Output:** Verilog netlist with a provenance header — source repo, commit hash,
  generics used — matching the header convention of the current vendored file.
  The commit hash must be resolved from the **library checkout path** (the registered
  fusesoc library location), not the generator's working directory: FuseSoC runs
  generators against files exported into its build tree, where `git rev-parse` fails.
  A dirty working tree stamps `-dirty` on the hash.
- This is the mechanism by which Verilog-only consumers (Byte Hamr) get the core without
  any VHDL toolchain knowledge in their own build.

### Makefile

- Root Makefile untouched functionally. Help text updated; convenience target
  **`make netlist-top`** wraps the generator for local use. Named distinctly because
  the existing synth flow already produces `build/synth/b8008.v` (entity `b8008`, no
  top-level memories); the new target emits a `b8008_top` netlist — different artifact,
  must not collide.
- `projects/b8008_net/` references removed from help/docs once extraction completes.

## Section 2 — `remote_8008` (new repo)

### Creation

- `git init` at `~/Development/remote_8008`.
- **Copy tracked project files only.** `projects/b8008_net/` is 911MB and contains
  15+ nested git clones vendored by `litex_setup.py` (litex, migen, liteeth, litedram,
  litex-boards, pythondata-*, …) plus `build/`, `obj_dir/`, `__pycache__/`, egg-info.
  A naive copy nests git repos inside the import commit. Use
  `git ls-files projects/b8008_net` in the source repo to enumerate what to copy.
- Single import commit recording the source commit hash of `intel-8008-vhdl`.
- LiteX environment is **re-created in the new repo** by running `litex_setup.py` there,
  pinned to a LiteX release tag (`litex_setup.py --tag`) — prior review already caught
  LiteX-master API drift (`wr_stb`/`rd_stb` rename); pin, don't track master. Vendored
  trees go in `.gitignore`.
- Layout: `soc/` (`versa_soc.py`, `b8008_integration.py`, `bench_core.py`), **`src/`
  (`b8008_net_core.vhdl` — the load-bearing VHDL wrapper — plus `rom_4kx8_bram.vhdl`
  copied from `projects/b8008_monitor/src/`, see Core consumption)**,
  **`sim/` (core tb, netlist tb, `bench_tb.cpp`, `models.v` — the pre-hardware
  verilator bench)**, `firmware/`, `host/` (the `b8008net` Python package + tests),
  `docs/`, `Makefile`.

### README (replaces git history — must be robust)

- Provenance: source repo, source commit hash, extraction date.
- Condensed work log: what was built, silicon-validation status, key design decisions
  from the b8008_net development history.
- Architecture overview: SoC structure, Etherbone monitor, host tooling.
- Setup: fusesoc install, `fusesoc library add` for the core repo, oss-cad-suite, LiteX.
- Link to the migrated Etherbone plan.

### Core consumption

- **The proven netlist flow is preserved** — LiteX does not consume raw core VHDL.
  Today (`b8008_integration.py:44,142`, `Makefile:124`): a project-local VHDL wrapper
  (`src/b8008_net_core.vhdl`, entity `b8008_net_core`) is GHDL-synthesized together
  with the core sources into `build/b8008_net_core.v`, and LiteX does
  `platform.add_source()` on that netlist plus `ghdl_gates.v`, instantiating
  `b8008_net_core`. Feeding raw VHDL to `add_source()` would push LiteX/yosys onto the
  untested ghdl-plugin path — explicitly not this phase.
- What changes: the local `ghdl --synth` recipe is replaced by an invocation of the
  core's `ghdl-synth-verilog` generator with `top=b8008_net_core` and
  `extra_files=[src/rom_4kx8_bram.vhdl, src/b8008_net_core.vhdl]` (mirrors the proven
  `CORE_SRCS` analyze order; no dependency between the two, and the executor may drop
  `rom_4kx8_bram` from `extra_files` since netlist elaboration never touches it — it
  must stay in `src/` for sim regardless). Output still lands at
  `build/b8008_net_core.v`; `b8008_integration.py` is unchanged in mechanism.
- **`sim-core` keeps the VHDL list.** The GHDL-level testbench (net Makefile
  `sim-core`) compiles `$(B8008_SRCS) $(CORE_SRCS) $(CORE_TB)` as raw VHDL — a
  netlist cannot substitute. The `B8008_SRCS` list therefore survives in remote_8008's
  Makefile, re-rooted via `CORE_DIR ?= $(HOME)/Development/intel-8008-vhdl` (same
  pattern as Byte Hamr's `INTEL8008_DIR`). This adds a fourth ordered source list —
  recorded in the three-list-drift risk. EDAM-parsing the list out of `fusesoc run
  --setup` output would kill the duplication but drags YAML-parsing machinery into
  the Makefile; deferred to the Migration Ladder.
- The wrapper's remaining `CORE_SRCS` dependencies resolve as follows:
  `debug_clock_control` / `usart` / `b8008_usart` come from the core's `debug-io`
  fileset (see §1); **`rom_4kx8_bram.vhdl` is copied from
  `projects/b8008_monitor/src/` into remote_8008's `src/`** — it is a
  monitor-project-specific ROM wrapper (analyzed but not instantiated by
  `b8008_net_core`, which exposes an external ROM bus) and does not belong in the
  packaged core.
- `ghdl_gates.v` resolved from the core's `synth-helpers` fileset instead of the
  `../../src/synth` path.

### In-flight work migrates

- `docs/superpowers/plans/2026-07-09-litex-ethernet-monitor.md` moves into
  `remote_8008/docs/superpowers/plans/`. The plan doc **already incorporates both
  review rounds** (buffer_depth=255, UDP per-word round-trip reality, sys_clk_freq
  test fix, run-is-restart semantics, Verilator-bench-not-TAP decision) — migration
  updates paths only; no content edits.

### Cleanup in core repo

- `projects/b8008_net/` deleted from `intel-8008-vhdl` only after remote_8008 builds a
  Versa bitstream and its test suites pass. A stub README pointer is left in
  `projects/`.

## Section 3 — Byte Hamr (`project_byte_hamr`)

Scoped strictly to the `b8008_hamr` design. The rest of Byte Hamr builds without
FuseSoC installed.

- New `b8008_hamr.core` with `depend: greygiant:retro:b8008`, invoking the
  `ghdl-synth-verilog` generator with `CLK_FREQ_HZ=25000000` and the default memory-map
  personality (ROM 4KB @ 0x0000, RAM 12KB @ 0x1000, monitor map) — the same
  configuration as the current vendored netlist.
- **Core discovery:** fusesoc locates the core repo via `INTEL8008_DIR ?=
  $(HOME)/Development/intel-8008-vhdl` passed as `--cores-root` (or a one-time
  `fusesoc library add` documented in the README). Same variable as the path cleanup
  below — one knob.
- Vendored `gateware/rev2/b8008_hamr/b8008_core.v` (24k lines) is deleted; the netlist
  becomes a build artifact under `build/`. The Makefile `$(JSON)` rule for
  `DESIGN=b8008_hamr` gains a fusesoc step that materializes the netlist before yosys
  runs — and **copies it (plus `ghdl_gates.v`) out of fusesoc's build tree** into
  `build/`, because generator output lands inside fusesoc's cache/build directory.
- **Wildcard fix — two rules, not one:** `VERILOG_SRC := $(filter-out
  %_tb.v,$(wildcard $(DESIGN_DIR)/*.v))` (Makefile:126) cannot see files in `build/`.
  With the vendored netlist and `ghdl_gates.v` deleted from the design dir, both the
  `$(JSON)` synthesis rule **and the `$(UNIT_OUT)` unit-test rule (Makefile:404-406,
  what runs `b8008_hamr_tb` via `make unit`)** compile `$(VERILOG_SRC)` and must gain
  the generated netlist and `ghdl_gates.v` paths explicitly (per-DESIGN conditional,
  same pattern as the existing `ifeq ($(DESIGN),b8008_hamr)` blocks). Miss the unit
  rule and §4's `b8008_hamr_tb` verification criterion is unrunnable.
- Local `gateware/rev2/b8008_hamr/ghdl_gates.v` copy deleted; supplied by the core's
  `synth-helpers` fileset.
- Hardcoded `$(HOME)/Development/intel-8008-vhdl` paths (mac8008 regeneration,
  `validate_mac8008.sh` sample programs) become `INTEL8008_DIR ?=` with the current
  value as default. These reference `isa.json` and assembly samples — developer-machine
  conveniences, not RTL — so they stay make-only, outside FuseSoC.

## Section 4 — Verification

Netlist regeneration will not be byte-identical to the old vendored file (GHDL version
drift), so verification is behavioral per repo:

- **Core repo:** existing testbench suite green (`make test-*`); `make netlist-top`
  produces a netlist that yosys parses cleanly.
- **Byte Hamr:** `b8008_hamr_tb` passes against the regenerated netlist;
  `make DESIGN=b8008_hamr bit` completes; **hardware smoke test on the Apple II card**
  (monitor comes up over the slot ROM terminal); other designs (e.g. `signal_check`)
  still build with fusesoc absent from PATH.
- **remote_8008:** `sim-core`, `sim-netlist`, and `sim-bench` all green (the
  pre-hardware verification tiers); Versa SoC bitstream builds; `pytest` host test
  suite green; firmware builds.

## Sequencing — three implementation plans

1. **Plan A — core repo:** fusesoc install, `b8008.core`, generator, `make netlist-top`,
   docs. Self-contained; proves the tooling.
2. **Plan B — remote_8008:** extraction, README, FuseSoC consumption, plan-doc
   migration, core-repo cleanup. Depends on A. Gets full LiteX + SoC treatment this
   phase since it is not yet hardware-tested.
3. **Plan C — Byte Hamr:** `b8008_hamr.core`, netlist-as-artifact, path variables.
   Depends on A; independent of B.

B and C can proceed in parallel after A.

## Migration Ladder (post-phase, recorded for direction)

Full FuseSoC in the core repo comes **after** this phase proves out. `.core` files are
identical either way; later steps only add `targets:` sections and swap Makefile guts
for `fusesoc run`. Each rung is independent and reversible; make wrappers remain during
transition.

1. Sim testbenches → fusesoc targets (edalize GHDL backend; cheap, high confidence).
2. Per-project synth/pnr/bit flows → edalize generic flow (yosys + nextpnr-ecp5 +
   ecppack), one project at a time, validating flag parity (abc9, seed, LPF, IDCODE).
3. ROM/assembler pipeline → FuseSoC generators, only if the make version becomes a
   maintenance burden.
4. `prog`/`prog-flash` and all software targets: never migrate; make forever.

Byte Hamr standard-layout reorganization is acknowledged as worthwhile and deferred to
its own future effort.

## Risks

- **Edalize/GHDL flag parity** (future rungs): current flows have tuned flags; parity
  must be validated per project when climbing the ladder. Not a this-phase risk.
- **Generator correctness:** regenerated netlist must be behaviorally equivalent to the
  vendored one. Mitigated by `b8008_hamr_tb` and hardware smoke test.
- **remote_8008 is untested on hardware:** extraction happens before hardware
  validation of the Etherbone monitor; the migrated plan continues in the new repo, so
  path churn lands before, not after, hardware bring-up. Intentional.
- **Reproducibility regression:** the vendored `b8008_core.v` was pinned (`@ 2ff4659`
  in its header); the regenerated artifact reflects whatever state the core checkout is
  in, including uncommitted edits. Mitigations: provenance header with `-dirty`
  stamping, and version discipline — consumers should build against a clean checkout at
  a VERSIONS.md-tagged commit.
- **Source-list drift:** after this phase, four ordered source lists coexist — root
  Makefile (24 files, entity `b8008`), `projects/project.mk` (27 files), the
  `b8008.core` fileset, and remote_8008's `CORE_DIR`-rooted `B8008_SRCS` (kept for
  `sim-core`, which needs raw VHDL). Drift risk persists until Migration Ladder rung 2
  makes `b8008.core` the single source of truth.
