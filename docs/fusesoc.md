# FuseSoC generator: `ghdl_synth_verilog`

This is the contract for the `ghdl_synth_verilog` FuseSoC generator provided
by `greygiant:retro:b8008` (`b8008.core`). It exists so downstream consumers
(remote_8008 extraction, Byte Hamr integration) can turn the b8008 VHDL core
into a self-contained Verilog netlist via the FuseSoC generator protocol,
without depending on GHDL-Yosys plugin availability. Anything that changes
this contract must update this file — Plans B/C read it verbatim (the
`fusesoc run` incantation and the copy-out `find` pattern in particular).

## Pinned tool version

**fusesoc 2.4.6**, installed via `pipx install fusesoc`. This is the exact
version the generator protocol was spiked and proven against (Task 1) and
wired up against (Task 4). Do not assume forward compatibility with other
2.x releases without re-verifying the findings below.

## GHDL prerequisite

The generator script resolves its GHDL binary as:
`os.environ.get("GHDL", ~/oss-cad-suite/bin/ghdl)` (`ghdl_synth_verilog.py:24`).
Downstream consumers need one of:

- GHDL from OSS CAD Suite installed at `~/oss-cad-suite` (the default the
  script falls back to), **or**
- a `GHDL` environment variable pointing at a working `ghdl` binary
  (`export GHDL=/path/to/ghdl`), which takes precedence when set.

If neither is present, the generator fails with a Python
`subprocess.FileNotFoundError` (no GHDL executable at the resolved path) —
there is no friendlier error message, so this is worth checking up front.

## PyYAML prerequisite

The generator script (`scripts/fusesoc/ghdl_synth_verilog.py`) and
`make netlist-top` both need `import yaml` under the **system** `python3`
(not a venv fusesoc may have been pipx-installed into). On Homebrew-managed
macOS python3, PEP 668 blocks a plain:

```
python3 -m pip install --user pyyaml
```

with an "externally-managed-environment" error. Use:

```
python3 -m pip install --user --break-system-packages pyyaml
```

(A venv is the other valid option; `--break-system-packages` is simplest.)
On this system, PyYAML 6.0.3 was already present for `python3` and no
install step was needed — but downstream consumers on a fresh machine should
expect to run the above.

## The generator

Declared in `b8008.core`:

```yaml
generators:
  ghdl_synth_verilog:
    interpreter: python3
    command: scripts/fusesoc/ghdl_synth_verilog.py
    description: >
      GHDL --synth the b8008 core (plus optional consumer-side wrapper
      files via extra_files) into a Verilog netlist + ghdl_gates.v.
```

Generator name (for `generate:` stanzas in consumer `.core` files):
**`ghdl_synth_verilog`**.

### Parameters (via a consumer's `generate:` stanza)

```yaml
generate:
  <generate-name>:
    generator: ghdl_synth_verilog
    parameters:
      top: b8008_top              # entity to synthesize (default: b8008_top)
      output: b8008_core.v        # output Verilog filename (default: <top>.v)
      generics:                   # optional; passed as -g<K>=<V> to ghdl --synth
        CLK_FREQ_HZ: 25000000
      extra_files:                # optional; consumer-side wrapper VHDL,
        - wrapper/my_wrapper.vhdl # resolved relative to files_root (the
                                   # consumer core's own directory), analyzed
                                   # after the b8008 rtl+debug_io filesets
```

Core sources (the ordered `rtl` + `debug_io` filesets) are read directly out
of `b8008.core` by the script — a consumer does not repeat that file list.

### The `depend:` requirement (load-bearing)

Any consumer core that invokes this generator **must** `depend:` on
`greygiant:retro:b8008` from a fileset that is included in the target that
declares the `generate:` stanza. FuseSoC 2.4.6 only harvests generators from
the *resolved dependency graph* of the target being run — a core merely
being visible via `--cores-root` (i.e. showing up in `fusesoc list-cores`)
is not sufficient. Omitting the `depend:` fails with:

```
ERROR: Setup failed : Could not find generator 'ghdl_synth_verilog' requested by <consumer-vlnv>
```

Minimal working shape (see `test/fusesoc_smoke/smoke.core` for the real,
verified example):

