#!/usr/bin/env python3
"""Офлайн-генератор фикстур и BPM-анализатор."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any


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
    generate_recoverable_clipped_pulse_track,
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
        choices=[
            "pulse",
            "silence",
            "noise",
            "white-noise",
            "pink-noise",
            "clipped",
            "recoverable-clipped",
            "breakdown",
            "dense",
            "unstable",
        ],
        default="pulse",
    )
    generate.add_argument("--duration", type=float, default=12.0)
    generate.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)
    generate.add_argument("--out", required=True)

    suite = subcommands.add_parser("generate-suite", help="generate the first deterministic fixture suite")
    suite.add_argument("--out-dir", default="datasets/synthetic/offline-lab")
    suite.add_argument("--duration", type=float, default=12.0)
    suite.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)

    report = subcommands.add_parser("report", help="analyze the deterministic fixture suite and emit JSON QA rows")
    report.add_argument("--duration", type=float, default=12.0)
    report.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)

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
        write_wav(
            output / "recoverable_clipped_200bpm.wav",
            generate_recoverable_clipped_pulse_track(200, args.duration, args.sample_rate),
            args.sample_rate,
        )
        write_wav(output / "breakdown_200bpm.wav", generate_breakdown_track(200, args.duration, sample_rate=args.sample_rate), args.sample_rate)
        write_wav(output / "dense_hitech_bassline_200bpm.wav", generate_dense_hitech_bassline(200, args.duration, args.sample_rate), args.sample_rate)
        write_wav(output / "unstable_club_simulation.wav", generate_unstable_club_simulation(args.duration, args.sample_rate), args.sample_rate)
        return 0

    if args.command == "report":
        rows = _run_report(args.duration, args.sample_rate)
        print(json.dumps(rows, indent=2, sort_keys=True))
        return 0 if all(row["pass"] for row in rows) else 1

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
    if kind == "recoverable-clipped":
        return generate_recoverable_clipped_pulse_track(bpm, duration, sample_rate)
    if kind == "breakdown":
        return generate_breakdown_track(bpm, duration, sample_rate=sample_rate)
    if kind == "dense":
        return generate_dense_hitech_bassline(bpm, duration, sample_rate)
    return generate_pulse_track(bpm, duration, sample_rate)


def _run_report(duration: float, sample_rate: int) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for spec in _report_specs():
        samples = _fixture_samples(spec["kind"], spec.get("bpm"), duration, sample_rate)
        result = result_to_dict(analyze_pcm(samples, sample_rate))
        detected = result["primary_bpm"]
        expected = spec["expected_bpm"]
        error = abs(float(detected) - float(expected)) if detected is not None and expected is not None else None
        rows.append(
            {
                "fixture": spec["name"],
                "expected_bpm": expected,
                "detected_bpm": detected,
                "error_bpm": round(error, 3) if error is not None else None,
                "confidence": result["confidence"],
                "lock_state": result["lock_state"],
                "signal_quality": result["signal_quality"],
                "candidates": result["candidates"],
                "pass": _report_row_passes(result, spec, error),
                "notes": spec["notes"],
            }
        )
    return rows


def _report_row_passes(result: dict[str, Any], spec: dict[str, Any], error: float | None) -> bool:
    if result["lock_state"] not in spec["allowed_lock_states"]:
        return False
    expected = spec["expected_bpm"]
    if expected is None:
        if result["primary_bpm"] is not None:
            return False
    elif error is None or error > spec["tolerance_bpm"]:
        return False

    candidates = result["candidates"]
    for requirement in spec["required_candidates"]:
        if not any(_candidate_satisfies(candidate, requirement, spec["candidate_tolerance_bpm"]) for candidate in candidates):
            return False
    return True


def _candidate_satisfies(candidate: dict[str, Any], requirement: dict[str, Any], tolerance: float) -> bool:
    if not isinstance(candidate.get("bpm"), (int, float)):
        return False
    if abs(float(candidate["bpm"]) - float(requirement["bpm"])) > tolerance:
        return False
    relations = requirement.get("relations")
    if relations is not None and candidate.get("relation") not in relations:
        return False
    source_bpm = requirement.get("source_bpm")
    if source_bpm is not None:
        candidate_source = candidate.get("source_bpm")
        if not isinstance(candidate_source, (int, float)):
            return False
        if abs(float(candidate_source) - float(source_bpm)) > tolerance:
            return False
    return True


def _report_specs() -> tuple[dict[str, Any], ...]:
    return (
        *_clean_report_specs(),
        {
            "name": "half_time_trap_100",
            "kind": "pulse",
            "bpm": 100.0,
            "expected_bpm": 200.0,
            "tolerance_bpm": 1.0,
            "required_candidates": (
                {"bpm": 100.0, "relations": ("raw",)},
                {"bpm": 200.0, "relations": ("normalized_from_half",), "source_bpm": 100.0},
            ),
            "candidate_tolerance_bpm": 1.0,
            "allowed_lock_states": ("STABLE",),
            "notes": "Raw 100 BPM remains visible while hitech mode chooses normalized 200 BPM.",
        },
        {
            "name": "double_time_trap_400",
            "kind": "pulse",
            "bpm": 400.0,
            "expected_bpm": 200.0,
            "tolerance_bpm": 1.0,
            "required_candidates": (
                {"bpm": 400.0, "relations": ("raw",)},
                {"bpm": 200.0, "relations": ("normalized_from_double",), "source_bpm": 400.0},
            ),
            "candidate_tolerance_bpm": 2.0,
            "allowed_lock_states": ("STABLE",),
            "notes": "Raw 400 BPM remains visible while hitech mode chooses normalized 200 BPM.",
        },
        {
            "name": "silence",
            "kind": "silence",
            "expected_bpm": None,
            "tolerance_bpm": None,
            "required_candidates": (),
            "candidate_tolerance_bpm": 1.0,
            "allowed_lock_states": ("SEARCHING", "NOISE_ONLY"),
            "notes": "Zero-valued PCM must not lock.",
        },
        {
            "name": "white_noise",
            "kind": "white-noise",
            "expected_bpm": None,
            "tolerance_bpm": None,
            "required_candidates": (),
            "candidate_tolerance_bpm": 1.0,
            "allowed_lock_states": ("SEARCHING", "NOISE_ONLY", "UNSTABLE"),
            "notes": "Deterministic broadband noise must not become STABLE.",
        },
        {
            "name": "pink_noise",
            "kind": "pink-noise",
            "expected_bpm": None,
            "tolerance_bpm": None,
            "required_candidates": (),
            "candidate_tolerance_bpm": 1.0,
            "allowed_lock_states": ("SEARCHING", "NOISE_ONLY", "UNSTABLE"),
            "notes": "Deterministic low-frequency-biased noise must not become STABLE.",
        },
        {
            "name": "clipped_200",
            "kind": "clipped",
            "bpm": 200.0,
            "expected_bpm": None,
            "tolerance_bpm": None,
            "required_candidates": ({"bpm": 200.0},),
            "candidate_tolerance_bpm": 2.0,
            "allowed_lock_states": ("CLIPPED_MIC", "UNSTABLE", "SEARCHING"),
            "notes": "Clipped microphone input must suppress final lock while preserving candidates.",
        },
        {
            "name": "recoverable_clipped_200",
            "kind": "recoverable-clipped",
            "bpm": 200.0,
            "expected_bpm": 200.0,
            "tolerance_bpm": 2.0,
            "required_candidates": (
                {"bpm": 200.0, "relations": ("main", "raw", "normalized_from_half")},
                {"bpm": 100.0},
            ),
            "candidate_tolerance_bpm": 2.0,
            "allowed_lock_states": ("LOCKING", "STABLE"),
            "notes": "Recoverable clipping keeps clipping visible while tempo remains usable.",
        },
        {
            "name": "breakdown_200",
            "kind": "breakdown",
            "bpm": 200.0,
            "expected_bpm": None,
            "tolerance_bpm": None,
            "required_candidates": ({"bpm": 200.0},),
            "candidate_tolerance_bpm": 2.0,
            "allowed_lock_states": ("BREAKDOWN", "UNSTABLE", "LOCKING", "SEARCHING"),
            "notes": "A valid intro followed by no-kick breakdown must not finish as STABLE.",
        },
        {
            "name": "dense_hitech_bassline_200",
            "kind": "dense",
            "bpm": 200.0,
            "expected_bpm": 200.0,
            "tolerance_bpm": 2.0,
            "required_candidates": ({"bpm": 200.0},),
            "candidate_tolerance_bpm": 2.0,
            "allowed_lock_states": ("STABLE",),
            "notes": "Dense hitech bassline simulation should preserve the main beat.",
        },
        {
            "name": "unstable_club_simulation",
            "kind": "unstable",
            "expected_bpm": None,
            "tolerance_bpm": None,
            "required_candidates": (),
            "candidate_tolerance_bpm": 1.0,
            "allowed_lock_states": ("SEARCHING", "NOISE_ONLY", "UNSTABLE", "LOCKING"),
            "notes": "Tempo drift, dropouts, rumble, and broadband noise must keep uncertainty visible.",
        },
    )


def _clean_report_specs() -> tuple[dict[str, Any], ...]:
    return tuple(
        {
            "name": f"clean_{bpm}",
            "kind": "pulse",
            "bpm": float(bpm),
            "expected_bpm": float(bpm),
            "tolerance_bpm": 1.0,
            "required_candidates": ({"bpm": float(bpm)},),
            "candidate_tolerance_bpm": 1.0,
            "allowed_lock_states": ("STABLE",),
            "notes": "Clean kick-like pulse track.",
        }
        for bpm in (170, 180, 190, 200, 220)
    )


if __name__ == "__main__":
    raise SystemExit(main())
