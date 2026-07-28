import unittest

from model.torus_ref import (
    Direction,
    VC0,
    VC1,
    X_DIM,
    Y_DIM,
    final_vc,
    minimal_hops,
    next_hop,
    node_coord,
    node_index,
    route_path,
)


class TorusReferenceModelTest(unittest.TestCase):
    def test_node_index_round_trip(self):
        for x in range(X_DIM):
            for y in range(Y_DIM):
                self.assertEqual(node_coord(node_index(x, y)), (x, y))

    def test_positive_direction_wins_equal_distance_ties(self):
        self.assertEqual(next_hop((0, 1), (2, 1)).direction, Direction.EAST)
        self.assertEqual(next_hop((3, 1), (1, 1)).direction, Direction.EAST)
        self.assertEqual(next_hop((1, 0), (1, 2)).direction, Direction.SOUTH)
        self.assertEqual(next_hop((1, 3), (1, 1)).direction, Direction.SOUTH)

    def test_all_directional_datelines_raise_vc(self):
        cases = (
            ((3, 1), (0, 1), Direction.EAST),
            ((0, 1), (3, 1), Direction.WEST),
            ((1, 3), (1, 0), Direction.SOUTH),
            ((1, 0), (1, 3), Direction.NORTH),
        )
        for source, destination, direction in cases:
            with self.subTest(source=source, destination=destination):
                hop = next_hop(source, destination, VC0)
                self.assertEqual(hop.direction, direction)
                self.assertTrue(hop.crosses_dateline)
                self.assertEqual(hop.outgoing_vc, VC1)

    def test_vc_classes_restart_at_x_to_y_transition(self):
        path = route_path((3, 1), (1, 2), VC0)
        self.assertEqual(
            tuple(hop.direction for hop in path),
            (Direction.EAST, Direction.EAST, Direction.SOUTH),
        )
        self.assertEqual(
            tuple(hop.outgoing_vc for hop in path),
            (VC1, VC1, VC0),
        )
        self.assertTrue(path[-1].dimension_change)

        dateline_path = route_path((3, 3), (1, 0), VC0)
        self.assertTrue(dateline_path[-1].dimension_change)
        self.assertTrue(dateline_path[-1].crosses_dateline)
        self.assertEqual(dateline_path[-1].outgoing_vc, VC1)

    def test_all_routes_are_minimal_contiguous_and_x_then_y(self):
        for src_x in range(X_DIM):
            for src_y in range(Y_DIM):
                for dst_x in range(X_DIM):
                    for dst_y in range(Y_DIM):
                        source = (src_x, src_y)
                        destination = (dst_x, dst_y)
                        with self.subTest(source=source, destination=destination):
                            path = route_path(source, destination)
                            self.assertEqual(len(path), minimal_hops(source, destination))

                            current = source
                            previous_direction = None
                            seen_y_hop = False
                            vc = VC0
                            for hop in path:
                                self.assertEqual(hop.current, current)
                                self.assertEqual(hop.incoming_vc, vc)
                                self.assertIn(hop.direction, tuple(Direction)[:-1])
                                if hop.direction in (
                                    Direction.NORTH,
                                    Direction.SOUTH,
                                ):
                                    seen_y_hop = True
                                else:
                                    self.assertFalse(seen_y_hop)
                                if hop.outgoing_vc < hop.incoming_vc:
                                    self.assertTrue(hop.dimension_change)
                                if hop.dimension_change:
                                    self.assertIn(
                                        previous_direction,
                                        (Direction.EAST, Direction.WEST),
                                    )
                                    self.assertIn(
                                        hop.direction,
                                        (Direction.NORTH, Direction.SOUTH),
                                    )
                                current = hop.next_coord
                                vc = hop.outgoing_vc
                                previous_direction = hop.direction

                            self.assertEqual(current, destination)
                            final_dimension = (
                                (Direction.NORTH, Direction.SOUTH)
                                if seen_y_hop
                                else (Direction.EAST, Direction.WEST)
                            )
                            expected_final_vc = VC1 if any(
                                hop.crosses_dateline and hop.direction in final_dimension
                                for hop in path
                            ) else VC0
                            self.assertEqual(
                                final_vc(source, destination),
                                expected_final_vc,
                            )

    def test_local_route_has_no_hops(self):
        self.assertEqual(route_path((2, 3), (2, 3)), ())
        self.assertEqual(final_vc((2, 3), (2, 3), VC1), VC1)


if __name__ == "__main__":
    unittest.main()
