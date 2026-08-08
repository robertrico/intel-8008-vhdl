# External bus-protocol monitor for b8008_top (VPLAN Tier1-4; the
# assertion tables live in docs/BUS_PROTOCOL.md).
#
# Whole-system run: the Python testbench serves the ROM through the
# external ROM port, boots the CPU with the bootstrap RST-0 jam, then
# checks the external bus at every (T-state, half) against independent
# references:
#   - state codes always decode to one of the 8 datasheet values (ST-01
#     system half)
#   - T1 first half: D7..D0 = low address byte - debug_pc for
#     PC-addressed cycles, REG.L for H:L data cycles, REG.A for I/O
#     cycles (BUS-01, BUS-10/11, INP/OUT T1)
#   - T2 first half: D6/D7 = cycle code predicted by the golden decoder
#     model from the IR (BUS-02/03 external half, BUS-07: cycle 1 always
#     PCI), D5..D0 = high address (pre-carry per the SQ-07 ruling) or
#     REG.H[5:0] for H:L cycles; PCC T2 drives the instruction register
#     byte (whose top bits ARE the PCC code)
#
#   - INP T4: the condition flip-flops on the bus, S->D0 Z->D1 P->D2
#     C->D3 (DS72 p.37 "COND FF OUT" - FLG-13's bus half)
#   - PCW T3: the write data on the bus - source register for MOV M,r,
#     the fetched immediate for MVI M (BUS-05's write half)
#   - READY is held high for the whole run, so WAIT must never appear
#     (RDY-01)
#
# Together the T1/T2/T3/T4 full-byte checks also close BUS-04: every
# CPU-driven state's D6/D7 are pinned to address/data/flag content -
# the cycle code exists ONLY at T2.
#
# Known residuals (documented, not asserted): BUS-09 bus-float is not
# modeled at this sim top; the
# T1I address emission (INT-02 double-address) is masked here because
# the top-level jam mux drives the interrupt byte onto the bus for the
# whole T1I cycle - covered behaviorally by check_jam_test.sh instead.

import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, NextTimeStep

from test_instruction_decoder import golden
from test_memory_io_control import cycle_types, data_cycle

REPO = os.path.join(os.path.dirname(__file__), "..", "..")

PCI, PCR, PCC, PCW = 0, 1, 2, 3


def _isa_state_table():
    """opcode -> (states_taken, states_not_taken|None) from docs/isa.json."""
    with open(os.path.join(REPO, "docs", "isa.json")) as f:
        isa = json.load(f)
    table, spec = {}, {}
    for ins in isa["instructions"]:
        pat = ins["D[7:0]"].replace(" ", "")
        st = ins["num_states_execution"]
        nt = ins.get("num_states_not_taken")
        literals = sum(1 for p in pat if p in "01")
        for op in range(256):
            bits = f"{op:08b}"
            # '0'/'1' are literal; letters and 'X' are wildcards. The
            # MOST SPECIFIC matching pattern wins (e.g. 11111111 HLT
            # beats 11DDDDSS MOV r,r; 11DDD111 LrM beats it too).
            if all(p not in "01" or p == b for p, b in zip(pat, bits)) \
               and literals > spec.get(op, -1):
                table[op] = (st, nt)
                spec[op] = literals
    return table


ISA_STATES = _isa_state_table()

STATE_CODES = {  # (s0, s1, s2) -> name
    (0, 1, 0): "T1", (0, 1, 1): "T1I", (0, 0, 1): "T2", (0, 0, 0): "WAIT",
    (1, 0, 0): "T3", (1, 1, 0): "STOPPED", (1, 1, 1): "T4", (1, 0, 1): "T5",
}


def load_mem(name):
    path = os.path.join(REPO, "test_programs", name)
    with open(path) as f:
        return [int(line.strip(), 16) for line in f if line.strip()]


async def rom_server(dut, mem):
    """Serve ROM bytes combinationally-enough (one clk of latency is
    fine: the bus is sampled mid-T-state, many clks later)."""
    while True:
        await RisingEdge(dut.clk_in)
        addr = dut.rom_a.value.integer & 0x1FFF
        dut.rom_d.value = mem[addr] if addr < len(mem) else 0


