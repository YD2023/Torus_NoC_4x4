import os

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from common.clock_reset import reset_active_low, start_clock
from common.flit import FLIT_BODY, FLIT_HEAD, FLIT_HEADTAIL, FLIT_TAIL, make_flit


PORT_NORTH = 0
PORT_EAST = 2
PORT_WEST = 3
PORT_LOCAL = 4

FIFO_DEPTH = int(os.environ["PORT_FIFO_DEPTH"])


def vc_signal(dut, vc, suffix):
    return getattr(dut, f"vc{vc}_{suffix}_o")


async def reset_input_port(dut, *, cur_x, cur_y):
    dut.link_valid_i.value = 0
    dut.link_flit_i.value = 0
    dut.link_vc_i.value = 0
    dut.pop_vc_i.value = 0
    dut.cur_x_i.value = cur_x
    dut.cur_y_i.value = cur_y

    start_clock(dut)
    await reset_active_low(dut)
    await Timer(1, unit="ns")


async def send_flit(dut, flit, vc):
    dut.link_valid_i.value = 1
    dut.link_flit_i.value = flit
    dut.link_vc_i.value = vc

    await Timer(1, unit="ns")
    assert int(dut.link_ready_o.value) == 1

    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.link_valid_i.value = 0


async def pop_vcs(dut, mask):
    dut.pop_vc_i.value = mask
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.pop_vc_i.value = 0


async def assert_vc(dut, vc, *, valid, flit=None, route=None, next_vc=None):
    await Timer(1, unit="ns")
    actual_valid = (int(dut.vc_valid_o.value) >> vc) & 1
    assert actual_valid == int(valid)

    if not valid:
        return
    if flit is not None:
        assert int(vc_signal(dut, vc, "flit").value) == flit
    if route is not None:
        assert int(vc_signal(dut, vc, "route").value) == route
    if next_vc is not None:
        assert int(vc_signal(dut, vc, "next").value) == next_vc


@cocotb.test()
async def test_vc_buffering_and_backpressure(dut):
    """Ingress demultiplexes by VC and backpressures only the selected full FIFO."""
    await reset_input_port(dut, cur_x=1, cur_y=1)

    for vc in (0, 1):
        dut.link_vc_i.value = vc
        await Timer(1, unit="ns")
        assert int(dut.link_ready_o.value) == 1

    flits = [
        make_flit(FLIT_HEADTAIL, 1, 1, payload=index)
        for index in range(FIFO_DEPTH)
    ]
    for flit in flits:
        await send_flit(dut, flit, 0)

    dut.link_vc_i.value = 0
    await Timer(1, unit="ns")
    assert int(dut.link_ready_o.value) == 0

    dut.link_vc_i.value = 1
    await Timer(1, unit="ns")
    assert int(dut.link_ready_o.value) == 1

    for expected_flit in flits:
        await assert_vc(
            dut,
            0,
            valid=True,
            flit=expected_flit,
            route=PORT_LOCAL,
            next_vc=0,
        )
        await pop_vcs(dut, 0b01)

    await assert_vc(dut, 0, valid=False)
    await pop_vcs(dut, 0b01)
    await assert_vc(dut, 0, valid=False)


@cocotb.test()
async def test_route_state_inheritance_and_release(dut):
    """BODY/TAIL inherit HEAD metadata, while HEADTAIL leaves no stale state."""
    await reset_input_port(dut, cur_x=3, cur_y=1)

    head = make_flit(FLIT_HEAD, 0, 1, pkt_len=3, payload=0x10)
    body = make_flit(FLIT_BODY, 3, 1, payload=0x20)
    tail = make_flit(FLIT_TAIL, 2, 1, payload=0x30)

    for flit in (head, body, tail):
        await send_flit(dut, flit, 0)

    await assert_vc(dut, 0, valid=True, flit=head, route=PORT_EAST, next_vc=1)
    await pop_vcs(dut, 0b01)
    await assert_vc(dut, 0, valid=True, flit=body, route=PORT_EAST, next_vc=1)
    await pop_vcs(dut, 0b01)
    await assert_vc(dut, 0, valid=True, flit=tail, route=PORT_EAST, next_vc=1)
    await pop_vcs(dut, 0b01)
    await assert_vc(dut, 0, valid=False)

    local_single = make_flit(FLIT_HEADTAIL, 3, 1, payload=0x40)
    await send_flit(dut, local_single, 0)
    await assert_vc(
        dut,
        0,
        valid=True,
        flit=local_single,
        route=PORT_LOCAL,
        next_vc=0,
    )
    await pop_vcs(dut, 0b01)

    west_single = make_flit(FLIT_HEADTAIL, 2, 1, payload=0x50)
    await send_flit(dut, west_single, 0)
    await assert_vc(
        dut,
        0,
        valid=True,
        flit=west_single,
        route=PORT_WEST,
        next_vc=0,
    )


