import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from common.clock_reset import reset_active_low, start_clock
from common.flit import FLIT_BODY, FLIT_HEAD, FLIT_HEADTAIL, FLIT_TAIL, make_flit
from drivers.torus_local import TorusLocalDriver
from model.torus_ref import final_vc, node_coord
from monitors.torus_scoreboard import (
    ExpectedPacket,
    PacketScoreboard,
    TorusEjectionMonitor,
)


NUM_NODES = 16
ALL_NODES = (1 << NUM_NODES) - 1


def make_packet(packet_id, source, destination, length, *, incoming_vc=0):
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
            payload=(packet_id << 8) | index,
        )
        for index, flit_type in enumerate(flit_types)
    )
    return ExpectedPacket(
        packet_id=packet_id,
        source=source,
        destination=destination,
        flits=flits,
        final_vc=final_vc(
            (src_x, src_y),
            (dst_x, dst_y),
            incoming_vc=incoming_vc,
        ),
    )


async def reset_network(dut, driver):
    driver.clear()
    dut.local_out_ready_i.value = 0
    start_clock(dut)
    await reset_active_low(dut)


async def drain_packets(dut, driver, packets, *, ready_pattern, cycle_limit=1200):
    scoreboard = PacketScoreboard(packets)
    monitor = TorusEjectionMonitor(dut)
    no_progress_cycles = 0

    for cycle in range(cycle_limit):
        driver.drive()
        dut.local_out_ready_i.value = ready_pattern(cycle)
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
            assert int(dut.protocol_error_o.value) == 0
            return cycle + 1

        if no_progress_cycles > 250:
            raise AssertionError(
                f"no progress for {no_progress_cycles} cycles with "
                f"{driver.pending_flits} injections and "
                f"{scoreboard.remaining_packets} packets remaining"
            )

        await FallingEdge(dut.clk)

    raise AssertionError(
        f"closure traffic did not drain in {cycle_limit} cycles; "
        f"{driver.pending_flits} injections and "
        f"{scoreboard.remaining_packets} packets remain"
    )


@cocotb.test()
async def test_packet_longer_than_fifo_depth_under_backpressure(dut):
    """An 11-flit packet streams through depth-3 FIFOs without corruption."""
    driver = TorusLocalDriver(dut)
    await reset_network(dut, driver)

    packet = make_packet(
        packet_id=0x51,
        source=12,
        destination=4,
        length=11,
    )
    driver.enqueue_packet(packet.source, packet.packet_id, packet.flits, vc=0)

    cycles = await drain_packets(
        dut,
        driver,
        (packet,),
        ready_pattern=lambda cycle: ALL_NODES if cycle % 5 in (0, 3, 4) else 0,
    )
    assert cycles > len(packet.flits)


@cocotb.test()
async def test_sustained_dual_vc_streams_share_one_physical_input(dut):
    """Interleaved VC0/VC1 packets make independent ordered progress."""
    driver = TorusLocalDriver(dut)
    await reset_network(dut, driver)

    vc0_packet = make_packet(
        packet_id=0x61,
        source=5,
        destination=9,
        length=8,
        incoming_vc=0,
    )
    vc1_packet = make_packet(
        packet_id=0x62,
        source=5,
        destination=6,
        length=8,
        incoming_vc=1,
    )
    for vc0_flit, vc1_flit in zip(vc0_packet.flits, vc1_packet.flits):
        driver.enqueue_flit(5, vc0_packet.packet_id, vc0_flit, vc=0)
        driver.enqueue_flit(5, vc1_packet.packet_id, vc1_flit, vc=1)

    await drain_packets(
        dut,
        driver,
        (vc0_packet, vc1_packet),
        ready_pattern=lambda cycle: (
            ALL_NODES if cycle % 4 else ALL_NODES & ~(1 << 9)
        ),
    )


@cocotb.test()
async def test_reset_flushes_inflight_traffic_and_recovers(dut):
    """Reset discards resident traffic and leaves the network reusable."""
    driver = TorusLocalDriver(dut)
    await reset_network(dut, driver)

    interrupted = make_packet(
        packet_id=0x71,
        source=0,
        destination=10,
        length=32,
    )
    driver.enqueue_packet(
        interrupted.source,
        interrupted.packet_id,
        interrupted.flits,
        vc=0,
    )

    accepted_count = 0
    for _ in range(6):
        driver.drive()
        dut.local_out_ready_i.value = 0
        await Timer(1, unit="ns")
        injection_ready = int(dut.local_in_ready_o.value)
        await RisingEdge(dut.clk)
        accepted_count += len(driver.commit(injection_ready))
        await FallingEdge(dut.clk)

    assert accepted_count > 0
    assert not driver.empty

    driver.clear()
    dut.local_out_ready_i.value = 0
    await reset_active_low(dut)
    await Timer(1, unit="ns")

    for signal_name in (
        "local_out_valid_o",
        "protocol_error_o",
        "flits_received_o",
        "flits_sent_o",
        "blocked_empty_o",
        "blocked_backpressure_o",
        "packets_ejected_o",
    ):
        assert int(getattr(dut, signal_name).value) == 0

    recovered = make_packet(
        packet_id=0x72,
        source=15,
        destination=0,
        length=4,
    )
    driver.enqueue_packet(
        recovered.source,
        recovered.packet_id,
        recovered.flits,
        vc=0,
    )
    await drain_packets(
        dut,
        driver,
        (recovered,),
        ready_pattern=lambda _cycle: ALL_NODES,
    )
