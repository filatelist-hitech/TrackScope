"""Детерминированные DSP-примитивы для офлайн-анализа BPM."""

from .tempo import (
    DspResult,
    SignalQuality,
    TempoCandidate,
    analyze_pcm,
    result_to_dict,
)

__all__ = [
    "DspResult",
    "SignalQuality",
    "TempoCandidate",
    "analyze_pcm",
    "result_to_dict",
]
