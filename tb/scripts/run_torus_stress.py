"""Run and merge a reproducible torus random-traffic stress matrix."""

import argparse
import json
import subprocess
import sys
from pathlib import Path

from model.functional_coverage import TorusFunctionalCoverage


TB_DIR = Path(__file__).resolve().parents[1]
DEFAULT_SEEDS = "20260723,314159,271828,161803,424242"
DEFAULT_FIFO_DEPTHS = "1,3,5"


def parse_integer_list(value):
    entries = value.replace(",", " ").split()
    if not entries:
        raise argparse.ArgumentTypeError("at least one integer is required")
    try:
        values = tuple(int(entry) for entry in entries)
    except ValueError as error:
        raise argparse.ArgumentTypeError(str(error)) from error
    if any(item < 0 for item in values):
        raise argparse.ArgumentTypeError("values must be non-negative")
    return values


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim", default="icarus")
    parser.add_argument(
        "--seeds",
        type=parse_integer_list,
        default=parse_integer_list(DEFAULT_SEEDS),
    )
    parser.add_argument(
        "--fifo-depths",
        type=parse_integer_list,
        default=parse_integer_list(DEFAULT_FIFO_DEPTHS),
    )
    parser.add_argument("--packets", type=int, default=64)
    parser.add_argument("--minimum-pairs", type=int, default=192)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=TB_DIR / "sim_build" / "stress",
    )
    args = parser.parse_args(argv)
    if args.packets <= 0:
        parser.error("--packets must be positive")
    if not 0 <= args.minimum_pairs <= 256:
        parser.error("--minimum-pairs must be between 0 and 256")
    if any(depth <= 0 for depth in args.fifo_depths):
        parser.error("--fifo-depths values must be positive")
    return args


def run_case(args, seed, fifo_depth, coverage_file):
    command = [
        "make",
        "-C",
        str(TB_DIR),
        "test",
        "COMPONENT=torus4x4_random",
        f"SIM={args.sim}",
        f"TORUS_RANDOM_SEED={seed}",
        f"RANDOM_PACKETS={args.packets}",
        f"TORUS_FIFO_DEPTH={fifo_depth}",
        f"TORUS_COVERAGE_FILE={coverage_file}",
    ]
    return subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


def main(argv=None):
    args = parse_args(argv)
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    aggregate = TorusFunctionalCoverage()
    cases = []
    failures = []

    total = len(args.seeds) * len(args.fifo_depths)
    case_number = 0
    for fifo_depth in args.fifo_depths:
        for seed in args.seeds:
            case_number += 1
            coverage_file = output_dir / f"fifo_{fifo_depth}_seed_{seed}.json"
            coverage_file.unlink(missing_ok=True)
            print(
                f"[{case_number}/{total}] fifo={fifo_depth} seed={seed} "
                f"packets/pattern={args.packets}",
                flush=True,
            )
            result = run_case(args, seed, fifo_depth, coverage_file)
            case = {
                "fifo_depth": fifo_depth,
                "seed": seed,
                "packets_per_pattern": args.packets,
                "passed": result.returncode == 0,
                "coverage_file": str(coverage_file),
            }

            if result.returncode != 0:
                failure = f"fifo={fifo_depth} seed={seed}: simulation failed"
                failures.append(failure)
                case["failure"] = failure
                print(result.stdout, end="")
            elif not coverage_file.exists():
                failure = f"fifo={fifo_depth} seed={seed}: coverage report missing"
                failures.append(failure)
                case["passed"] = False
                case["failure"] = failure
            else:
                coverage = TorusFunctionalCoverage.read_json(coverage_file)
                aggregate.merge(coverage)
                case["coverage"] = coverage.to_dict()
                print(f"    PASS: {coverage.summary()}")
            cases.append(case)

    coverage_failure = None
    if not failures:
        try:
            aggregate.assert_random_run_complete(
                minimum_source_nodes=16,
                minimum_destination_nodes=16,
                minimum_pairs=args.minimum_pairs,
            )
        except AssertionError as error:
            coverage_failure = str(error)
            failures.append(f"aggregate coverage: {error}")

    aggregate_file = output_dir / "functional_coverage.json"
    aggregate.write_json(aggregate_file)
    summary = {
        "schema_version": 1,
        "simulator": args.sim,
        "seeds": list(args.seeds),
        "fifo_depths": list(args.fifo_depths),
        "packets_per_pattern": args.packets,
        "minimum_pairs": args.minimum_pairs,
        "passed": not failures,
        "failures": failures,
        "coverage_failure": coverage_failure,
        "aggregate_coverage_file": str(aggregate_file),
        "aggregate_coverage": aggregate.to_dict(),
        "cases": cases,
    }
    summary_file = output_dir / "stress_summary.json"
    summary_file.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
        encoding="ascii",
    )

    print(f"Aggregate: {aggregate.summary()}")
    print(f"Reports: {summary_file}")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1

    print(f"PASS: {total} stress cases completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
