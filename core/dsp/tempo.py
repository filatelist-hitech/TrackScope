"""Simple deterministic offline tempo detector for hitech BPM fixtures."""

from __future__ import annotations

from dataclasses import asdict, dataclass, replace
import json
import math
import statistics
from typing import Any


LockState = str
TempoRelation = str


@dataclass(frozen=True)
class SignalQuality:
    input_level_dbfs: float | None
    peak_dbfs: float | None
    clipping: bool
    clipped_frame_ratio: float
    noise_level: str
    snr_estimate_db: float | None
    silence: bool
    breakdown_likely: bool


@dataclass(frozen=True)
class TempoCandidate:
    bpm: float
    relation: TempoRelation
    score: float
    raw_score: float
    stability_score: float
    range_score: float
    source_bpm: float | None
    confidence_factors: dict[str, float]


@dataclass(frozen=True)
class DspTiming:
    analysis_time_sec: float
    window_time_sec: float
    hop_time_sec: float
    first_lock_time_sec: float | None


@dataclass(frozen=True)
class DspDebug:
    onset_rate_hz: float
    onset_strength: float
    tempo_peak_prominence: float
    harmonic_ambiguity: float
    stability_score: float
    warnings: list[str]


@dataclass(frozen=True)
class DspResult:
    primary_bpm: float | None
    confidence: float
    lock_state: LockState
    signal_quality: SignalQuality
    candidates: list[TempoCandidate]
    timing: DspTiming
    debug: DspDebug


def analyze_pcm(
    samples: list[float],
    sample_rate: int,
    *,
    min_bpm: float = 80.0,
    max_bpm: float = 460.0,
    hitech_min_bpm: float = 170.0,
    hitech_max_bpm: float = 230.0,
) -> DspResult:
    """Analyze normalized mono PCM samples and return the DSP contract."""

    duration_sec = len(samples) / sample_rate if sample_rate else 0.0
    signal = _measure_signal(samples, sample_rate)
    timing = DspTiming(
        analysis_time_sec=round(duration_sec, 3),
        window_time_sec=round(duration_sec, 3),
        hop_time_sec=0.0025,
        first_lock_time_sec=None,
    )

    if not samples or sample_rate <= 0 or signal.silence:
        return _empty_result("SEARCHING", signal, timing, ["silence"])

    envelope, hop_sec = _onset_envelope(samples, sample_rate)
    if not envelope or max(envelope, default=0.0) <= 0.0:
        return _empty_result("NOISE_ONLY", signal, timing, ["no usable onset envelope"])
    if _tail_onset_breakdown(envelope, hop_sec):
        signal = replace(signal, breakdown_likely=True)

    raw_peaks = _tempo_autocorrelation(envelope, hop_sec, min_bpm, max_bpm)
    candidates = _build_candidates(raw_peaks, hitech_min_bpm, hitech_max_bpm)
    candidates = _dedupe_candidates(candidates)
    candidates = _mark_primary_candidate(candidates, hitech_min_bpm, hitech_max_bpm)

    onset_strength = sum(envelope) / len(envelope)
    prominence = _peak_prominence(raw_peaks)
    harmonic_ambiguity = _harmonic_ambiguity(candidates)
    periodicity = raw_peaks[0]["score"] if raw_peaks else 0.0
    warnings: list[str] = []

    if signal.clipping:
        warnings.append("clipped microphone input")
    if signal.breakdown_likely:
        warnings.append("recent no-kick breakdown")

    if not candidates:
        return _empty_result("NOISE_ONLY", signal, timing, ["no tempo candidates"])

    primary = candidates[0]
    signal_factor = _signal_factor(signal)
    duration_factor = _clamp(duration_sec / 6.0, 0.0, 1.0)
    clarity_factor = _clamp((periodicity - 0.08) / 0.42, 0.0, 1.0)
    prominence_factor = _clamp(prominence / 0.45, 0.0, 1.0)
    confidence = primary.score * (
        0.38 + 0.22 * signal_factor + 0.18 * duration_factor + 0.12 * clarity_factor + 0.10 * prominence_factor
    )
    confidence = _clamp(confidence, 0.0, 1.0)

    lock_state = "LOCKING"
    primary_bpm: float | None = round(primary.bpm, 1)

    if signal.clipping:
        lock_state = "CLIPPED_MIC"
        confidence = min(confidence, 0.34)
        primary_bpm = None
    elif signal.breakdown_likely:
        lock_state = "BREAKDOWN"
        confidence = min(confidence, 0.42)
        primary_bpm = None
    elif periodicity < 0.24 or prominence < 0.10 or onset_strength < 0.002:
        lock_state = "NOISE_ONLY"
        confidence = min(confidence, 0.28)
        primary_bpm = None
        warnings.append("weak periodic onset structure")
    elif confidence >= 0.72 and duration_sec >= 6.0:
        lock_state = "STABLE"
        timing = DspTiming(
            analysis_time_sec=round(duration_sec, 3),
            window_time_sec=round(duration_sec, 3),
            hop_time_sec=hop_sec,
            first_lock_time_sec=min(6.0, round(duration_sec, 3)),
        )
    elif confidence < 0.45:
        lock_state = "UNSTABLE"

    debug = DspDebug(
        onset_rate_hz=round(_onset_rate(envelope, hop_sec), 3),
        onset_strength=round(onset_strength, 6),
        tempo_peak_prominence=round(prominence, 6),
        harmonic_ambiguity=round(harmonic_ambiguity, 6),
        stability_score=round(primary.stability_score, 6),
        warnings=warnings,
    )
    return DspResult(
        primary_bpm=primary_bpm,
        confidence=round(confidence, 3),
        lock_state=lock_state,
        signal_quality=signal,
        candidates=candidates[:10],
        timing=timing,
        debug=debug,
    )


