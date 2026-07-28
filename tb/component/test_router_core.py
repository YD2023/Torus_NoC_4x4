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

NUM_PORTS = 5
NUM_VCS = 2
FLIT_W = 64
VC_W = 1
FIFO_DEPTH = int(os.environ["ROUTER_FIFO_DEPTH"])
ROUTER_X = int(os.environ["ROUTER_X"])
ROUTER_Y = int(os.environ["ROUTER_Y"])
COUNTER_W = int(os.environ["ROUTER_COUNTER_WIDTH"])


def pack_fields(values, width):
    packed = 0
    mask = (1 << width) - 1
    for index, value in enumerate(values):
        packed |= (value & mask) << (index * width)
    return packed


def unpack_field(packed, index, width):
    return (packed >> (index * width)) & ((1 << width) - 1)


def output_flit(dut, output):
    return unpack_field(int(dut.out_flit_o.value), output, FLIT_W)


def output_vc(dut, output):
    return unpack_field(int(dut.out_vc_o.value), output, VC_W)


def counter_value(dut, signal_name, port):
    packed = int(getattr(dut, signal_name).value)
    return unpack_field(packed, port, COUNTER_W)


def drive_input_requests(dut, requests):
    valid = 0
    flits = [0] * NUM_PORTS
    vcs = [0] * NUM_PORTS

    for input_port, (flit, vc) in requests.items():
        valid |= 1 << input_port
        flits[input_port] = flit
        vcs[input_port] = vc

    dut.in_valid_i.value = valid
    dut.in_flit_i.value = pack_fields(flits, FLIT_W)
    dut.in_vc_i.value = pack_fields(vcs, VC_W)


async def reset_router(dut):
    drive_input_requests(dut, {})
    dut.out_ready_i.value = 0
    dut.out_vc_ready_i.value = 0
    start_clock(dut)
    await reset_active_low(dut)
    await Timer(1, unit="ns")


async def accept_inputs(dut, requests):
    drive_input_requests(dut, requests)
    await Timer(1, unit="ns")

    requested_mask = sum(1 << input_port for input_port in requests)
    assert int(dut.in_ready_o.value) & requested_mask == requested_mask

    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    drive_input_requests(dut, {})


async def assert_outputs(dut, expected):
    await Timer(1, unit="ns")
    expected_mask = sum(1 << output for output in expected)
    assert int(dut.out_valid_o.value) == expected_mask

    for output, (flit, vc) in expected.items():
        assert output_flit(dut, output) == flit
        assert output_vc(dut, output) == vc


async def transfer_outputs(dut):
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)


@cocotb.test()
async def test_all_routes_vc_transitions_and_counters(dut):
    """Each route launches correctly and dateline hops monotonically select VC1."""
    assert (ROUTER_X, ROUTER_Y) == (3, 0)
    await reset_router(dut)
    dut.out_ready_i.value = (1 << NUM_PORTS) - 1

    cases = (
        (PORT_LOCAL, PORT_LOCAL, 3, 0, 0),
        (PORT_NORTH, PORT_EAST, 0, 0, 1),
        (PORT_SOUTH, PORT_WEST, 2, 0, 0),
        (PORT_EAST, PORT_SOUTH, 3, 1, 0),
        (PORT_WEST, PORT_NORTH, 3, 3, 1),
    )

    for payload, (input_port, output, dst_x, dst_y, expected_vc) in enumerate(cases):
        flit = make_flit(
            FLIT_HEADTAIL,
            dst_x,
            dst_y,
            src_x=ROUTER_X,
            src_y=ROUTER_Y,
            payload=0x100 + payload,
        )
        await accept_inputs(dut, {input_port: (flit, 0)})
        await assert_outputs(dut, {output: (flit, expected_vc)})
        await transfer_outputs(dut)

    await Timer(1, unit="ns")
    assert int(dut.out_valid_o.value) == 0
    for port in range(NUM_PORTS):
        assert counter_value(dut, "flits_received_o", port) == 1
        assert counter_value(dut, "flits_sent_o", port) == 1
    assert int(dut.packets_ejected_o.value) == 1


@cocotb.test()
async def test_parallel_independent_router_paths(dut):
    """All five input ports can traverse to distinct outputs in one cycle."""
    await reset_router(dut)
    dut.out_ready_i.value = (1 << NUM_PORTS) - 1

    routes = {
        PORT_LOCAL: (PORT_LOCAL, 3, 0, 0),
        PORT_NORTH: (PORT_EAST, 0, 0, 1),
        PORT_SOUTH: (PORT_WEST, 2, 0, 0),
        PORT_EAST: (PORT_SOUTH, 3, 1, 0),
        PORT_WEST: (PORT_NORTH, 3, 3, 1),
    }
    requests = {}
    expected = {}

    for input_port, (output, dst_x, dst_y, vc) in routes.items():
        flit = make_flit(FLIT_HEADTAIL, dst_x, dst_y, payload=0x200 + input_port)
        requests[input_port] = (flit, 0)
        expected[output] = (flit, vc)

    await accept_inputs(dut, requests)
    await assert_outputs(dut, expected)
    await transfer_outputs(dut)

    for port in range(NUM_PORTS):
        assert counter_value(dut, "flits_received_o", port) == 1
        assert counter_value(dut, "flits_sent_o", port) == 1


