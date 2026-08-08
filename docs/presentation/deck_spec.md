# b8008 Presentation — Deck Spec

> **REV 3 (2026-07-04):** `deck_build.py` is now the source of truth for
> verbatim slide content — edit it and rerun to regenerate
> `b8008_talk.pptx`. Changes since the spec below was written:
>
> 1. **Hook slide dropped.** "It boots into BASIC" no longer opens the deck;
>    the screenshot lives on the title and Q&A slides, and boot-to-BASIC is
>    the demo finale.
> 2. **New slide 10: "The FPGA I chose: Lattice ECP5-5G Versa"** — real
>    build-report stats: LFE5UM5G-45F, whole system = 1,672/43,848 LUTs
>    (3%), 8/108 BRAMs, fmax ~95 MHz vs 25 MHz clock vs 500 kHz needed.
>    Placeholder for a board shot (user supplies).
> 3. **Two-zone color theme.** Intel zone (slides 1–8: title, history,
>    quirks): Intel Blue structure, deep-blue dark slides, energy-blue
>    accents, NO yellow. Lattice zone (slides 9–23): charcoal + yellow;
>    titles on light slides go charcoal with yellow bars. The flip happens
>    on the FPGA-primer slide (dark charcoal, Lattice logo top-right) —
>    the theme itself says whose world we're in, never stated aloud.
>    Intel logo on slide 2 (what-is-the-8008), dual logos with
>    brand-color underline bars on slide 1.
> 4. Final slide order: 1 title / 2 what-is-8008 / 3 history / 4 lineage /
>    5–8 weirdness ×4 / 9 FPGA primer (theme flip) / 10 Versa / 11 VHDL /
>    12 project / 13 s8008 lesson / 14 AI / 15 block diagram / 16 dumb
>    modules / 17 stack pointer / 18 litmus / 19 scorecard / 20 rig /
>    21 demos / 22 takeaways / 23 Q&A.

Target: 45 minutes, mixed audience (hardware + software). 23 slides.
Live demos on ECP5-5G Versa board via minicom + `send_hex.py`.

Narrative arc: **WHAT (the 8008 + its quirks) → FPGA primer → the AI-aided project (and its failures) → the design those failures forced → how I know it works → live proof.**

Format key per slide:
- **Title** — verbatim slide title
- **Body** — verbatim on-slide text
- **Image** — what goes on the slide (repo path, or `GATHER:` for things to collect)
- **Notes** — speaker cue, not on slide

Timing budget: hook 2 / what+history 6 / quirks 8 / primer 3 / project+AI 7 /
design 7 / proof 4 / demos 8 / takeaways+Q&A 2.

---

# Design system

Tasteful mix of Lattice and Intel branding. One font family.
Hexes verified against the real sources (2026-07-04): Lattice yellow eyedropped
from latticesemi.com logo PNGs, greys from their site CSS; Intel Blue is the
official 2020-palette value (Pantone 660C).

**Palette:**

| Role | Color | Hex |
|------|-------|-----|
| Primary accent — titles, dividers, table headers | Intel Blue | `#0068B5` |
| Secondary accent — key numbers, "LIVE" flags, highlight bars | Lattice Yellow | `#FFC220` |
| Dark slide background (title, hook, demo slides) | Lattice Charcoal | `#333333` (alt `#3B3F44`) |
| Light slide background (content slides) | Off-white | `#F7F8FA` |
| Body text on light | Charcoal | `#333333` |
| Body text on dark | Soft white | `#F2F2F2` |
| Code block background | Charcoal `#2A2D31` on light slides; `#26292D` panel on dark |
| Optional tertiary (links, secondary chart series) | Lattice Sky | `#1F9DD8` |

**Usage rules:**
- Blue owns structure: slide titles, section-divider bars, table headers.
- Yellow is scarce: one element per slide max — a statistic, a ✓/✗, the word LIVE, an underline bar. Scarcity keeps it tasteful.
- Yellow text ONLY on charcoal (logo-style, high contrast). On light slides yellow appears as fills/bars/underlines behind charcoal text — never yellow text on white (illegible).
- Blue text fine on off-white; on charcoal use white/yellow text, blue only as a bar/shape.
- Dark charcoal slides bookend (1, 2, 20, 21, 23) + section dividers; light slides carry content. Photo slides go dark. Charcoal + yellow bookends read "Lattice"; blue-structured content slides read "Intel" — the mix.

