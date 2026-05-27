#!/usr/bin/env python3
"""Кросс-языковая проверка parity Python ↔ Rust DSP.

Два режима работы:

  **Manifest** (режим по умолчанию, `--fixture-set real` или `--fixture-set all`):
    Читает `datasets/fixture_manifest.json`, для каждой записи загружает
    snapshot JSON (захваченный ранее) и сравнивает `python.primary_bpm` vs
    `rust.primary_bpm` из снапшота с допуском `bpm_tolerance` per-фикстура.
    Работает в CI без аудиофайлов.

  **Synthetic** (`--fixture-set synthetic`):
    Генерирует синтетические фикстуры на лету, прогоняет Python-анализатор и
    Rust-бинарник `analyze_wav` на одних и тех же WAV-байтах и репортит дрейф.
    Поведение идентично прежнему baseline.

  **Live** (`--fixture-set real --live --input DIR`):
    Перезапускает текущий Rust-анализатор на аудиофайлах из DIR, сравнивает с
    Python из снапшота. Используется после изменений DSP для обновления снапшотов.

Завершается с не-нулевым кодом, если хотя бы одна фикстура нарушает допуск.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from core.dsp import analyze_pcm, result_to_dict
from core.tests.helpers.synthetic_fixtures import (
    fixture_names,
    make_fixture,
    write_wav,
)


MANIFEST_PATH = REPO_ROOT / "datasets" / "fixture_manifest.json"

# Legacy tolerance for synthetic fixtures (unchanged from original baseline)
SYNTHETIC_BPM_TOLERANCE = 2.0
CONFIDENCE_TOLERANCE = 0.12
EQUIVALENT_LOCK_STATES = {
    frozenset({"SEARCHING", "NOISE_ONLY"}),
    frozenset({"LOCKING", "STABLE"}),
}


# ── data classes ──────────────────────────────────────────────────────────────


@dataclass
class SyntheticParityRow:
    fixture: str
    python_bpm: float | None
    rust_bpm: float | None
    python_confidence: float
    rust_confidence: float
    python_lock: str
    rust_lock: str
    bpm_drift: float | None
    confidence_drift: float
    candidate_relations_match: bool
    passed: bool
    reason: str


@dataclass
class ManifestParityRow:
    name: str
    category: str
    tolerance: float
    python_bpm: float | None
    rust_bpm: float | None
    delta: float | None
    python_lock: str
    rust_lock: str
    lock_match: bool
    passed: bool
    reason: str


# ── entry point ───────────────────────────────────────────────────────────────


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--fixture-set",
        choices=["all", "synthetic", "real"],
        default="all",
        help=(
            "'synthetic' uses live generation (legacy baseline); "
            "'real' and 'all' read datasets/fixture_manifest.json "
            "(default: %(default)s)"
        ),
    )
    parser.add_argument(
        "--live",
        action="store_true",
        help=(
            "re-run current Rust analysis on audio files and compare to "
            "snapshot Python output (requires audio files locally; "
            "use with --fixture-set real and --input DIR)"
        ),
    )
    parser.add_argument(
        "--input",
        default=None,
        metavar="DIR",
        help="directory with audio files (required with --live for real fixtures)",
    )
    parser.add_argument(
        "--cargo",
        default="/opt/homebrew/opt/rust/bin/cargo",
        help="cargo binary (default: %(default)s)",
    )
    parser.add_argument(
        "--release",
        action="store_true",
        help="build Rust analyzer in --release mode",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit JSON report instead of a table",
    )
    args = parser.parse_args()

    cargo = args.cargo if Path(args.cargo).is_file() else shutil.which("cargo")
    if not cargo:
        print("error: cargo binary not found", file=sys.stderr)
        return 2

    if args.fixture_set == "synthetic":
        return _run_synthetic_parity(cargo=cargo, release=args.release, json_mode=args.json)

    # Manifest-based modes: "real" or "all"
    category_filter: str | None = None if args.fixture_set == "all" else args.fixture_set
    return _run_manifest_parity(
        cargo=cargo,
        release=args.release,
        json_mode=args.json,
        category_filter=category_filter,
        live=args.live,
        input_dir=args.input,
    )


# ── manifest parity ───────────────────────────────────────────────────────────


def _run_manifest_parity(
    cargo: str,
    release: bool,
    json_mode: bool,
    category_filter: str | None,
    live: bool,
    input_dir: str | None,
) -> int:
    if not MANIFEST_PATH.exists():
        print("error: datasets/fixture_manifest.json not found", file=sys.stderr)
        print(
            "Run: python3 tools/offline-lab/offline_lab.py snapshot --input datasets/hitech/",
            file=sys.stderr,
        )
        return 2

    manifest = json.loads(MANIFEST_PATH.read_text())
    fixtures = manifest.get("fixtures", [])

    if category_filter:
        fixtures = [f for f in fixtures if f.get("category") == category_filter]

    if not fixtures:
        print(f"No fixtures in manifest (category={category_filter!r})")
        return 0

    rows: list[ManifestParityRow] = []

    for entry in fixtures:
        snapshot_rel = entry.get("snapshot", "")
        snapshot_path = REPO_ROOT / snapshot_rel

        if not snapshot_path.exists():
            rows.append(ManifestParityRow(
                name=entry.get("name", snapshot_rel),
                category=entry.get("category", "unknown"),
                tolerance=float(entry.get("bpm_tolerance", 4.0)),
                python_bpm=None,
                rust_bpm=None,
                delta=None,
                python_lock="",
                rust_lock="",
                lock_match=False,
                passed=False,
                reason=f"snapshot not found: {snapshot_rel}",
            ))
            continue

        snapshot = json.loads(snapshot_path.read_text())
        tolerance = float(entry.get("bpm_tolerance", 4.0))
        lock_must_match = bool(entry.get("lock_state_must_match", False))

        if live:
            row = _compare_manifest_live(
                entry=entry,
                snapshot=snapshot,
                tolerance=tolerance,
                lock_must_match=lock_must_match,
                cargo=cargo,
                release=release,
                input_dir=input_dir,
            )
        else:
            py_result = snapshot.get("python", {})
            rust_result = snapshot.get("rust", {})
            row = _compare_manifest(
                name=entry.get("name", ""),
                category=entry.get("category", "unknown"),
                py=py_result,
                rust=rust_result,
                tolerance=tolerance,
                lock_must_match=lock_must_match,
            )

        rows.append(row)

    failed = [r for r in rows if not r.passed]

    if json_mode:
        print(json.dumps([r.__dict__ for r in rows], indent=2, sort_keys=True))
    else:
        _print_manifest_table(rows)
        if failed:
            print(f"\n{len(failed)} fixture(s) failed parity:", file=sys.stderr)
            for r in failed:
                print(f"  - {r.name}: {r.reason}", file=sys.stderr)

    return 0 if not failed else 1


def _compare_manifest_live(
    entry: dict[str, Any],
    snapshot: dict[str, Any],
    tolerance: float,
    lock_must_match: bool,
    cargo: str,
    release: bool,
    input_dir: str | None,
) -> ManifestParityRow:
    name = entry.get("name", "")
    category = entry.get("category", "unknown")
    source_file = snapshot.get("source_file", "")

    if input_dir:
        audio_path = Path(input_dir) / source_file
    else:
        # Infer from snapshot location: snapshots/<fixture>.json → parent.parent/<source_file>
        snap_path = REPO_ROOT / entry.get("snapshot", "")
        audio_path = snap_path.parent.parent / source_file

    if not audio_path.exists():
        return ManifestParityRow(
            name=name,
            category=category,
            tolerance=tolerance,
            python_bpm=None,
            rust_bpm=None,
            delta=None,
            python_lock="",
            rust_lock="",
            lock_match=False,
            passed=False,
            reason=(
                f"audio file not found: {source_file} "
                f"(use --input DIR to specify the audio directory)"
            ),
        )

    try:
        with tempfile.TemporaryDirectory(prefix="dsp-live-parity-") as tmp:
            tmp_wav = Path(tmp) / "converted.wav"
            _convert_to_mono_wav(audio_path, tmp_wav, duration=30.0)
            rust_result = _run_rust_analyzer(cargo, release, tmp_wav)
    except Exception as exc:
        return ManifestParityRow(
            name=name,
            category=category,
            tolerance=tolerance,
            python_bpm=None,
            rust_bpm=None,
            delta=None,
            python_lock="",
            rust_lock="",
            lock_match=False,
            passed=False,
            reason=f"live analysis failed: {exc}",
        )

    return _compare_manifest(
        name=name,
        category=category,
        py=snapshot.get("python", {}),
        rust=rust_result,
        tolerance=tolerance,
        lock_must_match=lock_must_match,
    )


def _compare_manifest(
    name: str,
    category: str,
    py: dict[str, Any],
    rust: dict[str, Any],
    tolerance: float,
    lock_must_match: bool,
) -> ManifestParityRow:
    py_bpm = py.get("primary_bpm")
    rust_bpm = rust.get("primary_bpm")

    delta: float | None = None
    bpm_ok = True
    if py_bpm is None and rust_bpm is None:
        bpm_ok = True
    elif py_bpm is None or rust_bpm is None:
        bpm_ok = False
    else:
        delta = abs(float(py_bpm) - float(rust_bpm))
        bpm_ok = delta <= tolerance

    py_lock = py.get("lock_state", "")
    rust_lock = rust.get("lock_state", "")
    if lock_must_match:
        lock_ok = py_lock == rust_lock or frozenset({py_lock, rust_lock}) in EQUIVALENT_LOCK_STATES
    else:
        lock_ok = True

    reasons = []
    if not bpm_ok:
        reasons.append(
            f"bpm drift {delta:.2f if delta is not None else '∞'} > {tolerance} "
            f"(py={py_bpm}, rust={rust_bpm})"
        )
    if not lock_ok:
        reasons.append(f"lock mismatch py={py_lock} rust={rust_lock}")

    return ManifestParityRow(
        name=name,
        category=category,
        tolerance=tolerance,
        python_bpm=py_bpm,
        rust_bpm=rust_bpm,
        delta=delta,
        python_lock=py_lock,
        rust_lock=rust_lock,
        lock_match=lock_ok,
        passed=bpm_ok and lock_ok,
        reason="; ".join(reasons) or "ok",
    )


def _print_manifest_table(rows: list[ManifestParityRow]) -> None:
    header = (
        f"{'name':<28} {'cat':>6} {'tol':>5} "
        f"{'py_bpm':>8} {'rust_bpm':>9} {'delta':>7} "
        f"{'py_lock':<12} {'ru_lock':<12} {'lock':>5} pass"
    )
    print(header)
    print("-" * len(header))
    for row in rows:
        py_bpm = f"{row.python_bpm:.1f}" if row.python_bpm is not None else "null"
        rust_bpm = f"{row.rust_bpm:.1f}" if row.rust_bpm is not None else "null"
        delta = f"{row.delta:.2f}" if row.delta is not None else "-"
        lock_tag = "ok" if row.lock_match else "DIFF"
        flag = "PASS" if row.passed else "FAIL"
        print(
            f"{row.name:<28} {row.category:>6} {row.tolerance:>5.1f} "
            f"{py_bpm:>8} {rust_bpm:>9} {delta:>7} "
            f"{row.python_lock:<12} {row.rust_lock:<12} {lock_tag:>5} {flag}"
        )


# ── synthetic parity (legacy baseline) ───────────────────────────────────────


def _run_synthetic_parity(cargo: str, release: bool, json_mode: bool) -> int:
    rows: list[SyntheticParityRow] = []
    with tempfile.TemporaryDirectory(prefix="dsp-parity-") as tmp:
        tmp_path = Path(tmp)
        for name in fixture_names():
            fixture = make_fixture(name)
            wav_path = tmp_path / f"{name}.wav"
            write_wav(fixture, str(wav_path))

            python_result = result_to_dict(analyze_pcm(list(fixture.samples), fixture.sample_rate))
            rust_result = _run_rust_analyzer(cargo, release, wav_path)

            rows.append(_compare_synthetic(name, python_result, rust_result))

    failed = [row for row in rows if not row.passed]

    if json_mode:
        print(json.dumps([row.__dict__ for row in rows], indent=2, sort_keys=True))
    else:
        _print_synthetic_table(rows)
        if failed:
            print(f"\n{len(failed)} fixture(s) failed parity:", file=sys.stderr)
            for row in failed:
                print(f"  - {row.fixture}: {row.reason}", file=sys.stderr)

    return 0 if not failed else 1


def _compare_synthetic(name: str, py: dict[str, Any], rust: dict[str, Any]) -> SyntheticParityRow:
    py_bpm = py.get("primary_bpm")
    rust_bpm = rust.get("primary_bpm")
    bpm_drift = None
    bpm_ok = True
    if py_bpm is None and rust_bpm is None:
        bpm_ok = True
    elif py_bpm is None or rust_bpm is None:
        bpm_ok = False
    else:
        bpm_drift = abs(py_bpm - rust_bpm)
        bpm_ok = bpm_drift <= SYNTHETIC_BPM_TOLERANCE

    py_conf = float(py.get("confidence", 0.0))
    rust_conf = float(rust.get("confidence", 0.0))
    conf_drift = abs(py_conf - rust_conf)
    conf_ok = conf_drift <= CONFIDENCE_TOLERANCE

    py_lock = py.get("lock_state", "")
    rust_lock = rust.get("lock_state", "")
    lock_ok = py_lock == rust_lock or frozenset({py_lock, rust_lock}) in EQUIVALENT_LOCK_STATES

    py_relations = {(round(c["bpm"]), c["relation"]) for c in py.get("candidates", [])}
    rust_relations = {(round(c["bpm"]), c["relation"]) for c in rust.get("candidates", [])}
    relations_match = _required_relations_present(name, py_relations, rust_relations)

    reasons = []
    if not bpm_ok:
        reasons.append(f"primary_bpm drift py={py_bpm} rust={rust_bpm}")
    if not conf_ok:
        reasons.append(f"confidence drift {conf_drift:.3f} > {CONFIDENCE_TOLERANCE}")
    if not lock_ok:
        reasons.append(f"lock_state mismatch py={py_lock} rust={rust_lock}")
    if not relations_match:
        reasons.append("required candidate relations missing")

    return SyntheticParityRow(
        fixture=name,
        python_bpm=py_bpm,
        rust_bpm=rust_bpm,
        python_confidence=py_conf,
        rust_confidence=rust_conf,
        python_lock=py_lock,
        rust_lock=rust_lock,
        bpm_drift=bpm_drift,
        confidence_drift=conf_drift,
        candidate_relations_match=relations_match,
        passed=bpm_ok and conf_ok and lock_ok and relations_match,
        reason="; ".join(reasons) or "ok",
    )


def _required_relations_present(
    name: str,
    py_relations: set[tuple[int, str]],
    rust_relations: set[tuple[int, str]],
) -> bool:
    required: set[tuple[int, str]] = set()
    if name == "half_time_trap_100":
        required = {(100, "raw"), (200, "normalized_from_half")}
    elif name == "double_time_trap_400":
        required = {(400, "raw"), (200, "normalized_from_double")}
    if not required:
        return True
    return required.issubset(py_relations) and required.issubset(rust_relations)


def _print_synthetic_table(rows: list[SyntheticParityRow]) -> None:
    header = (
        f"{'fixture':<28} {'py_bpm':>8} {'rust_bpm':>9} {'Δbpm':>6} "
        f"{'py_conf':>8} {'rust_conf':>9} {'Δconf':>6} {'lock(py/rust)':<26} pass"
    )
    print(header)
    print("-" * len(header))
    for row in rows:
        py_bpm = f"{row.python_bpm:.1f}" if row.python_bpm is not None else "null"
        rust_bpm = f"{row.rust_bpm:.1f}" if row.rust_bpm is not None else "null"
        drift_bpm = f"{row.bpm_drift:.2f}" if row.bpm_drift is not None else "-"
        lock_pair = f"{row.python_lock}/{row.rust_lock}"
        flag = "PASS" if row.passed else "FAIL"
        print(
            f"{row.fixture:<28} {py_bpm:>8} {rust_bpm:>9} {drift_bpm:>6} "
            f"{row.python_confidence:>8.3f} {row.rust_confidence:>9.3f} "
            f"{row.confidence_drift:>6.3f} {lock_pair:<26} {flag}"
        )


# ── shared helpers ────────────────────────────────────────────────────────────


def _run_rust_analyzer(cargo: str, release: bool, wav_path: Path) -> dict[str, Any]:
    cmd = [
        cargo,
        "run",
        "--quiet",
        "--manifest-path",
        str(REPO_ROOT / "core" / "dsp" / "Cargo.toml"),
        "--bin",
        "analyze_wav",
    ]
    if release:
        cmd.append("--release")
    cmd.extend(["--", "--input", str(wav_path)])
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise SystemExit(
            f"Rust analyzer failed on {wav_path.name}: {proc.stderr.strip() or proc.stdout.strip()}"
        )
    return json.loads(proc.stdout)


def _convert_to_mono_wav(src: Path, dst: Path, duration: float = 30.0) -> None:
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
        raise RuntimeError(f"ffmpeg conversion failed: {proc.stderr.decode()[-400:]}")


if __name__ == "__main__":
    raise SystemExit(main())
