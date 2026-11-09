"""Critical evidence checks for the optional native benchmark reporter."""
import importlib.util
from pathlib import Path
import unittest
import tempfile

spec = importlib.util.spec_from_file_location("benchmark", Path(__file__).resolve().parents[1] / "tools/benchmark.py")
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class BenchmarkEvidence(unittest.TestCase):
    def test_tail_is_not_reported_from_six_samples(self):
        result = benchmark.summarize([1, 2, 3, 4, 5, 6])
        self.assertEqual(3.5, result["median"])
        self.assertIsNone(result["p95"])
        self.assertEqual(result, benchmark.summarize([1, 2, 3, 4, 5, 6]))
        self.assertEqual(19, benchmark.summarize(list(range(1, 21)))["p95"])

    def test_partial_or_duplicate_sample_sets_are_not_results(self):
        samples = [{"phase": "subprocess", "iteration": i} for i in range(6)]
        benchmark.validate_samples(samples, ["subprocess"], 6)
        for broken in (samples[:-1], samples + samples[:1], samples[:-1] + samples[:1]):
            with self.assertRaises(ValueError):
                benchmark.validate_samples(broken, ["subprocess"], 6)

    def test_record_validation_requires_cleanup_setup_and_identical_payloads(self):
        rows = ["meta\tsbcl\t2.6.10", "meta\tasdf\t3.3.7", "meta\ttmux\t3.3a",
                "meta\tcontrol\tunsupported-before-3.7", "meta\tclock\tmonotonic", "meta\tclock-units-per-second\t1000000000",
                "setup\tfixture\t0\t0.1\t10\t9\t-"]
        rows += [f"sample\t{phase}\t{i}\t0.01\t10\t{launches}\t{payload}"
                 for phase, payload, launches in (("subprocess", "514", 2), ("snapshot", "-", 1)) for i in range(6)]
        rows += ["cleanup\tfixture\tPASS"]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "records.tsv"
            valid = "\n".join(rows) + "\n"
            path.write_text(valid)
            self.assertEqual(12, len(benchmark.read_records(path, 6, 2)[1]))
            path.write_text(valid.replace("unsupported-before-3.7", "unsupported-before-3.8"))
            self.assertEqual(12, len(benchmark.read_records(path, 6, 2)[1]))
            for broken in (valid.replace("\t514", "\t513"), "\n".join(rows[:-1]),
                           valid.replace(rows[6] + "\n", ""), valid.replace("0.01", "0.0"),
                           valid.replace("\t2\t514", "\t0\t514")):
                path.write_text(broken)
                with self.assertRaises(ValueError):
                    benchmark.read_records(path, 6, 2)

    def test_overlapping_intervals_do_not_claim_a_speedup(self):
        self.assertEqual({"status": "unresolved", "ratio": None}, benchmark.compare(
            {"median": 2, "median_ci95": [1, 4]}, {"median": 1, "median_ci95": [0.5, 3]}))
        self.assertEqual({"status": "separated", "ratio": 4}, benchmark.compare(
            {"median": 4, "median_ci95": [3, 5]}, {"median": 1, "median_ci95": [0.5, 2]}))


if __name__ == "__main__":
    unittest.main()
