# Smoke test proving the cocotb+GHDL VPI path works against this repo's
# build. Replaced by the real random-walk test in plan Task 13.
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


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
