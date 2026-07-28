import os

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from common.clock_reset import reset_active_low, start_clock
from common.flit import FLIT_BODY, FLIT_HEAD, FLIT_HEADTAIL, FLIT_TAIL, make_flit


X_DIM = 4
Y_DIM = 4
NUM_NODES = X_DIM * Y_DIM
NUM_PORTS = 5
NUM_VCS = 2
FLIT_W = 64
VC_W = 1
COUNTER_W = 32
FIFO_DEPTH = int(os.environ["TORUS_FIFO_DEPTH"])
ALL_NODES = (1 << NUM_NODES) - 1

PORT_NORTH = 0
PORT_SOUTH = 1
PORT_EAST = 2
PORT_WEST = 3
PORT_LOCAL = 4


def node_index(x, y):
    return x * Y_DIM + y


def pack_fields(values, width):
    packed = 0
    mask = (1 << width) - 1
    for index, value in enumerate(values):
        packed |= (value & mask) << (index * width)
    return packed


def unpack_field(packed, index, width):
    return (packed >> (index * width)) & ((1 << width) - 1)


def output_flit(dut, node):
    return unpack_field(int(dut.local_out_flit_o.value), node, FLIT_W)


def output_vc(dut, node):
    return unpack_field(int(dut.local_out_vc_o.value), node, VC_W)


def node_port_counter(dut, signal_name, node, port):
    packed = int(getattr(dut, signal_name).value)
    return unpack_field(packed, node * NUM_PORTS + port, COUNTER_W)


def node_counter(dut, signal_name, node):
    packed = int(getattr(dut, signal_name).value)
    return unpack_field(packed, node, COUNTER_W)


def drive_injections(dut, requests):
    valid = 0
    flits = [0] * NUM_NODES
    vcs = [0] * NUM_NODES

    for node, (flit, vc) in requests.items():
        valid |= 1 << node
        flits[node] = flit
        vcs[node] = vc

    dut.local_in_valid_i.value = valid
    dut.local_in_flit_i.value = pack_fields(flits, FLIT_W)
    dut.local_in_vc_i.value = pack_fields(vcs, VC_W)


async def reset_torus(dut):
    drive_injections(dut, {})
    dut.local_out_ready_i.value = 0
    start_clock(dut)
    await reset_active_low(dut)
    await Timer(1, unit="ns")


async def accept_injections(dut, requests, max_cycles=40):
    drive_injections(dut, requests)
    requested_mask = sum(1 << node for node in requests)

    for _ in range(max_cycles):
        await Timer(1, unit="ns")
        if int(dut.local_in_ready_o.value) & requested_mask == requested_mask:
            await RisingEdge(dut.clk)
            await FallingEdge(dut.clk)
            drive_injections(dut, {})
            return
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)

    raise AssertionError(f"injection timeout for mask 0x{requested_mask:04x}")


async def wait_for_delivery(dut, destination, expected_flit, expected_vc, max_cycles=40):
    expected_mask = 1 << destination

    for cycles in range(max_cycles + 1):
        await Timer(1, unit="ns")
        valid = int(dut.local_out_valid_o.value)
        assert valid & ~expected_mask == 0

        if valid == expected_mask:
            assert output_flit(dut, destination) == expected_flit
            assert output_vc(dut, destination) == expected_vc
            await RisingEdge(dut.clk)
            await FallingEdge(dut.clk)
            return cycles

        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)

    raise AssertionError(f"delivery timeout at node {destination}")


async def wait_for_held_outputs(dut, expected, max_cycles=50):
    expected_mask = sum(1 << node for node in expected)

    for _ in range(max_cycles):
        await Timer(1, unit="ns")
        valid = int(dut.local_out_valid_o.value)
        assert valid & ~expected_mask == 0

        if valid == expected_mask:
            for node, (flit, vc) in expected.items():
                assert output_flit(dut, node) == flit
                assert output_vc(dut, node) == vc
            return

        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)

    raise AssertionError(f"held-output timeout for mask 0x{expected_mask:04x}")


@cocotb.test()
async def test_directed_minimal_paths_and_datelines(dut):
    """Directed paths cover local, cardinal, wrap, tie, and longest routes."""
    await reset_torus(dut)
    dut.local_out_ready_i.value = ALL_NODES

    cases = (
        ((1, 1), (1, 1), 0, 0),
        ((0, 0), (1, 0), 0, 1),
        ((2, 1), (1, 1), 0, 1),
        ((1, 0), (1, 1), 0, 1),
        ((1, 2), (1, 1), 0, 1),
        ((3, 0), (0, 0), 1, 1),
        ((0, 1), (3, 1), 1, 1),
        ((2, 3), (2, 0), 1, 1),
        ((1, 0), (1, 3), 1, 1),
        ((0, 2), (2, 2), 0, 2),
        ((2, 0), (2, 2), 0, 2),
        ((3, 3), (1, 1), 1, 4),
    )

    for payload, (source, destination, expected_vc, expected_hops) in enumerate(cases):
        src_x, src_y = source
        dst_x, dst_y = destination
        source_node = node_index(src_x, src_y)
        destination_node = node_index(dst_x, dst_y)
        flit = make_flit(
            FLIT_HEADTAIL,
            dst_x,
            dst_y,
            src_x=src_x,
            src_y=src_y,
            payload=0x1000 + payload,
        )

        await accept_injections(dut, {source_node: (flit, 0)})
        observed_hops = await wait_for_delivery(
            dut,
            destination_node,
            flit,
            expected_vc,
        )
        assert observed_hops == expected_hops


