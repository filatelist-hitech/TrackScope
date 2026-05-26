"""Синтетические PCM-фикстуры для детерминированных регрессионных тестов темпа."""

from __future__ import annotations

import math
import random
import wave
from pathlib import Path
from typing import Iterable


DEFAULT_SAMPLE_RATE = 8000


def generate_pulse_track(
    bpm: float,
    duration_sec: float = 12.0,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
    amplitude: float = 0.85,
) -> list[float]:
    """Генерировать моно импульсный трейн, похожий на kick, без кодирования BPM в метаданные."""

    total_samples = int(duration_sec * sample_rate)
    samples = [0.0] * total_samples
    beat_period = 60.0 / bpm
    pulse_len = max(1, int(0.055 * sample_rate))
    beat_index = 0

    while True:
        start = int(round(beat_index * beat_period * sample_rate))
        if start >= total_samples:
            break

        for offset in range(pulse_len):
            pos = start + offset
            if pos >= total_samples:
                break
            t = offset / sample_rate
            transient = math.exp(-t * 90.0)
            low_thump = math.sin(2.0 * math.pi * 72.0 * t) * math.exp(-t * 34.0)
            click = math.sin(2.0 * math.pi * 1800.0 * t) * math.exp(-t * 170.0)
            samples[pos] += amplitude * (0.72 * transient + 0.22 * low_thump + 0.06 * click)

        beat_index += 1

    return _limit(samples)


def generate_silence(duration_sec: float = 12.0, sample_rate: int = DEFAULT_SAMPLE_RATE) -> list[float]:
    return [0.0] * int(duration_sec * sample_rate)


def generate_noise(
    duration_sec: float = 12.0,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
    amplitude: float = 0.18,
    seed: int = 12345,
) -> list[float]:
    rng = random.Random(seed)
    return [rng.uniform(-amplitude, amplitude) for _ in range(int(duration_sec * sample_rate))]


def generate_pink_noise(
    duration_sec: float = 12.0,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
    amplitude: float = 0.25,
    seed: int = 220220,
) -> list[float]:
    rng = random.Random(seed)
    value = 0.0
    samples: list[float] = []
    for _ in range(int(duration_sec * sample_rate)):
        value = (0.985 * value) + (0.015 * rng.uniform(-1.0, 1.0))
        samples.append(value)
    return _scale(samples, amplitude)


def generate_clipped_pulse_track(
    bpm: float,
    duration_sec: float = 12.0,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
) -> list[float]:
    samples = generate_pulse_track(bpm, duration_sec, sample_rate, amplitude=1.8)
    return [max(-0.78, min(0.78, sample * 2.8)) for sample in samples]


def generate_recoverable_clipped_pulse_track(
    bpm: float,
    duration_sec: float = 12.0,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
) -> list[float]:
    samples = generate_pulse_track(bpm, duration_sec, sample_rate, amplitude=1.12)
    return [max(-0.93, min(0.93, sample * 1.55)) for sample in samples]


def generate_breakdown_track(
    bpm: float,
    duration_sec: float = 12.0,
    active_sec: float = 7.0,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
) -> list[float]:
    active = generate_pulse_track(bpm, active_sec, sample_rate)
    silent = generate_silence(max(0.0, duration_sec - active_sec), sample_rate)
    return active + silent


def generate_dense_hitech_bassline(
    bpm: float = 200.0,
    duration_sec: float = 12.0,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
) -> list[float]:
    samples = generate_pulse_track(bpm, duration_sec, sample_rate, amplitude=0.82)
    step = 60.0 / (bpm * 4.0)
    pulse_len = max(1, int(0.045 * sample_rate))
    position = step / 2.0
    while position < duration_sec:
        start = int(round(position * sample_rate))
        for offset in range(pulse_len):
            idx = start + offset
            if idx >= len(samples):
                break
            t = offset / sample_rate
            envelope = math.exp(-38.0 * t)
            tone = math.sin(2.0 * math.pi * 98.0 * t)
            samples[idx] += 0.18 * tone * envelope
        position += step
    return _scale(samples, 0.92)


def generate_unstable_club_simulation(
    duration_sec: float = 12.0,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
    seed: int = 0x5150,
) -> list[float]:
    rng = random.Random(seed)
    samples = [0.0] * int(duration_sec * sample_rate)
    beat_time = 0.0
    while beat_time < duration_sec:
        bpm = rng.uniform(175.0, 245.0)
        beat_time += 60.0 / bpm
        if rng.random() < 0.22:
            continue
        start = int(round(beat_time * sample_rate))
        pulse_len = max(1, int(0.055 * sample_rate))
        amplitude = rng.uniform(0.25, 0.75)
        for offset in range(pulse_len):
            pos = start + offset
            if pos >= len(samples):
                break
            t = offset / sample_rate
            transient = math.exp(-t * 90.0)
            low_thump = math.sin(2.0 * math.pi * 72.0 * t) * math.exp(-t * 34.0)
            samples[pos] += amplitude * (0.72 * transient + 0.22 * low_thump)

    for idx in range(len(samples)):
        t = idx / sample_rate
        samples[idx] += 0.09 * math.sin(2.0 * math.pi * 43.0 * t)
        samples[idx] += rng.uniform(-0.32, 0.32)
    return _scale(samples, 0.9)


def write_wav(path: str | Path, samples: Iterable[float], sample_rate: int = DEFAULT_SAMPLE_RATE) -> None:
    """Записать моно 16-битный PCM WAV для офлайн-проверки и CLI-фикстур."""

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = bytearray()
    for sample in samples:
        value = int(max(-1.0, min(1.0, sample)) * 32767.0)
        pcm.extend(value.to_bytes(2, byteorder="little", signed=True))

    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(bytes(pcm))


def read_wav(path: str | Path) -> tuple[list[float], int]:
    """Прочитать моно/стерео 16-битный PCM WAV в нормализованные моно-флоаты."""

    with wave.open(str(path), "rb") as handle:
        channels = handle.getnchannels()
        sample_width = handle.getsampwidth()
        sample_rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())

    if sample_width != 2:
        raise ValueError(f"only 16-bit PCM WAV is supported, got sample width {sample_width}")

    values: list[float] = []
    stride = channels * sample_width
    for idx in range(0, len(frames), stride):
        total = 0.0
        for channel in range(channels):
            offset = idx + channel * sample_width
            raw = int.from_bytes(frames[offset : offset + sample_width], byteorder="little", signed=True)
            total += raw / 32768.0
        values.append(total / channels)
    return values, sample_rate


def _limit(samples: list[float]) -> list[float]:
    peak = max((abs(sample) for sample in samples), default=0.0)
    if peak <= 1.0:
        return samples
    scale = 0.98 / peak
    return [sample * scale for sample in samples]


def _scale(samples: list[float], peak: float) -> list[float]:
    current_peak = max((abs(sample) for sample in samples), default=0.0)
    if current_peak <= 0.0:
        return samples
    scale = peak / current_peak
    return [sample * scale for sample in samples]
