# Plan: Rust DSP native + authoritative parity

## 1. Task classification
- complexity: medium
- domains: dsp, qa, docs, performance (test runtime)

## 2. Agents
- `@archman` — placement of shared Rust fixtures (`core/dsp/tests/common/mod.rs`) so they stay test-only and out of the public surface.
- `@dspman` — confirm the Rust `analyze_pcm` pipeline is already native (it is) and own the JSON-emitting CLI.
- `@qaman` — extend the Rust fixture inventory to mirror `core/tests/helpers/synthetic_fixtures.py` and assert the contract per fixture.
- `@reviewman` — pre-merge gate: anti-fake, no Python subprocess in `cargo test`, candidates preserved, docs aligned.

## 3. Files to inspect
- `core/dsp/src/lib.rs` (native analyzer — already in place)
- `core/dsp/tests/offline_contract.rs` (Rust-native contract assertions)
- `core/dsp/tests/python_parity.rs` (shells out to `python3` — the only non-hermetic test)
- `core/dsp/tempo.py`, `core/dsp/synthetic.py` (Python reference, kept as reference)
- `core/tests/helpers/synthetic_fixtures.py` (Python fixture inventory)
- `tools/offline-lab/analyze.py` (Python analyzer CLI)

## 4. Current behavior
- Rust `analyze_pcm` is already a self-contained native pipeline (onset envelope → autocorrelation → hitech normalization → confidence → lock state). No subprocess.
- Only `core/dsp/tests/python_parity.rs` invokes `python3` during `cargo test`, so the Rust suite is implicitly coupled to a Python install.
- Fixture generators are duplicated between `offline_contract.rs` and `python_parity.rs`.

## 5. Target behavior
- `cargo test --workspace` runs hermetically, with `python3` removed from `PATH`, and exercises the full Rust fixture inventory.
- A single shared Rust fixture module (`core/dsp/tests/common/mod.rs`) hosts all generators; `offline_contract.rs` consumes it.
- `python_parity.rs` is removed (Option A). The Rust contract assertions in `offline_contract.rs` already cover every behavior the parity test asserted.
- A standalone, opt-in cross-language parity check lives in `tools/offline-lab/parity.py`, driving Python and a new Rust JSON-emitting binary (`analyze_wav`) over the same WAV fixtures and tabulating drift.

## 6. Data contracts
- `DspResult` shape unchanged (`primary_bpm`, `confidence`, `lock_state`, `signal_quality`, `candidates[]`, `timing`).
- `analyze_wav` binary stdout: a single JSON object matching `result_to_dict` from `core/dsp/__init__.py` (same key set the Python analyzer emits — `primary_bpm`, `confidence`, `lock_state`, `signal_quality`, `candidates`, `timing`).
- Parity tolerances per fixture: BPM ±2.0, confidence ±0.10, lock-state exact match where defined.

## 7. Implementation steps
1. Create `core/dsp/tests/common/mod.rs` with deterministic generators (silence, white_noise, pink_noise, clean 170/180/190/200/220, half-time/double-time traps, severely/recoverable clipped, breakdown, dense bassline, unstable club).
2. Refactor `core/dsp/tests/offline_contract.rs` to consume `common::*`.
3. Delete `core/dsp/tests/python_parity.rs`.
4. Add `serde` + `serde_json` to `core/dsp` deps and derive `Serialize` on result types.
5. Add `core/dsp/src/bin/analyze_wav.rs` — read 16-bit PCM WAV from `--input`, run `analyze_pcm`, print JSON.
6. Add `tools/offline-lab/parity.py` subcommand — generate fixtures with `core.dsp.synthetic`, write WAV, run Python analyzer + Rust binary, compare, exit non-zero on disagreement.
7. Update docs (`DSP_ALGORITHM.md`, `QA_MATRIX.md`, root `README.md`, `CHANGELOG.md`).

## 8. Tests
- `/opt/homebrew/opt/rust/bin/cargo test --workspace`
- Hermetic: `env -i PATH=/usr/bin:/bin:/opt/homebrew/opt/rust/bin /opt/homebrew/opt/rust/bin/cargo test --workspace`
- `python3 -m unittest discover core/tests`
- `/opt/homebrew/opt/nodejs/bin/node --test core/dsp/index.test.js`
- `python3 tools/offline-lab/offline_lab.py report`
- `python3 tools/offline-lab/parity.py` (new)

## 9. Risks
- Adding serde derives to the public types changes the lib API surface — mitigated by keeping the existing structs and only deriving on them (no rename).
- Rust binary needs a WAV reader. Mitigated by writing a minimal 16-bit PCM mono reader matching `core/dsp/synthetic.write_wav`.
- Parity tool may surface real algorithmic drift Python ↔ Rust. Mitigation: ship the tool with documented tolerances and note Rust is authoritative — drift becomes the next patch.

## 10. Done when
- `cargo test --workspace` passes hermetically (no `python3` in PATH).
- `python_parity.rs` is gone; `offline_contract.rs` covers the full fixture inventory using `common::*`.
- `tools/offline-lab/parity.py` runs end-to-end and reports parity per fixture.
- Docs and CHANGELOG updated; no anti-fake rules violated.
