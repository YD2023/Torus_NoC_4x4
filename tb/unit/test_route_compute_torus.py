import os

import cocotb
from cocotb.triggers import Timer


PORT_NORTH = 0
PORT_SOUTH = 1
PORT_EAST = 2
PORT_WEST = 3
PORT_LOCAL = 4

X_DIM = int(os.environ["X_DIM"])
Y_DIM = int(os.environ["Y_DIM"])
COORD_W = int(os.environ["COORD_W"])
VC_W = int(os.environ["VC_W"])


def reference_route(cur_x, cur_y, dst_x, dst_y, vc_in):
    dx_pos = (dst_x - cur_x) % X_DIM
    dx_neg = (cur_x - dst_x) % X_DIM
    dy_pos = (dst_y - cur_y) % Y_DIM
    dy_neg = (cur_y - dst_y) % Y_DIM

    if cur_x != dst_x:
        route = PORT_EAST if dx_pos <= dx_neg else PORT_WEST
    elif cur_y != dst_y:
        route = PORT_SOUTH if dy_pos <= dy_neg else PORT_NORTH
    else:
        route = PORT_LOCAL

    dateline = (
        (route == PORT_EAST and cur_x == X_DIM - 1)
        or (route == PORT_WEST and cur_x == 0)
        or (route == PORT_SOUTH and cur_y == Y_DIM - 1)
        or (route == PORT_NORTH and cur_y == 0)
    )
    vc_out = 1 if dateline else vc_in
    return route, vc_out, dateline


@cocotb.test()
async def test_exhaustive_routing_and_vc_policy(dut):
    """Check every 4x4 source/destination pair for both incoming VCs."""
    assert X_DIM == 4
    assert Y_DIM == 4
    assert COORD_W >= 2
    assert VC_W >= 1

    observed_routes = set()
    dateline_routes = set()
    saw_x_tie = False
    saw_y_tie = False
    saw_x_before_y = False

    for cur_x in range(X_DIM):
        for cur_y in range(Y_DIM):
            for dst_x in range(X_DIM):
                for dst_y in range(Y_DIM):
                    for vc_in in (0, 1):
                        dut.cur_x_i.value = cur_x
                        dut.cur_y_i.value = cur_y
                        dut.dst_x_i.value = dst_x
                        dut.dst_y_i.value = dst_y
                        dut.vc_i.value = vc_in

                        await Timer(1, unit="ns")

                        expected_route, expected_vc, expected_dateline = (
                            reference_route(cur_x, cur_y, dst_x, dst_y, vc_in)
                        )
                        actual_route = int(dut.route_o.value)
                        actual_vc = int(dut.vc_o.value)
                        actual_dateline = int(dut.dateline_cross_o.value)
                        context = (
                            f"cur=({cur_x},{cur_y}) dst=({dst_x},{dst_y}) "
                            f"vc_in={vc_in}"
                        )

                        assert actual_route == expected_route, context
                        assert actual_vc == expected_vc, context
                        assert actual_dateline == int(expected_dateline), context
                        if vc_in == 1:
                            assert actual_vc == 1, context

                        observed_routes.add(actual_route)
                        if actual_dateline:
                            dateline_routes.add(actual_route)

                        dx_pos = (dst_x - cur_x) % X_DIM
                        dx_neg = (cur_x - dst_x) % X_DIM
                        dy_pos = (dst_y - cur_y) % Y_DIM
                        dy_neg = (cur_y - dst_y) % Y_DIM

                        if cur_x != dst_x and dx_pos == dx_neg:
                            saw_x_tie = True
                            assert actual_route == PORT_EAST, context
                        if cur_x == dst_x and cur_y != dst_y and dy_pos == dy_neg:
                            saw_y_tie = True
                            assert actual_route == PORT_SOUTH, context
                        if cur_x != dst_x and cur_y != dst_y:
                            saw_x_before_y = True
                            assert actual_route in (PORT_EAST, PORT_WEST), context

    assert observed_routes == {
        PORT_NORTH,
        PORT_SOUTH,
        PORT_EAST,
        PORT_WEST,
        PORT_LOCAL,
    }
    assert dateline_routes == {
        PORT_NORTH,
        PORT_SOUTH,
        PORT_EAST,
        PORT_WEST,
    }
    assert saw_x_tie
    assert saw_y_tie
    assert saw_x_before_y
