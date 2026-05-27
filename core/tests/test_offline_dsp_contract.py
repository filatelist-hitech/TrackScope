from __future__ import annotations

from pathlib import Path
import tempfile
from typing import Any
import unittest

try:
    from .helpers.dsp_lab_runner import DspLabRunner
    from .helpers.synthetic_fixtures import FixtureAudio, fixture_names, make_fixture, write_wav
except ImportError:
    from helpers.dsp_lab_runner import DspLabRunner
    from helpers.synthetic_fixtures import FixtureAudio, fixture_names, make_fixture, write_wav


class OfflineDspContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.runner = DspLabRunner()

    def test_clean_synthetic_bpm_accuracy(self) -> None:
        for name in ("clean_170", "clean_180", "clean_190", "clean_200", "clean_220"):
            with self.subTest(name=name):
                fixture, result = self._analyze_fixture(name)
                self._assert_contract_shape(result)
                self._assert_primary_bpm(result, fixture)
                self.assertEqual(result["lock_state"], "STABLE")
                self.assertGreaterEqual(result["confidence"], 0.75)
                self._assert_required_candidates(result, fixture)

    def test_half_time_trap_preserves_100_and_200_candidates_and_prefers_200(self) -> None:
        fixture, result = self._analyze_fixture("half_time_trap_100")
        self._assert_contract_shape(result)
        self._assert_primary_bpm(result, fixture)
        self.assertEqual(result["lock_state"], "STABLE")
        self._assert_has_candidate_near(result, 100.0, tolerance=1.0)
        self._assert_has_candidate_near(result, 200.0, tolerance=1.0)
        self._assert_candidate_relation(result, 100.0, {"raw"})
        self._assert_candidate_relation(result, 200.0, {"main", "normalized_from_half"})
        self._assert_candidate_relation(result, 200.0, {"normalized_from_half"}, source_bpm=100.0)

    def test_double_time_trap_preserves_400_and_200_candidates_and_prefers_200(self) -> None:
        fixture, result = self._analyze_fixture("double_time_trap_400")
        self._assert_contract_shape(result)
        self._assert_primary_bpm(result, fixture)
        self.assertEqual(result["lock_state"], "STABLE")
        self._assert_has_candidate_near(result, 400.0, tolerance=1.0)
        self._assert_has_candidate_near(result, 200.0, tolerance=1.0)
        self._assert_candidate_relation(result, 400.0, {"raw"})
        self._assert_candidate_relation(result, 200.0, {"main", "normalized_from_double"})
        self._assert_candidate_relation(result, 200.0, {"normalized_from_double"}, source_bpm=400.0)

    def test_silence_white_noise_and_pink_noise_never_return_stable(self) -> None:
        for name in ("silence", "white_noise", "pink_noise"):
            with self.subTest(name=name):
                fixture, result = self._analyze_fixture(name)
                self._assert_contract_shape(result)
                self.assertIsNone(result["primary_bpm"])
                self.assertNotEqual(result["lock_state"], "STABLE")
                self.assertIn(result["lock_state"], fixture.expectation.allowed_lock_states)
                self.assertLess(result["confidence"], 0.5)

    def test_severely_clipped_microphone_is_not_false_stable(self) -> None:
        fixture, result = self._analyze_fixture("severely_clipped_mic")
        self._assert_contract_shape(result)
        self.assertNotEqual(result["lock_state"], "STABLE")
        self.assertIn(result["lock_state"], fixture.expectation.allowed_lock_states)
        self.assertTrue(result["signal_quality"]["clipping"])
        self.assertGreater(result["signal_quality"]["clipped_frame_ratio"], 0.05)
        self.assertLess(result["confidence"], 0.6)

    def test_recoverable_clipped_microphone_keeps_candidates_and_can_lock(self) -> None:
        fixture, result = self._analyze_fixture("recoverable_clipped_mic")
        self._assert_contract_shape(result)
        self.assertIn(result["lock_state"], fixture.expectation.allowed_lock_states)
        self.assertTrue(result["signal_quality"]["clipping"])
        self.assertLess(result["signal_quality"]["clipped_frame_ratio"], 0.05)
        self._assert_primary_bpm(result, fixture)
        self._assert_has_candidate_near(result, 200.0, tolerance=2.0)
        self._assert_has_candidate_near(result, 100.0, tolerance=2.0)
        self.assertGreaterEqual(result["confidence"], 0.45)

    def test_breakdown_without_kick_finishes_unlocked(self) -> None:
        fixture, result = self._analyze_fixture("breakdown_without_kick")
        self._assert_contract_shape(result)
        self.assertNotEqual(result["lock_state"], "STABLE")
        self.assertIn(result["lock_state"], fixture.expectation.allowed_lock_states)
        self.assertLess(result["confidence"], 0.7)
        self._assert_has_candidate_near(result, 200.0, tolerance=2.0)

    def test_dense_hitech_bassline_prefers_main_beat(self) -> None:
        fixture, result = self._analyze_fixture("dense_hitech_bassline")
        self._assert_contract_shape(result)
        self._assert_primary_bpm(result, fixture)
        self.assertEqual(result["lock_state"], "STABLE")
        self._assert_required_candidates(result, fixture)

    def test_unstable_club_simulation_keeps_uncertainty_visible(self) -> None:
        fixture, result = self._analyze_fixture("unstable_club_simulation")
        self._assert_contract_shape(result)
        self.assertIsNone(result["primary_bpm"])
        self.assertNotEqual(result["lock_state"], "STABLE")
        self.assertIn(result["lock_state"], fixture.expectation.allowed_lock_states)
        self.assertLess(result["confidence"], 0.5)

    def _analyze_fixture(self, name: str) -> tuple[FixtureAudio, dict[str, Any]]:
        self.assertIn(name, fixture_names())
        fixture = make_fixture(name)
        with tempfile.TemporaryDirectory() as tmpdir:
            wav_path = Path(tmpdir) / f"{name}.wav"
            write_wav(fixture, str(wav_path))
            return fixture, self.runner.analyze(wav_path, mode="hitech")

    def _assert_contract_shape(self, result: dict[str, Any]) -> None:
        self.assertIn("primary_bpm", result)
        self.assertIn("confidence", result)
        self.assertIn("lock_state", result)
        self.assertIn("signal_quality", result)
        self.assertIn("candidates", result)
        self.assertIsInstance(result["confidence"], (int, float))
        self.assertGreaterEqual(result["confidence"], 0.0)
        self.assertLessEqual(result["confidence"], 1.0)
        self.assertIsInstance(result["candidates"], list)
        self.assertIn(
            result["lock_state"],
            {
                "SEARCHING",
                "LOCKING",
                "STABLE",
                "UNSTABLE",
                "BREAKDOWN",
                "CLIPPED_MIC",
                "NOISE_ONLY",
            },
        )
        signal_quality = result["signal_quality"]
        self.assertIsInstance(signal_quality, dict)
        self.assertIn("clipping", signal_quality)
        self.assertIn("clipped_frame_ratio", signal_quality)

    def _assert_primary_bpm(self, result: dict[str, Any], fixture: FixtureAudio) -> None:
        expected = fixture.expectation.primary_bpm
        tolerance = fixture.expectation.tolerance_bpm
        if expected is None:
            self.assertIsNone(result["primary_bpm"])
            return
        self.assertIsNotNone(result["primary_bpm"])
        self.assertLessEqual(abs(float(result["primary_bpm"]) - expected), tolerance)

    def _assert_required_candidates(self, result: dict[str, Any], fixture: FixtureAudio) -> None:
        for bpm in fixture.expectation.required_candidate_bpms:
            self._assert_has_candidate_near(
                result,
                bpm,
                tolerance=fixture.expectation.tolerance_bpm or 1.0,
            )

    def _assert_has_candidate_near(self, result: dict[str, Any], bpm: float, *, tolerance: float) -> None:
        matches = [
            candidate
            for candidate in result["candidates"]
            if isinstance(candidate, dict)
            and isinstance(candidate.get("bpm"), (int, float))
            and abs(float(candidate["bpm"]) - bpm) <= tolerance
        ]
        self.assertTrue(matches, f"missing candidate near {bpm} BPM in {result['candidates']!r}")

    def _assert_candidate_relation(
        self,
        result: dict[str, Any],
        bpm: float,
        allowed_relations: set[str],
        *,
        source_bpm: float | None = None,
    ) -> None:
        matches = [
            candidate
            for candidate in result["candidates"]
            if isinstance(candidate, dict)
            and isinstance(candidate.get("bpm"), (int, float))
            and abs(float(candidate["bpm"]) - bpm) <= 1.0
        ]
        self.assertTrue(matches, f"missing candidate near {bpm} BPM")
        if source_bpm is not None:
            matches = [
                candidate
                for candidate in matches
                if isinstance(candidate.get("source_bpm"), (int, float))
                and abs(float(candidate["source_bpm"]) - source_bpm) <= 1.0
            ]
            self.assertTrue(matches, f"candidate near {bpm} BPM must preserve source {source_bpm} BPM")
        self.assertTrue(
            any(candidate.get("relation") in allowed_relations for candidate in matches),
            f"candidate near {bpm} BPM must have one of {allowed_relations}, got {matches!r}",
        )
