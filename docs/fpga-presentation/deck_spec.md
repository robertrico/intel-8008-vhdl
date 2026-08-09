# FPGA Talk — Deck Spec

**Status: DRAFT 4** (2026-08-08). 33 slides.

> **Changes since draft 3 — factual refresh + one new slide.**
>
> 1. Numbers updated to current repo state: 25 VHDL modules (was 29 —
>    orphan-module sweep), 367 commits (was 297), regression suite 37/37
>    (was 28/28), ALU sweep 1,049,600 arithmetic + logical cases (was
>    656,384 arithmetic-only).
> 2. **New slide after the verification ladder: "Beyond tests: proofs,
>    equivalence, fuzzing"** — introduces the tooling without deep-diving:
>    SBY property proofs (11 suites), RTL-vs-netlist equivalence (7 miters +
>    6 EQY), exhaustive sweeps, cocotb bus-protocol monitor, differential
>    fuzzer (three oracles). Yellow bar: 37 CI jobs per push, every checker
>    mutation-tested, verification plan 102 rows zero gaps. On-theme for
>    this deck: it is the same YosysHQ ecosystem as the build flow, and the
>    equivalence row is the structural answer to the 0xFF war story.
> 3. "Oracle emulator" credit removed from the verification sweep row —
>    the old Python emulator was discarded as a bad implementation and is
>    not cited as a reference anywhere; `isa.json` stands alone.

> **Changes since draft 2 — the arc was rebuilt.** Draft 2 hopped: a
> personal-narrative slide sat mid-deck and posed a question the deck never
> answered. Draft 3 is **teach → prove → reflect**:
>
> 1. **The teaching run (Parts 1–4) is uninterrupted — no exceptions.** The
>    mid-deck AI slide is gone entirely, not shrunk. Roadmap card 5 already
>    makes the promise; a second promise mid-talk was redundant *and* a
>    hop. A slide titled "One thing before we go on" is an interruption
>    announcing itself.
> 2. **New slide 21** — where the architecture came from. Intel's 1972 block
>    diagram, the RTL-partition provenance claim, and the survey result.
>    This is the keystone; the finale depends on it.
> 3. Verification and the live demo now come *before* the reflection, so the
>    demo is the proof that earns it.
> 4. **New finale (28–31)** — a retrospective sweep back through every part
>    of the talk: *what the AI did* ‖ *what I had to learn myself*. The
>    promised question gets answered, cumulatively.

This is a **parallel deck**, not a replacement. It lives alongside
`docs/presentation/` (the 8008-focused talk) and shares nothing with it —
separate build script, separate assets copy, separate `.pptx`. Editing one
cannot affect the other.

| | `docs/presentation/` | `docs/fpga-presentation/` (this one) |
|---|---|---|
| Subject | The Intel 8008 and its resurrection | **FPGAs and HDL** |
| The 8008 is… | the point | the payload that makes it concrete |
| Slides on "what is an FPGA" | 1 | **7** |
| Slides showing HDL | 1 | **7** |
| Slides on the toolchain | 0 | **4** |
| Slides on learning it / the AI | 3 | **4**, all at the end (a finale, not a subplot) |
| Output | `b8008_talk.pptx` | `fpga_talk.pptx` |

`deck_build.py` is the source of truth for verbatim slide content. Edit it
and rerun to regenerate `fpga_talk.pptx`. This spec describes intent and
running order; the script describes pixels.

```bash
cd docs/fpga-presentation
python3 deck_build.py        # needs python-pptx + Pillow
```

---

## Why this deck exists

Audience feedback on the original talk: the FPGA work drew more interest
than the fact that it was an 8008. So this version inverts the emphasis.
Someone who has never touched an FPGA should leave able to explain what a
LUT is, what a bitstream is, why HDL is not software, and what the four
tools in the flow actually do.

---

## The AI thread

Kept, and in draft 3 it is no longer a subplot — it is the **finale**, and
it is built as a retrospective sweep back through the entire talk.

Why it earns that much room:

1. **Honesty.** Most of this VHDL was drafted by an AI. Presenting it as
   solo work would be a lie, and a room full of engineers can smell one.
2. **It is useful.** "You can learn a hard technical skill with an AI, and
   learn it *properly*" is a claim this audience is actively arguing about.
   This project is real evidence — including two failed attempts, which is
   what makes it evidence rather than a testimonial.

### The mechanism that makes the story work

The AI's training corpus for "Intel 8008" is **instruction-set
simulators** — sequential software that executes one opcode at a time. So
its prior for *implement an 8008* is emulator-shaped. Look at what the
first two versions were:

- **s8008** — monolithic, single-cycle. An ISS written in VHDL.
- **v8008** — multi-cycle rewrite. Still fighting the same pull.
- **b8008** — 29 structural blocks, derived from the 1972 block diagram.

