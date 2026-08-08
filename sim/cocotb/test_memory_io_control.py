# Scenario tests for memory_io_control: walk whole instructions through
# their (cycle, T-state, half) sequences and check every control strobe.
#
# Ground truth is deliberately NOT the VHDL: state sequences come from
# docs/isa.json, decoder inputs from the golden() model in
# test_instruction_decoder.py, and the expected strobes from the isa.json
# per-state actions. The driver emulates what state_timing_generator and
# machine_cycle_control feed the DUT:
#   - states advance every phi1, two halves per T-state
#   - the cycle counter updates at the end of T1's first half, so
#     T1-half0 still shows the previous cycle number and next_cycle
#     predicts the new one (this makes the next_cycle-gated windows,
#     H:L and REG.A output, first-half-only by construction)
#   - decoder flags are zero during the fetch cycle until the IR loads
#     at T3 (they describe the previous instruction there; the driver
#     uses a neutral zero like a post-reset core)
#   - advance_state rises at the end of the final cycle
#
# Risk focus per the module: suppress_pc_inc_next_cycle (PC must not
# advance in H:L / I/O data cycles) and the H:L output windows (REG.L /
# REG.H to the data bus at T1/T2 of memory-indirect data cycles).

import json
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, NextTimeStep

from test_instruction_decoder import golden

ISA_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "isa.json")

T1, T2, T3, T4, T5, T1I = "T1", "T2", "T3", "T4", "T5", "T1I"

PCI, PCR, PCC, PCW = 0, 1, 2, 3

with open(ISA_PATH) as _f:
    _ISA = json.load(_f)["instructions"]


def isa_entry(op):
    """isa.json instruction matching opcode op (most literal bits wins,
    since patterns like 11DDDSSS also cover the more specific 11DDD111)."""
    best, best_score = None, -1
    for ins in _ISA:
        coding = ins["coding"]
        score = 0
        for bit in range(8):
            want = coding[f"D{bit}"]
            if want in ("0", "1"):
                if int(want) != ((op >> bit) & 1):
                    score = None
                    break
                score += 1
        if score is not None and score > best_score:
            best, best_score = ins, score
    if best is None:
        raise ValueError(f"no isa.json entry matches 0x{op:02X}")
    return best


def states_for(ins, cycle_idx, cond_taken=True):
    """T-state list for one cycle, honoring skips and conditionals."""
    cyc = ins[f"cycle_{cycle_idx + 1}"]
    states = [T1, T2, T3]
    for t in (T4, T5):
        action = cyc[t]
        if action and action.lower() != "skip":
            states.append(t)
    # Conditionals drop their T4/T5 tail when not taken
    # (machine_cycle_control gates needs_t4t5 on condition_met in the
    # first and last cycles).
    if not cond_taken and cycle_idx in (0, ins["num_cycles"] - 1):
        states = [T1, T2, T3]
    return states


def cycle_types(g, num_cycles):
    """cycle_type per cycle, mirroring the 8008 bus-status encoding."""
    types = [PCI]
    for c in range(1, num_cycles):
        if g["instr_is_io"]:
            types.append(PCC)
        elif g["instr_is_write"] and (
            (c == 1 and not g["instr_needs_address"])
            or (c == 2 and g["instr_needs_address"])
        ):
            types.append(PCW)
        else:
            types.append(PCR)
    return types


def data_cycle(g, num_cycles):
    """Index of the cycle addressed via H:L or the I/O port (PC unused),
    or None. This is the cycle whose T1 must NOT increment the PC."""
    if g["instr_is_io"]:
        return 1
    if g["instr_is_mem_indirect"]:
        # LMI's cycle 2 fetches the immediate via PC; H:L is cycle 3
        return 2 if g["instr_needs_address"] else 1
    return None


ZERO_DECODE = {k: 0 for k in golden(0xC0)}

DECODE_PORTS = [
    "instr_needs_immediate", "instr_needs_address", "instr_is_io",
    "instr_is_write", "instr_is_alu", "instr_is_call", "instr_is_ret",
    "instr_is_rst", "instr_writes_reg", "instr_reads_reg",
    "instr_is_mem_indirect", "eval_condition",
]


