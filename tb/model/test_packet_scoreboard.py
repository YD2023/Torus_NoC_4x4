import unittest

from common.flit import FLIT_BODY, FLIT_HEAD, FLIT_HEADTAIL, FLIT_TAIL, make_flit
from monitors.torus_scoreboard import ExpectedPacket, PacketScoreboard


def packet(packet_id, destination, flit_types, final_vc=0):
    dst_x, dst_y = divmod(destination, 4)
    flits = tuple(
        make_flit(
            flit_type,
            dst_x,
            dst_y,
            pkt_len=len(flit_types),
            payload=(packet_id << 8) | index,
        )
        for index, flit_type in enumerate(flit_types)
    )
    return ExpectedPacket(packet_id, 0, destination, flits, final_vc)


class PacketScoreboardTest(unittest.TestCase):
    def test_accepts_complete_packets_at_independent_destinations(self):
        first = packet(1, 3, (FLIT_HEAD, FLIT_BODY, FLIT_TAIL), final_vc=1)
        second = packet(2, 4, (FLIT_HEADTAIL,))
        scoreboard = PacketScoreboard((first, second))

        scoreboard.observe(3, first.flits[0], 1)
        scoreboard.observe(4, second.flits[0], 0)
        scoreboard.observe(3, first.flits[1], 1)
        scoreboard.observe(3, first.flits[2], 1)

        scoreboard.assert_complete()

    def test_rejects_wrong_destination_vc_and_order(self):
        expected = packet(3, 7, (FLIT_HEAD, FLIT_TAIL), final_vc=1)

        with self.assertRaisesRegex(AssertionError, "expected 7"):
            PacketScoreboard((expected,)).observe(6, expected.flits[0], 1)
        with self.assertRaisesRegex(AssertionError, "expected VC1"):
            PacketScoreboard((expected,)).observe(7, expected.flits[0], 0)
        with self.assertRaisesRegex(AssertionError, "expected 0"):
            PacketScoreboard((expected,)).observe(7, expected.flits[1], 1)

    def test_accepts_packet_interleaving_across_destination_vcs(self):
        first = packet(4, 8, (FLIT_HEAD, FLIT_TAIL), final_vc=0)
        second = packet(5, 8, (FLIT_HEAD, FLIT_TAIL), final_vc=1)
        scoreboard = PacketScoreboard((first, second))

        scoreboard.observe(8, first.flits[0], 0)
        scoreboard.observe(8, second.flits[0], 1)
        scoreboard.observe(8, first.flits[1], 0)
        scoreboard.observe(8, second.flits[1], 1)
        scoreboard.assert_complete()

    def test_rejects_packet_interleaving_at_one_destination(self):
        first = packet(4, 8, (FLIT_HEAD, FLIT_TAIL))
        second = packet(5, 8, (FLIT_HEAD, FLIT_TAIL))
        scoreboard = PacketScoreboard((first, second))
        scoreboard.observe(8, first.flits[0], 0)

        with self.assertRaisesRegex(AssertionError, "interleaved"):
            scoreboard.observe(8, second.flits[0], 0)


if __name__ == "__main__":
    unittest.main()
