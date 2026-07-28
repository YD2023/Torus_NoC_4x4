from dataclasses import dataclass

from common.flit import FLIT_BODY, FLIT_HEAD, FLIT_HEADTAIL, FLIT_TAIL
from common.packed import unpack_field


@dataclass(frozen=True)
class ExpectedPacket:
    packet_id: int
    source: int
    destination: int
    flits: tuple[int, ...]
    final_vc: int


class PacketScoreboard:
    """Check exact packet delivery, ejection VC, order, and contiguity."""

    def __init__(self, packets):
        self.packets = {packet.packet_id: packet for packet in packets}
        self.flit_lookup = {}
        self.next_index = {packet.packet_id: 0 for packet in packets}
        self.active_packet = {}
        self.completed = set()
        self.observed_flits = 0

        for packet in packets:
            if not packet.flits:
                raise ValueError(f"packet {packet.packet_id} has no flits")
            for index, flit in enumerate(packet.flits):
                if flit in self.flit_lookup:
                    raise ValueError(f"flit 0x{flit:016x} is not unique")
                self.flit_lookup[flit] = (packet.packet_id, index)

    @property
    def complete(self):
        return len(self.completed) == len(self.packets)

    @property
    def remaining_packets(self):
        return len(self.packets) - len(self.completed)

    @property
    def expected_flits(self):
        return len(self.flit_lookup)

    def observe(self, destination, flit, vc):
        if flit not in self.flit_lookup:
            raise AssertionError(
                f"unexpected flit 0x{flit:016x} ejected at node {destination}"
            )

        packet_id, index = self.flit_lookup[flit]
        packet = self.packets[packet_id]
        expected_index = self.next_index[packet_id]
        flit_type = (flit >> 62) & 0x3
        stream = (destination, vc)

        if packet_id in self.completed:
            raise AssertionError(f"packet {packet_id} was delivered more than once")
        if destination != packet.destination:
            raise AssertionError(
                f"packet {packet_id} reached node {destination}, "
                f"expected {packet.destination}"
            )
        if vc != packet.final_vc:
            raise AssertionError(
                f"packet {packet_id} ejected on VC{vc}, "
                f"expected VC{packet.final_vc}"
            )
        if index != expected_index:
            raise AssertionError(
                f"packet {packet_id} flit index {index} arrived, "
                f"expected {expected_index}"
            )

        active = self.active_packet.get(stream)
        if flit_type == FLIT_HEAD:
            if active is not None:
                raise AssertionError(
                    f"packet {packet_id} head interleaved into packet {active} "
                    f"at node {destination}"
                )
            if index != 0 or len(packet.flits) == 1:
                raise AssertionError(f"packet {packet_id} has an illegal HEAD")
            self.active_packet[stream] = packet_id
        elif flit_type == FLIT_HEADTAIL:
            if active is not None:
                raise AssertionError(
                    f"single-flit packet {packet_id} interleaved into packet "
                    f"{active} at node {destination}"
                )
            if index != 0 or len(packet.flits) != 1:
                raise AssertionError(f"packet {packet_id} has an illegal HEADTAIL")
        elif flit_type in (FLIT_BODY, FLIT_TAIL):
            if active != packet_id:
                raise AssertionError(
                    f"packet {packet_id} continuation arrived while packet "
                    f"{active} owns node {destination}"
                )
            if flit_type == FLIT_TAIL and index != len(packet.flits) - 1:
                raise AssertionError(f"packet {packet_id} has an early TAIL")
            if flit_type == FLIT_BODY and index == len(packet.flits) - 1:
                raise AssertionError(f"packet {packet_id} ends with BODY")
        else:
            raise AssertionError(f"packet {packet_id} has invalid flit type")

        self.next_index[packet_id] += 1
        self.observed_flits += 1
        if flit_type in (FLIT_TAIL, FLIT_HEADTAIL):
            if self.next_index[packet_id] != len(packet.flits):
                raise AssertionError(f"packet {packet_id} terminated early")
            self.completed.add(packet_id)
            self.active_packet.pop(stream, None)

    def assert_complete(self):
        if not self.complete:
            pending = sorted(set(self.packets) - self.completed)
            raise AssertionError(f"undelivered packets: {pending}")
        if self.active_packet:
            raise AssertionError(f"unterminated ejection streams: {self.active_packet}")
        if self.observed_flits != self.expected_flits:
            raise AssertionError(
                f"observed {self.observed_flits} flits, "
                f"expected {self.expected_flits}"
            )


def sample_ejections(dut, *, num_nodes=16, flit_width=64, vc_width=1):
    """Return all local output transfers visible in the current cycle."""
    transfer_mask = int(dut.local_out_valid_o.value) & int(
        dut.local_out_ready_i.value
    )
    packed_flits = int(dut.local_out_flit_o.value)
    packed_vcs = int(dut.local_out_vc_o.value)

    return [
        (
            node,
            unpack_field(packed_flits, node, flit_width),
            unpack_field(packed_vcs, node, vc_width),
        )
        for node in range(num_nodes)
        if transfer_mask & (1 << node)
    ]


class TorusEjectionMonitor:
    """Sample transfers and enforce valid/ready stability under backpressure."""

    def __init__(self, dut, *, num_nodes=16, flit_width=64, vc_width=1):
        self.dut = dut
        self.num_nodes = num_nodes
        self.flit_width = flit_width
        self.vc_width = vc_width
        self.held = {}

    def sample(self):
        valid_mask = int(self.dut.local_out_valid_o.value)
        ready_mask = int(self.dut.local_out_ready_i.value)
        packed_flits = int(self.dut.local_out_flit_o.value)
        packed_vcs = int(self.dut.local_out_vc_o.value)
        transfers = []

        for node in range(self.num_nodes):
            valid = bool(valid_mask & (1 << node))
            ready = bool(ready_mask & (1 << node))
            flit = unpack_field(packed_flits, node, self.flit_width)
            vc = unpack_field(packed_vcs, node, self.vc_width)

            if node in self.held:
                if not valid:
                    raise AssertionError(
                        f"node {node} withdrew valid while backpressured"
                    )
                if (flit, vc) != self.held[node]:
                    raise AssertionError(
                        f"node {node} changed flit or VC while backpressured"
                    )

            if valid and ready:
                transfers.append((node, flit, vc))

            if valid and not ready:
                self.held[node] = (flit, vc)
            else:
                self.held.pop(node, None)

        return transfers