```yaml
filesets:
  smoke_deps:
    depend: [greygiant:retro:b8008]
generate:
  b8008_netlist:
    generator: ghdl_synth_verilog
    parameters: {top: b8008_top, output: b8008_core.v}
targets:
  default:
    filesets: [smoke_deps]
    generate: [b8008_netlist]
    toplevel: b8008_top
```

### Fileset reachability: `synth_helpers` / `debug_io` are generator-internal, not `depend:`-able

`b8008.core`'s `synth_helpers` (`src/synth/ghdl_gates.v`) and `debug_io`
(`debug_clock_control`, `usart`, `b8008_usart`) filesets exist in the core
file, but a consumer cannot reach either one by `depend:`-ing on
`greygiant:retro:b8008`. `depend:` pulls in whatever filesets the
*dependency's default target* lists, and `targets.default.filesets` in
`b8008.core` is `[rtl]` only — `synth_helpers` and `debug_io` are not
members of it, and CAPI2 gives a dependent no syntax to cherry-pick a
non-default fileset out of another core. Do not try to `depend:` your way
to either fileset; it will not resolve, and there is no combination of
`generate:`/`depend:` stanzas in a consumer `.core` that makes it resolve.

Both filesets are generator-internal instead: the `ghdl_synth_verilog`
generator script reads `debug_io` itself (`core_sources()` in
`scripts/fusesoc/ghdl_synth_verilog.py`, alongside `rtl`) when it builds
the GHDL analysis order, and it copies `src/synth/ghdl_gates.v` into its
own output directory as `ghdl_gates.v` — see "Outputs" above and the
generated `.core` file's `netlist` fileset. Consumers get `ghdl_gates.v`
by taking the copy the generator writes out, the same way they take the
generated netlist itself (via the copy-out path described above), not by
depending on `synth_helpers` directly. This is also how the design spec's
§2 phrasing "`ghdl_gates.v` resolved from the core's `synth-helpers`
fileset" and §3's "supplied by the core's `synth-helpers` fileset" are
actually realized in practice: *through* the generator's own copy step,
not through a consumer-side `depend:`.

Adding `synth_helpers` and `debug_io` to the core's `default` target (so
`depend:` would reach them) was considered and deliberately rejected: a
consumer that both depended on the core for `ghdl_gates.v` directly *and*
consumed the generator's output would end up with two copies of the
`ghdl_gates.v` Verilog module in its build — the depended-in source copy
and the generator's own copy in its output directory — which is a
duplicate-module hazard for any EDA tool that flattens both into one
build (icarus/yosys will refuse to elaborate two definitions of the same
module name). Keeping `default` at `[rtl]` only avoids that hazard by
construction.

### The `files: []` schema constraint

fusesoc 2.4.6 rejects an empty `files` list in a fileset
(`Error validating data.filesets.<name>.files must contain at least 1
items`). This is silent at the point of failure — the whole `.core` file is
dropped from the library scan (`WARNING: Parse error. Ignoring file ...`)
and the real error only surfaces later as a confusing "core not found".

Fix used here: the `depend:`-carrying fileset (`smoke_deps` above) simply
omits the `files:` key entirely — a fileset with only `depend:` and no
`files:` key is schema-valid under 2.4.6 (distinct from `files: []`, which
is not). If a fileset needs to declare real files, give it at least one.

## The proven `fusesoc run` incantation

```bash
cd <repo-root>
rm -rf build/<build-root-subdir>   # see caching/residue note below
fusesoc --cores-root . run --setup --tool icarus \
    --build-root build/<build-root-subdir> <consumer-vlnv>
```

Verified end-to-end against `greygiant:retro:fusesoc-smoke:0.1`
(`test/fusesoc_smoke/smoke.core`):

```bash
rm -rf build/fusesoc-smoke
fusesoc --cores-root . run --setup --tool icarus \
    --build-root build/fusesoc-smoke greygiant:retro:fusesoc-smoke
```

- Exit code 0.
- Generation fires during `--setup` (`INFO: Generating
  greygiant:retro:fusesoc-smoke-b8008_netlist:0.1`), before any EDA
  toolchain step.
