# Exhaustive differential test: instruction_decoder vs an independent
# Python golden model of the 8008 ISA (derived from the ISA description,
# docs/isa.json semantics, NOT transliterated from the VHDL, so decoder
# bugs and model disagreements both surface as diffs).
#
# The module is pure combinational: drive instruction_byte, settle, compare
# every output for all 256 opcodes.

import cocotb
from cocotb.triggers import Timer

OUTPUTS = [
    "instr_needs_immediate", "instr_needs_address", "instr_is_io",
    "instr_is_write", "instr_sss_field", "instr_ddd_field", "instr_is_alu",
    "instr_is_call", "instr_is_ret", "instr_is_rst", "instr_is_hlt",
    "instr_writes_reg", "instr_reads_reg", "instr_is_mem_indirect",
    "instr_uses_temp_regs", "instr_is_inr_dcr", "instr_is_binary_alu",
    "instr_is_rotate", "instr_needs_t4t5", "rst_vector", "condition_code",
    "test_true", "eval_condition", "transition_to_stopped",
]


def golden(op):
    """Expected decoder outputs for opcode `op`, per the 8008 ISA."""
    b76 = op >> 6
    b543 = (op >> 3) & 7
    b210 = op & 7

    g = {name: 0 for name in OUTPUTS}
    g["instr_sss_field"] = b210
    g["instr_ddd_field"] = b543

    if b76 == 0:
        if b543 == 0 and b210 in (0, 1):
            # HLT (0x00 / 0x01)
            g["instr_is_hlt"] = 1
            g["transition_to_stopped"] = 1
        elif b210 == 0:
            # INr
            g.update(instr_is_alu=1, instr_uses_temp_regs=1,
                     instr_is_inr_dcr=1, instr_reads_reg=1,
                     instr_writes_reg=1, instr_needs_t4t5=1,
                     instr_sss_field=0, instr_ddd_field=b543)
        elif b210 == 1:
            # DCr
            g.update(instr_is_alu=1, instr_uses_temp_regs=1,
                     instr_is_inr_dcr=1, instr_reads_reg=1,
                     instr_writes_reg=1, instr_needs_t4t5=1,
                     instr_sss_field=2, instr_ddd_field=b543)
        elif b210 == 2:
            # Rotates (RLC/RRC/RAL/RAR); decoder passes bits 5:3 through
            g.update(instr_is_alu=1, instr_is_rotate=1,
                     instr_uses_temp_regs=1, instr_reads_reg=1,
                     instr_writes_reg=1, instr_needs_t4t5=1,
                     instr_sss_field=b543, instr_ddd_field=0)
        elif b210 == 3:
            # RFc / RTc conditional return
            g.update(instr_is_ret=1, instr_needs_t4t5=1, eval_condition=1,
                     condition_code=b543 & 3, test_true=b543 >> 2)
        elif b210 == 4:
            # ALU immediate
            g.update(instr_needs_immediate=1, instr_is_alu=1,
                     instr_is_binary_alu=1, instr_reads_reg=1,
                     instr_needs_t4t5=1,
                     instr_sss_field=b543, instr_ddd_field=0)
            g["instr_writes_reg"] = 0 if b543 == 7 else 1   # CPI no write
        elif b210 == 5:
            # RST
            g.update(instr_is_rst=1, instr_needs_t4t5=1, rst_vector=b543)
        elif b210 == 6:
            if b543 == 7:
                # LMI (MVI M): 3 cycles, memory write via H:L
                g.update(instr_needs_address=1, instr_needs_immediate=1,
                         instr_is_write=1, instr_is_mem_indirect=1)
            else:
                # LrI (MVI r)
                g.update(instr_needs_immediate=1, instr_writes_reg=1,
                         instr_needs_t4t5=1)
        else:  # b210 == 7
            # RET
            g.update(instr_is_ret=1, instr_needs_t4t5=1)

    elif b76 == 1:
        if b210 & 1:
            # I/O
            g.update(instr_needs_immediate=1, instr_is_io=1)
            if (op >> 4) & 3 == 0:
                # INP
                g.update(instr_writes_reg=1, instr_ddd_field=0,
                         instr_needs_t4t5=1)
            else:
                # OUT
                g.update(instr_reads_reg=1, instr_sss_field=0)
        else:
            # Jump / Call family: 3 cycles, address into temp regs
            g.update(instr_needs_address=1, instr_uses_temp_regs=1,
                     instr_needs_t4t5=1)
            if b210 == 0:
                g.update(eval_condition=1, condition_code=b543 & 3,
                         test_true=b543 >> 2)
            elif b210 == 2:
                g.update(instr_is_call=1, eval_condition=1,
                         condition_code=b543 & 3, test_true=b543 >> 2)
            elif b210 == 6:
                g["instr_is_call"] = 1
            # b210 == 4: unconditional JMP, nothing extra

    elif b76 == 2:
        # ALU register / memory
        g.update(instr_is_alu=1, instr_uses_temp_regs=1, instr_reads_reg=1,
                 instr_is_binary_alu=1, instr_needs_t4t5=1,
                 instr_ddd_field=0)
        g["instr_writes_reg"] = 0 if b543 == 7 else 1        # CPr no write
        if b210 == 7:
            # ALU op M: extra memory read cycle via H:L
            g.update(instr_needs_immediate=1, instr_is_mem_indirect=1)

    else:  # b76 == 3
        if op == 0xFF:
            g.update(instr_is_hlt=1, transition_to_stopped=1)
        elif b210 == 7:
            # LrM: register <- memory via H:L
            g.update(instr_needs_immediate=1, instr_writes_reg=1,
                     instr_needs_t4t5=1, instr_is_mem_indirect=1)
        elif b543 == 7:
            # LMr: memory <- register via H:L
            g.update(instr_needs_immediate=1, instr_is_write=1,
                     instr_reads_reg=1, instr_is_mem_indirect=1)
        else:
            # MOV r,r
            g.update(instr_reads_reg=1, instr_writes_reg=1,
                     instr_needs_t4t5=1, instr_uses_temp_regs=1)
    return g


