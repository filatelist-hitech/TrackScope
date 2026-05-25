#!/usr/bin/env python3
"""Offline fixture generator and BPM analyzer."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from core.dsp import analyze_pcm, result_to_dict
from core.dsp.synthetic import (
    DEFAULT_SAMPLE_RATE,
    generate_breakdown_track,
    generate_clipped_pulse_track,
    generate_dense_hitech_bassline,
    generate_noise,
    generate_pink_noise,
    generate_pulse_track,
    generate_silence,
    generate_unstable_club_simulation,
    read_wav,
    write_wav,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Offline DSP lab for deterministic BPM analysis")
    subcommands = parser.add_subparsers(dest="command", required=True)

    generate = subcommands.add_parser("generate", help="generate one synthetic WAV fixture")
    generate.add_argument("--bpm", type=float, default=None)
    generate.add_argument(
        "--kind",
        choices=["pulse", "silence", "noise", "white-noise", "pink-noise", "clipped", "breakdown", "dense", "unstable"],
        default="pulse",
    )
    generate.add_argument("--duration", type=float, default=12.0)
    generate.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)
    generate.add_argument("--out", required=True)

    suite = subcommands.add_parser("generate-suite", help="generate the first deterministic fixture suite")
    suite.add_argument("--out-dir", default="datasets/synthetic/offline-lab")
    suite.add_argument("--duration", type=float, default=12.0)
    suite.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)

    analyze = subcommands.add_parser("analyze", help="analyze a 16-bit PCM WAV file")
    analyze.add_argument("path")

    args = parser.parse_args()
    if args.command == "generate":
        samples = _fixture_samples(args.kind, args.bpm, args.duration, args.sample_rate)
        write_wav(args.out, samples, args.sample_rate)
        return 0

    if args.command == "generate-suite":
        output = Path(args.out_dir)
        for bpm in (170, 180, 190, 200, 220):
            write_wav(output / f"pulse_{bpm}bpm.wav", generate_pulse_track(bpm, args.duration, args.sample_rate), args.sample_rate)
        write_wav(output / "half_time_100bpm.wav", generate_pulse_track(100, args.duration, args.sample_rate), args.sample_rate)
        write_wav(output / "double_time_400bpm.wav", generate_pulse_track(400, args.duration, args.sample_rate), args.sample_rate)
        write_wav(output / "silence.wav", generate_silence(args.duration, args.sample_rate), args.sample_rate)
        write_wav(output / "white_noise.wav", generate_noise(args.duration, args.sample_rate), args.sample_rate)
        write_wav(output / "pink_noise.wav", generate_pink_noise(args.duration, args.sample_rate), args.sample_rate)
        write_wav(output / "clipped_200bpm.wav", generate_clipped_pulse_track(200, args.duration, args.sample_rate), args.sample_rate)
        write_wav(output / "breakdown_200bpm.wav", generate_breakdown_track(200, args.duration, sample_rate=args.sample_rate), args.sample_rate)
        write_wav(output / "dense_hitech_bassline_200bpm.wav", generate_dense_hitech_bassline(200, args.duration, args.sample_rate), args.sample_rate)
        write_wav(output / "unstable_club_simulation.wav", generate_unstable_club_simulation(args.duration, args.sample_rate), args.sample_rate)
        return 0

    samples, sample_rate = read_wav(args.path)
    result = analyze_pcm(samples, sample_rate)
    print(json.dumps(result_to_dict(result), indent=2, sort_keys=True))
    return 0


def _fixture_samples(kind: str, bpm: float | None, duration: float, sample_rate: int) -> list[float]:
    if kind == "silence":
        return generate_silence(duration, sample_rate)
    if kind in {"noise", "white-noise"}:
        return generate_noise(duration, sample_rate)
    if kind == "pink-noise":
        return generate_pink_noise(duration, sample_rate)
    if kind == "unstable":
        return generate_unstable_club_simulation(duration, sample_rate)
    if bpm is None:
        raise SystemExit("--bpm is required for pulse, clipped, breakdown, and dense fixtures")
    if kind == "clipped":
        return generate_clipped_pulse_track(bpm, duration, sample_rate)
    if kind == "breakdown":
        return generate_breakdown_track(bpm, duration, sample_rate=sample_rate)
    if kind == "dense":
        return generate_dense_hitech_bassline(bpm, duration, sample_rate)
    return generate_pulse_track(bpm, duration, sample_rate)


if __name__ == "__main__":
    raise SystemExit(main())