@cocotb.test()
async def test_fifo_backpressure_and_ordered_recovery(dut):
    """A stalled full input VC backpressures ingress and drains without reordering."""
    await reset_router(dut)

    initial_flits = [
        make_flit(FLIT_HEADTAIL, 0, 0, payload=0x300 + index)
        for index in range(FIFO_DEPTH)
    ]
    for flit in initial_flits:
        await accept_inputs(dut, {PORT_LOCAL: (flit, 0)})

    await Timer(1, unit="ns")
    assert ((int(dut.in_ready_o.value) >> PORT_LOCAL) & 1) == 0
    await assert_outputs(dut, {PORT_EAST: (initial_flits[0], 1)})
    assert counter_value(dut, "flits_received_o", PORT_LOCAL) == FIFO_DEPTH
    assert counter_value(dut, "flits_sent_o", PORT_EAST) == 0

    dut.out_ready_i.value = 1 << PORT_EAST
    await transfer_outputs(dut)
    dut.out_ready_i.value = 0

    extra_flit = make_flit(FLIT_HEADTAIL, 0, 0, payload=0x3FF)
    await accept_inputs(dut, {PORT_LOCAL: (extra_flit, 0)})

    for expected_flit in initial_flits[1:] + [extra_flit]:
        dut.out_ready_i.value = 1 << PORT_EAST
        await assert_outputs(dut, {PORT_EAST: (expected_flit, 1)})
        await transfer_outputs(dut)
        dut.out_ready_i.value = 0

    await Timer(1, unit="ns")
    assert int(dut.out_valid_o.value) == 0
    assert counter_value(dut, "flits_received_o", PORT_LOCAL) == FIFO_DEPTH + 1
    assert counter_value(dut, "flits_sent_o", PORT_EAST) == FIFO_DEPTH + 1


@cocotb.test()
async def test_contending_multiflit_packets_remain_contiguous(dut):
    """Output arbitration preserves complete packet order across competing inputs."""
    await reset_router(dut)

    packet_a = [
        make_flit(FLIT_HEAD, 0, 0, pkt_len=3, payload=0xA0),
        make_flit(FLIT_BODY, 3, 0, pkt_len=3, payload=0xA1),
        make_flit(FLIT_TAIL, 2, 0, pkt_len=3, payload=0xA2),
    ]
    packet_b = [
        make_flit(FLIT_HEAD, 0, 0, pkt_len=3, payload=0xB0),
        make_flit(FLIT_BODY, 3, 0, pkt_len=3, payload=0xB1),
        make_flit(FLIT_TAIL, 2, 0, pkt_len=3, payload=0xB2),
    ]

    for flit in packet_a:
        await accept_inputs(dut, {PORT_NORTH: (flit, 0)})
    for flit in packet_b:
        await accept_inputs(dut, {PORT_SOUTH: (flit, 0)})

    dut.out_ready_i.value = 1 << PORT_EAST
    for expected_flit in packet_a + packet_b:
        await assert_outputs(dut, {PORT_EAST: (expected_flit, 1)})
        await transfer_outputs(dut)

    await Timer(1, unit="ns")
    assert int(dut.out_valid_o.value) == 0
    assert counter_value(dut, "flits_received_o", PORT_NORTH) == 3
    assert counter_value(dut, "flits_received_o", PORT_SOUTH) == 3
    assert counter_value(dut, "flits_sent_o", PORT_EAST) == 6
    assert int(dut.packets_ejected_o.value) == 0


