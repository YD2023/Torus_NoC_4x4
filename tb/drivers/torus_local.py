from collections import deque
from dataclasses import dataclass

from common.packed import pack_fields


@dataclass(frozen=True)
class Injection:
    packet_id: int
    flit: int
    vc: int


class TorusLocalDriver:
    """Drive independent valid/ready injection streams at all local ports."""

    def __init__(self, dut, *, num_nodes=16, flit_width=64, vc_width=1):
        self.dut = dut
        self.num_nodes = num_nodes
        self.flit_width = flit_width
        self.vc_width = vc_width
        self.queues = [deque() for _ in range(num_nodes)]

    def enqueue_packet(self, source, packet_id, flits, *, vc=0):
        if not flits:
            raise ValueError("a packet must contain at least one flit")
        for flit in flits:
            self.enqueue_flit(source, packet_id, flit, vc=vc)

    def enqueue_flit(self, source, packet_id, flit, *, vc=0):
        """Queue one flit, allowing deliberate interleaving across input VCs."""
        if not 0 <= source < self.num_nodes:
            raise ValueError(f"invalid source node {source}")
        if not 0 <= vc < (1 << self.vc_width):
            raise ValueError(f"invalid VC {vc}")
        self.queues[source].append(Injection(packet_id=packet_id, flit=flit, vc=vc))

    def clear(self):
        """Discard all queued injections and release the physical inputs."""
        for queue in self.queues:
            queue.clear()
        self.clear_signals()

    @property
    def empty(self):
        return all(not queue for queue in self.queues)

    @property
    def pending_flits(self):
        return sum(len(queue) for queue in self.queues)

    def clear_signals(self):
        self.dut.local_in_valid_i.value = 0
        self.dut.local_in_flit_i.value = 0
        self.dut.local_in_vc_i.value = 0

    def drive(self):
        valid = 0
        flits = [0] * self.num_nodes
        vcs = [0] * self.num_nodes

        for source, queue in enumerate(self.queues):
            if queue:
                injection = queue[0]
                valid |= 1 << source
                flits[source] = injection.flit
                vcs[source] = injection.vc

        self.dut.local_in_flit_i.value = pack_fields(flits, self.flit_width)
        self.dut.local_in_vc_i.value = pack_fields(vcs, self.vc_width)
        self.dut.local_in_valid_i.value = valid

    def commit(self, ready_mask):
        """Pop and return injections accepted on the current cycle."""
        accepted = []
        for source, queue in enumerate(self.queues):
            if queue and ready_mask & (1 << source):
                accepted.append((source, queue.popleft()))
        return accepted