async def boot(dut):
    dut.reset.value = 1
    dut.interrupt.value = 0
    dut.ready_in.value = 1
    dut.int_instruction.value = 0x05
    dut.io_port_in.value = 0
    dut.io_port_in_select.value = 0
    dut.io_port_in_enable.value = 0
    for _ in range(20):
        await RisingEdge(dut.clk_in)
    dut.reset.value = 0
    for _ in range(10):
        await RisingEdge(dut.clk_in)
    dut.interrupt.value = 1
    # wait for T1I
    while True:
        await RisingEdge(dut.clk_in)
        s = (int(dut.s0_out.value), int(dut.s1_out.value), int(dut.s2_out.value))
        if STATE_CODES.get(s) == "T1I":
            break
    for _ in range(5):
        await RisingEdge(dut.clk_in)
    dut.interrupt.value = 0


async def run_monitor(dut, rom_name, max_ms=40):
    return await run_monitor_mem(dut, load_mem(rom_name), max_ms=max_ms)


async def run_monitor_mem(dut, mem, max_ms=40, timing=False, trace=None,
                          tag="", min_checks=50):
    """Core monitor loop. Spawned tasks (clock, ROM server) are killed
    on exit so the fuzzer can call this repeatedly in one test.
    `timing=True` adds the per-instruction oracle:
    every instruction window's T-state count must equal the isa.json
    value FOR ITS OUTCOME (branch outcome inferred from the next fetch
    address), and non-branch instructions must advance PC by exactly
    their encoded length. `trace` (a list) collects one record per
    machine cycle plus a final register trailer - the differential
    fuzzer diffs these between the rtl and netlist cores."""
    t_clk = cocotb.start_soon(Clock(dut.clk_in, 10, "ns").start())
    t_rom = cocotb.start_soon(rom_server(dut, mem))
    try:
        return await _monitor_body(dut, mem, max_ms, timing, trace, tag,
                                   min_checks)
    finally:
        t_clk.kill()
        t_rom.kill()
        await NextTimeStep()