@cocotb.test()
async def test_blocked_counter_event_semantics(dut):
    """Empty inputs and stalled outputs count exactly once per active cycle."""
    await reset_router(dut)

    for signal_name in (
        "flits_received_o",
        "flits_sent_o",
        "blocked_empty_o",
        "blocked_backpressure_o",
    ):
        assert int(getattr(dut, signal_name).value) == 0
    assert int(dut.packets_ejected_o.value) == 0

    for _ in range(2):
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)

    for port in range(NUM_PORTS):
        assert counter_value(dut, "blocked_empty_o", port) == 2
        assert counter_value(dut, "blocked_backpressure_o", port) == 0

    flit = make_flit(FLIT_HEADTAIL, 0, 0, payload=0xC00)
    await accept_inputs(dut, {PORT_LOCAL: (flit, 0)})
    await assert_outputs(dut, {PORT_EAST: (flit, 1)})

    for _ in range(3):
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)

    assert counter_value(dut, "blocked_empty_o", PORT_LOCAL) == 3
    for port in range(NUM_PORTS - 1):
        assert counter_value(dut, "blocked_empty_o", port) == 6
    assert counter_value(dut, "blocked_backpressure_o", PORT_EAST) == 3
    assert counter_value(dut, "flits_sent_o", PORT_EAST) == 0

    dut.out_ready_i.value = 1 << PORT_EAST
    await transfer_outputs(dut)
    assert counter_value(dut, "blocked_backpressure_o", PORT_EAST) == 3
    assert counter_value(dut, "flits_received_o", PORT_LOCAL) == 1
    assert counter_value(dut, "flits_sent_o", PORT_EAST) == 1


@cocotb.test()
async def test_observability_counters_saturate(dut):
    """Every counter class holds at its maximum instead of wrapping."""
    assert COUNTER_W <= 8
    maximum = (1 << COUNTER_W) - 1
    await reset_router(dut)

    for _ in range(maximum + 2):
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
    for port in range(NUM_PORTS):
        assert counter_value(dut, "blocked_empty_o", port) == maximum

    stalled = make_flit(FLIT_HEADTAIL, 0, 0, payload=0xD00)
    await accept_inputs(dut, {PORT_LOCAL: (stalled, 0)})
    await assert_outputs(dut, {PORT_EAST: (stalled, 1)})
    for _ in range(maximum + 2):
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)
    assert counter_value(dut, "blocked_backpressure_o", PORT_EAST) == maximum

    dut.out_ready_i.value = 1 << PORT_EAST
    await transfer_outputs(dut)
    dut.out_ready_i.value = 1 << PORT_LOCAL

    for index in range(maximum + 2):
        flit = make_flit(
            FLIT_HEADTAIL,
            ROUTER_X,
            ROUTER_Y,
            payload=0xE00 + index,
        )
        await accept_inputs(dut, {PORT_LOCAL: (flit, 0)})
        await assert_outputs(dut, {PORT_LOCAL: (flit, 0)})
        await transfer_outputs(dut)

    assert counter_value(dut, "flits_received_o", PORT_LOCAL) == maximum
    assert counter_value(dut, "flits_sent_o", PORT_LOCAL) == maximum
    assert int(dut.packets_ejected_o.value) == maximum
    assert counter_value(dut, "blocked_backpressure_o", PORT_EAST) == maximum


@cocotb.test()
async def test_protocol_error_exposure_and_reset(dut):
    """Router status preserves port and VC ordering and clears on reset."""
    await reset_router(dut)
    assert int(dut.protocol_error_o.value) == 0

    malformed_body = make_flit(
        FLIT_BODY,
        ROUTER_X,
        ROUTER_Y,
        payload=0xF00,
    )
    malformed_single = make_flit(
        FLIT_HEADTAIL,
        ROUTER_X,
        ROUTER_Y,
        pkt_len=2,
        payload=0xF01,
    )
    await accept_inputs(
        dut,
        {
            PORT_LOCAL: (malformed_body, 0),
            PORT_NORTH: (malformed_single, 1),
        },
    )

    local_vc0 = PORT_LOCAL * NUM_VCS
    north_vc1 = PORT_NORTH * NUM_VCS + 1
    expected = (1 << local_vc0) | (1 << north_vc1)
    assert int(dut.protocol_error_o.value) == expected

    await reset_active_low(dut)
    await Timer(1, unit="ns")
    assert int(dut.protocol_error_o.value) == 0


@cocotb.test()
async def test_dual_vc_selection_holds_through_backpressure(dut):
    """One input presents one VC, holding it stable until downstream accepts."""
    await reset_router(dut)

    vc0_flit = make_flit(
        FLIT_HEADTAIL,
        ROUTER_X,
        ROUTER_Y,
        payload=0x1100,
    )
    vc1_flit = make_flit(
        FLIT_HEADTAIL,
        ROUTER_X,
        (ROUTER_Y - 1) % 4,
        payload=0x1101,
    )
    await accept_inputs(dut, {PORT_LOCAL: (vc0_flit, 0)})
    await accept_inputs(dut, {PORT_LOCAL: (vc1_flit, 1)})

    dut.out_ready_i.value = 1 << PORT_NORTH
    for _ in range(3):
        await assert_outputs(dut, {PORT_LOCAL: (vc0_flit, 0)})
        await transfer_outputs(dut)

    assert counter_value(dut, "flits_sent_o", PORT_LOCAL) == 0
    assert counter_value(dut, "flits_sent_o", PORT_NORTH) == 0

    dut.out_ready_i.value = 1 << PORT_LOCAL
    await assert_outputs(dut, {PORT_LOCAL: (vc0_flit, 0)})
    await transfer_outputs(dut)

    dut.out_ready_i.value = 1 << PORT_NORTH
    await assert_outputs(dut, {PORT_NORTH: (vc1_flit, 1)})
    await transfer_outputs(dut)
    assert counter_value(dut, "flits_sent_o", PORT_LOCAL) == 1
    assert counter_value(dut, "flits_sent_o", PORT_NORTH) == 1