@cocotb.test()
async def test_multiflit_packet_crosses_dateline_in_order(dut):
    """A three-flit packet remains ordered and in VC1 after a wrap crossing."""
    assert FIFO_DEPTH >= 3
    await reset_torus(dut)

    source = node_index(3, 0)
    destination = node_index(1, 0)
    packet = (
        make_flit(FLIT_HEAD, 1, 0, src_x=3, src_y=0, pkt_len=3, payload=0xA0),
        make_flit(FLIT_BODY, 3, 3, src_x=3, src_y=0, pkt_len=3, payload=0xA1),
        make_flit(FLIT_TAIL, 0, 3, src_x=3, src_y=0, pkt_len=3, payload=0xA2),
    )

    for flit in packet:
        await accept_injections(dut, {source: (flit, 0)})

    await wait_for_held_outputs(dut, {destination: (packet[0], 1)})
    dut.local_out_ready_i.value = 1 << destination

    for expected_flit in packet:
        await wait_for_delivery(dut, destination, expected_flit, 1)

    await Timer(1, unit="ns")
    assert int(dut.local_out_valid_o.value) == 0


@cocotb.test()
async def test_concurrent_end_to_end_deliveries(dut):
    """Concurrent packets on overlapping routes all reach distinct destinations."""
    await reset_torus(dut)

    pairs = (
        ((0, 0), (2, 2), 0),
        ((3, 3), (1, 1), 1),
        ((0, 3), (3, 0), 1),
        ((2, 1), (1, 3), 0),
    )
    requests = {}
    expected = {}

    for payload, (source, destination, vc) in enumerate(pairs):
        src_x, src_y = source
        dst_x, dst_y = destination
        source_node = node_index(src_x, src_y)
        destination_node = node_index(dst_x, dst_y)
        flit = make_flit(
            FLIT_HEADTAIL,
            dst_x,
            dst_y,
            src_x=src_x,
            src_y=src_y,
            payload=0x2000 + payload,
        )
        requests[source_node] = (flit, 0)
        expected[destination_node] = (flit, vc)

    await accept_injections(dut, requests)
    await wait_for_held_outputs(dut, expected)

    expected_mask = sum(1 << node for node in expected)
    dut.local_out_ready_i.value = expected_mask
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert int(dut.local_out_valid_o.value) == 0


@cocotb.test()
async def test_network_counter_exposure_and_backpressure(dut):
    """Network outputs preserve node-major counter ordering and event counts."""
    await reset_torus(dut)

    for signal_name in (
        "flits_received_o",
        "flits_sent_o",
        "blocked_empty_o",
        "blocked_backpressure_o",
        "packets_ejected_o",
    ):
        assert int(getattr(dut, signal_name).value) == 0

    source = node_index(0, 0)
    destination = node_index(1, 0)
    flit = make_flit(
        FLIT_HEADTAIL,
        1,
        0,
        src_x=0,
        src_y=0,
        payload=0x3000,
    )

    await accept_injections(dut, {source: (flit, 0)})
    await wait_for_held_outputs(dut, {destination: (flit, 0)})

    baseline = node_port_counter(
        dut,
        "blocked_backpressure_o",
        destination,
        PORT_LOCAL,
    )
    for _ in range(3):
        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)

    assert node_port_counter(
        dut,
        "blocked_backpressure_o",
        destination,
        PORT_LOCAL,
    ) == baseline + 3

    dut.local_out_ready_i.value = 1 << destination
    await wait_for_delivery(dut, destination, flit, 0)

    assert node_port_counter(
        dut,
        "flits_received_o",
        source,
        PORT_LOCAL,
    ) == 1
    assert node_port_counter(dut, "flits_sent_o", source, PORT_EAST) == 1
    assert node_port_counter(
        dut,
        "flits_received_o",
        destination,
        PORT_WEST,
    ) == 1
    assert node_port_counter(
        dut,
        "flits_sent_o",
        destination,
        PORT_LOCAL,
    ) == 1
    assert node_counter(dut, "packets_ejected_o", destination) == 1


@cocotb.test()
async def test_protocol_error_node_major_exposure(dut):
    """Malformed traffic is forwarded while node-major status remains sticky."""
    await reset_torus(dut)
    assert int(dut.protocol_error_o.value) == 0

    source = node_index(2, 1)
    malformed = make_flit(
        FLIT_BODY,
        3,
        1,
        src_x=2,
        src_y=1,
        payload=0x4000,
    )
    await accept_injections(dut, {source: (malformed, 1)})

    error_index = (source * NUM_PORTS * NUM_VCS) + (PORT_LOCAL * NUM_VCS) + 1
    assert int(dut.protocol_error_o.value) == 1 << error_index

    destination = node_index(3, 1)
    dut.local_out_ready_i.value = 1 << destination
    await wait_for_delivery(dut, destination, malformed, 1)

    destination_error_index = (
        (destination * NUM_PORTS * NUM_VCS) + (PORT_WEST * NUM_VCS) + 1
    )
    expected_errors = (1 << error_index) | (1 << destination_error_index)
    assert int(dut.protocol_error_o.value) == expected_errors

    await reset_active_low(dut)
    await Timer(1, unit="ns")
    assert int(dut.protocol_error_o.value) == 0
