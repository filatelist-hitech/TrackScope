#!/usr/bin/env python3
"""Публичный CLI офлайн-анализатора для регрессионных тестов и отчётов по фикстурам."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from core.dsp import analyze_pcm, result_to_dict
from core.dsp.synthetic import read_wav


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze a WAV file with the offline DSP BPM detector")
    parser.add_argument("--input", required=True, help="16-bit PCM WAV input")
    parser.add_argument("--mode", choices=["hitech"], default="hitech")
    parser.add_argument("--json", action="store_true", help="emit JSON only")
    args = parser.parse_args()

    samples, sample_rate = read_wav(args.input)
    result = analyze_pcm(samples, sample_rate)
    payload = result_to_dict(result)

    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print(f"primary_bpm: {payload['primary_bpm']}")
        print(f"confidence: {payload['confidence']}")
        print(f"lock_state: {payload['lock_state']}")
        print(json.dumps(payload["candidates"], indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