class Driver:
    """Feeds the DUT the same input timeline the real core produces."""

    def __init__(self, dut):
        self.dut = dut

    async def reset(self):
        d = self.dut
        d.reset.value = 1
        d.phi1_rising.value = 1
        self.apply_decode(ZERO_DECODE, cond_met=False)
        for name in (
            "state_t1", "state_t2", "state_t3", "state_t4", "state_t5",
            "state_t1i", "state_stopped", "state_half",
            "status_s0", "status_s1", "status_s2",
            "advance_state",
            "interrupt_pending", "ready_status", "pc_carry_in",
        ):
            getattr(d, name).value = 0
        d.cycle_type.value = 0
        d.current_cycle.value = 0
        d.next_cycle.value = 0
        for _ in range(2):
            await RisingEdge(d.clk)
        d.reset.value = 0
        await RisingEdge(d.clk)

    def apply_decode(self, g, cond_met):
        d = self.dut
        for name in DECODE_PORTS:
            getattr(d, name).value = g[name]
        d.instr_sss_field.value = g["instr_sss_field"]
        d.instr_ddd_field.value = g["instr_ddd_field"]
        d.condition_met.value = 1 if cond_met else 0

    async def half_step(self, state, half, cur, nxt, ctype, advance):
        """One phi1 clk: one half of one T-state."""
        d = self.dut
        for s in (T1, T2, T3, T4, T5):
            getattr(d, f"state_{s.lower()}").value = 1 if state == s else 0
        d.state_t1i.value = 1 if state == T1I else 0
        d.state_half.value = half
        d.current_cycle.value = cur
        d.next_cycle.value = nxt
        d.cycle_type.value = ctype
        d.advance_state.value = advance
        await RisingEdge(d.clk)


def next_of(cycle_count, g, flags_live):
    """machine_cycle_control's next_cycle formula."""
    if not flags_live:
        return 0
    needs2 = g["instr_needs_immediate"] or g["instr_needs_address"]
    needs3 = g["instr_needs_address"]
    if cycle_count == 0 and needs2:
        return 1
    if cycle_count == 1 and needs3:
        return 2
    return 0


async def run_instruction(dut, drv, op, cond_met=True, label=""):
    g = golden(op)
    ins = isa_entry(op)
    num_cycles = ins["num_cycles"]
    taken = (not g["eval_condition"]) or cond_met
    types = cycle_types(g, num_cycles)
    dcyc = data_cycle(g, num_cycles)

    flags_live = False  # decoder shows the previous (neutral) instruction
    drv.apply_decode(ZERO_DECODE, cond_met=False)

    for c in range(num_cycles):
        states = states_for(ins, c, cond_taken=taken)
        last_cycle = c == num_cycles - 1
        for st in states:
            for half in (0, 1):
                # IR loads during T3 half0 of the fetch; flags valid half1
                if c == 0 and st == T3 and half == 1 and not flags_live:
                    flags_live = True
                    drv.apply_decode(g, cond_met)

                if st == T1 and half == 0:
                    cur = c - 1 if c > 0 else 0
                else:
                    cur = c
                nxt = next_of(cur, g, flags_live)
                adv = 1 if (last_cycle and st in (T3, T4, T5)
                            and not (st == T3 and half == 0)) else 0

                await drv.half_step(st, half, cur, nxt, types[c], adv)
                await ReadOnly()
                o = snapshot(dut)
                o.update(cycle=c, state=st, half=half,
                         label=label or f"0x{op:02X}")
                check_expectations(o, g, c, st, half, types[c], dcyc, taken)
                await NextTimeStep()


OUT_STROBES = [
    "ir_load", "ir_output_enable", "io_buffer_enable", "io_buffer_direction",
    "scratchpad_read", "scratchpad_write", "memory_read", "memory_write",
    "regfile_to_bus", "bus_to_regfile",
    "pc_load_from_regs", "pc_load_from_rst",
    "stack_push", "stack_pop",
    "pc_increment_lower", "pc_increment_upper", "pc_load",
]


def snapshot(dut):
    o = {name: int(getattr(dut, name).value) for name in OUT_STROBES}
    o["scratchpad_select"] = int(dut.scratchpad_select.value)
    return o