def result_to_dict(result: DspResult) -> dict[str, Any]:
    return asdict(result)


def result_to_json(result: DspResult) -> str:
    return json.dumps(result_to_dict(result), indent=2, sort_keys=True)


def _measure_signal(samples: list[float], sample_rate: int) -> SignalQuality:
    count = len(samples)
    peak = max((abs(sample) for sample in samples), default=0.0)
    rms = math.sqrt(sum(sample * sample for sample in samples) / count) if count else 0.0
    full_scale_ratio = sum(1 for sample in samples if abs(sample) >= 0.985) / count if count else 0.0
    flat_top_sample_ratio = sum(1 for sample in samples if peak > 0.7 and abs(sample) >= peak * 0.995) / count if count else 0.0
    flat_top_frame_ratio = _flat_top_frame_ratio(samples, sample_rate, peak)
    clipping = full_scale_ratio > 0.01 or flat_top_sample_ratio > 0.015
    if full_scale_ratio > 0.01:
        clipped_ratio = max(full_scale_ratio, flat_top_frame_ratio)
    elif flat_top_sample_ratio > 0.015:
        clipped_ratio = max(flat_top_sample_ratio, flat_top_frame_ratio)
    else:
        clipped_ratio = max(full_scale_ratio, flat_top_sample_ratio)
    silence = rms < 0.0002 or peak < 0.001
    tail = samples[int(max(0, count - sample_rate * 3)) :]
    tail_rms = math.sqrt(sum(sample * sample for sample in tail) / len(tail)) if tail else 0.0
    breakdown_likely = not silence and count >= sample_rate * 6 and tail_rms < max(0.004, rms * 0.18)
    noise_level = "unknown"
    if silence:
        noise_level = "low"
    elif rms > 0.14 and peak < 0.6:
        noise_level = "noise_only"
    elif rms < 0.035:
        noise_level = "low"
    elif rms < 0.18:
        noise_level = "medium"
    else:
        noise_level = "high"
    return SignalQuality(
        input_level_dbfs=_dbfs(rms),
        peak_dbfs=_dbfs(peak),
        clipping=clipping,
        clipped_frame_ratio=round(clipped_ratio, 6),
        noise_level=noise_level,
        snr_estimate_db=None,
        silence=silence,
        breakdown_likely=breakdown_likely,
    )


def _onset_envelope(samples: list[float], sample_rate: int) -> tuple[list[float], float]:
    hop_size = max(1, int(sample_rate * 0.0025))
    frame_size = max(hop_size, int(sample_rate * 0.010))
    frame_rms: list[float] = []
    for start in range(0, max(0, len(samples) - frame_size), hop_size):
        frame = samples[start : start + frame_size]
        rms = math.sqrt(sum(sample * sample for sample in frame) / len(frame))
        frame_rms.append(rms)

    if len(frame_rms) < 4:
        return [], hop_size / sample_rate

    flux: list[float] = [0.0]
    for idx in range(1, len(frame_rms)):
        flux.append(max(0.0, frame_rms[idx] - frame_rms[idx - 1]))

    floor = statistics.median(flux)
    envelope = [max(0.0, value - floor) for value in flux]
    peak = max(envelope, default=0.0)
    if peak <= 0.0:
        return envelope, hop_size / sample_rate
    return [value / peak for value in envelope], hop_size / sample_rate