@cocotb.test()
async def test_independent_packet_state_per_vc(dut):
    """Interleaved VC0 and VC1 packets retain independent route metadata."""
    await reset_input_port(dut, cur_x=3, cur_y=1)

    vc0_flits = [
        make_flit(FLIT_HEAD, 0, 1, pkt_len=3, payload=0x100),
        make_flit(FLIT_BODY, 3, 1, payload=0x101),
        make_flit(FLIT_TAIL, 2, 1, payload=0x102),
    ]
    vc1_flits = [
        make_flit(FLIT_HEAD, 3, 0, pkt_len=3, payload=0x200),
        make_flit(FLIT_BODY, 3, 1, payload=0x201),
        make_flit(FLIT_TAIL, 2, 1, payload=0x202),
    ]

    for vc0_flit, vc1_flit in zip(vc0_flits, vc1_flits):
        await send_flit(dut, vc0_flit, 0)
        await send_flit(dut, vc1_flit, 1)

    await assert_vc(dut, 0, valid=True, route=PORT_EAST, next_vc=1)
    await assert_vc(dut, 1, valid=True, route=PORT_NORTH, next_vc=1)

    await pop_vcs(dut, 0b11)
    await assert_vc(dut, 0, valid=True, flit=vc0_flits[1], route=PORT_EAST, next_vc=1)
    await assert_vc(dut, 1, valid=True, flit=vc1_flits[1], route=PORT_NORTH, next_vc=1)

    await pop_vcs(dut, 0b01)
    await assert_vc(dut, 0, valid=True, flit=vc0_flits[2], route=PORT_EAST, next_vc=1)
    await assert_vc(dut, 1, valid=True, flit=vc1_flits[1], route=PORT_NORTH, next_vc=1)

    await pop_vcs(dut, 0b10)
    await assert_vc(dut, 1, valid=True, flit=vc1_flits[2], route=PORT_NORTH, next_vc=1)

    await pop_vcs(dut, 0b11)
    await assert_vc(dut, 0, valid=False)
    await assert_vc(dut, 1, valid=False)


@cocotb.test()
async def test_protocol_error_detects_invalid_packet_starts_and_lengths(dut):
    """Both VCs latch malformed starts and invalid header length declarations."""
    await reset_input_port(dut, cur_x=1, cur_y=1)
    assert int(dut.protocol_error_o.value) == 0

    await send_flit(dut, make_flit(FLIT_BODY, 1, 1), 0)
    assert int(dut.protocol_error_o.value) == 0b01

    invalid_single = make_flit(FLIT_HEADTAIL, 1, 1, pkt_len=2)
    await send_flit(dut, invalid_single, 1)
    assert int(dut.protocol_error_o.value) == 0b11

    dut.link_valid_i.value = 0
    dut.pop_vc_i.value = 0
    await reset_active_low(dut)
    await Timer(1, unit="ns")
    assert int(dut.protocol_error_o.value) == 0

    await send_flit(dut, make_flit(FLIT_HEAD, 1, 1, pkt_len=1), 0)
    await send_flit(dut, make_flit(FLIT_HEADTAIL, 1, 1, pkt_len=0), 1)
    assert int(dut.protocol_error_o.value) == 0b11


@cocotb.test()
async def test_protocol_error_detects_position_and_nested_header_faults(dut):
    """Length position errors latch, and a nested header becomes a resync point."""
    await reset_input_port(dut, cur_x=1, cur_y=1)

    await send_flit(dut, make_flit(FLIT_HEAD, 2, 1, pkt_len=4), 0)
    await pop_vcs(dut, 0b01)
    await send_flit(dut, make_flit(FLIT_BODY, 1, 1), 0)
    await pop_vcs(dut, 0b01)
    await send_flit(dut, make_flit(FLIT_TAIL, 1, 1), 0)
    assert int(dut.protocol_error_o.value) == 0b01

    await send_flit(dut, make_flit(FLIT_HEAD, 1, 2, pkt_len=2), 1)
    await pop_vcs(dut, 0b10)
    await send_flit(dut, make_flit(FLIT_BODY, 1, 1), 1)
    assert int(dut.protocol_error_o.value) == 0b11

    dut.link_valid_i.value = 0
    dut.pop_vc_i.value = 0
    await reset_active_low(dut)
    await Timer(1, unit="ns")
    assert int(dut.protocol_error_o.value) == 0

    await send_flit(dut, make_flit(FLIT_HEAD, 2, 1, pkt_len=4), 0)
    await pop_vcs(dut, 0b01)
    await send_flit(dut, make_flit(FLIT_HEAD, 1, 2, pkt_len=2), 0)
    await pop_vcs(dut, 0b01)
    assert int(dut.protocol_error_o.value) == 0b01

    await send_flit(dut, make_flit(FLIT_TAIL, 1, 1), 0)
    await pop_vcs(dut, 0b01)
    assert int(dut.protocol_error_o.value) == 0b01