So the diagnosis is not the vague "I produced more code than I understood".
It is specific: **I was building the architecture the corpus knew instead
of the one the datasheet drew.** The block-based decomposition is the one
thing no model could have supplied, and it is the reason version three is
different in kind rather than merely in quality.

That claim lives on **slide 21** and is cashed in on **slide 30, row 4**.
Cutting slide 21 breaks the finale.

### Structure: promise once, then sweep

The promise is made **once**, on roadmap card 5, and then not mentioned
again until the finale. There is deliberately **no mid-deck AI slide.**

An earlier draft had one — a "signpost" in Part 2 restating the promise
and introducing the book. It was cut, and the reasoning is worth recording
so it does not come back:

- Roadmap card 5 already promises it. A second promise adds nothing.
- It stopped the teaching run to deliver narrative, which is the exact
  failure the draft-3 restructure existed to fix.
- Its own title — *"One thing before we go on"* — conceded that it was an
  interruption.
- Everything on it had a better home: the "eighteen months ago" line opens
  slide 28, where it is chronologically right; the book is step zero on 28,
  the first rule on 31, and **"Start here:"** on the Q&A slide, which is
  where people actually photograph it.

**Slides 28–31** keep the promise in full. Slide 28 tells the three
versions in one place; 29–30 walk back through every part of the talk in
two columns — *what the AI did* ‖ *what I had to learn myself*; 31 is the
transferable advice.

The payoff line, on slide 30: **"Version three worked because by then I
had learned the right-hand column."** That answers the question the deck
poses without ever stating it as a thesis — the answer accumulates.

### Lines not to soften

- Slide 29, row 1 is deliberately the least flattering to the AI: for
  foundations it is a *tempting shortcut that does not work*. That row is
  what makes the credit in rows 2–3 believable. Keep it.
- Slide 30, row 5: *"otherwise you are grading its homework with its own
  answer key."* This is the sentence people write down.
- Slide 28's bottom bar carries the corpus-vs-datasheet diagnosis. It is
  the thesis of the whole finale.

### The provenance claim (slide 21)

Two claims, deliberately kept separate because they are different kinds of
claim:

1. **The RTL partition is the author's own work**, derived from the 1972
   datasheet. Note the precise framing on the slide: Intel drew a
   *conceptual* block diagram; turning those boxes into 29 synthesizable,
   independently testable modules with explicit control signals is
   engineering, and it is his. "Intel drew the concept" is not a hedge —
   it forecloses the obvious objection and makes the real claim stronger.
2. **The survey**: eighteen months of searching — Google Groups,
   period websites, the SCELBI archives — turned up only instruction-set
   simulators. Stated boldly, backed by the search, and closed with a
   genuine invitation: *if you find another, please tell me.* The
   invitation is the credibility; someone who wants the counterexample has
   obviously looked for it.

## Design system

Inherited from the sibling deck, with one deliberate change: **Lattice
charcoal + yellow is now the default zone**, because we are in FPGA-land
for the whole talk. Intel blue is available (`ZONE = 'intel'`) but the
draft does not currently use it — the 8008 appears as payload, not as
protagonist.

| Role | Color | Hex |
|------|--------|-----|
| Structure — titles, table headers | Lattice Charcoal | `#333333` / `#3B3F44` |
| Accent — one per slide: a bar, a stat, a highlight | Lattice Yellow | `#FFC220` |
| Dark slide background | Charcoal | `#333333` |
| Light slide background | Off-white | `#F7F8FA` |
| Code panels | Charcoal | `#2A2D31` (light slides) / `#26292D` (dark) |
| Code comments | Sky | `#6FC2EA` |
| "Wrong way" callouts | Brick | `#B3332E` |

Font: **Aptos** / **Aptos Mono** throughout. Fallback: Segoe UI + Consolas.

Rhythm: dark slides open each act and carry the war stories; light slides
carry content. Roughly every third slide is dark.

---

## Running order

**Timing budget (45 min):** frame 3 / what-is-an-FPGA 10 / HDL 10 /
toolchain 6 / building it 7 / proof 2 / demo 6 / reflection 6 / close 2.
Runs long by design — see *Cuts* below.

**The arc: teach → prove → reflect.** Parts 1–4 teach, uninterrupted.
Part 5 proves it works and Part 6 shows it working. Part 7 goes back
through all of it and asks what the AI did and what had to be learned
first-hand. Nothing in the teaching run is interrupted by narrative, and
nothing in the finale is unearned.

### Frame

| # | Title | Carries |
|---|-------|---------|
| 1 | **Nothing → CPU** | Title. Names the real subject up front: FPGA + HDL, told through an 8008. |
| 2 | **Five questions, in order** | Roadmap cards. Sets the contract so nobody is lost or bored for more than ~10 min. Card 5 flags the AI question up front rather than springing it. |