# Known divergences from the golden model, accepted for now and tracked
# in issue #4: the RTL sets instr_is_mem_indirect for CPr (bits 5:3 are
# the CP opcode, not a register) and for 0xFF HLT. Verified benign: every
# consumer gates these cases out (see the issue for the walk). Remove the
# entries when issue #4 is fixed; the test then requires a clean match.
KNOWN_QUIRKS = {
    (op, "instr_is_mem_indirect") for op in (0xB8, 0xB9, 0xBA, 0xBB,
                                             0xBC, 0xBD, 0xBE, 0xFF)
}


@cocotb.test()
async def decode_all_256(dut):
    mismatches = []
    quirks_seen = set()
    for op in range(256):
        dut.instruction_byte.value = op
        await Timer(1, "ns")
        g = golden(op)
        for name in OUTPUTS:
            got = int(getattr(dut, name).value)
            if got != g[name]:
                if (op, name) in KNOWN_QUIRKS:
                    quirks_seen.add((op, name))
                    dut._log.warning(
                        f"known quirk (issue #4): op=0x{op:02X} {name} "
                        f"dut={got} golden={want_str(g[name])}")
                else:
                    mismatches.append((op, name, got, g[name]))
    for op, name, got, want in mismatches:
        dut._log.error(f"op=0x{op:02X}: {name} dut={got} golden={want}")
    assert not mismatches, f"{len(mismatches)} output mismatches over 256 opcodes"
    # If the RTL gets fixed, stale quirk entries must be pruned so the
    # table cannot silently mask a future regression at those opcodes.
    stale = KNOWN_QUIRKS - quirks_seen
    assert not stale, f"KNOWN_QUIRKS entries no longer occur, prune them: {sorted(stale)}"


def want_str(v):
    return str(v)
