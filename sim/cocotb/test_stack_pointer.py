# Smoke test proving the cocotb+GHDL VPI path works against this repo's
# build. Replaced by the real random-walk test in plan Task 13.
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, NextTimeStep


@cocotb.test()
async def smoke(dut):
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    dut.reset.value = 1
    dut.phi1_rising.value = 0
    dut.stack_push.value = 0
    dut.stack_pop.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    assert int(dut.sp_out.value) == 0

@cocotb.test()
async def sp_random_walk(dut):
    # Python drives; Python also predicts. The model is the oracle:
    # 4 lines re-stating what the RTL is SUPPOSED to do.
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())

    dut.reset.value = 1
    dut.phi1_rising.value = 0
    dut.stack_push.value = 0
    dut.stack_pop.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    model_sp = 0
    rng = random.Random(1972)   # seeded = reproducible failures
    for i in range(1000):
        push = rng.randint(0, 1)
        pop = rng.randint(0, 1)
        phi1 = rng.randint(0, 1)
        dut.stack_push.value = push
        dut.stack_pop.value = pop
        dut.phi1_rising.value = phi1
        await RisingEdge(dut.clk)
        # model mirrors the RTL contract: enabled + push wins over pop
        if phi1:
            if push:
                model_sp = (model_sp + 1) % 8
            elif pop:
                model_sp = (model_sp - 1) % 8
        await ReadOnly()        # let the design settle post-edge
        got = int(dut.sp_out.value)
        assert got == model_sp, f"cycle {i}: dut={got} model={model_sp}"
        await NextTimeStep()