- **No "no toplevel" error occurred** in this run: the smoke core sets
  `toplevel: b8008_top` in its target and the generated netlist supplies
  that module, so the cosmetic "Target 'default' has no toplevel" artifact
  seen in the Task 1 spike (which had no real toplevel available) did not
  reproduce here.
- Only warnings emitted are cosmetic: an edalizer deprecation notice for the
  legacy backend API, and one "unknown file type 'vhdlSource-2008'" warning
  per b8008 VHDL source file pulled in via the `depend:` (icarus doesn't
  recognize VHDL file types; harmless since the actual synthesizable output
  is the generated Verilog netlist, not those VHDL sources directly).

`--tool icarus` is mandatory in this incantation (2.4.6 requires *a* tool to
resolve a target even though the tool is never actually invoked to build
anything meaningful here — it only needs to get through `--setup`).

### Cross-repo form (consumer core in a different repo)

remote_8008 and Byte Hamr don't live in this repo, so their consumer `.core`
files can't rely on `--cores-root .` reaching `greygiant:retro:b8008`. Pass
**two** `--cores-root` flags instead — one pointing at this repo, one at the
consumer's own repo/directory — and run from the consumer side:

```bash
cd <consumer-repo-dir>
rm -rf build/<build-root-subdir>
fusesoc --cores-root /path/to/intel-8008-vhdl --cores-root <consumer-dir> \
    run --setup --tool icarus \
    --build-root build/<build-root-subdir> <consumer-vlnv>
```

Verified end-to-end (fusesoc 2.4.6) with a throwaway consumer core at
`/private/tmp/xrepo-test/xrepo.core` — same minimal shape as
`test/fusesoc_smoke/smoke.core` (a `depend: [greygiant:retro:b8008]`
fileset with no `files:` key, a `generate:` stanza, `toplevel: b8008_top`):

```bash
cd /private/tmp/xrepo-test
rm -rf build
fusesoc --cores-root /Users/hambook/Development/intel-8008-vhdl \
    --cores-root /private/tmp/xrepo-test \
    run --setup --tool icarus \
    --build-root build/xrepo-test greygiant:retro:xrepo-test
```

Worked on the first attempt, no library-registration step needed — exit 0,
`INFO: Preparing greygiant:retro:b8008:3.0` followed by
`INFO: Generating greygiant:retro:xrepo-test-b8008_netlist:0.1`, and the
copied-out netlist carries a provenance header pointing at the *b8008 repo*
(not the consumer dir), confirming sources were pulled from the right
`--cores-root`:

```
// GENERATED FILE - do not edit.
// Source: /Users/hambook/Development/intel-8008-vhdl @ d419396-dirty, entity b8008_top
```

Same warnings as the same-repo run (deprecated backend notice,
`vhdlSource-2008` unknown-file-type per b8008 source); no cross-repo-specific
errors. The `depend:`/`files: []` constraints above apply identically here —
they're per-core-file rules, independent of which `--cores-root` supplied
the core.

## Output path pattern (copy-out)

Two locations land under the per-target build root
`build/<consumer-vlnv-sanitized>/<target>-<tool>/`:

1. **Generator scratch/cache** (where the script actually runs and writes
   first):
   ```
   build/<consumer-vlnv-sanitized>/<target>-<tool>/generator_cache/<generated-vlnv-sanitized>-<content-hash>/<output-file>
   ```

2. **Copy-out into the build's `src/` tree** — **this is the path Plans B/C
   should `find`/copy from**:
   ```
   build/<consumer-vlnv-sanitized>/<target>-<tool>/src/<generated-vlnv-sanitized>/<output-file>
   ```

Verified concretely:

```
build/fusesoc-smoke/greygiant_retro_fusesoc-smoke_0.1/default-icarus/src/greygiant_retro_fusesoc-smoke-b8008_netlist_0.1/b8008_core.v
```

Recommended copy-out pattern for downstream Makefiles:

```bash
find build/<build-root-subdir> -path '*/src/*' -name '<output-file>'
```

(Add `-path '*/src/*'` to exclude the `generator_cache/` scratch copy, which
has the same filename but is not the one the EDA backend actually consumes.)

## `files_root` semantics