def check_expectations(o, g, c, st, half, ctype, dcyc, taken):
    where = f"{o['label']} cycle{c + 1} {st} half{half}"

    # --- PC increment: T1 second half only, and never in a data cycle
    want_inc = 1 if (st == T1 and half == 1 and c != dcyc) else 0
    assert o["pc_increment_lower"] == want_inc, (
        f"{where}: pc_increment_lower={o['pc_increment_lower']} want {want_inc}")

    # --- H:L address windows in the memory-indirect data cycle:
    #     T1 is gated by next_cycle, so it is first-half-only; T2 is
    #     gated by current_cycle and covers the whole state.
    if c == dcyc and not g["instr_is_io"]:
        if (st == T1 and half == 0) or st == T2:
            assert o["scratchpad_read"] and o["regfile_to_bus"], (
                f"{where}: H:L window must read the register file to the bus")
            assert o["io_buffer_enable"] and o["io_buffer_direction"] == 1, (
                f"{where}: H:L window must drive the external bus")

    # --- I/O cycle 2: REG.A out at T1 (first half), port byte out at T2
    if c == dcyc and g["instr_is_io"]:
        if st == T1 and half == 0:
            assert o["scratchpad_select"] == 0 and o["scratchpad_read"], (
                f"{where}: I/O T1 must put REG.A on the bus")
        if (st == T1 and half == 0) or st == T2:
            assert o["io_buffer_enable"] and o["io_buffer_direction"] == 1, (
                f"{where}: I/O T1/T2 must drive the external bus")

    # --- T3 strobes by cycle type
    if st == T3:
        if ctype == PCI:
            assert o["memory_read"] and o["io_buffer_enable"], (
                f"{where}: fetch must read memory")
            assert o["ir_load"] == 1, f"{where}: fetch must load IR"
        elif ctype == PCR:
            assert o["memory_read"] and not o["memory_write"], (
                f"{where}: PCR must read memory")
        elif ctype == PCW:
            assert o["memory_write"] and not o["memory_read"], (
                f"{where}: PCW must write memory")
            assert o["io_buffer_direction"] == 1, f"{where}: PCW drives outward"
        elif ctype == PCC:
            assert o["io_buffer_enable"], f"{where}: PCC must enable I/O buffer"

    # --- stack pointer motion
    want_push = 1 if (
        (g["instr_is_rst"] and c == 0 and st == T4 and half == 0)
        or (g["instr_is_call"] and taken and c == 2 and st == T4 and half == 1)
    ) else 0
    want_pop = 1 if (
        g["instr_is_ret"] and taken and c == 0 and st == T4 and half == 0
    ) else 0
    assert o["stack_push"] == want_push, (
        f"{where}: stack_push={o['stack_push']} want {want_push}")
    assert o["stack_pop"] == want_pop, (
        f"{where}: stack_pop={o['stack_pop']} want {want_pop}")

    # --- PC loads
    is_jmp_call = g["instr_needs_address"] and not g["instr_is_write"]
    want_pc_load = 1 if st == T5 and (
        (is_jmp_call and c == 2 and taken) or g["instr_is_rst"]
    ) else 0
    assert o["pc_load"] == want_pc_load, (
        f"{where}: pc_load={o['pc_load']} want {want_pc_load}")
    if st == T5 and is_jmp_call and c == 2:
        assert o["pc_load_from_regs"] == 1, (
            f"{where}: JMP/CALL T5 must select temp regs as PC source")
    if st == T5 and g["instr_is_rst"]:
        assert o["pc_load_from_rst"] == 1, (
            f"{where}: RST T5 must select the RST vector as PC source")

    # --- register writeback at T5 (I/O checked separately: INP writes A)
    if st == T5 and g["instr_writes_reg"] and not g["instr_is_io"]:
        if (c == 0 and not g["instr_needs_immediate"]) or (
            c == 1 and g["instr_needs_immediate"]
        ):
            assert o["scratchpad_write"] and o["bus_to_regfile"], (
                f"{where}: T5 must write the destination register")
            assert o["scratchpad_select"] == g["instr_ddd_field"], (
                f"{where}: T5 writeback selects DDD")


# --------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------

