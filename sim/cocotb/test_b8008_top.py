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
# Known residuals (documented, not asserted): FLG-13's flags-on-bus at
# INP T4 is unimplemented in the RTL (condition_flags' bus path is
# never enabled); BUS-09 bus-float is not modeled at this sim top; the
# T1I address emission (INT-02 double-address) is masked here because
# the top-level jam mux drives the interrupt byte onto the bus for the
# whole T1I cycle - covered behaviorally by check_jam_test.sh instead.

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, NextTimeStep

from test_instruction_decoder import golden
from test_memory_io_control import cycle_types, data_cycle

REPO = os.path.join(os.path.dirname(__file__), "..", "..")

PCI, PCR, PCC, PCW = 0, 1, 2, 3

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
    dut.int_vector.value = 0
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
    mem = load_mem(rom_name)
    cocotb.start_soon(Clock(dut.clk_in, 10, "ns").start())
    cocotb.start_soon(rom_server(dut, mem))
    await boot(dut)

    errors = []
    checked = {"t1": 0, "t2": 0, "codes": 0}
    prev_key = None
    settle = 0   # clks remaining until the current window's check fires

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
            break  # program finished (HLT)

        half = int(dut.debug_state_half.value)
        key = (name, half)
        if key != prev_key:
            prev_key = key
            # Check 60 clks (0.6us) into each (state, half0) window: past
            # the cycle-type latch (which waits for the phi1 edge ~0.4us
            # into the state) and the address-latch capture, well before
            # any second-half increment. T1I is skipped (jam mux masks
            # bus - see header).
            settle = 60 if (half == 0 and name in ("T1", "T2")) else 0
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
                errors.append(f"{name} entering cyc{entering} IR={ir:02X}: "
                              f"D={data:02X} want {what}={want:02X} (PC={pc:04X})")
            checked["t1"] += 1

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
                    errors.append(f"T2 cyc{cyc} IR={ir:02X}: D[5:0]="
                                  f"{data & 0x3F:02X} want PC high={want_h:02X}")
            checked["t2"] += 1

        await NextTimeStep()

    assert checked["t1"] > 50 and checked["t2"] > 50, \
        f"monitor barely ran: {checked}"
    for e in errors[:20]:
        dut._log.error(e)
    assert not errors, f"{len(errors)} bus-protocol violations (first 20 logged)"
    dut._log.info(f"bus monitor clean: {checked}")


@cocotb.test()
async def bus_protocol_memory_alu(dut):
    """PCI + PCR-immediate + PCR-H:L + PCW coverage."""
    await run_monitor(dut, "memory_alu_test_as.mem")


@cocotb.test()
async def bus_protocol_io(dut):
    """PCC coverage (INP/OUT): REG.A at T1, IR byte at T2."""
    await run_monitor(dut, "io_test_as.mem")
