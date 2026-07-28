import tempfile
import unittest
from pathlib import Path

from model.functional_coverage import TorusFunctionalCoverage
from model.torus_ref import node_index


class TorusFunctionalCoverageTest(unittest.TestCase):
    def test_exhaustive_samples_fill_all_required_bins(self):
        coverage = TorusFunctionalCoverage()

        for source in range(16):
            for destination in range(16):
                pattern = "uniform" if (source + destination) % 2 else "hotspot"
                length = ((source + destination) % 4) + 1
                coverage.sample(source, destination, length, pattern)

        coverage.assert_random_run_complete(
            minimum_source_nodes=16,
            minimum_destination_nodes=16,
            minimum_pairs=256,
        )
        self.assertEqual(coverage.packet_count, 256)
        self.assertEqual(len(coverage.source_destination_pairs), 256)

    def test_identifies_incomplete_coverage(self):
        coverage = TorusFunctionalCoverage()
        coverage.sample(node_index(0, 0), node_index(0, 0), 1, "uniform")

        with self.assertRaisesRegex(AssertionError, "missing functional coverage"):
            coverage.assert_random_run_complete()

    def test_merge_and_json_round_trip(self):
        first = TorusFunctionalCoverage()
        second = TorusFunctionalCoverage()
        first.sample(0, 1, 2, "uniform")
        second.sample(15, 0, 4, "hotspot")
        first.merge(second)

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "coverage.json"
            first.write_json(path)
            restored = TorusFunctionalCoverage.read_json(path)

        self.assertEqual(restored.to_dict(), first.to_dict())
        self.assertEqual(restored.packet_count, 2)
        self.assertEqual(restored.flit_count, 6)


if __name__ == "__main__":
    unittest.main()
