import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge


def start_clock(dut, period_ns=10):
    """Start the DUT clock and return its cocotb task."""
    return cocotb.start_soon(Clock(dut.clk, period_ns, unit="ns").start())


async def reset_active_low(dut, cycles=2):
    """Assert rst_n across complete clock edges and release it off-edge."""
    dut.rst_n.value = 0

    for _ in range(cycles):
        await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
