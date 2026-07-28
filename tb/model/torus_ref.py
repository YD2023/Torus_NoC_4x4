"""Independent routing oracle for the 4x4 deterministic torus."""

from dataclasses import dataclass
from enum import IntEnum


X_DIM = 4
Y_DIM = 4
VC0 = 0
VC1 = 1


class Direction(IntEnum):
    NORTH = 0
    SOUTH = 1
    EAST = 2
    WEST = 3
    LOCAL = 4


@dataclass(frozen=True)
class Hop:
    current: tuple[int, int]
    direction: Direction
    next_coord: tuple[int, int]
    incoming_vc: int
    outgoing_vc: int
    crosses_dateline: bool
    dimension_change: bool


def node_index(x: int, y: int, *, y_dim: int = Y_DIM) -> int:
    """Map an (x, y) coordinate to the RTL's packed endpoint index."""
    return x * y_dim + y


def node_coord(index: int, *, y_dim: int = Y_DIM) -> tuple[int, int]:
    """Invert node_index for a packed endpoint index."""
    return divmod(index, y_dim)


def minimal_hops(
    source: tuple[int, int],
    destination: tuple[int, int],
    *,
    x_dim: int = X_DIM,
    y_dim: int = Y_DIM,
) -> int:
    """Return the Manhattan distance using minimal movement on each ring."""
    dx = abs(destination[0] - source[0])
    dy = abs(destination[1] - source[1])
    return min(dx, x_dim - dx) + min(dy, y_dim - dy)


def _ring_direction(current: int, destination: int, size: int) -> int:
    """Return +1 or -1 for a minimal ring hop; positive wins ties."""
    positive = (destination - current) % size
    negative = (current - destination) % size
    return 1 if positive <= negative else -1


def next_hop(
    current: tuple[int, int],
    destination: tuple[int, int],
    incoming_vc: int = VC0,
    incoming_direction: Direction | None = None,
    *,
    x_dim: int = X_DIM,
    y_dim: int = Y_DIM,
) -> Hop | None:
    """Compute one X-then-Y hop with dimension-local dateline VC classes."""
    if incoming_vc not in (VC0, VC1):
        raise ValueError(f"invalid incoming VC {incoming_vc}")

    cur_x, cur_y = current
    dst_x, dst_y = destination
    if not (0 <= cur_x < x_dim and 0 <= dst_x < x_dim):
        raise ValueError("x coordinate outside torus")
    if not (0 <= cur_y < y_dim and 0 <= dst_y < y_dim):
        raise ValueError("y coordinate outside torus")

    if current == destination:
        return None

    if cur_x != dst_x:
        step = _ring_direction(cur_x, dst_x, x_dim)
        direction = Direction.EAST if step > 0 else Direction.WEST
        next_coord = ((cur_x + step) % x_dim, cur_y)
        crosses_dateline = (step > 0 and cur_x == x_dim - 1) or (
            step < 0 and cur_x == 0
        )
    else:
        step = _ring_direction(cur_y, dst_y, y_dim)
        direction = Direction.SOUTH if step > 0 else Direction.NORTH
        next_coord = (cur_x, (cur_y + step) % y_dim)
        crosses_dateline = (step > 0 and cur_y == y_dim - 1) or (
            step < 0 and cur_y == 0
        )

    dimension_change = (
        incoming_direction in (Direction.EAST, Direction.WEST)
        and direction in (Direction.NORTH, Direction.SOUTH)
    )
    base_vc = VC0 if dimension_change else incoming_vc
    outgoing_vc = VC1 if base_vc == VC1 or crosses_dateline else VC0
    return Hop(
        current=current,
        direction=direction,
        next_coord=next_coord,
        incoming_vc=incoming_vc,
        outgoing_vc=outgoing_vc,
        crosses_dateline=crosses_dateline,
        dimension_change=dimension_change,
    )


def route_path(
    source: tuple[int, int],
    destination: tuple[int, int],
    incoming_vc: int = VC0,
    *,
    x_dim: int = X_DIM,
    y_dim: int = Y_DIM,
) -> tuple[Hop, ...]:
    """Return the complete deterministic route from source to destination."""
    current = source
    vc = incoming_vc
    hops = []
    incoming_direction = None

    while current != destination:
        hop = next_hop(
            current,
            destination,
            vc,
            incoming_direction=incoming_direction,
            x_dim=x_dim,
            y_dim=y_dim,
        )
        if hop is None:
            raise AssertionError("route terminated before reaching destination")
        hops.append(hop)
        current = hop.next_coord
        vc = hop.outgoing_vc
        incoming_direction = hop.direction
        if len(hops) > x_dim + y_dim:
            raise AssertionError("routing oracle failed to converge")

    return tuple(hops)


def final_vc(
    source: tuple[int, int],
    destination: tuple[int, int],
    incoming_vc: int = VC0,
) -> int:
    """Return the VC expected when a flit reaches its local destination."""
    path = route_path(source, destination, incoming_vc)
    return path[-1].outgoing_vc if path else incoming_vc