### Part 1 — What an FPGA is (7 slides)

| # | Title | Carries |
|---|-------|---------|
| 3 | Three ways to build a digital system | CPU vs FPGA vs ASIC table. "An FPGA is the middle chair." |
| 4 | Inside: a grid of tiny identical tiles | Fabric diagram + one tile unpacked (LUT4, FF, carry chain). Routing is most of the die *and* most of the delay. |
| 5 | **The LUT: a truth table you can rewrite** | The money slide. `q <= (a and b) or (c and not d);` worked out into its actual 16 config bits, rendered as a grid. |
| 6 | LUTs alone would be wasteful — so: hard blocks | DP16KD / EHXPLLL / MULT18X18D / TRELLIS_IO with real ECP5-45F counts and this project's usage. Plants *inference*. |
| 7 | So what is a "bitstream"? | Config SRAM, volatile, JTAG. Kills the "the FPGA runs the bitstream" misconception. |
| 8 | **This is not emulation** | Software `while` loop vs nine blocks settling simultaneously. "The board is not running an 8008. The board **is** an 8008." |
| 9 | The board I used: ECP5-5G Versa | Real part numbers. Honest reason for the choice: open toolchain, not speed. |

### Part 2 — Describing hardware (7 slides)

| # | Title | Carries |
|---|-------|---------|
| 10 | **HDL is not a programming language** | Three cards: concurrency, structure-not-behavior, the clock is the only "when". |
| 11 | Two languages, one job | VHDL vs Verilog counter, side by side. 60 seconds, no language war. |
| 12 | You only ever write three kinds of thing | Combinational / sequential / structural, with what each *becomes*. Demystifies the language's size. |
| 13 | A whole real module, start to finish | `stack_pointer.vhdl` in full. 3 FFs, an incrementer, a mux. Introduces the dumb-module rule. |
| 14 | **All the way down: one line of VHDL → silicon** | `sp_r <= sp_r + 1;` traced through GHDL → Yosys → nextpnr. Four levels, all inspectable. |
| 15 | **Inference: say the magic words** | `ram_sync.vhdl` → 8 block RAMs, zero LUTs. Move the read out of the clocked process → 131,072 flip-flops in a chip with 43,848. |
| 16 | Things that do not exist inside an FPGA | Tri-states, free initial values, "wait a moment". Where a 1972 datasheet collides with 2013 silicon. |

### Part 3 — The toolchain (4 slides)

| # | Title | Carries |
|---|-------|---------|
| 17 | Source to silicon, entirely open source | The chain + the actual commands from `projects/project.mk`. `tribuf -logic` visible in the flow. |
| 18 | The two hard steps: place, then route | Non-determinism, finite wires. "Synthesis is the compiler, P&R is the linker — except the linker decides how fast you run." |
| 19 | **Timing closure** | Real critical-path excerpt. 3.09 ns logic vs 5.74 ns routing. 115.66 MHz PASS at 25 MHz. |
| 20 | What a 1972 computer costs in 2013 silicon | Utilization table. 4% of the fabric. |

### Part 4 — Building it, and what bit me (5 slides)

| # | Title | Carries |
|---|-------|---------|
| 21 | **Where the architecture came from** | **Keystone.** Intel's 1972 block diagram; every module is one box. The provenance claim and the survey result, with the invitation. Slide 30 depends on this. |
| 22 | The whole computer, on one die | SoC map: 29-module core + ROM/RAM BRAM + UART + PLL + phase clocks + debug control. The CPU is the small part. |
| 23 | **φ1 and φ2 are data, not clocks** | The most transferable lesson here. Derive clocks in a PLL or not at all. Wrong/right code side by side. |
| 24 | **War story: the day the toolchain ate my ROM** | The 0xFF bug as a five-beat detective story. Two red herrings, one-character fix. |
| 25 | Patch firmware, skip the build | `ecpbram`. 90 s → 3 s. Generalises to any BRAM-resident firmware or LUT. |

### Part 5 — Proof (1 slide)

| # | Title | Carries |
|---|-------|---------|
| 26 | How you know gateware is right | Verification ladder: per-module → exhaustive ALU (656,384 cases) → 28/28 regression → 27/27 cycle-exact → 46/46 on the board. |

### Part 6 — Live (1 slide)

| # | Title | Carries |
|---|-------|---------|
| 27 | The circuit, running | Scope on φ1/φ2 (Part 1 made physical), pi, calculator, boot-to-BASIC finale. **This is the proof that earns the reflection.** |

### Part 7 — How this got built (4 slides)