`files_root` in the gapi input the generator receives is the **consumer**
core's directory (the core that declares the `generate:` stanza) — not the
generator-providing core's (`greygiant:retro:b8008`) directory. This is why
`extra_files` in the parameters resolve relative to the consumer core, not
to `b8008.core`'s location.

## Caching / re-run behavior

- **No caching across `--setup` runs.** Every `fusesoc run --setup` on the
  same target re-executes the generator (confirmed: `b8008_core.v` mtime
  and content-hash generator_cache directory both refresh on an immediate
  second run with unchanged parameters; console repeats `INFO: Generating
  ...`). Correctness is unaffected — but there is no free build-time win
  from re-running `--setup` without changes; expect the full GHDL analyze +
  `--synth` cost (~20+ MB/24k-line netlist) on every invocation.

- **Duplicate-VLNV / stale residue risk with `--cores-root .`:** the Task 1
  spike used a narrow `--cores-root genrepo --cores-root userrepo` that
  never reached into `build/`, and concluded residue was a non-issue under
  that scope. **This repo's incantation uses `--cores-root .`, which *does*
  recursively discover the residual generated `.core` file left in
  `build/.../generator_cache/...` by a prior run** (confirmed via
  `fusesoc --cores-root . list-cores`, which lists
  `greygiant:retro:fusesoc-smoke-b8008_netlist:0.1` after one run). Despite
  that, **two consecutive `fusesoc run --setup` invocations with the build
  root left in place from the prior run produced no duplicate-VLNV error or
  warning** in this repo (verified: exit 0 both times, no `ERROR`/
  `duplicate` in either log) — the generator's own regeneration on each
  `--setup` appears to keep the residual core's content consistent with
  what the library scan would otherwise flag as a conflict. **Still,
  `rm -rf build/<build-root-subdir>` before each run remains the
  recommended, defensive pattern** (as the brief's Step 3 already does) —
  it removes any doubt around residue from parameter changes between runs,
  and this finding should be re-checked if a future consumer's build root
  lives somewhere `--cores-root .` reaches recursively in a more
  complicated way (e.g. nested consumer cores under `build/`).

## `make netlist-top` (direct-invocation form, no FuseSoC project setup)

For cases that just want the netlist without standing up a FuseSoC
consumer core (e.g. quick local iteration), the generator script can be
invoked directly with a hand-written gapi YAML:

```make
NETLIST_TOP_DIR := build/netlist-top
netlist-top:
	@mkdir -p $(NETLIST_TOP_DIR)
	@printf 'gapi: "1.0"\nfiles_root: .\nvlnv: "greygiant:retro:b8008-top-netlist:0"\nparameters:\n  top: b8008_top\n  output: b8008_top.v\n' > $(NETLIST_TOP_DIR)/input.yml
	cd $(NETLIST_TOP_DIR) && python3 ../../scripts/fusesoc/ghdl_synth_verilog.py input.yml
```

Verified: `make netlist-top` produces `build/netlist-top/b8008_top.v`
(24119 lines) with the provenance header:

```
// GENERATED FILE - do not edit.
// Source: <repo> @ <short-sha>[-dirty], entity b8008_top
// Generics: defaults
// Personality: defaults (ROM 4KB @ 0x0000, RAM 12KB @ 0x1000, monitor map)
```

and parses cleanly under yosys:
`yosys -p "read_verilog build/netlist-top/ghdl_gates.v build/netlist-top/b8008_top.v; hierarchy -check -top b8008_top"`
completes with no errors (only informational "Removed unused module" notes
for the unused gate-primitive modules).

## Generated `.core` file (informational)

The script also emits a small CAPI2 `.core` describing its own output, e.g.:

```yaml
CAPI=2:
name: greygiant:retro:fusesoc-smoke-b8008_netlist:0.1
filesets:
  netlist:
    file_type: verilogSource
    files: [b8008_core.v, ghdl_gates.v]
targets:
  default:
    filesets: [netlist]
```

This is what FuseSoC feeds back into the consumer's build as the generated
core's fileset; downstream tooling normally doesn't need to read it
directly (the netlist + `ghdl_gates.v` files are the useful artifacts), but
it's there if a consumer wants to depend on the generated core by VLNV.