SCENARIOS = [
    # label, opcode, cond_met
    ("MOV A,B", 0xC1, True),
    ("ADD B", 0x81, True),
    ("CPr B", 0xB9, True),
    ("MVI B", 0x0E, True),
    ("ADI", 0x04, True),
    ("ADD M", 0x87, True),
    ("MOV A,M (LrM)", 0xC7, True),
    ("MOV M,B (LMr)", 0xF9, True),
    ("MVI M (LMI)", 0x3E, True),
    ("INP 0", 0x41, True),
    ("OUT 8", 0x51, True),
    ("JMP", 0x44, True),
    ("CAL", 0x46, True),
    ("JFC taken", 0x40, True),
    ("JFC not taken", 0x40, False),
    ("CFC taken", 0x42, True),
    ("CFC not taken", 0x42, False),
    ("RET", 0x07, True),
    ("RFC taken", 0x03, True),
    ("RFC not taken", 0x03, False),
    ("RST 1", 0x0D, True),
]


@cocotb.test()
async def instruction_scenarios(dut):
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    drv = Driver(dut)
    for label, op, cond in SCENARIOS:
        await drv.reset()
        await run_instruction(dut, drv, op, cond_met=cond, label=label)


@cocotb.test()
async def interrupt_jam_suppresses_fetch_ir_load(dut):
    """T1I loads the IR in its second half; the following fetch-shaped
    T3 must NOT reload the IR (the instruction was jammed)."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    drv = Driver(dut)
    await drv.reset()
    g = golden(0x0D)  # RST 1, the classic jammed instruction
    drv.apply_decode(g, cond_met=True)

    async def step(state, half, adv=0):
        await drv.half_step(state, half, 0, 0, PCI, adv)

    # T1I first half: no IR load yet
    await step(T1I, 0)
    await ReadOnly()
    assert int(dut.ir_load.value) == 0, "T1I half0 must not load IR"
    await NextTimeStep()

    # T1I second half: IR load from the jammed bus
    await step(T1I, 1)
    await ReadOnly()
    assert int(dut.ir_load.value) == 1, "T1I half1 must load the jammed IR"
    assert int(dut.io_buffer_enable.value) == 1
    assert int(dut.io_buffer_direction.value) == 0, "T1I reads external bus"
    await NextTimeStep()

    # The interrupt cycle continues T2/T3: T3 is fetch-shaped (PCI) but
    # the IR was already jammed, so ir_load must stay low.
    for st, half in ((T2, 0), (T2, 1), (T3, 0), (T3, 1)):
        await step(st, half)
        await ReadOnly()
        assert int(dut.ir_load.value) == 0, (
            f"{st} half{half}: IR reload after T1I jam must be suppressed")
        await NextTimeStep()

    # RST executes T4/T5; the jam flag clears after T4...
    for st, half in ((T4, 0), (T4, 1), (T5, 0), (T5, 1)):
        await step(st, half, adv=1 if st == T5 else 0)
        await NextTimeStep()

    # ...so the next real fetch loads the IR again.
    drv.apply_decode(ZERO_DECODE, cond_met=False)
    for st, half in ((T1, 0), (T1, 1), (T2, 0), (T2, 1)):
        await step(st, half)
        await NextTimeStep()
    await step(T3, 0)
    await ReadOnly()
    assert int(dut.ir_load.value) == 1, "next real fetch must reload the IR"
    await NextTimeStep()


@cocotb.test()
async def stopped_blocks_ir_load(dut):
    """A halted CPU must not load the IR even in a fetch-shaped T3."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    drv = Driver(dut)
    await drv.reset()
    dut.state_stopped.value = 1
    await drv.half_step(T3, 0, 0, 0, PCI, 0)
    await ReadOnly()
    assert int(dut.ir_load.value) == 0, "stopped CPU must not load IR"
    await NextTimeStep()


@cocotb.test()
async def pc_upper_increment_follows_carry(dut):
    """T2 second half increments the upper PC byte iff the lower byte
    wrapped at T1 (pc_carry_in)."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    drv = Driver(dut)
    await drv.reset()

    for carry in (0, 1):
        dut.pc_carry_in.value = carry
        for st, half in ((T1, 0), (T1, 1), (T2, 0), (T2, 1)):
            await drv.half_step(st, half, 0, 0, PCI, 0)
            await ReadOnly()
            want = 1 if (st == T2 and half == 1 and carry) else 0
            assert int(dut.pc_increment_upper.value) == want, (
                f"carry={carry} {st} half{half}: pc_increment_upper="
                f"{int(dut.pc_increment_upper.value)} want {want}")
            await NextTimeStep()
