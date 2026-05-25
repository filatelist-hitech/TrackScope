# tools/offline-lab

Offline analyzer and fixture generator boundary.

The offline lab must feed audio into the same `core/dsp` engine used by mobile. It may decode files, generate fixtures, and write reports, but it must not implement a separate BPM detector.

## Commands

Generate the deterministic WAV fixture suite:

```sh
python3 tools/offline-lab/offline_lab.py generate-suite --out-dir datasets/synthetic/offline-lab
```

Analyze one 16-bit PCM WAV fixture:

```sh
python3 tools/offline-lab/offline_lab.py analyze datasets/synthetic/offline-lab/pulse_200bpm.wav
```

Run the in-memory QA report for the required first-lab matrix:

```sh
python3 tools/offline-lab/offline_lab.py report
```

Each report row includes fixture name, expected BPM, detected BPM, BPM error, confidence, lock state, signal quality, candidates, pass/fail, and notes. Expected BPM metadata is used only by the offline QA report; the analyzer still computes tempo from PCM onset evidence. The command exits non-zero if any row fails, so it can be used as a validation gate. Trap rows require the raw candidate plus the normalized relation and `source_bpm`.
