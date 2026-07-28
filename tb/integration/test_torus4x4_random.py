import os
import random

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from common.clock_reset import reset_active_low, start_clock
from common.flit import FLIT_BODY, FLIT_HEAD, FLIT_HEADTAIL, FLIT_TAIL, make_flit
from drivers.torus_local import TorusLocalDriver
from model.functional_coverage import TorusFunctionalCoverage
from model.torus_ref import final_vc, node_coord
from monitors.torus_scoreboard import (
    ExpectedPacket,
    PacketScoreboard,
    TorusEjectionMonitor,
)


NUM_NODES = 16
ALL_NODES = (1 << NUM_NODES) - 1
BASE_SEED = int(os.environ["TORUS_RANDOM_SEED"])
PACKET_COUNT = int(os.environ["RANDOM_PACKETS"])
COVERAGE_FILE = os.environ["TORUS_COVERAGE_FILE"]
RUN_COVERAGE = TorusFunctionalCoverage()


def make_packet(packet_id, source, destination, length):
    src_x, src_y = node_coord(source)
    dst_x, dst_y = node_coord(destination)
    if length == 1:
        flit_types = (FLIT_HEADTAIL,)
    else:
        flit_types = (FLIT_HEAD,) + (FLIT_BODY,) * (length - 2) + (FLIT_TAIL,)

    flits = tuple(
        make_flit(
            flit_type,
            dst_x,
            dst_y,
            src_x=src_x,
            src_y=src_y,
            pkt_len=length,
            payload=(packet_id << 6) | index,
        )
        for index, flit_type in enumerate(flit_types)
    )
    return ExpectedPacket(
        packet_id=packet_id,
        source=source,
        destination=destination,
        flits=flits,
        final_vc=final_vc((src_x, src_y), (dst_x, dst_y)),
    )


def uniform_packets(rng, count):
    packets = []
    for packet_id in range(count):
        source = rng.randrange(NUM_NODES)
        destination = rng.randrange(NUM_NODES)
        length = rng.randint(1, 4)
        packets.append(make_packet(packet_id, source, destination, length))
    return packets


def hotspot_packets(rng, count, hotspot=0):
    packets = []
    for offset in range(count):
        packet_id = 1_000_000 + offset
        source = rng.randrange(NUM_NODES)
        if rng.random() < 0.75:
            destination = hotspot
        else:
            destination = rng.randrange(NUM_NODES)
        length = rng.randint(1, 4)
        packets.append(make_packet(packet_id, source, destination, length))
    return packets


async def reset_network(dut, driver):
    driver.clear_signals()
    dut.local_out_ready_i.value = 0
    start_clock(dut)
    await reset_active_low(dut)


async def run_traffic(dut, packets, *, seed, ready_probability=0.80):
    rng = random.Random(seed)
    driver = TorusLocalDriver(dut)
    monitor = TorusEjectionMonitor(dut)
    scoreboard = PacketScoreboard(packets)

    for packet in packets:
        driver.enqueue_packet(
            packet.source,
            packet.packet_id,
            packet.flits,
            vc=0,
        )

    await reset_network(dut, driver)

    no_progress_cycles = 0
    watchdog_limit = 200
    cycle_limit = 500 + (len(packets) * 80)

    for cycle in range(cycle_limit):
        driver.drive()
        if cycle % 8 == 0:
            ready_mask = ALL_NODES
        else:
            ready_mask = sum(
                (1 << node)
                for node in range(NUM_NODES)
                if rng.random() < ready_probability
            )
        dut.local_out_ready_i.value = ready_mask

        await Timer(1, unit="ns")
        injection_ready = int(dut.local_in_ready_o.value)
        ejections = monitor.sample()

        await RisingEdge(dut.clk)
        accepted = driver.commit(injection_ready)
        for destination, flit, vc in ejections:
            scoreboard.observe(destination, flit, vc)

        if accepted or ejections:
            no_progress_cycles = 0
        else:
            no_progress_cycles += 1

        if driver.empty and scoreboard.complete:
            scoreboard.assert_complete()
            protocol_errors = int(dut.protocol_error_o.value)
            assert protocol_errors == 0, (
                f"legal traffic raised protocol status 0x{protocol_errors:040x}"
            )
            dut._log.info(
                "drained %d packets / %d flits in %d cycles (seed=%d)",
                len(packets),
                scoreboard.observed_flits,
                cycle + 1,
                seed,
            )
            return

        if no_progress_cycles > watchdog_limit:
            raise AssertionError(
                f"no endpoint progress for {no_progress_cycles} cycles; "
                f"{driver.pending_flits} flits await injection and "
                f"{scoreboard.remaining_packets} packets await delivery "
                f"(seed={seed}, cycle={cycle})"
            )

        await FallingEdge(dut.clk)

    raise AssertionError(
        f"traffic did not drain within {cycle_limit} cycles; "
        f"{driver.pending_flits} flits await injection and "
        f"{scoreboard.remaining_packets} packets await delivery (seed={seed})"
    )


@cocotb.test()
async def test_uniform_random_traffic(dut):
    """Uniform traffic delivers exact packets under randomized backpressure."""
    seed = BASE_SEED
    packets = uniform_packets(random.Random(seed), PACKET_COUNT)
    RUN_COVERAGE.sample_packets(packets, "uniform")
    RUN_COVERAGE.write_json(COVERAGE_FILE)
    await run_traffic(dut, packets, seed=seed)


@cocotb.test()
async def test_hotspot_random_traffic(dut):
    """A shared hotspot drains without packet corruption or starvation."""
    seed = BASE_SEED ^ 0x5A17
    packets = hotspot_packets(random.Random(seed), PACKET_COUNT)
    RUN_COVERAGE.sample_packets(packets, "hotspot")
    RUN_COVERAGE.write_json(COVERAGE_FILE)
    await run_traffic(dut, packets, seed=seed, ready_probability=0.75)


@cocotb.test()
async def test_random_traffic_functional_coverage(dut):
    """The combined random patterns must hit the required architecture bins."""
    RUN_COVERAGE.assert_random_run_complete()
    RUN_COVERAGE.write_json(COVERAGE_FILE)
    dut._log.info("functional coverage: %s", RUN_COVERAGE.summary())