| # | Title | Carries |
|---|-------|---------|
| 28 | **Three versions, eighteen months** | Opens with "eighteen months ago I could not read a VHDL `process`". Book → s8008 → v8008 → b8008 in one place. Bottom bar carries the thesis: both failures were the corpus's architecture, not the datasheet's. |
| 29 | **What it did, and what I had to learn** | The sweep begins. Foundations, HDL, inference. Two columns throughout. |
| 30 | **…(cont.)** | Toolchain, clocks, the 0xFF bug, **the architecture**, verification. Closing bar is the payoff: *version three worked because by then I had learned the right-hand column.* |
| 31 | What I'd tell you about learning this way | Six rules. Read the book first; own the spec; derive the architecture yourself; keep modules reviewable; let it draft, you reject; nothing is done until the board says so. |

### Close

| # | Title | Carries |
|---|-------|---------|
| 32 | Questions? | Credits, **"Start here:"** the book, toolchain acknowledgements, "come type at it". |

---

## Editorial choices in this draft

1. **The 8008 history is gone.** No CTC/Datapoint slide, no TI TMX 1795,
   no x86 lineage, no SCELBI backstory. All of it is good material and all
   of it is in the other deck. Here it would compete with the FPGA content.
2. **The teaching run is never interrupted by narrative — no exceptions.**
   Draft 2's mistake, and an earlier draft-3 attempt kept a shrunken
   version of it. Both are gone. Roadmap card 5 carries the promise alone.
3. **The demo comes before the reflection.** A consequence of ending on the
   learning story: the talk closes on synthesis rather than on the running
   machine. If you would rather go out on the hardware, swap 27 with 28–31
   — but then slide 30's payoff has to move to the demo's speaker notes,
   and it loses.
4. **Three slides have no counterpart in the original deck and are the
   best things here:** slide 5 (the LUT's actual 16 bits), slide 15
   (inference — one line moved, and the design no longer fits), and slide
   30 (the sweep's payoff).
5. **Slide 14 is the spine of the teaching half**; slide 30 is the spine of
   the reflective half.

## If it runs long — cut in this order

1. Slide 11 (VHDL vs Verilog) — nice-to-have, not load-bearing.
2. Slide 18 (place & route detail) — fold the one-line analogy into 17.
3. Slide 25 (ecpbram) — delightful, but a tangent.
4. Slide 29, rows 1–2 — tighten to one row. Slide 30's rows 4–5 carry the
   argument; 29 is supporting evidence.
5. Slide 3 (CPU/FPGA/ASIC table) — only if the room is already hardware
   people.

**Never cut 5, 8, 14, 15, 21, 23, 28, or 30.** Those are the deck. In
particular 21 and 30 are load-bearing for each other: cutting the
architecture-provenance slide leaves slide 30's keystone row unsupported,
and cutting 30 leaves roadmap card 5's promise unkept.

## If it runs short

- Slide 4 has room for a live `yosys` run.
- Slide 19 can expand into reading a full critical path aloud.
- Slide 28 can expand into showing `isa.json` beside the datasheet page it
  was transcribed from — the best "this is what owning the ground truth
  means" visual, and it needs no new slide.
- Slide 27 has a fourth demo (HEXPAWN, self-modifying 1973 code) in reserve.

## Asset checklist

**Already wired in and working:**
- [x] `assets/lattice_logo_ondark.png` — slides 1, 7, 9, 17, 27, 32
- [x] `docs/images/tiny_os_scelbal.png` — slides 1, 27, 32
- [x] `docs/two_phase_oscope_cap_1.png` — slide 27
- [x] `assets/8008_block_diagram.png` — slide 21 (**now in use**)

**Drawn in code, no asset needed:** the fabric grid (4), the LUT bit grid
(5), all flow chains (7, 17, 25), the module maps (8, 22), the four-level
chain (14), the three-version timeline (28), both sweep tables (29, 30).

**Worth producing before the talk:**
- [ ] **Cover shot of *Getting Started with FPGAs*** — slide 28's STEP ZERO
      card is text-only and would carry a photo well. A shot of your own
      copy beats a stock cover image; a worn one beats a clean one.
- [ ] Bench photo — board + laptop + scope. Candidate for slide 1 or 9.
- [ ] A die-shot or fabric photomicrograph of an ECP5 for slide 4, if one
      exists under a usable license (currently drawn, which is fine).
- [ ] `isa.json` next to the datasheet table it came from — optional for
      slide 28, and the best visual in reserve if the talk runs short.
- [ ] Fallback screen recordings of all demos for slide 27.
- [ ] Fill in the repo URL on slide 32.

---

## Unused assets from the sibling deck

`assets/` was copied wholesale, so these are present but not currently
placed. Available if you want to reintroduce any 8008 context:
`intel_c8008_chip.jpg`, `8008_instruction_cycle.png`, `sim8_01_schematic.png`,
`intel_1968_ondark.png` / `_onlight.png`, `intel_logo_*.png`.

The most likely reintroduction is `sim8_01_schematic.png` on slide 22 —
"in 1972 this was a rack" lands harder with the picture of the rack.
