"""Deterministic synthetic audio fixtures for the offline DSP lab.

The helpers intentionally generate audio, not expected analyzer output. Tests
use the metadata only as acceptance criteria for a real public DSP API/CLI.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
import random
import wave


SAMPLE_RATE = 48_000
DEFAULT_DURATION_SEC = 14.0


@dataclass(frozen=True)
class FixtureExpectation:
    primary_bpm: float | None
    tolerance_bpm: float | None
    stable_allowed: bool
    required_candidate_bpms: tuple[float, ...] = ()
    allowed_lock_states: tuple[str, ...] = ()


@dataclass(frozen=True)
class FixtureAudio:
    name: str
    samples: tuple[float, ...]
    sample_rate: int
    expectation: FixtureExpectation
    notes: str


def fixture_names() -> tuple[str, ...]:
    return (
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
    )


def make_fixture(name: str) -> FixtureAudio:
    if name.startswith("clean_"):
        bpm = float(name.removeprefix("clean_"))
        return _pulse_fixture(
            name=name,
            bpm=bpm,
            expected_primary=bpm,
            tolerance=1.0,
            required_candidates=(bpm,),
            notes="Clean kick-like click track.",
        )

    if name == "half_time_trap_100":
        return _pulse_fixture(
            name=name,
            bpm=100.0,
            expected_primary=200.0,
            tolerance=1.0,
            required_candidates=(100.0, 200.0),
            notes="Raw 100 BPM pulse must stay visible while hitech mode chooses normalized 200 BPM.",
        )

    if name == "double_time_trap_400":
        return _pulse_fixture(
            name=name,
            bpm=400.0,
            expected_primary=200.0,
            tolerance=1.0,
            required_candidates=(400.0, 200.0),
            notes="Raw 400 BPM pulse must stay visible while hitech mode chooses normalized 200 BPM.",
        )

    if name == "silence":
        return FixtureAudio(
            name=name,
            samples=tuple(0.0 for _ in range(_sample_count())),
            sample_rate=SAMPLE_RATE,
            expectation=FixtureExpectation(
                primary_bpm=None,
                tolerance_bpm=None,
                stable_allowed=False,
                allowed_lock_states=("SEARCHING", "NOISE_ONLY"),
            ),
            notes="Zero-valued PCM must not lock.",
        )

    if name == "white_noise":
        samples = _white_noise(seed=170_170, amplitude=0.28)
        return FixtureAudio(
            name=name,
            samples=tuple(samples),
            sample_rate=SAMPLE_RATE,
            expectation=FixtureExpectation(
                primary_bpm=None,
                tolerance_bpm=None,
                stable_allowed=False,
                allowed_lock_states=("SEARCHING", "NOISE_ONLY", "UNSTABLE"),
            ),
            notes="Deterministic broadband noise must not become STABLE.",
        )

    if name == "pink_noise":
        samples = _pink_noise(seed=220_220, amplitude=0.32)
        return FixtureAudio(
            name=name,
            samples=tuple(samples),
            sample_rate=SAMPLE_RATE,
            expectation=FixtureExpectation(
                primary_bpm=None,
                tolerance_bpm=None,
                stable_allowed=False,
                allowed_lock_states=("SEARCHING", "NOISE_ONLY", "UNSTABLE"),
            ),
            notes="Deterministic low-frequency-biased noise must not become STABLE.",
        )

    if name == "severely_clipped_mic":
        samples = _pulse_samples(200.0, amplitude=1.8)
        clipped = [_clip(sample * 2.8, ceiling=0.78) for sample in samples]
        return FixtureAudio(
            name=name,
            samples=tuple(clipped),
            sample_rate=SAMPLE_RATE,
            expectation=FixtureExpectation(
                primary_bpm=None,
                tolerance_bpm=None,
                stable_allowed=False,
                required_candidate_bpms=(200.0,),
                allowed_lock_states=("CLIPPED_MIC", "UNSTABLE", "SEARCHING"),
            ),
            notes="Hard-limited microphone overload should flag clipping and suppress final lock.",
        )

    if name == "recoverable_clipped_mic":
        samples = _pulse_samples(200.0, amplitude=1.12)
        clipped = [_clip(sample * 1.55, ceiling=0.93) for sample in samples]
        return FixtureAudio(
            name=name,
            samples=tuple(clipped),
            sample_rate=SAMPLE_RATE,
            expectation=FixtureExpectation(
                primary_bpm=200.0,
                tolerance_bpm=2.0,
                stable_allowed=True,
                required_candidate_bpms=(200.0, 100.0),
                allowed_lock_states=("LOCKING", "STABLE"),
            ),
            notes="Moderate clipping should keep clipping visible but still allow recoverable tempo detection.",
        )

    if name == "breakdown_without_kick":
        samples = _pulse_samples(200.0, duration_sec=6.0)
        tail = _low_rumble(duration_sec=8.0, seed=0xBEEFDA, amplitude=0.08)
        return FixtureAudio(
            name=name,
            samples=tuple(samples + tail),
            sample_rate=SAMPLE_RATE,
            expectation=FixtureExpectation(
                primary_bpm=None,
                tolerance_bpm=None,
                stable_allowed=False,
                required_candidate_bpms=(200.0,),
                allowed_lock_states=("BREAKDOWN", "UNSTABLE", "LOCKING", "SEARCHING"),
            ),
            notes="A valid intro followed by no-kick breakdown must not finish as STABLE.",
        )

    if name == "dense_hitech_bassline":
        bpm = 200.0
        samples = _pulse_samples(bpm, amplitude=0.82)
        _add_rolling_bassline(samples, bpm=bpm)
        return FixtureAudio(
            name=name,
            samples=tuple(_normalize(samples, peak=0.92)),
            sample_rate=SAMPLE_RATE,
            expectation=FixtureExpectation(
                primary_bpm=200.0,
                tolerance_bpm=2.0,
                stable_allowed=True,
                required_candidate_bpms=(200.0,),
                allowed_lock_states=("STABLE",),
            ),
            notes="Dense simulated hitech bassline should not promote sub-pulses over the beat.",
        )

    if name == "unstable_club_simulation":
        return FixtureAudio(
            name=name,
            samples=tuple(_unstable_club_simulation()),
            sample_rate=SAMPLE_RATE,
            expectation=FixtureExpectation(
                primary_bpm=None,
                tolerance_bpm=None,
                stable_allowed=False,
                allowed_lock_states=("SEARCHING", "NOISE_ONLY", "UNSTABLE", "LOCKING"),
            ),
            notes="Tempo drift, dropouts, rumble, and broadband noise must keep uncertainty visible.",
        )

    raise ValueError(f"unknown fixture: {name}")


def write_wav(fixture: FixtureAudio, path: str) -> None:
    with wave.open(path, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(fixture.sample_rate)
        frames = bytearray()
        for sample in fixture.samples:
            int_sample = int(round(_clip(sample, ceiling=1.0) * 32767.0))
            frames.extend(int_sample.to_bytes(2, byteorder="little", signed=True))
        wav_file.writeframes(bytes(frames))


def _pulse_fixture(
    *,
    name: str,
    bpm: float,
    expected_primary: float,
    tolerance: float,
    required_candidates: tuple[float, ...],
    notes: str,
) -> FixtureAudio:
    return FixtureAudio(
        name=name,
        samples=tuple(_pulse_samples(bpm)),
        sample_rate=SAMPLE_RATE,
        expectation=FixtureExpectation(
            primary_bpm=expected_primary,
            tolerance_bpm=tolerance,
            stable_allowed=True,
            required_candidate_bpms=required_candidates,
            allowed_lock_states=("STABLE",),
        ),
        notes=notes,
    )


def _sample_count(duration_sec: float = DEFAULT_DURATION_SEC) -> int:
    return int(round(duration_sec * SAMPLE_RATE))


def _pulse_samples(
    bpm: float,
    *,
    duration_sec: float = DEFAULT_DURATION_SEC,
    amplitude: float = 0.9,
) -> list[float]:
    samples = [0.0 for _ in range(_sample_count(duration_sec))]
    beat_period = 60.0 / bpm
    beat = 0.0
    while beat < duration_sec:
        _add_kick(samples, int(round(beat * SAMPLE_RATE)), amplitude=amplitude)
        beat += beat_period
    return _normalize(samples, peak=0.88)


def _add_kick(samples: list[float], start: int, *, amplitude: float) -> None:
    length = int(0.055 * SAMPLE_RATE)
    transient_len = max(1, int(0.003 * SAMPLE_RATE))
    for offset in range(length):
        idx = start + offset
        if idx >= len(samples):
            return
        t = offset / SAMPLE_RATE
        envelope = math.exp(-72.0 * t)
        tone = math.sin(2.0 * math.pi * 72.0 * t)
        click = (1.0 - (offset / transient_len)) if offset < transient_len else 0.0
        samples[idx] += amplitude * ((0.72 * tone * envelope) + (0.55 * click * envelope))


def _add_rolling_bassline(samples: list[float], *, bpm: float) -> None:
    step = 60.0 / (bpm * 4.0)
    pulse_len = int(0.045 * SAMPLE_RATE)
    position = step / 2.0
    while position < DEFAULT_DURATION_SEC:
        start = int(round(position * SAMPLE_RATE))
        for offset in range(pulse_len):
            idx = start + offset
            if idx >= len(samples):
                break
            t = offset / SAMPLE_RATE
            envelope = math.exp(-38.0 * t)
            tone = math.sin(2.0 * math.pi * 98.0 * t)
            samples[idx] += 0.18 * tone * envelope
        position += step


def _white_noise(*, seed: int, amplitude: float) -> list[float]:
    rng = random.Random(seed)
    return [rng.uniform(-amplitude, amplitude) for _ in range(_sample_count())]


def _pink_noise(*, seed: int, amplitude: float) -> list[float]:
    rng = random.Random(seed)
    value = 0.0
    samples: list[float] = []
    for _ in range(_sample_count()):
        value = (0.985 * value) + (0.015 * rng.uniform(-1.0, 1.0))
        samples.append(value)
    return _normalize(samples, peak=amplitude)


def _low_rumble(*, duration_sec: float, seed: int, amplitude: float) -> list[float]:
    rng = random.Random(seed)
    count = _sample_count(duration_sec)
    samples = []
    for idx in range(count):
        t = idx / SAMPLE_RATE
        rumble = math.sin(2.0 * math.pi * 37.0 * t) * 0.7
        drift = math.sin(2.0 * math.pi * 0.21 * t) * 0.2
        samples.append(amplitude * (rumble + drift + rng.uniform(-0.08, 0.08)))
    return samples


def _unstable_club_simulation() -> list[float]:
    rng = random.Random(0x5150)
    samples = [0.0 for _ in range(_sample_count())]
    beat_time = 0.0
    while beat_time < DEFAULT_DURATION_SEC:
        bpm = rng.uniform(175.0, 245.0)
        beat_time += 60.0 / bpm
        if rng.random() < 0.22:
            continue
        _add_kick(samples, int(round(beat_time * SAMPLE_RATE)), amplitude=rng.uniform(0.25, 0.75))

    for idx in range(len(samples)):
        t = idx / SAMPLE_RATE
        rumble = 0.09 * math.sin(2.0 * math.pi * 43.0 * t)
        samples[idx] += rumble + rng.uniform(-0.32, 0.32)

    return _normalize(samples, peak=0.9)


def _normalize(samples: list[float], *, peak: float) -> list[float]:
    current_peak = max((abs(sample) for sample in samples), default=0.0)
    if current_peak == 0.0:
        return samples
    scale = peak / current_peak
    return [sample * scale for sample in samples]


def _clip(sample: float, *, ceiling: float) -> float:
    return max(-ceiling, min(ceiling, sample))
