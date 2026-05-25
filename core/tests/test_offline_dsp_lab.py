from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from core.dsp import analyze_pcm, result_to_dict
from core.dsp.synthetic import (
    DEFAULT_SAMPLE_RATE,
    generate_breakdown_track,
    generate_clipped_pulse_track,
    generate_noise,
    generate_pulse_track,
    generate_recoverable_clipped_pulse_track,
    generate_silence,
)


class OfflineDspLabTest(unittest.TestCase):
    def test_clean_hitech_synthetic_tempos_lock_within_one_bpm(self) -> None:
        for expected_bpm in (170, 180, 190, 200, 220):
            with self.subTest(bpm=expected_bpm):
                result = analyze_pcm(generate_pulse_track(expected_bpm), DEFAULT_SAMPLE_RATE)

                self.assertEqual(result.lock_state, "STABLE")
                self.assertIsNotNone(result.primary_bpm)
                self.assertLessEqual(abs(result.primary_bpm - expected_bpm), 1.0)
                self.assertGreaterEqual(result.confidence, 0.72)
                self.assert_result_contract(result_to_dict(result))

    def test_half_time_trap_keeps_100_and_200_but_chooses_200(self) -> None:
        result = analyze_pcm(generate_pulse_track(100), DEFAULT_SAMPLE_RATE)
        candidate_bpms = [candidate.bpm for candidate in result.candidates]

        self.assertEqual(result.lock_state, "STABLE")
        self.assertAlmostEqual(result.primary_bpm or 0.0, 200.0, delta=1.0)
        self.assertTrue(any(abs(bpm - 100.0) <= 1.0 for bpm in candidate_bpms))
        self.assertTrue(any(abs(bpm - 200.0) <= 1.0 for bpm in candidate_bpms))
        self.assertTrue(any(candidate.relation == "normalized_from_half" for candidate in result.candidates))

    def test_double_time_trap_keeps_400_and_200_but_chooses_200(self) -> None:
        result = analyze_pcm(generate_pulse_track(400), DEFAULT_SAMPLE_RATE)
        candidate_bpms = [candidate.bpm for candidate in result.candidates]

        self.assertEqual(result.lock_state, "STABLE")
        self.assertAlmostEqual(result.primary_bpm or 0.0, 200.0, delta=1.0)
        self.assertTrue(any(abs(bpm - 400.0) <= 1.0 for bpm in candidate_bpms))
        self.assertTrue(any(abs(bpm - 200.0) <= 1.0 for bpm in candidate_bpms))
        self.assertTrue(any(candidate.relation == "normalized_from_double" for candidate in result.candidates))

    def test_silence_noise_and_breakdown_do_not_return_stable(self) -> None:
        fixtures = {
            "silence": generate_silence(),
            "noise": generate_noise(),
            "breakdown": generate_breakdown_track(200),
        }
        for name, samples in fixtures.items():
            with self.subTest(name=name):
                result = analyze_pcm(samples, DEFAULT_SAMPLE_RATE)

                self.assertIsNone(result.primary_bpm)
                self.assertNotEqual(result.lock_state, "STABLE")
                self.assertLess(result.confidence, 0.72)

    def test_severe_clipping_suppresses_final_bpm(self) -> None:
        result = analyze_pcm(generate_clipped_pulse_track(200), DEFAULT_SAMPLE_RATE)
        self.assertIsNone(result.primary_bpm)
        self.assertEqual(result.lock_state, "CLIPPED_MIC")
        self.assertTrue(result.signal_quality.clipping)
        self.assertGreaterEqual(result.signal_quality.clipped_frame_ratio, 0.05)

    def test_recoverable_clipping_can_keep_bpm_locking(self) -> None:
        result = analyze_pcm(generate_recoverable_clipped_pulse_track(200), DEFAULT_SAMPLE_RATE)
        self.assertIsNotNone(result.primary_bpm)
        self.assertIn(result.lock_state, {"LOCKING", "STABLE"})
        self.assertTrue(result.signal_quality.clipping)
        self.assertLess(result.signal_quality.clipped_frame_ratio, 0.05)
        self.assertAlmostEqual(result.primary_bpm or 0.0, 200.0, delta=2.0)

    def test_offline_cli_generates_and_analyzes_pcm_fixture(self) -> None:
        cli = Path(__file__).resolve().parents[2] / "tools" / "offline-lab" / "offline_lab.py"
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture_path = Path(temp_dir) / "pulse_200.wav"
            subprocess.run(
                [sys.executable, str(cli), "generate", "--bpm", "200", "--out", str(fixture_path)],
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [sys.executable, str(cli), "analyze", str(fixture_path)],
                check=True,
                capture_output=True,
                text=True,
            )

        payload = json.loads(completed.stdout)
        self.assertEqual(payload["lock_state"], "STABLE")
        self.assertAlmostEqual(payload["primary_bpm"], 200.0, delta=1.0)
        self.assertIn("signal_quality", payload)
        self.assertIn("candidates", payload)

    def test_offline_cli_report_runs_required_fixture_matrix(self) -> None:
        cli = Path(__file__).resolve().parents[2] / "tools" / "offline-lab" / "offline_lab.py"
        completed = subprocess.run(
            [sys.executable, str(cli), "report"],
            check=True,
            capture_output=True,
            text=True,
        )

        rows = json.loads(completed.stdout)
        by_fixture = {row["fixture"]: row for row in rows}

        self.assertTrue(all(row["pass"] for row in rows), rows)
        self.assertTrue(all(row["signal_quality"]["snr_estimate_db"] is None for row in rows), rows)
        for fixture_name in (
            "clean_170",
            "clean_180",
            "clean_190",
            "clean_200",
            "clean_220",
            "half_time_trap_100",
            "double_time_trap_400",
            "silence",
            "white_noise",
            "pink_noise",
            "clipped_200",
            "recoverable_clipped_200",
            "breakdown_200",
            "dense_hitech_bassline_200",
            "unstable_club_simulation",
        ):
            self.assertIn(fixture_name, by_fixture)

        self.assertAlmostEqual(by_fixture["half_time_trap_100"]["detected_bpm"], 200.0, delta=1.0)
        self.assertAlmostEqual(by_fixture["double_time_trap_400"]["detected_bpm"], 200.0, delta=1.0)
        self.assert_has_candidate(by_fixture["half_time_trap_100"], 100.0, relation="raw")
        self.assert_has_candidate(
            by_fixture["half_time_trap_100"],
            200.0,
            relation="normalized_from_half",
            source_bpm=100.0,
        )
        self.assert_has_candidate(by_fixture["double_time_trap_400"], 400.0, relation="raw", tolerance=2.0)
        self.assert_has_candidate(
            by_fixture["double_time_trap_400"],
            200.0,
            relation="normalized_from_double",
            source_bpm=400.0,
            tolerance=2.0,
        )
        self.assertIsNone(by_fixture["silence"]["detected_bpm"])
        self.assertNotEqual(by_fixture["white_noise"]["lock_state"], "STABLE")

    def test_offline_cli_report_returns_nonzero_when_fixture_matrix_fails(self) -> None:
        cli = Path(__file__).resolve().parents[2] / "tools" / "offline-lab" / "offline_lab.py"
        completed = subprocess.run(
            [sys.executable, str(cli), "report", "--duration", "1"],
            check=False,
            capture_output=True,
            text=True,
        )

        rows = json.loads(completed.stdout)
        self.assertNotEqual(completed.returncode, 0)
        self.assertTrue(any(not row["pass"] for row in rows), rows)

    def assert_result_contract(self, payload: dict[str, object]) -> None:
        for key in ("primary_bpm", "confidence", "lock_state", "signal_quality", "candidates"):
            self.assertIn(key, payload)
        self.assertIsInstance(payload["candidates"], list)
        self.assertGreater(len(payload["candidates"]), 0)

    def assert_has_candidate(
        self,
        row: dict[str, object],
        bpm: float,
        *,
        relation: str,
        source_bpm: float | None = None,
        tolerance: float = 1.0,
    ) -> None:
        candidates = row["candidates"]
        self.assertIsInstance(candidates, list)
        matches = [
            candidate
            for candidate in candidates
            if isinstance(candidate, dict)
            and abs(float(candidate["bpm"]) - bpm) <= tolerance
            and candidate.get("relation") == relation
            and (
                source_bpm is None
                or (
                    isinstance(candidate.get("source_bpm"), (int, float))
                    and abs(float(candidate["source_bpm"]) - source_bpm) <= tolerance
                )
            )
        ]
        self.assertTrue(matches, f"missing {relation} candidate near {bpm} BPM in {candidates!r}")


if __name__ == "__main__":
    unittest.main()
