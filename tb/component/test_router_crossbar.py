import os

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from common.clock_reset import reset_active_low, start_clock
from common.flit import FLIT_BODY, FLIT_HEAD, FLIT_HEADTAIL, FLIT_TAIL, make_flit


PORT_NORTH = 0
PORT_SOUTH = 1
PORT_EAST = 2
PORT_WEST = 3
PORT_LOCAL = 4

NUM_PORTS = int(os.environ["NUM_PORTS"])
NUM_REQ = int(os.environ["NUM_REQ"])
FLIT_W = int(os.environ["FLIT_W"])
VC_W = int(os.environ["VC_W"])
PORT_W = int(os.environ["PORT_W"])

def test_flit(flit_type, payload):
    return make_flit(flit_type, 0, 0, pkt_len=3, payload=payload)



def pack_fields(values, width):
    packed = 0
    mask = (1 << width) - 1
    for index, value in enumerate(values):
        packed |= (value & mask) << (index * width)
    return packed


def unpack_field(packed, index, width):
    return (packed >> (index * width)) & ((1 << width) - 1)


def drive_requests(dut, requests):
    valid = 0
    flits = [0] * NUM_REQ
    vcs = [0] * NUM_REQ
    routes = [0] * NUM_REQ

    for requester, request in requests.items():
        route, flit, vc = request
        valid |= 1 << requester
        flits[requester] = flit
        vcs[requester] = vc
        routes[requester] = route

    dut.in_valid_i.value = valid
    dut.in_flit_i.value = pack_fields(flits, FLIT_W)
    dut.in_vc_i.value = pack_fields(vcs, VC_W)
    dut.in_route_i.value = pack_fields(routes, PORT_W)


async def reset_crossbar(dut):
    drive_requests(dut, {})
    dut.out_ready_i.value = 0
    dut.out_vc_ready_i.value = 0
    start_clock(dut)
    await reset_active_low(dut)
    await Timer(1, unit="ns")


def output_flit(dut, output):
    return unpack_field(int(dut.out_flit_o.value), output, FLIT_W)


def output_vc(dut, output):
    return unpack_field(int(dut.out_vc_o.value), output, VC_W)


@cocotb.test()
async def test_idle_and_invalid_route(dut):
    """Idle and out-of-range routes produce no grant or transfer readiness."""
    assert NUM_PORTS == 5
    assert NUM_REQ == 10
    await reset_crossbar(dut)

    dut.out_ready_i.value = (1 << NUM_PORTS) - 1
    await Timer(1, unit="ns")
    assert int(dut.out_valid_o.value) == 0
    assert int(dut.in_ready_o.value) == 0
    assert int(dut.in_grant_o.value) == 0
    assert int(dut.in_stalled_o.value) == 0

    drive_requests(dut, {4: (7, 0x4444, 0)})
    await Timer(1, unit="ns")
    assert int(dut.out_valid_o.value) == 0
    assert int(dut.in_ready_o.value) == 0


@cocotb.test()
async def test_parallel_independent_outputs(dut):
    """Five requesters targeting distinct outputs can transfer in one cycle."""
    await reset_crossbar(dut)

    requests = {
        0: (PORT_NORTH, test_flit(FLIT_HEADTAIL, 0x100), 0),
        3: (PORT_SOUTH, test_flit(FLIT_HEADTAIL, 0x103), 1),
        6: (PORT_EAST, test_flit(FLIT_HEADTAIL, 0x106), 0),
        8: (PORT_WEST, test_flit(FLIT_HEADTAIL, 0x108), 1),
        9: (PORT_LOCAL, test_flit(FLIT_HEADTAIL, 0x109), 1),
    }
    drive_requests(dut, requests)
    dut.out_ready_i.value = (1 << NUM_PORTS) - 1
    await Timer(1, unit="ns")

    assert int(dut.out_valid_o.value) == (1 << NUM_PORTS) - 1
    assert int(dut.in_ready_o.value) == sum(1 << req for req in requests)

    for requester, (output, flit, vc) in requests.items():
        assert output_flit(dut, output) == flit
        assert output_vc(dut, output) == vc
        assert (int(dut.in_ready_o.value) >> requester) & 1


@cocotb.test()
async def test_backpressure_holds_grant(dut):
    """A stalled output holds its selected requester until a handshake occurs."""
    await reset_crossbar(dut)

    requests = {
        1: (PORT_EAST, test_flit(FLIT_HEADTAIL, 0xA1), 0),
        4: (PORT_EAST, test_flit(FLIT_HEADTAIL, 0xA4), 1),
    }
    drive_requests(dut, requests)
    dut.out_ready_i.value = 0

    for _ in range(3):
        await Timer(1, unit="ns")
        assert int(dut.out_valid_o.value) == (1 << PORT_EAST)
        assert output_flit(dut, PORT_EAST) == requests[1][1]
        assert int(dut.in_ready_o.value) == 0
        assert int(dut.in_grant_o.value) == (1 << 1)
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        assert int(dut.in_stalled_o.value) == (1 << 1)
        await FallingEdge(dut.clk)

    dut.out_ready_i.value = 1 << PORT_EAST
    await Timer(1, unit="ns")
    assert int(dut.in_ready_o.value) == (1 << 1)
    assert output_flit(dut, PORT_EAST) == requests[1][1]

    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert int(dut.in_ready_o.value) == (1 << 4)
    assert int(dut.in_grant_o.value) == (1 << 4)
    assert output_flit(dut, PORT_EAST) == requests[4][1]


