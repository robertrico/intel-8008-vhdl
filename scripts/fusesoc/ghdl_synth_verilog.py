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
        stdout=subprocess.PIPE, text=True, check=True)

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
