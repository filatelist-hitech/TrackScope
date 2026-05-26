"""Публичный адаптер CLI офлайн-DSP-лаба, используемый в регрессионных тестах."""

from __future__ import annotations

import json
from pathlib import Path
import shlex
import subprocess
import sys
from typing import Any
import os


REPO_ROOT = Path(__file__).resolve().parents[3]
PYTHON_ANALYZER = REPO_ROOT / "tools" / "offline-lab" / "analyze.py"
NODE_ANALYZER = REPO_ROOT / "tools" / "offline-lab" / "analyze.js"
PYTHON_OFFLINE_LAB = REPO_ROOT / "tools" / "offline-lab" / "offline_lab.py"


class DspLabRunner:
    """Запускает публичный офлайн-анализатор и возвращает его JSON-результат."""

    def __init__(self, command_template: str | None = None) -> None:
        self.command_template = command_template or os.environ.get("DSP_LAB_CMD")

    def analyze(self, wav_path: Path, *, mode: str = "hitech") -> dict[str, Any]:
        command = self._build_command(wav_path=wav_path, mode=mode)
        completed = subprocess.run(
            command,
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if completed.returncode != 0:
            raise AssertionError(
                "offline DSP analyzer command failed\n"
                f"command: {shlex.join(command)}\n"
                f"exit code: {completed.returncode}\n"
                f"stdout:\n{completed.stdout}\n"
                f"stderr:\n{completed.stderr}\n"
                "Expected a public offline analyzer CLI. Auto-detected shapes are "
                "`python3 tools/offline-lab/analyze.py --input <wav> --mode hitech --json`, "
                "`node tools/offline-lab/analyze.js <wav> --json`, and "
                "`python3 tools/offline-lab/offline_lab.py analyze <wav>`. "
                "Set DSP_LAB_CMD with {fixture} and {mode} placeholders to override."
            )

        try:
            result = json.loads(completed.stdout)
        except json.JSONDecodeError as exc:
            raise AssertionError(
                "offline DSP analyzer did not emit JSON on stdout\n"
                f"command: {shlex.join(command)}\n"
                f"stdout:\n{completed.stdout}\n"
                f"stderr:\n{completed.stderr}"
            ) from exc

        if not isinstance(result, dict):
            raise AssertionError(f"offline DSP analyzer JSON must be an object, got {type(result)!r}")
        return result

    def _build_command(self, *, wav_path: Path, mode: str) -> list[str]:
        if self.command_template:
            command_text = self.command_template.format(fixture=str(wav_path), mode=mode)
            return shlex.split(command_text)

        if PYTHON_ANALYZER.exists():
            return [sys.executable, str(PYTHON_ANALYZER), "--input", str(wav_path), "--mode", mode, "--json"]

        if NODE_ANALYZER.exists():
            return ["node", str(NODE_ANALYZER), str(wav_path), "--json"]

        return [sys.executable, str(PYTHON_OFFLINE_LAB), "analyze", str(wav_path)]
