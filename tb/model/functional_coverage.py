"""Functional coverage for deterministic 4x4 torus traffic."""

import json
from dataclasses import dataclass, field
from pathlib import Path

from model.torus_ref import Direction, final_vc, node_coord, route_path


ALL_DIRECTIONS = {direction.name for direction in Direction}
ALL_DATELINES = {
    Direction.NORTH.name,
    Direction.SOUTH.name,
    Direction.EAST.name,
    Direction.WEST.name,
}
ALL_HOP_COUNTS = set(range(5))
ALL_PACKET_LENGTHS = set(range(1, 5))
ALL_FINAL_VCS = {0, 1}
ALL_TIE_DIMENSIONS = {"X", "Y"}
ALL_TRAFFIC_PATTERNS = {"uniform", "hotspot"}


def _sorted(values):
    return sorted(values, key=lambda value: (isinstance(value, str), value))


@dataclass
class TorusFunctionalCoverage:
    packet_count: int = 0
    flit_count: int = 0
    source_nodes: set[int] = field(default_factory=set)
    destination_nodes: set[int] = field(default_factory=set)
    source_destination_pairs: set[str] = field(default_factory=set)
    directions: set[str] = field(default_factory=set)
    datelines: set[str] = field(default_factory=set)
    hop_counts: set[int] = field(default_factory=set)
    packet_lengths: set[int] = field(default_factory=set)
    final_vcs: set[int] = field(default_factory=set)
    tie_dimensions: set[str] = field(default_factory=set)
    traffic_patterns: set[str] = field(default_factory=set)

    def sample(self, source, destination, packet_length, traffic_pattern):
        if not 0 <= source < 16 or not 0 <= destination < 16:
            raise ValueError("coverage node index outside 4x4 torus")
        if packet_length <= 0:
            raise ValueError("packet length must be positive")
        if not traffic_pattern:
            raise ValueError("traffic pattern must be named")

        source_coord = node_coord(source)
        destination_coord = node_coord(destination)
        path = route_path(source_coord, destination_coord)

        self.packet_count += 1
        self.flit_count += packet_length
        self.source_nodes.add(source)
        self.destination_nodes.add(destination)
        self.source_destination_pairs.add(f"{source}->{destination}")
        self.hop_counts.add(len(path))
        self.packet_lengths.add(packet_length)
        self.final_vcs.add(final_vc(source_coord, destination_coord))
        self.traffic_patterns.add(traffic_pattern)

        if not path:
            self.directions.add(Direction.LOCAL.name)
        for hop in path:
            self.directions.add(hop.direction.name)
            if hop.crosses_dateline:
                self.datelines.add(hop.direction.name)

        src_x, src_y = source_coord
        dst_x, dst_y = destination_coord
        if src_x != dst_x:
            positive = (dst_x - src_x) % 4
            negative = (src_x - dst_x) % 4
            if positive == negative:
                self.tie_dimensions.add("X")
        if src_y != dst_y:
            positive = (dst_y - src_y) % 4
            negative = (src_y - dst_y) % 4
            if positive == negative:
                self.tie_dimensions.add("Y")

    def sample_packets(self, packets, traffic_pattern):
        for packet in packets:
            self.sample(
                packet.source,
                packet.destination,
                len(packet.flits),
                traffic_pattern,
            )

    def merge(self, other):
        self.packet_count += other.packet_count
        self.flit_count += other.flit_count
        for field_name in self._bin_names():
            getattr(self, field_name).update(getattr(other, field_name))
        return self

    def missing_required_bins(self):
        required = {
            "directions": ALL_DIRECTIONS,
            "datelines": ALL_DATELINES,
            "hop_counts": ALL_HOP_COUNTS,
            "packet_lengths": ALL_PACKET_LENGTHS,
            "final_vcs": ALL_FINAL_VCS,
            "tie_dimensions": ALL_TIE_DIMENSIONS,
            "traffic_patterns": ALL_TRAFFIC_PATTERNS,
        }
        return {
            name: _sorted(values - getattr(self, name))
            for name, values in required.items()
            if values - getattr(self, name)
        }

    def assert_random_run_complete(
        self,
        *,
        minimum_source_nodes=14,
        minimum_destination_nodes=14,
        minimum_pairs=48,
    ):
        missing = self.missing_required_bins()
        if missing:
            raise AssertionError(f"missing functional coverage bins: {missing}")

        breadth = {
            "source_nodes": (len(self.source_nodes), minimum_source_nodes),
            "destination_nodes": (
                len(self.destination_nodes),
                minimum_destination_nodes,
            ),
            "source_destination_pairs": (
                len(self.source_destination_pairs),
                minimum_pairs,
            ),
        }
        shortfalls = {
            name: {"observed": observed, "required": required}
            for name, (observed, required) in breadth.items()
            if observed < required
        }
        if shortfalls:
            raise AssertionError(f"functional coverage breadth shortfall: {shortfalls}")

    def summary(self):
        return (
            f"{self.packet_count} packets, {self.flit_count} flits, "
            f"{len(self.source_destination_pairs)}/256 source/destination pairs, "
            f"{len(self.source_nodes)}/16 sources, "
            f"{len(self.destination_nodes)}/16 destinations"
        )

    def to_dict(self):
        bins = {
            field_name: _sorted(getattr(self, field_name))
            for field_name in self._bin_names()
        }
        return {
            "schema_version": 1,
            "packet_count": self.packet_count,
            "flit_count": self.flit_count,
            "bins": bins,
        }

    @classmethod
    def from_dict(cls, report):
        if report.get("schema_version") != 1:
            raise ValueError("unsupported functional coverage schema")
        coverage = cls(
            packet_count=int(report["packet_count"]),
            flit_count=int(report["flit_count"]),
        )
        bins = report["bins"]
        for field_name in cls._bin_names():
            setattr(coverage, field_name, set(bins[field_name]))
        return coverage

    def write_json(self, path):
        output = Path(path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(
            json.dumps(self.to_dict(), indent=2, sort_keys=True) + "\n",
            encoding="ascii",
        )

    @classmethod
    def read_json(cls, path):
        return cls.from_dict(json.loads(Path(path).read_text(encoding="ascii")))

    @staticmethod
    def _bin_names():
        return (
            "source_nodes",
            "destination_nodes",
            "source_destination_pairs",
            "directions",
            "datelines",
            "hop_counts",
            "packet_lengths",
            "final_vcs",
            "tie_dimensions",
            "traffic_patterns",
        )
