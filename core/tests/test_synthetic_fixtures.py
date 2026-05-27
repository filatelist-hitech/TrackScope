from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile
import unittest
import wave

try:
    from .helpers.synthetic_fixtures import SAMPLE_RATE, fixture_names, make_fixture, write_wav
except ImportError:
    from helpers.synthetic_fixtures import SAMPLE_RATE, fixture_names, make_fixture, write_wav


class SyntheticFixtureTests(unittest.TestCase):
    def test_required_fixture_matrix_is_present(self) -> None:
        self.assertEqual(
            set(fixture_names()),
            {
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
                "recoverable_clipped_mic",
                "severely_clipped_mic",
                "breakdown_without_kick",
                "dense_hitech_bassline",
                "unstable_club_simulation",
            },
        )

    def test_fixture_generation_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            for name in fixture_names():
                with self.subTest(name=name):
                    first = tmp_path / f"{name}.first.wav"
                    second = tmp_path / f"{name}.second.wav"
                    write_wav(make_fixture(name), str(first))
                    write_wav(make_fixture(name), str(second))
                    self.assertEqual(_sha256(first), _sha256(second))

    def test_wav_shape_matches_offline_lab_contract(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            for name in fixture_names():
                with self.subTest(name=name):
                    path = Path(tmpdir) / f"{name}.wav"
                    write_wav(make_fixture(name), str(path))
                    with wave.open(str(path), "rb") as wav_file:
                        self.assertEqual(wav_file.getnchannels(), 1)
                        self.assertEqual(wav_file.getsampwidth(), 2)
                        self.assertEqual(wav_file.getframerate(), SAMPLE_RATE)
                        self.assertGreaterEqual(wav_file.getnframes(), SAMPLE_RATE * 6)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
