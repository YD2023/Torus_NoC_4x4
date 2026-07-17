import os
from collections import deque

import cocotb
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge

from common.clock_reset import reset_active_low, start_clock


FIFO_DEPTH = int(os.environ["FIFO_DEPTH"])
FIFO_WIDTH = int(os.environ["FIFO_WIDTH"])
DATA_MASK = (1 << FIFO_WIDTH) - 1

async def fifo_cycle(dut, model, *, push=False, pop=False, data=0):
    was_full = len(model) == FIFO_DEPTH
    was_empty = len(model) == 0

    dut.push.value = int(push)
    dut.pop.value = int(pop)
    dut.data_i.value = data & DATA_MASK

    await RisingEdge(dut.clk)

    if pop and not was_empty:
        model.popleft()
    if push and not was_full:
        model.append(data & DATA_MASK)

    await ReadOnly()
    assert int(dut.count.value) == len(model)
    assert int(dut.empty.value) == (len(model) == 0)
    assert int(dut.full.value) == (len(model) == FIFO_DEPTH)
    assert int(dut.data_o.value) == (model[0] if model else 0)

    await FallingEdge(dut.clk)


@cocotb.test()
async def test_fifo_contract(dut):
    """Exercise ordering, boundaries, simultaneous operations, and pointer wrap."""
    start_clock(dut)
    model = deque()

    dut.push.value = 0
    dut.pop.value = 0
    dut.data_i.value = 0

    assert len(dut.data_i) == FIFO_WIDTH
    await reset_active_low(dut)
    await ReadOnly()
    assert int(dut.count.value) == 0
    assert int(dut.empty.value) == 1
    assert int(dut.full.value) == 0
    assert int(dut.data_o.value) == 0
    await FallingEdge(dut.clk)

    for index in range(FIFO_DEPTH):
        await fifo_cycle(dut, model, push=True, data=0x10 + index)

    # A full FIFO accepts the pop but rejects the same-cycle push.
    await fifo_cycle(dut, model, push=True, pop=True, data=0x44)
    await fifo_cycle(dut, model, push=True, pop=True, data=0x44)

    while model:
        await fifo_cycle(dut, model, pop=True)

    # An empty FIFO accepts the push but rejects the same-cycle pop.
    await fifo_cycle(dut, model, push=True, pop=True, data=0x55)
    await fifo_cycle(dut, model, pop=True)
    await fifo_cycle(dut, model, pop=True)

    # Refill after pointer wrap to verify non-power-of-two pointer handling.
    for index in range(FIFO_DEPTH):
        await fifo_cycle(dut, model, push=True, data=0x60 + index)

    while model:
        await fifo_cycle(dut, model, pop=True)