def _flat_top_frame_ratio(samples: list[float], sample_rate: int, peak: float) -> float:
    if not samples or peak < 0.7:
        return 0.0
    frame_size = max(1, int(sample_rate * 0.010))
    frames = 0
    clipped_frames = 0
    for start in range(0, len(samples), frame_size):
        frame = samples[start : start + frame_size]
        if not frame:
            continue
        frames += 1
        if any(abs(sample) >= peak * 0.995 for sample in frame):
            clipped_frames += 1
    return clipped_frames / frames if frames else 0.0


def _tail_onset_breakdown(envelope: list[float], hop_sec: float) -> bool:
    tail_frames = max(1, int(3.0 / hop_sec))
    if len(envelope) < tail_frames * 2:
        return False
    tail = envelope[-tail_frames:]
    history = envelope[:-tail_frames]
    if not history:
        return False
    history_mean = sum(history) / len(history)
    tail_mean = sum(tail) / len(tail)
    history_peak = max(history)
    tail_peak = max(tail)
    return history_peak > 0.45 and tail_peak < 0.20 and tail_mean < max(0.003, history_mean * 0.95)


def _tempo_autocorrelation(
    envelope: list[float],
    hop_sec: float,
    min_bpm: float,
    max_bpm: float,
) -> list[dict[str, float]]:
    min_lag = max(1, int(math.floor(60.0 / max_bpm / hop_sec)))
    max_lag = min(len(envelope) - 2, int(math.ceil(60.0 / min_bpm / hop_sec)))
    scores: list[tuple[int, float]] = []
    for lag in range(min_lag, max_lag + 1):
        current_energy = 0.0
        shifted_energy = 0.0
        numerator = 0.0
        for idx in range(lag, len(envelope)):
            current = envelope[idx]
            shifted = envelope[idx - lag]
            numerator += current * shifted
            current_energy += current * current
            shifted_energy += shifted * shifted
        denom = math.sqrt(current_energy * shifted_energy)
        score = numerator / denom if denom > 0.0 else 0.0
        scores.append((lag, score))

    peaks: list[dict[str, float]] = []
    for idx in range(1, len(scores) - 1):
        lag, score = scores[idx]
        if score >= scores[idx - 1][1] and score >= scores[idx + 1][1]:
            bpm = 60.0 / (lag * hop_sec)
            peaks.append({"bpm": bpm, "score": score, "lag": float(lag)})

    peaks.sort(key=lambda item: item["score"], reverse=True)
    return peaks[:16]


def _build_candidates(
    raw_peaks: list[dict[str, float]],
    hitech_min_bpm: float,
    hitech_max_bpm: float,
) -> list[TempoCandidate]:
    candidates: list[TempoCandidate] = []
    for peak in raw_peaks:
        bpm = peak["bpm"]
        raw_score = _clamp(peak["score"], 0.0, 1.0)
        candidates.append(_candidate(bpm, "raw", raw_score, raw_score, None, hitech_min_bpm, hitech_max_bpm))

        if bpm < 130.0:
            normalized = bpm * 2.0
            candidates.append(
                _candidate(
                    normalized,
                    "normalized_from_half",
                    raw_score * 1.08,
                    raw_score,
                    bpm,
                    hitech_min_bpm,
                    hitech_max_bpm,
                )
            )
        if bpm > 260.0:
            normalized = bpm / 2.0
            candidates.append(
                _candidate(
                    normalized,
                    "normalized_from_double",
                    raw_score * 1.08,
                    raw_score,
                    bpm,
                    hitech_min_bpm,
                    hitech_max_bpm,
                )
            )

    candidates.sort(key=lambda item: item.score, reverse=True)
    if candidates:
        primary = candidates[0]
        candidates.append(
            _candidate(
                primary.bpm / 2.0,
                "half_time",
                primary.raw_score * 0.62,
                primary.raw_score,
                primary.bpm,
                hitech_min_bpm,
                hitech_max_bpm,
            )
        )
        candidates.append(
            _candidate(
                primary.bpm * 2.0,
                "double_time",
                primary.raw_score * 0.48,
                primary.raw_score,
                primary.bpm,
                hitech_min_bpm,
                hitech_max_bpm,
            )
        )
    return candidates