@cocotb.test()
async def test_dual_vc_selection_round_robin_fairness(dut):
    """Sustained VC0 and VC1 traffic alternates on one physical input."""
    assert FIFO_DEPTH >= 3
    await reset_router(dut)

    vc0_flits = [
        make_flit(
            FLIT_HEADTAIL,
            ROUTER_X,
            ROUTER_Y,
            payload=0x1200 + index,
        )
        for index in range(3)
    ]
    vc1_flits = [
        make_flit(
            FLIT_HEADTAIL,
            ROUTER_X,
            (ROUTER_Y - 1) % 4,
            payload=0x1300 + index,
        )
        for index in range(3)
    ]

    for vc0_flit, vc1_flit in zip(vc0_flits, vc1_flits):
        await accept_inputs(dut, {PORT_LOCAL: (vc0_flit, 0)})
        await accept_inputs(dut, {PORT_LOCAL: (vc1_flit, 1)})

    dut.out_ready_i.value = (1 << PORT_LOCAL) | (1 << PORT_NORTH)
    for index in range(3):
        await assert_outputs(dut, {PORT_LOCAL: (vc0_flits[index], 0)})
        await transfer_outputs(dut)
        await assert_outputs(dut, {PORT_NORTH: (vc1_flits[index], 1)})
        await transfer_outputs(dut)

    assert counter_value(dut, "flits_received_o", PORT_LOCAL) == 6
    assert counter_value(dut, "flits_sent_o", PORT_LOCAL) == 3
    assert counter_value(dut, "flits_sent_o", PORT_NORTH) == 3


@cocotb.test()
async def test_dual_vc_selection_retries_after_output_loss(dut):
    """A VC that loses output arbitration yields one attempt to its sibling."""
    await reset_router(dut)

    competitor = make_flit(
        FLIT_HEADTAIL,
        ROUTER_X,
        ROUTER_Y,
        payload=0x1400,
    )
    blocked = make_flit(
        FLIT_HEADTAIL,
        ROUTER_X,
        ROUTER_Y,
        payload=0x1401,
    )
    alternate = make_flit(
        FLIT_HEADTAIL,
        ROUTER_X,
        (ROUTER_Y - 1) % 4,
        payload=0x1402,
    )

    await accept_inputs(dut, {PORT_NORTH: (competitor, 0)})
    await accept_inputs(dut, {PORT_LOCAL: (blocked, 0)})
    await accept_inputs(dut, {PORT_LOCAL: (alternate, 1)})

    dut.out_ready_i.value = 1 << PORT_NORTH
    await assert_outputs(
        dut,
        {
            PORT_LOCAL: (competitor, 0),
            PORT_NORTH: (alternate, 1),
        },
    )
    await transfer_outputs(dut)

    dut.out_ready_i.value = 1 << PORT_LOCAL
    await assert_outputs(dut, {PORT_LOCAL: (competitor, 0)})
    await transfer_outputs(dut)
    await assert_outputs(dut, {PORT_LOCAL: (blocked, 0)})
    await transfer_outputs(dut)

    assert counter_value(dut, "flits_sent_o", PORT_NORTH) == 1
    assert counter_value(dut, "flits_sent_o", PORT_LOCAL) == 2


@cocotb.test()
async def test_vc_classes_restart_at_x_to_y_dimension_boundary(dut):
    """A horizontal arrival restarts the VC class before entering Y."""
    assert (ROUTER_X, ROUTER_Y) == (3, 0)
    await reset_router(dut)
    dut.out_ready_i.value = (1 << NUM_PORTS) - 1

    y_non_dateline = make_flit(
        FLIT_HEADTAIL,
        3,
        1,
        src_x=1,
        src_y=0,
        payload=0xD00,
    )
    await accept_inputs(dut, {PORT_WEST: (y_non_dateline, 1)})
    await assert_outputs(dut, {PORT_SOUTH: (y_non_dateline, 0)})
    await transfer_outputs(dut)

    y_dateline = make_flit(
        FLIT_HEADTAIL,
        3,
        3,
        src_x=1,
        src_y=0,
        payload=0xD01,
    )
    await accept_inputs(dut, {PORT_EAST: (y_dateline, 1)})
    await assert_outputs(dut, {PORT_NORTH: (y_dateline, 1)})
    await transfer_outputs(dut)