async def _monitor_body(dut, mem, max_ms, timing, trace, tag, min_checks):
    await boot(dut)

    errors = []
    checked = {"t1": 0, "t2": 0, "codes": 0, "flags": 0, "wr": 0, "win": 0}
    prev_key = None
    settle = 0   # clks remaining until the current window's check fires

    # Timing-oracle window bookkeeping. A window = one instruction.
    # Boundary detection counts T1 entries against the opcode's cycle
    # count (outcome-INDEPENDENT: not-taken conditionals still run all
    # their cycles, just truncated ones) - immune to the mid-T1
    # debug_cycle update race that the T1 value checks tolerate.
    prev_name = None
    win_states = 0        # state entries in the current window
    win_t1s = 0           # T1 entries in the current window
    win_start_pc = None   # fetch address of the window's instruction
    win_open = False
    pending = None        # closed window awaiting next-fetch-addr: (op, states, pc)

    def _n_cycles(op):
        g = golden(op)
        return 1 + (1 if (g["instr_needs_immediate"] or
                          g["instr_needs_address"]) else 0) \
                 + (1 if g["instr_needs_address"] else 0)

    def _length(op):
        """Instruction BYTE length (the decoder's needs_immediate /
        needs_address are cycle-structure flags: LrM is 1 byte but 2
        cycles, LMI 2 bytes but 3 cycles)."""
        if (op & 0xC7) in (0x06, 0x04):        # MVI r/M, ALU immediate
            return 2
        if (op & 0xC0) == 0x40 and (op & 1) == 0:   # JMP/Jcc/CAL/Ccc
            return 3
        return 1

    def _validate(op, states, start_pc, next_pc):
        exp = ISA_STATES.get(op)
        if exp is None or op in (0x00, 0x01, 0xFF):
            return
        fallthrough = (start_pc + _length(op)) & 0x3FFF
        st, nt = exp
        is_jump3 = (op & 0xC0) == 0x40 and (op & 1) == 0   # JMP/Jcc/CAL/Ccc
        is_ret = (op & 0xC7) == 0x07 or (op & 0xE7) in (0x03, 0x23)
        is_rst = (op & 0xC7) == 0x05
        conditional = nt is not None

        wants = None   # acceptable state counts
        if is_jump3:
            # Jump-target oracle: the operand bytes are in mem
            target = (mem[(start_pc + 1) & 0x3FFF] |
                      mem[(start_pc + 2) & 0x3FFF] << 8) & 0x3FFF
            if not conditional:
                if next_pc != target:
                    errors.append(f"{tag}jump target IR={op:02X} "
                                  f"@{start_pc:04X}: next fetch {next_pc:04X}, "
                                  f"want {target:04X}")
                wants = (st,)
            else:
                if next_pc not in (target, fallthrough):
                    errors.append(f"{tag}jump target IR={op:02X} "
                                  f"@{start_pc:04X}: next fetch {next_pc:04X}, "
                                  f"want {target:04X} or {fallthrough:04X}")
                if target == fallthrough:
                    wants = (st, nt)   # outcome unobservable from PC
                else:
                    wants = (st,) if next_pc == target else (nt,)
        elif is_ret:
            # Return address unknown to the oracle; ambiguous only when
            # the CPU lands on the fallthrough
            if conditional:
                wants = (st, nt) if next_pc == fallthrough else (st,)
            else:
                wants = (st,)
        elif is_rst:
            if next_pc != (op & 0x38):
                errors.append(f"{tag}RST target IR={op:02X} @{start_pc:04X}: "
                              f"next fetch {next_pc:04X}, want {op & 0x38:04X}")
            wants = (st,)
        else:
            if next_pc != fallthrough:
                errors.append(f"{tag}PC advance IR={op:02X} @{start_pc:04X}: "
                              f"next fetch {next_pc:04X}, want {fallthrough:04X}")
            wants = (st,)

        if states not in wants:
            errors.append(f"{tag}timing IR={op:02X} @{start_pc:04X}: "
                          f"{states} states, want {'/'.join(map(str, wants))}")
        checked["win"] += 1

    max_cycles = max_ms * 100_000  # 10 ns clk
    for _ in range(max_cycles):
        await RisingEdge(dut.clk_in)
        await ReadOnly()

        s = (int(dut.s0_out.value), int(dut.s1_out.value), int(dut.s2_out.value))
        name = STATE_CODES.get(s)
        if name is None:
            errors.append(f"invalid state code S0S1S2={s}")
            await NextTimeStep()
            continue

        if name == "STOPPED":
            await NextTimeStep()   # leave ReadOnly before caller writes
            break  # program finished (HLT)

        if name == "WAIT":
            # READY is tied high for the whole run (RDY-01)
            errors.append("WAIT status observed with READY held high")
            await NextTimeStep()
            continue

        half = int(dut.debug_state_half.value)
        if name != prev_name:
            prev_name = name
            if timing and name == "T1":
                ir_now = int(dut.debug_ir.value)
                if os.environ.get("FUZZ_DEBUG"):
                    dut._log.info(f"T1entry ir={ir_now:02X} t1s={win_t1s} "
                                  f"ncyc={_n_cycles(ir_now)} states={win_states} "
                                  f"pc={int(dut.debug_pc.value):04X}")
                if win_open and win_t1s >= _n_cycles(ir_now):
                    # This T1 opens the NEXT instruction's window
                    pending = (ir_now, win_states, win_start_pc)
                    win_states = 0
                    win_t1s = 0
                    win_start_pc = None
                win_t1s += 1
                win_open = True
            if win_open and name not in ("WAIT",):
                win_states += 1
            if trace is not None and name in ("T1", "T1I"):
                trace.append({"s": name})
        key = (name, half)
        if key != prev_key:
            prev_key = key
            # Check 60 clks (0.6us) into each (state, half0) window: past
            # the cycle-type latch (which waits for the phi1 edge ~0.4us
            # into the state) and the address-latch capture, well before
            # any second-half increment. T1I is skipped (jam mux masks
            # bus - see header).
            settle = 60 if (half == 0 and name in ("T1", "T2", "T3", "T4")) else 0
            await NextTimeStep()
            continue
        if settle == 0:
            await NextTimeStep()
            continue
        settle -= 1
        if settle != 0:
            await NextTimeStep()
            continue

        # Steady references
        ir = int(dut.debug_ir.value)
        g = golden(ir)
        cyc = int(dut.debug_cycle.value)
        n_cycles = 1 + (1 if (g["instr_needs_immediate"] or g["instr_needs_address"]) else 0) \
                     + (1 if g["instr_needs_address"] else 0)
        types = cycle_types(g, n_cycles)
        dcyc = data_cycle(g, n_cycles)
        data = int(dut.data_out.value)
        pc = int(dut.debug_pc.value)

        if name == "T1":
            # Early sample: the counter still shows the PREVIOUS cycle;
            # infer the entered cycle the way the hardware does
            # (machine_cycle_control's next_cycle formula).
            needs2 = g["instr_needs_immediate"] or g["instr_needs_address"]
            needs3 = g["instr_needs_address"]
            if cyc == 0 and needs2:
                entering = 1
            elif cyc == 1 and needs3:
                entering = 2
            else:
                entering = 0
            if timing and win_start_pc is None:
                # First T1 check of this window: pc is the fetch address;
                # it also settles the previous window's branch outcome
                win_start_pc = pc
                if pending is not None:
                    _validate(*pending, next_pc=pc)
                    pending = None
            if entering == 0 or entering != dcyc:
                # PC-addressed (fetch/immediate/address cycles)
                want = pc & 0xFF
                what = "PC low"
            elif types[entering] == PCC:
                want = int(dut.debug_reg_a.value)
                what = "REG.A"
            else:
                want = int(dut.debug_reg_l.value)
                what = "REG.L"
            if data != want:
                errors.append(f"{tag}{name} entering cyc{entering} IR={ir:02X}: "
                              f"D={data:02X} want {what}={want:02X} (PC={pc:04X})")
            checked["t1"] += 1
            if trace is not None:
                trace.append({"t1": data})

        elif name == "T2":
            code = (data >> 6) & 3  # D7 D6
            # cycle code encoding on D6/D7: PCI=00 PCR=01(D7=1? see below)
            # DS72: PCI D6=0 D7=0; PCR D6=0 D7=1; PCC D6=1 D7=0; PCW both.
            code_d6 = (data >> 6) & 1
            code_d7 = (data >> 7) & 1
            expected = types[cyc] if cyc < len(types) else None
            exp_bits = {PCI: (0, 0), PCR: (0, 1), PCC: (1, 0), PCW: (1, 1)}[expected] \
                if expected is not None else None
            if cyc == 0 and (code_d6, code_d7) != (0, 0):
                errors.append(f"T2 cyc0 IR={ir:02X}: cycle code D6D7="
                              f"{code_d6}{code_d7}, cycle 1 must be PCI")
            elif exp_bits is not None and (code_d6, code_d7) != exp_bits:
                errors.append(f"T2 cyc{cyc} IR={ir:02X}: cycle code D6D7="
                              f"{code_d6}{code_d7} want {exp_bits}")
            checked["codes"] += 1

            if cyc != 0 and types[cyc] == PCC:
                # DS72: the instruction register byte is on the bus at
                # PCC T2 (its top bits are the PCC code)
                if data != ir:
                    errors.append(f"PCC T2: D={data:02X} want IR={ir:02X}")
            elif cyc == dcyc and cyc != 0:
                want_h = int(dut.debug_reg_h.value) & 0x3F
                if (data & 0x3F) != want_h:
                    errors.append(f"T2 H:L cyc{cyc} IR={ir:02X}: D[5:0]="
                                  f"{data & 0x3F:02X} want REG.H[5:0]={want_h:02X}")
            else:
                # PC-addressed: high 6 address bits, pre-carry (SQ-07)
                want_h = (pc >> 8) & 0x3F
                if (data & 0x3F) != want_h:
                    errors.append(f"{tag}T2 cyc{cyc} IR={ir:02X}: D[5:0]="
                                  f"{data & 0x3F:02X} want PC high={want_h:02X}")
            checked["t2"] += 1
            if trace is not None:
                trace.append({"t2": data})

        elif name == "T3":
            if cyc == dcyc and cyc < len(types) and types[cyc] == PCW:
                # PCW T3: the CPU drives the write data (BUS-05 write half)
                if (ir & 0xF8) == 0xF8 and (ir & 7) != 7:
                    # MOV M,r (LMr): source register SSS
                    regs = [dut.debug_reg_a, dut.debug_reg_b, dut.debug_reg_c,
                            dut.debug_reg_d, dut.debug_reg_e, dut.debug_reg_h,
                            dut.debug_reg_l]
                    want = int(regs[ir & 7].value)
                    what = f"REG[{ir & 7}]"
                elif ir == 0x3E:
                    # MVI M (LMI): the immediate fetched in cycle 2 - PC
                    # already points past it
                    want = mem[(pc - 1) & 0x3FFF] if ((pc - 1) & 0x3FFF) < len(mem) else 0
                    what = "imm byte"
                else:
                    want = None
                if want is not None:
                    if data != want:
                        errors.append(f"{tag}PCW T3 IR={ir:02X}: D={data:02X} "
                                      f"want {what}={want:02X}")
                    checked["wr"] += 1
                    if trace is not None:
                        trace.append({"t3w": data})

        elif name == "T4":
            if cyc < len(types) and types[cyc] == PCC and g["instr_writes_reg"]:
                # INP T4: condition flip-flops out (DS72 p.37 order)
                want = ((int(dut.debug_flag_carry.value) << 3)
                        | (int(dut.debug_flag_parity.value) << 2)
                        | (int(dut.debug_flag_zero.value) << 1)
                        | int(dut.debug_flag_sign.value))
                if data != want:
                    errors.append(f"INP T4 flags: D={data:02X} want {want:02X} "
                                  f"(C={int(dut.debug_flag_carry.value)}"
                                  f"Z={int(dut.debug_flag_zero.value)}"
                                  f"S={int(dut.debug_flag_sign.value)}"
                                  f"P={int(dut.debug_flag_parity.value)})")
                checked["flags"] += 1

        await NextTimeStep()

    if trace is not None:
        trace.append({"regs": [int(r.value) for r in
                               (dut.debug_reg_a, dut.debug_reg_b,
                                dut.debug_reg_c, dut.debug_reg_d,
                                dut.debug_reg_e, dut.debug_reg_h,
                                dut.debug_reg_l)],
                      "flags": [int(dut.debug_flag_carry.value),
                                int(dut.debug_flag_zero.value),
                                int(dut.debug_flag_sign.value),
                                int(dut.debug_flag_parity.value)],
                      "ram0": int(dut.ram_byte_0.value)})
    assert checked["t1"] >= min_checks and checked["t2"] >= min_checks, \
        f"{tag}monitor barely ran: {checked}"
    for e in errors[:20]:
        dut._log.error(e)
    assert not errors, \
        f"{tag}{len(errors)} bus-protocol violations (first 20 logged)"
    dut._log.info(f"{tag}bus monitor clean: {checked}")
    return checked


@cocotb.test()
async def bus_protocol_memory_alu(dut):
    """PCI + PCR-immediate + PCR-H:L + PCW coverage."""
    await run_monitor(dut, "memory_alu_test_as.mem")


@cocotb.test()
async def bus_protocol_io(dut):
    """PCC coverage (INP/OUT): REG.A at T1, IR byte at T2."""
    await run_monitor(dut, "io_test_as.mem")


@cocotb.test()
async def bus_protocol_mem_write(dut):
    """PCW T3 write-data coverage: MOV M,r source register."""
    checked = await run_monitor(dut, "mov_mem_test_as.mem")
    assert checked["wr"] > 0, "no PCW T3 write ever checked"


@cocotb.test()
async def bus_protocol_mem_write_imm(dut):
    """PCW T3 write-data coverage: MVI M immediate byte."""
    checked = await run_monitor(dut, "mvi_m_test_as.mem")
    assert checked["wr"] > 0, "no PCW T3 write ever checked"