def _candidate(
    bpm: float,
    relation: TempoRelation,
    evidence_score: float,
    raw_score: float,
    source_bpm: float | None,
    hitech_min_bpm: float,
    hitech_max_bpm: float,
) -> TempoCandidate:
    range_score = _range_score(bpm, hitech_min_bpm, hitech_max_bpm)
    stability_score = _clamp(raw_score, 0.0, 1.0)
    score = _clamp(evidence_score * (0.58 + 0.42 * range_score), 0.0, 1.0)
    factors = {
        "onset_clarity": round(_clamp(raw_score, 0.0, 1.0), 6),
        "peak_prominence": round(_clamp(evidence_score, 0.0, 1.0), 6),
        "harmonic_support": 0.82 if source_bpm else 0.68,
        "recent_stability": round(stability_score, 6),
        "signal_quality": 1.0,
    }
    return TempoCandidate(
        bpm=round(bpm, 3),
        relation=relation,
        score=round(score, 6),
        raw_score=round(raw_score, 6),
        stability_score=round(stability_score, 6),
        range_score=round(range_score, 6),
        source_bpm=round(source_bpm, 3) if source_bpm is not None else None,
        confidence_factors=factors,
    )


def _dedupe_candidates(candidates: list[TempoCandidate]) -> list[TempoCandidate]:
    ordered = sorted(candidates, key=lambda item: item.score, reverse=True)
    deduped: list[TempoCandidate] = []
    seen: set[tuple[int, str]] = set()
    for candidate in ordered:
        key = (round(candidate.bpm), candidate.relation)
        if key in seen:
            continue
        seen.add(key)
        deduped.append(candidate)
    return deduped


def _mark_primary_candidate(
    candidates: list[TempoCandidate],
    hitech_min_bpm: float,
    hitech_max_bpm: float,
) -> list[TempoCandidate]:
    if not candidates:
        return []
    primary = candidates[0]
    main = _candidate(
        primary.bpm,
        "main",
        primary.score,
        primary.raw_score,
        primary.source_bpm,
        hitech_min_bpm,
        hitech_max_bpm,
    )
    main = TempoCandidate(
        bpm=main.bpm,
        relation=main.relation,
        score=primary.score,
        raw_score=primary.raw_score,
        stability_score=primary.stability_score,
        range_score=primary.range_score,
        source_bpm=primary.source_bpm,
        confidence_factors=primary.confidence_factors,
    )
    return [main, *candidates]


def _range_score(bpm: float, hitech_min_bpm: float, hitech_max_bpm: float) -> float:
    if hitech_min_bpm <= bpm <= hitech_max_bpm:
        return 1.0
    if 130.0 <= bpm < hitech_min_bpm:
        return 0.45 + 0.55 * ((bpm - 130.0) / (hitech_min_bpm - 130.0))
    if hitech_max_bpm < bpm <= 260.0:
        return 1.0 - 0.45 * ((bpm - hitech_max_bpm) / (260.0 - hitech_max_bpm))
    if 80.0 <= bpm < 130.0 or 260.0 < bpm <= 460.0:
        return 0.26
    return 0.1


def _peak_prominence(raw_peaks: list[dict[str, float]]) -> float:
    if not raw_peaks:
        return 0.0
    scores = [peak["score"] for peak in raw_peaks]
    median = statistics.median(scores)
    return _clamp(scores[0] - median, 0.0, 1.0)


def _harmonic_ambiguity(candidates: list[TempoCandidate]) -> float:
    if len(candidates) < 2:
        return 0.0
    return _clamp(candidates[1].score / max(candidates[0].score, 0.0001), 0.0, 1.0)


def _onset_rate(envelope: list[float], hop_sec: float) -> float:
    threshold = max(0.15, statistics.mean(envelope) + statistics.pstdev(envelope))
    peaks = 0
    for idx in range(1, len(envelope) - 1):
        if envelope[idx] > threshold and envelope[idx] >= envelope[idx - 1] and envelope[idx] >= envelope[idx + 1]:
            peaks += 1
    duration = len(envelope) * hop_sec
    return peaks / duration if duration > 0.0 else 0.0


def _signal_factor(signal: SignalQuality) -> float:
    if signal.silence or signal.clipping or signal.breakdown_likely:
        return 0.0
    if signal.noise_level == "noise_only":
        return 0.4
    if signal.noise_level == "high":
        return 0.72
    return 1.0


def _empty_result(lock_state: LockState, signal: SignalQuality, timing: DspTiming, warnings: list[str]) -> DspResult:
    return DspResult(
        primary_bpm=None,
        confidence=0.0,
        lock_state=lock_state,
        signal_quality=signal,
        candidates=[],
        timing=timing,
        debug=DspDebug(
            onset_rate_hz=0.0,
            onset_strength=0.0,
            tempo_peak_prominence=0.0,
            harmonic_ambiguity=0.0,
            stability_score=0.0,
            warnings=warnings,
        ),
    )


def _dbfs(value: float) -> float | None:
    if value <= 0.0:
        return None
    return round(20.0 * math.log10(min(value, 1.0)), 3)


def _clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))