@cocotb.test()
async def test_late_requester_cannot_replace_stalled_grant(dut):
    """A newly eligible requester cannot change a visible blocked transfer."""
    await reset_crossbar(dut)

    held_flit = test_flit(FLIT_HEADTAIL, 0xD4)
    late_flit = test_flit(FLIT_HEADTAIL, 0xD0)
    drive_requests(dut, {4: (PORT_EAST, held_flit, 0)})
    dut.out_ready_i.value = 0
    await Timer(1, unit="ns")
    assert output_flit(dut, PORT_EAST) == held_flit

    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    drive_requests(
        dut,
        {
            0: (PORT_EAST, late_flit, 0),
            4: (PORT_EAST, held_flit, 0),
        },
    )
    await Timer(1, unit="ns")

    assert output_flit(dut, PORT_EAST) == held_flit
    assert int(dut.in_ready_o.value) == 0

    dut.out_ready_i.value = 1 << PORT_EAST
    await Timer(1, unit="ns")
    assert output_flit(dut, PORT_EAST) == held_flit
    assert int(dut.in_ready_o.value) == (1 << 4)


@cocotb.test()
async def test_round_robin_sparse_fairness(dut):
    """Persistent sparse contenders are served in circular requester order."""
    await reset_crossbar(dut)

    contenders = (0, 3, 9)
    requests = {
        requester: (PORT_EAST, test_flit(FLIT_HEADTAIL, 0xB0 + requester), requester & 1)
        for requester in contenders
    }
    drive_requests(dut, requests)
    dut.out_ready_i.value = 1 << PORT_EAST

    for expected_requester in contenders * 2:
        await Timer(1, unit="ns")
        assert int(dut.out_valid_o.value) == (1 << PORT_EAST)
        assert int(dut.in_ready_o.value) == (1 << expected_requester)
        assert output_flit(dut, PORT_EAST) == requests[expected_requester][1]
        assert output_vc(dut, PORT_EAST) == (expected_requester & 1)

        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)


@cocotb.test()
async def test_multiflit_packet_holds_output(dut):
    """A multi-flit packet owns its output through its tail, including input gaps."""
    await reset_crossbar(dut)

    owner = 2
    contender = 5
    ready = 1 << PORT_EAST
    contender_flit = test_flit(FLIT_HEADTAIL, 0xC5)

    drive_requests(
        dut,
        {
            owner: (PORT_EAST, test_flit(FLIT_HEAD, 0xC0), 0),
            contender: (PORT_EAST, contender_flit, 0),
        },
    )
    dut.out_ready_i.value = ready
    await Timer(1, unit="ns")
    assert int(dut.in_ready_o.value) == (1 << owner)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)

    drive_requests(dut, {contender: (PORT_EAST, contender_flit, 0)})
    await Timer(1, unit="ns")
    assert int(dut.out_valid_o.value) == 0
    assert int(dut.in_ready_o.value) == 0

    body_flit = test_flit(FLIT_BODY, 0xC1)
    drive_requests(
        dut,
        {
            owner: (PORT_EAST, body_flit, 0),
            contender: (PORT_EAST, contender_flit, 0),
        },
    )
    await Timer(1, unit="ns")
    assert int(dut.in_ready_o.value) == (1 << owner)
    assert output_flit(dut, PORT_EAST) == body_flit
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)

    tail_flit = test_flit(FLIT_TAIL, 0xC2)
    drive_requests(
        dut,
        {
            owner: (PORT_EAST, tail_flit, 0),
            contender: (PORT_EAST, contender_flit, 0),
        },
    )
    await Timer(1, unit="ns")
    assert int(dut.in_ready_o.value) == (1 << owner)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    await Timer(1, unit="ns")

    assert int(dut.in_ready_o.value) == (1 << contender)
    assert output_flit(dut, PORT_EAST) == contender_flit


@cocotb.test()
async def test_other_vc_bypasses_packet_gap(dut):
    """An owned output VC does not block an independent VC on the same link."""
    await reset_crossbar(dut)

    owner = 2
    contender = 5
    ready = 1 << PORT_EAST
    head_flit = test_flit(FLIT_HEAD, 0xE0)
    contender_flit = test_flit(FLIT_HEADTAIL, 0xE5)

    drive_requests(dut, {owner: (PORT_EAST, head_flit, 0)})
    dut.out_ready_i.value = ready
    await Timer(1, unit="ns")
    assert int(dut.in_ready_o.value) == (1 << owner)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)

    drive_requests(dut, {contender: (PORT_EAST, contender_flit, 1)})
    await Timer(1, unit="ns")
    assert int(dut.in_ready_o.value) == (1 << contender)
    assert output_flit(dut, PORT_EAST) == contender_flit
    assert output_vc(dut, PORT_EAST) == 1
