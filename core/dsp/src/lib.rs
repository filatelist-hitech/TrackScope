//! Rust DSP core contract for hitech-bpm-radar.
//!
//! The current implementation intentionally starts with the public data model,
//! signal-quality gates, and hitech candidate normalization. Realtime onset
//! detection and candidate estimation will fill this boundary in Phase 2.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LockState {
    Searching,
    Locking,
    Stable,
    Unstable,
    Breakdown,
    ClippedMic,
    NoiseOnly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TempoRelation {
    Raw,
    Main,
    HalfTime,
    DoubleTime,
    NormalizedFromHalf,
    NormalizedFromDouble,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DspConfig {
    pub sample_rate: u32,
    pub target_bpm_min: f32,
    pub target_bpm_max: f32,
    pub broad_bpm_min: f32,
    pub broad_bpm_max: f32,
    pub analysis_window_seconds: f32,
    pub lock_min_seconds: f32,
    pub stable_min_seconds: f32,
}

impl Default for DspConfig {
    fn default() -> Self {
        Self {
            sample_rate: 48_000,
            target_bpm_min: 170.0,
            target_bpm_max: 230.0,
            broad_bpm_min: 80.0,
            broad_bpm_max: 460.0,
            analysis_window_seconds: 12.0,
            lock_min_seconds: 6.0,
            stable_min_seconds: 12.0,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct SignalQuality {
    pub input_level_dbfs: Option<f32>,
    pub peak_dbfs: Option<f32>,
    pub clipping: bool,
    pub clipped_frame_ratio: f32,
    pub noise_level: NoiseLevel,
    pub snr_estimate_db: Option<f32>,
    pub silence: bool,
    pub breakdown_likely: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NoiseLevel {
    Low,
    Medium,
    High,
    NoiseOnly,
    Unknown,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ConfidenceFactors {
    pub onset_clarity: f32,
    pub peak_prominence: f32,
    pub harmonic_support: f32,
    pub recent_stability: f32,
    pub signal_quality: f32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TempoCandidate {
    pub bpm: f32,
    pub relation: TempoRelation,
    pub score: f32,
    pub raw_score: f32,
    pub stability_score: f32,
    pub range_score: f32,
    pub source_bpm: Option<f32>,
    pub confidence_factors: ConfidenceFactors,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DspTiming {
    pub analysis_time_sec: f32,
    pub window_time_sec: f32,
    pub hop_time_sec: f32,
    pub first_lock_time_sec: Option<f32>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DspResult {
    pub primary_bpm: Option<f32>,
    pub confidence: f32,
    pub lock_state: LockState,
    pub signal_quality: SignalQuality,
    pub candidates: Vec<TempoCandidate>,
    pub timing: DspTiming,
}

#[derive(Debug, Clone)]
pub struct DspEngine {
    config: DspConfig,
    observed_samples: u64,
}

impl DspEngine {
    pub fn new(config: DspConfig) -> Self {
        Self {
            config,
            observed_samples: 0,
        }
    }

    pub fn config(&self) -> DspConfig {
        self.config
    }

    pub fn push_samples(&mut self, samples: &[f32], sample_rate: u32) {
        if sample_rate == 0 || samples.is_empty() {
            return;
        }
        let normalized_count = if sample_rate == self.config.sample_rate {
            samples.len() as u64
        } else {
            ((samples.len() as f64 * self.config.sample_rate as f64) / sample_rate as f64)
                .round()
                .max(0.0) as u64
        };
        self.observed_samples = self.observed_samples.saturating_add(normalized_count);
    }

    pub fn analyze_raw_candidates(&self, raw_candidates: &[(f32, f32)]) -> DspResult {
        analyze_candidates(raw_candidates, self.observed_seconds(), self.config)
    }

    pub fn reset(&mut self) {
        self.observed_samples = 0;
    }

    fn observed_seconds(&self) -> f32 {
        if self.config.sample_rate == 0 {
            0.0
        } else {
            self.observed_samples as f32 / self.config.sample_rate as f32
        }
    }
}

impl Default for DspEngine {
    fn default() -> Self {
        Self::new(DspConfig::default())
    }
}

pub fn analyze_candidates(
    raw_candidates: &[(f32, f32)],
    analysis_time_sec: f32,
    config: DspConfig,
) -> DspResult {
    let mut candidates = normalize_candidates(raw_candidates, config);
    let signal_quality = default_signal_quality(raw_candidates.is_empty());

    if raw_candidates.is_empty() {
        return empty_result(LockState::Searching, signal_quality, analysis_time_sec, config);
    }

    candidates.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let primary = candidates.first().cloned();
    let confidence = primary.as_ref().map(|item| item.score).unwrap_or(0.0).clamp(0.0, 1.0);
    let lock_state = if confidence >= 0.72 && analysis_time_sec >= config.stable_min_seconds {
        LockState::Stable
    } else if confidence >= 0.45 && analysis_time_sec >= config.lock_min_seconds {
        LockState::Locking
    } else {
        LockState::Unstable
    };
    let primary_bpm = if matches!(lock_state, LockState::Stable | LockState::Locking) {
        primary.as_ref().map(|item| round_3(item.bpm))
    } else {
        None
    };

    if let Some(primary) = primary {
        candidates.insert(
            0,
            TempoCandidate {
                relation: TempoRelation::Main,
                ..primary
            },
        );
    }

    DspResult {
        primary_bpm,
        confidence: round_3(confidence),
        lock_state,
        signal_quality,
        candidates,
        timing: DspTiming {
            analysis_time_sec: round_3(analysis_time_sec),
            window_time_sec: config.analysis_window_seconds,
            hop_time_sec: 0.0,
            first_lock_time_sec: primary_bpm.map(|_| analysis_time_sec.min(config.lock_min_seconds)),
        },
    }
}

pub fn normalize_candidates(raw_candidates: &[(f32, f32)], config: DspConfig) -> Vec<TempoCandidate> {
    let mut candidates = Vec::new();
    for &(bpm, score) in raw_candidates {
        if !bpm.is_finite() || !score.is_finite() || bpm <= 0.0 {
            continue;
        }
        let raw_score = score.clamp(0.0, 1.0);
        candidates.push(candidate(
            bpm,
            TempoRelation::Raw,
            raw_score,
            raw_score,
            None,
            config,
        ));

        if bpm < 130.0 {
            candidates.push(candidate(
                bpm * 2.0,
                TempoRelation::NormalizedFromHalf,
                (raw_score * 1.08).clamp(0.0, 1.0),
                raw_score,
                Some(bpm),
                config,
            ));
        }

        if bpm > 260.0 {
            candidates.push(candidate(
                bpm / 2.0,
                TempoRelation::NormalizedFromDouble,
                (raw_score * 1.08).clamp(0.0, 1.0),
                raw_score,
                Some(bpm),
                config,
            ));
        }
    }
    candidates
}

fn candidate(
    bpm: f32,
    relation: TempoRelation,
    evidence_score: f32,
    raw_score: f32,
    source_bpm: Option<f32>,
    config: DspConfig,
) -> TempoCandidate {
    let range_score = range_score(bpm, config);
    let score = (evidence_score * (0.58 + 0.42 * range_score)).clamp(0.0, 1.0);
    TempoCandidate {
        bpm: round_3(bpm),
        relation,
        score: round_3(score),
        raw_score: round_3(raw_score),
        stability_score: round_3(raw_score.clamp(0.0, 1.0)),
        range_score: round_3(range_score),
        source_bpm: source_bpm.map(round_3),
        confidence_factors: ConfidenceFactors {
            onset_clarity: round_3(raw_score),
            peak_prominence: round_3(evidence_score),
            harmonic_support: if source_bpm.is_some() { 0.82 } else { 0.68 },
            recent_stability: round_3(raw_score),
            signal_quality: 1.0,
        },
    }
}

fn range_score(bpm: f32, config: DspConfig) -> f32 {
    if (config.target_bpm_min..=config.target_bpm_max).contains(&bpm) {
        return 1.0;
    }
    if (130.0..config.target_bpm_min).contains(&bpm) {
        return 0.45 + 0.55 * ((bpm - 130.0) / (config.target_bpm_min - 130.0));
    }
    if bpm > config.target_bpm_max && bpm <= 260.0 {
        return 1.0 - 0.45 * ((bpm - config.target_bpm_max) / (260.0 - config.target_bpm_max));
    }
    if (config.broad_bpm_min..130.0).contains(&bpm)
        || (260.0..=config.broad_bpm_max).contains(&bpm)
    {
        return 0.26;
    }
    0.1
}

fn default_signal_quality(empty: bool) -> SignalQuality {
    SignalQuality {
        input_level_dbfs: None,
        peak_dbfs: None,
        clipping: false,
        clipped_frame_ratio: 0.0,
        noise_level: if empty { NoiseLevel::Unknown } else { NoiseLevel::Medium },
        snr_estimate_db: None,
        silence: empty,
        breakdown_likely: false,
    }
}

fn empty_result(
    lock_state: LockState,
    signal_quality: SignalQuality,
    analysis_time_sec: f32,
    config: DspConfig,
) -> DspResult {
    DspResult {
        primary_bpm: None,
        confidence: 0.0,
        lock_state,
        signal_quality,
        candidates: Vec::new(),
        timing: DspTiming {
            analysis_time_sec,
            window_time_sec: config.analysis_window_seconds,
            hop_time_sec: 0.0,
            first_lock_time_sec: None,
        },
    }
}

fn round_3(value: f32) -> f32 {
    (value * 1000.0).round() / 1000.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn half_time_candidate_is_preserved_and_normalized() {
        let result = analyze_candidates(&[(100.0, 0.9)], 12.0, DspConfig::default());

        assert_eq!(result.lock_state, LockState::Stable);
        assert_eq!(result.primary_bpm, Some(200.0));
        assert!(result
            .candidates
            .iter()
            .any(|candidate| candidate.bpm == 100.0 && candidate.relation == TempoRelation::Raw));
        assert!(result.candidates.iter().any(|candidate| {
            candidate.bpm == 200.0 && candidate.relation == TempoRelation::NormalizedFromHalf
        }));
    }

    #[test]
    fn double_time_candidate_is_preserved_and_normalized() {
        let result = analyze_candidates(&[(400.0, 0.9)], 12.0, DspConfig::default());

        assert_eq!(result.lock_state, LockState::Stable);
        assert_eq!(result.primary_bpm, Some(200.0));
        assert!(result
            .candidates
            .iter()
            .any(|candidate| candidate.bpm == 400.0 && candidate.relation == TempoRelation::Raw));
        assert!(result.candidates.iter().any(|candidate| {
            candidate.bpm == 200.0 && candidate.relation == TempoRelation::NormalizedFromDouble
        }));
    }

    #[test]
    fn empty_input_does_not_invent_a_bpm() {
        let result = analyze_candidates(&[], 0.0, DspConfig::default());

        assert_eq!(result.primary_bpm, None);
        assert_eq!(result.lock_state, LockState::Searching);
        assert!(result.signal_quality.silence);
    }
}
