# Plan A: FuseSoC Core Packaging (intel-8008-vhdl)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the b8008 core as FuseSoC core `greygiant:retro:b8008:3.0` with a `ghdl-synth-verilog` generator, so remote_8008 (Plan B) and Byte Hamr (Plan C) can consume it.

**Architecture:** A CAPI2 `b8008.core` at repo root declares three filesets (rtl, debug_io, synth_helpers). A Python generator script wraps the existing `ghdl --synth --out=verilog` flow, reading its source list from `b8008.core` itself (no new duplicated list). A smoke-consumer core inside the repo proves the full FuseSoC generator protocol end-to-end before Plans B/C rely on it.

**Tech Stack:** FuseSoC 2.x (pipx), GHDL from oss-cad-suite, Python 3 + PyYAML.

**Spec:** `docs/superpowers/specs/2026-07-10-fusesoc-refactor-design.md`

## Global Constraints

- VLNV: `greygiant:retro:b8008:3.0` (version tracks VERSIONS.md).
- GHDL flags: `--std=08 --work=work`. GHDL binary: `$(GHDL)` env or `~/oss-cad-suite/bin/ghdl`.
- Existing Makefile flows must keep working untouched — this plan only adds files and one new make target.
- rtl fileset = the 27 ordered files from `projects/project.mk` `B8008_SRCS` (NOT the root Makefile's 24-file list — that one cannot elaborate `b8008_top`).
- debug_io fileset order: `debug_clock_control.vhdl`, `usart.vhdl`, `b8008_usart.vhdl` (usart before b8008_usart — dependency).
- Generator output header must carry: source path, commit hash (with `-dirty` suffix when the working tree is dirty), top entity, generics.
- Repo CLAUDE.md forbids running GHDL by hand *for development*; the generator script is sanctioned build tooling (it IS the make-target machinery).
- New make target is `netlist-top` — must NOT collide with existing `build/synth/b8008.v` flow (entity `b8008`).

---

### Task 1: Install FuseSoC + generator-protocol spike

The FuseSoC generator protocol has two facts we must observe, not assume:
(a) what `files_root` points at when a consumer core invokes another core's generator,
(b) the exact `fusesoc run` incantation that triggers generation and where outputs land.
Everything in Plans B/C depends on these. Spike files are throwaway (scratch dir); the *finding* is recorded in `docs/fusesoc.md` in Task 4.

**Files:**
- Create (scratch, not committed): `/private/tmp/fusesoc-spike/` contents

**Interfaces:**
- Produces: pinned fusesoc version; observed `files_root` semantics and working `fusesoc run` incantation (consumed by Task 4's docs and by Plans B/C).

- [ ] **Step 1: Install and pin fusesoc**

```bash
pipx install fusesoc
fusesoc --version
```

Expected: version 2.x prints (e.g. `2.4.3`). Record the exact number for Task 4.

- [ ] **Step 2: Check PyYAML availability for the system python3 (generator runs under `interpreter: python3`)**

```bash
python3 -c "import yaml; print(yaml.__version__)" || python3 -m pip install --user pyyaml
```

- [ ] **Step 3: Build the spike — a generator that dumps its input, and a consumer that calls it**

```bash
mkdir -p /private/tmp/fusesoc-spike/genrepo /private/tmp/fusesoc-spike/userrepo
```

`/private/tmp/fusesoc-spike/genrepo/spikegen.core`:
```yaml
CAPI=2:
name: spike:lib:spikegen:0.1
filesets: {}
generators:
  dumpgen:
    interpreter: python3
    command: dumpgen.py
    description: dump the gapi input for inspection
```

`/private/tmp/fusesoc-spike/genrepo/dumpgen.py`:
```python
import sys, os, yaml
with open(sys.argv[1]) as f:
    gapi = yaml.safe_load(f)
with open("dump.txt", "w") as f:
    f.write(f"cwd={os.getcwd()}\n")
    f.write(f"script={os.path.abspath(__file__)}\n")
    f.write(yaml.safe_dump(gapi))
name = gapi["vlnv"].split(":")[2]
with open(f"{name}.core", "w") as f:
    f.write("CAPI=2:\n" + yaml.safe_dump({
        "name": gapi["vlnv"],
        "filesets": {"out": {"files": ["dump.txt"],
                             "file_type": "user"}},
        "targets": {"default": {"filesets": ["out"]}}}))
```

`/private/tmp/fusesoc-spike/userrepo/spikeuser.core`:
```yaml
CAPI=2:
name: spike:lib:spikeuser:0.1
filesets:
  empty:
    files: []
generate:
  mydump:
    generator: dumpgen
    parameters:
      hello: world
targets:
  default:
    filesets: [empty]
    generate: [mydump]
```

- [ ] **Step 4: Run it and observe**

```bash
cd /private/tmp/fusesoc-spike
fusesoc --cores-root genrepo --cores-root userrepo run --setup --tool icarus spike:lib:spikeuser
find . -name dump.txt -exec cat {} \;
```

If `--tool icarus` errors, try `--target default` alone, then `fusesoc run --setup --flag ...` variants until generation fires. Record what worked.

Expected observations to write down:
- `script=` path — does the generator run from the genrepo checkout (script can resolve its own repo) or from an exported copy? (Determines whether `Path(__file__).parents[n]` is safe in Task 3.)
- `files_root` in the dump — consumer core dir or generator core dir?
- Where `dump.txt` landed (`find` output) — the copy-out path pattern for Plans B/C.
- **Caching:** run the same `fusesoc run --setup` a second time — does the generator
  re-execute (fresh `dump.txt` mtime) or serve a cached copy (CAPI2 `cache_type`
  default)? This decides whether Plan B/C netlist rules actually regenerate when the
  core repo changes, or need a cache-busting step.
- **Re-run with residue:** run a third time WITHOUT clearing the build root — does the
  previously generated `.core` inside it get rediscovered (duplicate-VLNV warning or
  error)? This feeds the `rm -rf <build-root>` mitigation Plans B/C carry.

- [ ] **Step 5: Clean up scratch**

```bash
rm -rf /private/tmp/fusesoc-spike
```

No commit for this task; findings go into `docs/fusesoc.md` (Task 4).

**CHECKPOINT:** If the generator runs from an *exported copy* rather than the library checkout, Task 3's `REPO = Path(__file__).resolve().parents[2]` strategy is invalid — stop and report; the fallback is resolving the repo root from an env var (`B8008_CORE_DIR`) set by consumers, and Task 3/4 code must be adjusted before proceeding.

---

### Task 2: `b8008.core`

**Files:**
- Create: `b8008.core` (repo root)

**Interfaces:**
- Produces: VLNV `greygiant:retro:b8008:3.0`; filesets `rtl`, `debug_io`, `synth_helpers` (names used by Task 3's generator and Plan B/C consumers).

- [ ] **Step 1: Write `b8008.core`**

```yaml
CAPI=2:
name: greygiant:retro:b8008:3.0
description: >
  b8008 - block-based VHDL implementation of the Intel 8008. Silicon-validated
  (ECP5-5G Versa). rtl fileset is the ordered 27-file list from
  projects/project.mk B8008_SRCS; order is load-bearing for GHDL analysis.

filesets:
  rtl:
    files:
      - src/b8008/b8008_types.vhdl
      - src/b8008/stack_pointer.vhdl
      - src/b8008/stack_memory.vhdl
      - src/b8008/stack_addr_mux.vhdl
      - src/b8008/instruction_register.vhdl
      - src/b8008/instruction_decoder.vhdl
      - src/b8008/condition_flags.vhdl
      - src/b8008/register_file.vhdl
      - src/b8008/scratchpad_decoder.vhdl
      - src/b8008/scratchpad_addr_mux.vhdl
      - src/b8008/sss_ddd_selector.vhdl
      - src/b8008/ahl_pointer.vhdl
      - src/b8008/temp_registers.vhdl
      - src/b8008/alu.vhdl
      - src/b8008/carry_lookahead.vhdl
      - src/b8008/io_buffer.vhdl
      - src/b8008/mem_mux_refresh.vhdl
      - src/components/phase_clocks.vhdl
      - src/b8008/state_timing_generator.vhdl
      - src/b8008/machine_cycle_control.vhdl
      - src/b8008/memory_io_control.vhdl
      - src/b8008/register_alu_control.vhdl
      - src/b8008/interrupt_ready_ff.vhdl
      - src/b8008/b8008.vhdl
      - src/b8008/ram_sync.vhdl
      - src/b8008/address_decoder.vhdl
      - src/b8008/b8008_top.vhdl
    file_type: vhdlSource-2008

  debug_io:
    files:
      - src/b8008/debug_clock_control.vhdl
      - src/components/usart.vhdl
      - src/components/b8008_usart.vhdl
    file_type: vhdlSource-2008

  synth_helpers:
    files:
      - src/synth/ghdl_gates.v
    file_type: verilogSource

targets:
  default:
    filesets: [rtl]
    toplevel: b8008_top
```

- [ ] **Step 2: Verify FuseSoC parses it**

```bash
cd ~/Development/intel-8008-vhdl
fusesoc --cores-root . list-cores
fusesoc --cores-root . core-info greygiant:retro:b8008
```

Expected: `greygiant:retro:b8008:3.0` listed; core-info shows the three filesets with 27/3/1 files, no parse errors.

- [ ] **Step 3: Verify the fileset actually elaborates `b8008_top` (guards against list typos)**

```bash
mkdir -p build/coretest
~/oss-cad-suite/bin/ghdl -a --std=08 --work=work --workdir=build/coretest \
  $(python3 -c "
import yaml
capi = yaml.safe_load(open('b8008.core').read().split('\n',1)[1])
print(' '.join(f for fs in ('rtl','debug_io') for f in capi['filesets'][fs]['files']))")
~/oss-cad-suite/bin/ghdl --synth --std=08 --work=work --workdir=build/coretest b8008_top > /dev/null && echo ELAB_OK
rm -rf build/coretest
```

Expected: `ELAB_OK`.

- [ ] **Step 4: Commit**

```bash
git add b8008.core
git commit -m "feat: add FuseSoC core file greygiant:retro:b8008:3.0"
```

---

### Task 3: Generator script `scripts/fusesoc/ghdl_synth_verilog.py`

**Files:**
- Create: `scripts/fusesoc/ghdl_synth_verilog.py`

**Interfaces:**
- Consumes: `b8008.core` filesets `rtl` + `debug_io` (Task 2); GHDL from `$GHDL` or oss-cad-suite.
- Produces: gapi-protocol generator. Parameters: `top` (str, default `b8008_top`), `output` (str, default `<top>.v`), `generics` (dict), `extra_files` (list of paths relative to `files_root`). Emits `<output>` + `ghdl_gates.v` + `<name>.core` in cwd.

- [ ] **Step 1: Write the script**

```python
#!/usr/bin/env python3
"""FuseSoC generator: GHDL --synth a b8008-based top to a Verilog netlist.

Input (argv[1]): gapi YAML — {gapi, files_root, vlnv, parameters:
{top, output, generics, extra_files}}. `make netlist-top` hand-writes the
same YAML and calls this directly, so the script has exactly one mode.

Core sources are read from b8008.core (rtl + debug_io filesets) so the
ordered list has no additional copy. extra_files resolve relative to
files_root (the consumer's core root) and are analyzed last.

Outputs (cwd): the netlist, a copy of ghdl_gates.v (primitives the netlist
needs downstream), and a CAPI2 .core describing both.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]  # scripts/fusesoc/ -> repo root
CORE_FILE = REPO / "b8008.core"
GHDL = os.environ.get("GHDL", str(Path.home() / "oss-cad-suite/bin/ghdl"))
GHDL_GATES = REPO / "src" / "synth" / "ghdl_gates.v"
GHDL_FLAGS = ["--std=08", "--work=work"]


def core_sources():
    capi = yaml.safe_load(CORE_FILE.read_text().split("\n", 1)[1])
    return [REPO / f
            for fs in ("rtl", "debug_io")
            for f in capi["filesets"][fs]["files"]]


def provenance():
    def git(*args):
        r = subprocess.run(["git", "-C", str(REPO), *args],
                           capture_output=True, text=True)
        return r.stdout.strip()
    h = git("rev-parse", "--short", "HEAD") or "unknown"
    if git("status", "--porcelain"):
        h += "-dirty"
    return h


def main():
    gapi = yaml.safe_load(Path(sys.argv[1]).read_text())
    p = gapi.get("parameters") or {}
    files_root = Path(gapi.get("files_root", "."))
    top = p.get("top", "b8008_top")
    out_name = p.get("output", f"{top}.v")
    generics = p.get("generics") or {}
    extra = [files_root / e for e in (p.get("extra_files") or [])]

    workdir = Path("ghdl-work")
    workdir.mkdir(exist_ok=True)
    flags = GHDL_FLAGS + [f"--workdir={workdir}"]
    srcs = [str(s) for s in core_sources() + extra]
    subprocess.run([GHDL, "-a", *flags, *srcs], check=True)
    synth = subprocess.run(
        [GHDL, "--synth", *flags, "--out=verilog",
         *[f"-g{k}={v}" for k, v in generics.items()], top],
        capture_output=True, text=True, check=True)

    personality = ("custom (see Generics)"
                   if any(k.startswith(("ROM_", "RAM_")) for k in generics)
                   else "defaults (ROM 4KB @ 0x0000, RAM 12KB @ 0x1000, monitor map)")
    header = ("// GENERATED FILE - do not edit.\n"
              f"// Source: {REPO} @ {provenance()}, entity {top}\n"
              f"// Generics: {generics if generics else 'defaults'}\n"
              f"// Personality: {personality}\n")
    Path(out_name).write_text(header + synth.stdout)
    shutil.copy(GHDL_GATES, "ghdl_gates.v")

    vlnv = gapi.get("vlnv", "::b8008-netlist:0")
    name = vlnv.split(":")[2] or "b8008-netlist"
    Path(f"{name}.core").write_text("CAPI=2:\n" + yaml.safe_dump({
        "name": vlnv,
        "filesets": {"netlist": {"files": [out_name, "ghdl_gates.v"],
                                 "file_type": "verilogSource"}},
        "targets": {"default": {"filesets": ["netlist"]}}}))
    print(f"wrote {out_name} "
          f"({len(synth.stdout.splitlines())} lines) @ {provenance()}")


if __name__ == "__main__":
    main()
```

(If Task 1's CHECKPOINT fired — generator runs from an exported copy — replace the `REPO = ...` line with `REPO = Path(os.environ["B8008_CORE_DIR"])` and note the env var in every consumer.)

- [ ] **Step 2: Test it directly (failing first — no input file)**

```bash
cd ~/Development/intel-8008-vhdl
python3 scripts/fusesoc/ghdl_synth_verilog.py 2>&1 | head -1
```

Expected: `IndexError`/usage failure — confirms the script needs its gapi input.

- [ ] **Step 3: Test the real flow with a hand-written gapi file**

```bash
mkdir -p build/gentest && cd build/gentest
cat > input.yml <<'EOF'
gapi: "1.0"
files_root: .
vlnv: "greygiant:retro:test-netlist:0"
parameters:
  top: b8008_top
  output: b8008_core.v
  generics:
    CLK_FREQ_HZ: 25000000
EOF
python3 ../../scripts/fusesoc/ghdl_synth_verilog.py input.yml
head -3 b8008_core.v
ls test-netlist.core ghdl_gates.v
```

Expected: `wrote b8008_core.v (…lines) @ <hash>`; header shows `entity b8008_top` and `{'CLK_FREQ_HZ': 25000000}`; both listed files exist.

- [ ] **Step 4: Verify yosys parses the output**

```bash
~/oss-cad-suite/bin/yosys -q -p "read_verilog b8008_core.v ghdl_gates.v; hierarchy -top b8008_top" && echo YOSYS_OK
cd ../.. && rm -rf build/gentest
```

Expected: `YOSYS_OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/fusesoc/ghdl_synth_verilog.py
git commit -m "feat: ghdl-synth-verilog FuseSoC generator"
```

---

### Task 4: Wire generator into b8008.core, smoke-consumer proof, `make netlist-top`, docs

**Files:**
- Modify: `b8008.core` (add `generators:` section)
- Create: `test/fusesoc_smoke/smoke.core`
- Modify: `Makefile` (add `netlist-top` target + help line)
- Create: `docs/fusesoc.md`

**Interfaces:**
- Consumes: Task 3 script; Task 1 incantation findings.
- Produces: generator name `ghdl_synth_verilog` (the exact name Plan B/C `generate:` sections reference); `docs/fusesoc.md` with the proven `fusesoc run` command + copy-out path pattern (Plans B/C read this).

- [ ] **Step 1: Add generators section to `b8008.core`** (append at top level, after `filesets:` block)

```yaml
generators:
  ghdl_synth_verilog:
    interpreter: python3
    command: scripts/fusesoc/ghdl_synth_verilog.py
    description: >
      GHDL --synth the b8008 core (plus optional consumer-side wrapper
      files via extra_files) into a Verilog netlist + ghdl_gates.v.
```

- [ ] **Step 2: Write the smoke consumer `test/fusesoc_smoke/smoke.core`**

```yaml
CAPI=2:
name: greygiant:retro:fusesoc-smoke:0.1
description: In-repo proof that the ghdl_synth_verilog generator protocol works end-to-end.
filesets:
  empty:
    files: []
generate:
  b8008_netlist:
    generator: ghdl_synth_verilog
    parameters:
      top: b8008_top
      output: b8008_core.v
      generics:
        CLK_FREQ_HZ: 25000000
targets:
  default:
    filesets: [empty]
    generate: [b8008_netlist]
    toplevel: b8008_top
```

- [ ] **Step 3: Run the smoke consumer with the Task 1 incantation**

```bash
cd ~/Development/intel-8008-vhdl
rm -rf build/fusesoc-smoke   # --cores-root . scans recursively; a prior run's generated .core in here would be rediscovered (duplicate VLNV)
fusesoc --cores-root . run --setup --build-root build/fusesoc-smoke greygiant:retro:fusesoc-smoke
find build/fusesoc-smoke ~/.cache/fusesoc -name b8008_core.v 2>/dev/null
```

(Adjust flags per Task 1 findings — e.g. `--tool icarus` if a tool is mandatory.)
Expected: netlist found; `head -3` on it shows the provenance header.

- [ ] **Step 4: Add `netlist-top` to the root Makefile** (after the existing synth targets; also add one help line)

```make
# FuseSoC-generated b8008_top netlist (distinct from build/synth/b8008.v,
# which is entity b8008 without the top-level memories).
NETLIST_TOP_DIR := build/netlist-top
.PHONY: netlist-top
netlist-top:
	@mkdir -p $(NETLIST_TOP_DIR)
	@printf 'gapi: "1.0"\nfiles_root: .\nvlnv: "greygiant:retro:b8008-top-netlist:0"\nparameters:\n  top: b8008_top\n  output: b8008_top.v\n' > $(NETLIST_TOP_DIR)/input.yml
	cd $(NETLIST_TOP_DIR) && python3 ../../scripts/fusesoc/ghdl_synth_verilog.py input.yml
```

Help line to add in the `help:` recipe: `@echo "  make netlist-top          - FuseSoC generator: b8008_top Verilog netlist"`

- [ ] **Step 5: Run it**

```bash
make netlist-top
head -3 build/netlist-top/b8008_top.v
```

Expected: provenance header, entity `b8008_top`, `Generics: defaults`.

- [ ] **Step 6: Write `docs/fusesoc.md`** — record: pinned fusesoc version (Task 1), the proven `fusesoc run` incantation and copy-out `find` pattern (Step 3), `files_root` semantics observed, generator caching behavior and the re-run/duplicate-VLNV behavior (Task 1 — whether consumers need `rm -rf <build-root>` and/or a cache-buster to regenerate on core changes), generator parameter reference (top/output/generics/extra_files), and the PyYAML prerequisite. This file is the contract Plans B and C read.

- [ ] **Step 7: Regression check — existing flows untouched**

```bash
make test-b8008-top 2>&1 | tail -3
./test_programs/verification_scripts/run_all_tests.sh 2>&1 | tail -3
```

Expected: same results as before this plan (all PASS).

- [ ] **Step 8: Commit**

```bash
git add b8008.core test/fusesoc_smoke/smoke.core Makefile docs/fusesoc.md
git commit -m "feat: wire ghdl_synth_verilog generator, smoke consumer, make netlist-top, docs"
```

---

## Verification (spec §4, core repo)

- [ ] Existing testbench suite green (Task 4 Step 7).
- [ ] `make netlist-top` produces a netlist yosys parses cleanly (Task 3 Step 4 + Task 4 Step 5).
- [ ] Smoke consumer proves the FuseSoC generator protocol (Task 4 Step 3) — the gate for starting Plans B and C.
