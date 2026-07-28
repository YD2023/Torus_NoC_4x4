import os

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from common.clock_reset import reset_active_low, start_clock


NUM_REQ = int(os.environ["NUM_REQ"])
REQ_MASK = (1 << NUM_REQ) - 1


def expected_grant(requests, rr_ptr):
    for offset in range(NUM_REQ):
        index = (rr_ptr + offset) % NUM_REQ
        if requests & (1 << index):
            return index
    return None


async def reset_arbiter(dut):
    dut.req_i.value = 0
    dut.advance_i.value = 0
    start_clock(dut)
    await reset_active_low(dut)


async def check_cycle(dut, rr_ptr, requests, *, advance=False):
    requests &= REQ_MASK
    dut.req_i.value = requests
    dut.advance_i.value = int(advance)

    await Timer(1, unit="ns")
    expected_index = expected_grant(requests, rr_ptr)
    grant = int(dut.grant_o.value)

    assert grant & ~REQ_MASK == 0
    assert grant == 0 or (grant & (grant - 1)) == 0

    if expected_index is None:
        assert int(dut.grant_valid_o.value) == 0
        assert grant == 0
        assert int(dut.grant_idx_o.value) == 0
    else:
        assert int(dut.grant_valid_o.value) == 1
        assert grant == (1 << expected_index)
        assert int(dut.grant_idx_o.value) == expected_index

    await RisingEdge(dut.clk)
    if advance and expected_index is not None:
        rr_ptr = (expected_index + 1) % NUM_REQ

    await FallingEdge(dut.clk)
    return rr_ptr


@cocotb.test()
async def test_no_request_and_pointer_hold(dut):
    """No request produces no grant; a grant does not rotate without advance."""
    await reset_arbiter(dut)

    rr_ptr = 0
    rr_ptr = await check_cycle(dut, rr_ptr, 0, advance=True)

    requester = NUM_REQ - 1
    requests = 1 << requester
    rr_ptr = await check_cycle(dut, rr_ptr, requests)
    rr_ptr = await check_cycle(dut, rr_ptr, requests)

    assert rr_ptr == 0


@cocotb.test()
async def test_round_robin_fairness_and_wrap(dut):
    """Persistent requesters are served once each in circular order."""
    await reset_arbiter(dut)

    rr_ptr = 0
    for expected_index in range(NUM_REQ):
        assert rr_ptr == expected_index
        rr_ptr = await check_cycle(dut, rr_ptr, REQ_MASK, advance=True)

    assert rr_ptr == 0


@cocotb.test()
async def test_sparse_requests_and_advance(dut):
    """Sparse grants skip inactive requesters and wrap across requester zero."""
    await reset_arbiter(dut)

    rr_ptr = 0
    high_requester = max(NUM_REQ - 2, 0)
    sparse_requests = (1 << high_requester) | 1

    rr_ptr = await check_cycle(dut, rr_ptr, sparse_requests, advance=True)
    assert rr_ptr == (0 + 1) % NUM_REQ

    rr_ptr = await check_cycle(dut, rr_ptr, sparse_requests, advance=True)
    assert rr_ptr == (high_requester + 1) % NUM_REQ

    rr_ptr_before_idle = rr_ptr
    rr_ptr = await check_cycle(dut, rr_ptr, 0, advance=True)