**Font:** **Aptos** family throughout (Microsoft 365 default — already installed with MS Suite).
- Aptos Bold for titles, Aptos Regular for body, **Aptos Mono** for code/terminal text (slide 17 VHDL, demo commands).
- Single family, three weights — satisfies "single font" while code stays monospace.
- Fallback if Aptos missing on the presenting machine: Segoe UI + Consolas.

---

# Act I — WHAT: the 8008 and its quirks

## Slide 1 — Title

**Title:** b8008 — Resurrecting the World's First 8-Bit Microprocessor

**Body:**
> A cycle-exact Intel 8008 in VHDL, built with an AI pair programmer
>
> Robert Rico

**Image:** `docs/images/tiny_os_scelbal.png` (dimmed, as background) — or GATHER: photo of the Versa board on the bench.

**Notes:** One-liner intro. "In 1972 Intel shipped the first 8-bit microprocessor. I spent 8 months bringing it back — and tonight it's running on the table."

---

## Slide 2 — The Hook

**Title:** It boots into BASIC

**Body:**
> Power on → SCELBAL BASIC (1976), from ROM
>
> `MON` drops to a machine monitor. `G 1FB6` warm-returns — program intact.
>
> The Apple II workflow, five years early, on the world's first 8-bit microprocessor.

**Image:** `docs/images/tiny_os_scelbal.png` (full-bleed).

**Notes:** This is the destination. Everything else in the talk is how we got here. Tease that this exact sequence runs live at the end.

---

## Slide 3 — What is the Intel 8008?

**Title:** The Intel 8008 (April 1972)

**Body:**
> - World's first 8-bit microprocessor
> - 3,500 transistors, 10 µm PMOS
> - **18 pins** — for a CPU
> - 500 kHz clock; instructions take 5, 8, or 11 T-states
> - 16 KB address space (14-bit), seven 8-bit registers (A,B,C,D,E,H,L)
> - 48 instructions

**Image:** GATHER: Intel C8008 chip photo (Wikipedia Commons has good CC-licensed package + die shots).

**Notes:** Emphasize 18 pins — that single number causes most of the weirdness coming up. Modern context: an ATtiny has more pins.

---

## Slide 4 — Where it came from

**Title:** Built for a terminal, rejected by its buyer

**Body:**
> - 1969-70: **CTC (Computer Terminal Corp., later Datapoint)** designs the Datapoint 2200 "programmable terminal" — CPU built from ~100 TTL chips
> - CTC asks **Intel** and **Texas Instruments** to shrink it to one chip
> - TI's **TMX 1795** (1971): technically first 8-bit CPU chip — never shipped
> - Intel's chip: late, and slower than CTC's TTL board — **CTC walks away**
> - Intel keeps the rights in trade, sells it as the **8008**

