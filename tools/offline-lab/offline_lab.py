#!/usr/bin/env python3
"""Офлайн-генератор фикстур и BPM-анализатор."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
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


MANIFEST_PATH = REPO_ROOT / "datasets" / "fixture_manifest.json"
_AUDIO_EXTENSIONS = frozenset({".wav", ".aiff", ".aif", ".flac"})
# Directories whose name indicates generated synthetic fixtures vs real recordings
_SYNTHETIC_DIRS = frozenset({"synthetic", "offline-lab"})


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

    analyze_cmd = subcommands.add_parser("analyze", help="analyze a 16-bit PCM WAV file")
    analyze_cmd.add_argument("path")

    snapshot_cmd = subcommands.add_parser(
        "snapshot",
        help=(
            "capture Python+Rust analysis snapshots for audio files in a directory. "
            "Snapshots (JSON) are saved to <input>/snapshots/ and committed; "
            "audio source files are not committed."
        ),
    )
    snapshot_cmd.add_argument(
        "--input",
        required=True,
        metavar="DIR",
        help="directory containing audio files (.wav .aiff .aif .flac)",
    )
    snapshot_cmd.add_argument(
        "--force",
        action="store_true",
        help="overwrite existing snapshot files",
    )
    snapshot_cmd.add_argument(
        "--duration",
        type=float,
        default=30.0,
        metavar="SECS",
        help="seconds of audio to analyze per file (default: 30.0)",
    )
    snapshot_cmd.add_argument(
        "--cargo",
        default="/opt/homebrew/opt/rust/bin/cargo",
        help="cargo binary to invoke for Rust analysis (default: %(default)s)",
    )
    snapshot_cmd.add_argument(
        "--release",
        action="store_true",
        help="build Rust analyzer in --release mode",
    )

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

    if args.command == "analyze":
        samples, sample_rate = read_wav(args.path)
        result = analyze_pcm(samples, sample_rate)
        print(json.dumps(result_to_dict(result), indent=2, sort_keys=True))
        return 0

    if args.command == "snapshot":
        cargo = args.cargo if Path(args.cargo).is_file() else shutil.which("cargo")
        if not cargo:
            print("error: cargo binary not found; pass --cargo or add cargo to PATH", file=sys.stderr)
            return 2
        return _run_snapshot(
            input_dir=args.input,
            force=args.force,
            duration=args.duration,
            cargo=cargo,
            release=args.release,
        )

    return 1  # unreachable


# ── snapshot ──────────────────────────────────────────────────────────────────


def _run_snapshot(
    input_dir: str,
    force: bool,
    duration: float,
    cargo: str,
    release: bool,
) -> int:
    """Analyze each audio file in input_dir with Python and Rust, save JSON snapshots."""
    input_path = Path(input_dir).resolve()
    if not input_path.is_dir():
        print(f"error: {input_dir!r} is not a directory", file=sys.stderr)
        return 1

    audio_files = sorted(
        f for f in input_path.iterdir()
        if f.is_file() and f.suffix.lower() in _AUDIO_EXTENSIONS
    )
    if not audio_files:
        print(f"No audio files found in {input_dir!r} (looking for .wav .aiff .aif .flac)")
        return 0

    snapshots_dir = input_path / "snapshots"
    snapshots_dir.mkdir(exist_ok=True)
    dir_name = input_path.name  # e.g. "hitech" — used as fixture name prefix
    # Logical category for manifest filtering: "synthetic" vs "real"
    category = "synthetic" if dir_name in _SYNTHETIC_DIRS else "real"

    created = skipped = failed = 0
    manifest_entries: list[dict[str, Any]] = []

    for audio_file in audio_files:
        name = _make_fixture_name(audio_file.stem, dir_name)
        snapshot_path = snapshots_dir / f"{name}.json"

        if snapshot_path.exists() and not force:
            print(f"  skip  {audio_file.name!r}")
            skipped += 1
            existing = json.loads(snapshot_path.read_text())
            entry = _snapshot_to_manifest_entry(
                name=name,
                snapshot_path=snapshot_path,
                category=category,
                py_bpm=existing.get("python", {}).get("primary_bpm"),
                rust_bpm=existing.get("rust", {}).get("primary_bpm"),
            )
            if entry is not None:
                manifest_entries.append(entry)
            continue

        print(f"  → {audio_file.name}")
        try:
            py_result, rust_result, wav_sha256 = _analyze_audio_file(
                audio_file, duration, cargo, release
            )
        except Exception as exc:
            print(f"    FAIL: {exc}", file=sys.stderr)
            failed += 1
            continue

        bpm_hint = _extract_bpm_hint(audio_file.stem)
        py_bpm = py_result.get("primary_bpm")
        rust_bpm = rust_result.get("primary_bpm")

        snapshot: dict[str, Any] = {
            "captured_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "category": category,
            "expected_bpm_hint": bpm_hint,
            "fixture_sha256": wav_sha256,
            "python": py_result,
            "rust": rust_result,
            "source_file": audio_file.name,
        }
        snapshot_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n")

        hint_str = f"  hint={bpm_hint:.0f}" if bpm_hint else ""
        print(f"    py={_fmt_bpm(py_bpm)} rust={_fmt_bpm(rust_bpm)}{hint_str}")
        created += 1

        entry = _snapshot_to_manifest_entry(
            name=name,
            snapshot_path=snapshot_path,
            category=category,
            py_bpm=py_bpm,
            rust_bpm=rust_bpm,
        )
        if entry is not None:
            manifest_entries.append(entry)
        else:
            print(
                f"    NOTE: excluded from manifest (null/non-null mismatch; "
                f"add manually with wider tolerance if needed)"
            )

    if manifest_entries:
        _update_fixture_manifest(manifest_entries)

    print(f"\nDone: {created} created, {skipped} skipped, {failed} failed")
    print(f"Manifest: {len(manifest_entries)} fixture(s) upserted")
    return 0 if failed == 0 else 1


def _analyze_audio_file(
    src: Path,
    duration: float,
    cargo: str,
    release: bool,
) -> tuple[dict[str, Any], dict[str, Any], str]:
    """Convert src to 16-bit mono WAV, run Python+Rust analysis, return results + SHA256."""
    with tempfile.TemporaryDirectory(prefix="dsp-snapshot-") as tmp:
        tmp_wav = Path(tmp) / "converted.wav"
        _convert_to_mono_wav(src, tmp_wav, duration)
        wav_sha256 = hashlib.sha256(tmp_wav.read_bytes()).hexdigest()

        samples, sample_rate = read_wav(str(tmp_wav))
        py_result = result_to_dict(analyze_pcm(samples, sample_rate))

        rust_result = _invoke_rust_analyzer(cargo, release, tmp_wav)

    return py_result, rust_result, wav_sha256


def _convert_to_mono_wav(src: Path, dst: Path, duration: float) -> None:
    """Convert any audio format to 16-bit mono PCM WAV at 44100 Hz via ffmpeg."""
    ffmpeg = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
    cmd = [
        ffmpeg, "-y", "-loglevel", "error",
        "-i", str(src),
        "-t", str(duration),
        "-ac", "1",
        "-ar", "44100",
        "-sample_fmt", "s16",
        str(dst),
    ]
    proc = subprocess.run(cmd, capture_output=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {proc.stderr.decode()[-400:]}")


def _invoke_rust_analyzer(cargo: str, release: bool, wav_path: Path) -> dict[str, Any]:
    cmd = [
        cargo, "run", "--quiet",
        "--manifest-path", str(REPO_ROOT / "core" / "dsp" / "Cargo.toml"),
        "--bin", "analyze_wav",
    ]
    if release:
        cmd.append("--release")
    cmd.extend(["--", "--input", str(wav_path)])
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"Rust analyzer failed: {proc.stderr.strip()[-400:]}")
    return json.loads(proc.stdout)


def _make_fixture_name(stem: str, dir_prefix: str) -> str:
    """Derive a stable fixture name from a filename stem.

    Leading-number files: '<dir>_real_NN' (e.g. 'hitech_real_01').
    Fallback: sanitized stem with '<dir>_real_' prefix.
    """
    m = re.match(r"^(\d+)\s+", stem)
    if m:
        return f"{dir_prefix}_real_{int(m.group(1)):02d}"
    sanitized = re.sub(r"[^\w]", "_", stem).lower().strip("_")[:40]
    return f"{dir_prefix}_real_{sanitized}"


def _extract_bpm_hint(stem: str) -> float | None:
    """Parse BPM from a filename stem if present (e.g. '(180)', '[188 BPM]', '186bpm')."""
    patterns = [
        r"\((\d{2,3})\s*(?:[Bb][Pp][Mm])?\)",
        r"\[(\d{2,3})\s*[Bb][Pp][Mm]\]",
        r"(?<!\d)(\d{2,3})\s*[Bb][Pp][Mm]",
        r"(?<!\d)(\d{3})(?!\d)",
    ]
    for pattern in patterns:
        for m in re.finditer(pattern, stem):
            bpm = float(m.group(1))
            if 80.0 <= bpm <= 320.0:
                return bpm
    return None


def _snapshot_to_manifest_entry(
    name: str,
    snapshot_path: Path,
    category: str,
    py_bpm: float | None,
    rust_bpm: float | None,
) -> dict[str, Any] | None:
    """Build a manifest entry for this snapshot.

    Returns None when exactly one side is null — a null/non-null parity issue
    that needs manual review before committing to CI.
    """
    if (py_bpm is None) != (rust_bpm is None):
        print(
            f"    SKIP manifest: null/non-null mismatch "
            f"(py={_fmt_bpm(py_bpm)}, rust={_fmt_bpm(rust_bpm)})"
        )
        return None

    # Per-fixture tolerance: min 4.0 BPM, or initial delta + 1.0 BPM buffer.
    # The initial delta is the baseline; future regressions raise it above tolerance.
    if py_bpm is not None and rust_bpm is not None:
        delta = abs(py_bpm - rust_bpm)
        tolerance = max(4.0, round(delta + 1.0, 1))
    else:
        tolerance = 4.0  # both null; tolerance is irrelevant but set canonical default

    return {
        "bpm_tolerance": tolerance,
        "category": category,
        "lock_state_must_match": False,
        "name": name,
        "snapshot": str(snapshot_path.relative_to(REPO_ROOT)),
    }


def _update_fixture_manifest(new_entries: list[dict[str, Any]]) -> None:
    """Upsert fixture entries into datasets/fixture_manifest.json (merge by name)."""
    if MANIFEST_PATH.exists():
        manifest = json.loads(MANIFEST_PATH.read_text())
    else:
        manifest = {"fixtures": []}

    by_name = {entry["name"]: i for i, entry in enumerate(manifest["fixtures"])}
    for entry in new_entries:
        idx = by_name.get(entry["name"])
        if idx is not None:
            manifest["fixtures"][idx] = entry
        else:
            manifest["fixtures"].append(entry)
            by_name[entry["name"]] = len(manifest["fixtures"]) - 1

    manifest["fixtures"].sort(key=lambda e: (e.get("category", ""), e.get("name", "")))
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"  manifest → {MANIFEST_PATH.relative_to(REPO_ROOT)}")


def _fmt_bpm(bpm: float | None) -> str:
    return f"{bpm:.1f}" if bpm is not None else "null"


# ── report (unchanged) ────────────────────────────────────────────────────────


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
