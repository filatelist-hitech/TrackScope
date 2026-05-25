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

    def test_silence_noise_clipping_and_breakdown_do_not_return_stable(self) -> None:
        fixtures = {
            "silence": generate_silence(),
            "noise": generate_noise(),
            "clipped": generate_clipped_pulse_track(200),
            "breakdown": generate_breakdown_track(200),
        }
        for name, samples in fixtures.items():
            with self.subTest(name=name):
                result = analyze_pcm(samples, DEFAULT_SAMPLE_RATE)

                self.assertIsNone(result.primary_bpm)
                self.assertNotEqual(result.lock_state, "STABLE")
                self.assertLess(result.confidence, 0.72)

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

    def assert_result_contract(self, payload: dict[str, object]) -> None:
        for key in ("primary_bpm", "confidence", "lock_state", "signal_quality", "candidates"):
            self.assertIn(key, payload)
        self.assertIsInstance(payload["candidates"], list)
        self.assertGreater(len(payload["candidates"]), 0)


if __name__ == "__main__":
    unittest.main()
