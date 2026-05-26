#!/usr/bin/env python3
"""Автономная проверка parity Python ↔ Rust DSP.

Генерирует канонический инвентарь фикстур, запускает и Python-референсный
анализатор, и Rust-бинарник ``analyze_wav`` на одних и тех же WAV-байтах,
и сообщает о дрифте по каждой фикстуре. Завершается с не-нулевым кодом,
если любая фикстура нарушает задокументированные допуски.

Этот инструмент намеренно отделён от ``cargo test``, чтобы Rust-тест-сюит
оставался герметичным.
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


BPM_TOLERANCE = 2.0
CONFIDENCE_TOLERANCE = 0.12
EQUIVALENT_LOCK_STATES = {
    frozenset({"SEARCHING", "NOISE_ONLY"}),
    frozenset({"LOCKING", "STABLE"}),
}


@dataclass
class ParityRow:
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cargo",
        default="/opt/homebrew/opt/rust/bin/cargo",
        help="cargo binary to invoke (default: %(default)s)",
    )
    parser.add_argument(
        "--release",
        action="store_true",
        help="build the Rust analyzer in release mode",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit a JSON report instead of a table",
    )
    args = parser.parse_args()

    cargo = args.cargo if Path(args.cargo).is_file() else shutil.which("cargo")
    if not cargo:
        print("error: cargo binary not found", file=sys.stderr)
        return 2

    rows: list[ParityRow] = []
    with tempfile.TemporaryDirectory(prefix="dsp-parity-") as tmp:
        tmp_path = Path(tmp)
        for name in fixture_names():
            fixture = make_fixture(name)
            wav_path = tmp_path / f"{name}.wav"
            write_wav(fixture, str(wav_path))

            python_result = result_to_dict(analyze_pcm(list(fixture.samples), fixture.sample_rate))
            rust_result = _run_rust_analyzer(cargo, args.release, wav_path)

            rows.append(_compare(name, python_result, rust_result))

    failed = [row for row in rows if not row.passed]

    if args.json:
        print(json.dumps([row.__dict__ for row in rows], indent=2, sort_keys=True))
    else:
        _print_table(rows)
        if failed:
            print(f"\n{len(failed)} fixture(s) failed parity:", file=sys.stderr)
            for row in failed:
                print(f"  - {row.fixture}: {row.reason}", file=sys.stderr)

    return 0 if not failed else 1


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


def _compare(name: str, py: dict[str, Any], rust: dict[str, Any]) -> ParityRow:
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
        bpm_ok = bpm_drift <= BPM_TOLERANCE

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

    return ParityRow(
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
        required = {
            (100, "raw"),
            (200, "normalized_from_half"),
        }
    elif name == "double_time_trap_400":
        required = {
            (400, "raw"),
            (200, "normalized_from_double"),
        }
    if not required:
        return True
    return required.issubset(py_relations) and required.issubset(rust_relations)


def _print_table(rows: list[ParityRow]) -> None:
    header = f"{'fixture':<28} {'py_bpm':>8} {'rust_bpm':>9} {'Δbpm':>6} {'py_conf':>8} {'rust_conf':>9} {'Δconf':>6} {'lock(py/rust)':<26} pass"
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


if __name__ == "__main__":
    raise SystemExit(main())