**Image:** GATHER: Datapoint 2200 photo (Wikimedia Commons). Optional: TMX 1795 die photo (Ken Shirriff's blog has one).

**Notes:** The ISA was CTC's design, not Intel's. TI beat everyone to silicon but never productized — the 8008 outlasted it by shipping.

---

## Slide 5 — Why it mattered

**Title:** Your laptop still carries its DNA

**Body:**
> 8008 → 8080 → 8086 → x86
>
> The instruction-set lineage in every PC today traces back to a terminal company in San Antonio, Texas.
>
> And in 1974, the **SCELBI-8H** — arguably the first personal computer — was built around this chip. That's where our demo software comes from.

**Image:** GATHER: simple lineage graphic (can be drawn in PowerPoint: four chips with arrows). Optional: SCELBI-8H photo (willegal.net).

**Notes:** Bridge slide — plants SCELBI now so the demos later have context.

---

## Slide 6 — Weirdness #1: The clocks

**Title:** Weirdness #1 — Two clocks, never high together

**Body:**
> The 8008 needs **two non-overlapping clock phases** (φ1, φ2).
>
> No single clock pin. External circuitry must generate both phases with guaranteed dead time between them.
>
> Get the overlap wrong → internal buses fight → undefined behavior.

**Image:** `docs/two_phase_oscope_cap_1.png` and/or `docs/two_phase_oscope_cap_2.png` — real oscilloscope captures from this project.

**Notes:** These scope shots are from my bench — this is the FPGA generating the two phases. In 1972 you built this from discrete logic before the CPU would even blink.

---

## Slide 7 — Weirdness #2: The bus

**Title:** Weirdness #2 — One bus, three jobs

**Body:**
> 18 pins means **8 data pins total**. So the bus is time-multiplexed, three ways, every machine cycle:
>
> | T-state | What's on the 8 pins |
> |---------|----------------------|
> | T1 | Address, low byte |
> | T2 | Address high 6 bits + cycle type |
> | T3 | The actual data |
>
> External latches must grab each piece at the right instant.

**Image:** Table above as the visual; optional GATHER: timing diagram from 8008 datasheet (`docs/8008_1972.pdf`).

**Notes:** "Tri-plexed" bus. Every memory access is a little three-act play. The CPU also broadcasts its internal state on pins S0-S2 so external logic can follow along.

---

## Slide 8 — Weirdness #3: It can't even start

**Title:** Weirdness #3 — It boots by being interrupted

**Body:**
> - No reset vector. At power-on the PC is garbage.
> - The *only* way to start it: assert the interrupt line and **jam an instruction onto the bus** (typically `RST 0`)
> - Startup is an interrupt. Interrupts are instruction injection. It's injection all the way down.
>
> Intel's own reference design (SIM8-01) needed **dozens of TTL support chips** just to make the CPU usable.

**Image:** GATHER: crop of `docs/SIM8_01_Schematic.pdf` showing the sea of support chips around the CPU.

**Notes:** This is why "just wire up the CPU" was never an option — in 1972 or now. The support glue is half the project.

---

## Slide 9 — Weirdness #4: The hidden program counter

**Title:** Weirdness #4 — There is no program counter

**Body:**
> ...there are **eight** of them.
>
> The PC is whichever slot of an 8 × 14-bit address stack the stack pointer selects.
>
> - **CALL** = SP moves forward (old slot keeps the return address)
> - **RET** = SP moves back
> - 7 levels of nesting; the 8th CALL silently wraps onto the oldest
>
> No stack in memory. No PUSH/POP of data. 1972 had opinions.

**Image:** Simple diagram: 8 slots, SP arrow, CALL/RET animation (build in PowerPoint, 2 clicks).

**Notes:** Remember this one — it becomes the heart of the final design later. Implemented structurally, exactly as drawn, the stack-wrap behavior falls out for free.

---

# Act II — FPGA primer

## Slide 10 — Primer: What's an FPGA?

**Title:** 30-second FPGA primer

**Body:**
> - A chip full of uncommitted logic blocks and programmable wiring
> - You describe a circuit; the toolchain configures the chip to *become* it
> - Not emulation, not software — it **is** the circuit, in real silicon, in parallel
> - This project targets a **Lattice ECP5-5G** using a fully open-source toolchain (GHDL + Yosys + nextpnr)

**Image:** GATHER: FPGA fabric diagram (generic LUT/routing illustration) — or draw a simple grid graphic in PowerPoint.

**Notes:** For the software folks. Key distinction to land: the 8008 design isn't simulated on the board — the board is wired up as an 8008. All that 1972 support glue — clocks, latches, ROM, RAM, UART — fits inside the same chip.

---

## Slide 11 — Primer: VHDL (vs Verilog)

**Title:** Hardware description languages in one slide

**Body:**
> Two mainstream ways to describe digital hardware:
>
> - **Verilog** — C-flavored, terse, dominant in US industry
> - **VHDL** — Ada-flavored, verbose, strongly typed
>
> Same job: describe registers and logic; tools synthesize real gates.
>
> This project: **VHDL**, one file per functional block.

**Image:** Side-by-side snippet, same 3-line counter in Verilog and VHDL (write in PowerPoint code boxes).

**Notes:** Don't linger. "Verbose but strict — it catches a class of mistakes at compile time, which matters when your collaborator is an AI."

---

# Act III — The AI-aided project

## Slide 12 — The project

**Title:** The project: 8 months, 3 attempts

**Body:**
> - **Nov 2025 → Jul 2026** — 297 commits
> - **3 iterations, 2 complete bottom-to-top rewrites:**
>   - `s8008` — monolithic, single-cycle. *Worked in simulation. Broke on hardware.*
>   - `v8008` — multi-cycle rewrite. Collapsed under its own complexity.
>   - `b8008` — block-based, cycle-exact. **Silicon validated.** ✓
> - Built in collaboration with Claude (Anthropic's AI) — every line reviewed, tested, and frequently rejected

**Image:** Timeline graphic (draw in PowerPoint): three arcs, first two ending in ✗.

**Notes:** Set expectations honestly: this was NOT "AI, build me an 8008." Eight months of iteration, and I threw the whole thing away twice. Here's what the first two attempts taught me.

---

## Slide 13 — Lesson from the first attempt

**Title:** s8008: when "all tests pass" lies to you

**Body:**
> The monolithic version passed its whole simulation suite.
> On the FPGA, ALU operations returned garbage.
>
> - Single-cycle timing masked bugs simulation couldn't see
> - One 1,500-line file nobody — human or AI — could fully reason about
>
> **Rule adopted: nothing is "done" until it's proven on silicon.**

**Image:** None needed — or GATHER: photo of the Versa board with logic analyzer leads attached (the debugging reality).

**Notes:** This failure defined the whole methodology afterward: sim-pass is a hypothesis, hardware is the proof. The v8008 rewrite then failed differently — too clever, too entangled. Two failures, one diagnosis: complexity nobody could reason about.

---

## Slide 14 — Working with an AI, honestly

**Title:** The AI wrote most of the VHDL. Here's why that worked.

**Body:**
> It worked because I could tell when it was wrong.
>
> - I had to learn the 8008 cold: T-states, machine cycles, every ISA quirk
> - Built `isa.json` — a line-by-line mapping of **every opcode to its documented T-state sequence** — as ground truth
> - 28-test regression suite; cycle counts diffed against the datasheet automatically
>
> **The AI multiplied effort. The verification was the job.**

**Image:** GATHER: screenshot of a snippet of `docs/isa.json` next to the matching datasheet table — the "ground truth" visual.

**Notes:** The transferable lesson for this audience: AI collaboration shifts your work from writing to specifying and verifying. You must know enough to catch it being confidently wrong — and it will be. **Segue line: "So attempt #3 needed a design that a human AND an AI could each fully reason about. Turns out Intel drew it for us in 1972."**

---

# Act IV — The design the failures forced

## Slide 15 — The map: Intel's block diagram

**Title:** The fix: build Intel's own block diagram. Literally.

**Body:**
> (minimal text — let the diagram carry the slide)
>
> Attempt #3: **one module per block. No cleverness.**

**Image:** GATHER: block diagram scan from `docs/8008_1972.pdf` or `docs/8008UM.pdf` (extract page, clean up).

**Notes:** After two failures from complexity, the answer was radical simplicity: stop inventing an architecture and copy the one on the datasheet. Walk the diagram: address stack, scratchpad registers, ALU, instruction register/decoder, timing & control. Every box becomes a VHDL file.

---

## Slide 16 — The build: dumb modules

**Title:** Design rule: every module is dumb

**Body:**
> 29 VHDL files. Each block:
>
> - Does **one job**, ~50–100 lines
> - Knows **nothing** about instructions, interrupts, or other modules
> - Responds only to explicit control signals
> - Has its own testbench
>
> All the intelligence lives in one place: the timing & control unit.

**Image:** Module map graphic (draw in PowerPoint): control unit on top, control signals fanning out to stack / registers / ALU / decoder blocks. Mirror the Slide 15 diagram so the correspondence is visible.

**Notes:** Direct answer to the s8008 postmortem: when a module can't know about instructions, it can't harbor an instruction-specific bug. Debugging becomes: which control signal was wrong, and when? Also the AI payoff: a 70-line module with one job is something Claude gets right — and something I can fully review.

---

## Slide 17 — What a dumb module looks like

**Title:** The whole stack pointer. All of it.

**Body:**
```vhdl
if reset = '1' then
    sp <= (others => '0');
elsif rising_edge(clk) then
    if phi1_rising = '1' then
        if stack_push = '1' then
            sp <= sp + 1;   -- wraps 7 -> 0
        elsif stack_pop = '1' then
            sp <= sp - 1;   -- wraps 0 -> 7
        end if;
    end if;
end if;
```
> 69 lines including comments. It has never had a bug.

**Image:** Code as the visual (from `src/b8008/stack_pointer.vhdl`).

**Notes:** It doesn't know what CALL is. It doesn't know interrupts exist. It counts. CALL/RET/RST semantics — even the stack-wrap behavior from Weirdness #4 — emerge from structure, not from logic.

---

# Act V — How do I know it works?

## Slide 18 — The litmus test

**Title:** The real test suite was written in 1974

**Body:**
> Directed tests prove what you thought to test.
> **Period software proves the machine.**
>
> - SCELBI floating-point calculator (1974)
> - HEXPAWN — self-modifying learning game (1973)
> - STARS (Byte magazine, 1976)
> - Pi digit generator, Mandelbrot renderer
> - SCELBAL BASIC (1976)
>
> Each ported with a minimal, documented change ledger — I/O shims and memory-map constants only.

**Image:** GATHER: scan/photo of a SCELBI book cover or Byte May 1976 cover (adds period flavor).

**Notes:** If a self-modifying 1973 game and a floating-point interpreter both run, the CPU is right in ways no directed test can claim. This software exercised corners I'd never have thought to test.

---

## Slide 19 — Did it work?

**Title:** Verification scorecard

**Body:**
> | Check | Result |
> |-------|--------|
> | Regression suite | **28/28** |
> | Cycle-exact T-states vs datasheet (all 27 timing classes) | **27/27** |
> | Interrupt suite | **10/10** |
> | Hardware ISA self-test, running *on the board* | **46/46** |
> | Flags spec-exact (INR/DCR preserve carry; rotates carry-only) | ✓ |
> | Interrupts at instruction boundaries only (per User's Manual Fig. 2) | ✓ |

**Image:** Table is the visual. Optional: green terminal screenshot of `run_all_tests.sh` output — GATHER by running it.

**Notes:** "Cycle-exact" means: not just the right answer — the right answer in exactly the number of clock states the 1972 datasheet specifies, for every instruction class.

---

# Act VI — Live proof

## Slide 20 — The machine on the table

**Title:** The demo rig

**Body:**
> - Lattice **ECP5-5G Versa** board — the 8008, its clocks, ROM, RAM, UART, and all the SIM8-style glue, on one chip
> - Serial terminal: **115200 8N1** (it's 1976 over there: local echo off, DEL for rubout)
> - Machine monitor in ROM: **D**ump / **W**rite / **L**oad Intel HEX / **G**o
> - Front-panel DIP switches: interrupt injection, READY/WAIT
>
> Two personalities: boots-to-monitor, or boots-to-BASIC (the "tiny OS")

**Image:** GATHER: photo of your actual bench setup — board + laptop + minicom on screen. Take this photo before the talk.

**Notes:** Everything 1972 needed a rack for is inside the FPGA. The monitor is original firmware written for this project. Set up demos: minicom open, `send_hex.py` ready.

---

## Slide 21 — Demos (live)

**Title:** Live: 1970s software on the board

**Body:**
> 1. **Pi** — 50 digits via Machin's formula, multiprecision arithmetic (2013 program for SCELBI hardware)
> 2. **SCELBI Calculator (1974)** — 23-bit floating point: `12.2 X 2.2 = 26.84`
> 3. **HEXPAWN (1973)** — self-modifying code: it learns as it loses
> 4. **Finale — the tiny OS:** power on → BASIC → `MON` → monitor dumps the tokenized program from RAM → `G 1FB6` → back in BASIC, program intact

**Image:** None — switch to the terminal. Keep this slide up as the running order.

**Notes — demo cheat sheet (verify commands before talk):**
- Pi: `L` in monitor → send hex via `send_hex.py` → `G <entry>` (entry 0x0040). ~75 s at 500 kHz for 50 digits — narrate history while it grinds. 49/50 digits correct; the 50th is the *original program's* guard-byte truncation — great trivia beat.
- Calc: load, `G`, type `12.2 X 2.2 =` live.
- HEXPAWN: play 2 quick games, point out it stops making the losing move. **Drop candidate if running long.**
- Tiny OS: power-cycle board into the `b8008_basic` bitstream. Type a 3-line FOR/NEXT program, RUN, `MON`, `D` the program region, `G 1FB6`, `LIST` — program survived.
- Fallback: pre-record terminal captures of all four (GATHER: asciinema or QuickTime recordings) in case hardware misbehaves.

---

## Slide 22 — Takeaways

**Title:** What I'd tell you to steal

**Body:**
> - **Dumb modules, smart control** — structure beats cleverness; the block diagram was right all along
> - **Simulation passing is a hypothesis. Hardware is the proof.**
> - **AI pair programming works when you own the ground truth** — I specified and verified; it multiplied
> - **Old software is the best test suite** — it encodes assumptions no one thinks to write down
> - 1972 engineers did all of this with 3,500 transistors. Respect.

**Image:** None, or small board photo.

**Notes:** Close on the human point: the 8008's designers had no simulator, no regression suite, no second chances on a mask set.

---

## Slide 23 — Thanks / Q&A

**Title:** Questions?

**Body:**
> Robert Rico
>
> Project: github.com/<repo-url-here>
> SCELBAL: Jim Loos (jim11662418/8008-SBC) · Period software: Mike Willegal's SCELBI archive (willegal.net)
> Original SCELBAL: Arnold & Wadsworth, 1976
>
> *Board stays up after — come play with BASIC.*

**Image:** `docs/images/tiny_os_scelbal.png` small, corner.

**Notes:** Fill in real repo URL if/when public. Invite people to type at the machine — most memorable 8-bit demo is the one they drive.

---

# Image gather checklist

**Already in repo:**
- [x] `docs/images/tiny_os_scelbal.png` (slides 1, 2, 23)
- [x] `docs/two_phase_oscope_cap_1.png`, `_2.png` (slide 6)
- [x] `src/b8008/stack_pointer.vhdl` code snippet (slide 17)

**Extract from repo PDFs:**
- [ ] Intel block diagram page from `docs/8008_1972.pdf` or `docs/8008UM.pdf` (slide 15)
- [ ] Bus-timing diagram from datasheet (slide 7, optional)
- [ ] SIM8-01 schematic crop showing support-chip sprawl from `docs/SIM8_01_Schematic.pdf` (slide 8)

**Gather externally:**
- [ ] Intel C8008 chip photo — Wikimedia Commons, CC (slide 3)
- [ ] Datapoint 2200 photo — Wikimedia Commons (slide 4)
- [ ] TMX 1795 die photo — Ken Shirriff's blog, ask/attribute (slide 4, optional)
- [ ] SCELBI-8H photo — willegal.net, attribute (slide 5, optional)
- [ ] Generic FPGA fabric diagram (slide 10) — or draw in PowerPoint
- [ ] SCELBI book cover / Byte May 1976 cover scan (slide 18, optional)

**Produce yourself before talk:**
- [ ] Bench photo: Versa board + laptop + minicom (slide 20) — also candidate for slide 1
- [ ] Screenshot of `run_all_tests.sh` green output (slide 19, optional)
- [ ] `isa.json` snippet next to datasheet table screenshot (slide 14)
- [ ] **Fallback recordings of all four demos** (slide 21 insurance)

**Draw in PowerPoint:**
- [ ] x86 lineage graphic (slide 5)
- [ ] PC-in-stack 8-slot diagram with SP arrow (slide 9)
- [ ] 3-attempt timeline with two ✗ (slide 12)
- [ ] b8008 module map mirroring Intel diagram (slide 16)
- [ ] Verilog-vs-VHDL counter snippet boxes (slide 11)
