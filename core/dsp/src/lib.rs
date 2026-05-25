//! Rust DSP core contract for hitech-bpm-radar.
//!
//! The current implementation intentionally starts with the public data model,
//! signal-quality gates, and hitech candidate normalization. Realtime onset
//! detection and candidate estimation will fill this boundary in Phase 2.

use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum LockState {
    Searching,
    Locking,
    Stable,
    Unstable,
    Breakdown,
    ClippedMic,
    NoiseOnly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "snake_case")]
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

#[derive(Debug, Clone, PartialEq, Serialize)]
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum NoiseLevel {
    Low,
    Medium,
    High,
    NoiseOnly,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ConfidenceFactors {
    pub onset_clarity: f32,
    pub peak_prominence: f32,
    pub harmonic_support: f32,
    pub recent_stability: f32,
    pub signal_quality: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
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

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DspTiming {
    pub analysis_time_sec: f32,
    pub window_time_sec: f32,
    pub hop_time_sec: f32,
    pub first_lock_time_sec: Option<f32>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
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
    samples: Vec<f32>,
}

impl DspEngine {
    pub fn new(config: DspConfig) -> Self {
        Self {
            config,
            observed_samples: 0,
            samples: Vec::new(),
        }
    }

    pub fn config(&self) -> DspConfig {
        self.config
    }

    pub fn push_samples(&mut self, samples: &[f32], sample_rate: u32) {
        if sample_rate == 0 || samples.is_empty() {
            return;
        }

        let normalized = if sample_rate == self.config.sample_rate {
            samples.to_vec()
        } else {
            resample_linear(samples, sample_rate, self.config.sample_rate)
        };

        self.observed_samples = self
            .observed_samples
            .saturating_add(normalized.len() as u64);
        self.samples.extend(normalized);

        let max_samples = (self.config.analysis_window_seconds.max(0.0)
            * self.config.sample_rate as f32)
            .round() as usize;
        if max_samples > 0 && self.samples.len() > max_samples {
            let drain_count = self.samples.len() - max_samples;
            self.samples.drain(0..drain_count);
        }
    }

    pub fn analyze_raw_candidates(&self, raw_candidates: &[(f32, f32)]) -> DspResult {
        analyze_candidates(raw_candidates, self.observed_seconds(), self.config)
    }

    pub fn analyze(&self) -> DspResult {
        analyze_pcm(&self.samples, self.config.sample_rate, self.config)
    }

    pub fn reset(&mut self) {
        self.observed_samples = 0;
        self.samples.clear();
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

#[derive(Debug, Clone, Copy)]
struct RawPeak {
    bpm: f32,
    score: f32,
}

pub fn analyze_pcm(samples: &[f32], sample_rate: u32, config: DspConfig) -> DspResult {
    let duration_sec = if sample_rate == 0 {
        0.0
    } else {
        samples.len() as f32 / sample_rate as f32
    };
    let mut signal_quality = measure_signal(samples, sample_rate);
    let mut timing = DspTiming {
        analysis_time_sec: round_3(duration_sec),
        window_time_sec: round_3(duration_sec),
        hop_time_sec: 0.0025,
        first_lock_time_sec: None,
    };

    if samples.is_empty() || sample_rate == 0 || signal_quality.silence {
        return empty_result(LockState::Searching, signal_quality, duration_sec, config);
    }

    let (envelope, hop_sec) = onset_envelope(samples, sample_rate);
    if envelope.is_empty() || envelope.iter().copied().fold(0.0, f32::max) <= 0.0 {
        return empty_result(LockState::NoiseOnly, signal_quality, duration_sec, config);
    }
    timing.hop_time_sec = hop_sec;

    if tail_onset_breakdown(&envelope, hop_sec) {
        signal_quality.breakdown_likely = true;
    }

    let raw_peaks = tempo_autocorrelation(
        &envelope,
        hop_sec,
        config.broad_bpm_min,
        config.broad_bpm_max,
    );
    let mut candidates = build_candidates(&raw_peaks, config);
    candidates = dedupe_candidates(candidates);
    candidates = mark_primary_candidate(candidates, config);
    let signal_factor = signal_factor(&signal_quality);
    candidates = apply_signal_quality_factor(candidates, signal_factor);

    let onset_strength = envelope.iter().sum::<f32>() / envelope.len() as f32;
    let prominence = peak_prominence(&raw_peaks);
    let harmonic_ambiguity = harmonic_ambiguity(&candidates);
    let periodicity = raw_peaks.first().map(|peak| peak.score).unwrap_or(0.0);

    if candidates.is_empty() {
        return empty_result(LockState::NoiseOnly, signal_quality, duration_sec, config);
    }

    let primary = candidates[0].clone();
    let duration_factor = (duration_sec / 6.0).clamp(0.0, 1.0);
    let clarity_factor = ((periodicity - 0.08) / 0.42).clamp(0.0, 1.0);
    let prominence_factor = (prominence / 0.45).clamp(0.0, 1.0);
    let ambiguity_factor = 1.0 - (0.16 * harmonic_ambiguity);
    let mut confidence = primary.score
        * (0.38
            + 0.22 * signal_factor
            + 0.18 * duration_factor
            + 0.12 * clarity_factor
            + 0.10 * prominence_factor)
        * ambiguity_factor;
    confidence = confidence.clamp(0.0, 1.0);

    let mut lock_state = LockState::Locking;
    let mut primary_bpm = Some(round_1(primary.bpm));
    let severe_clipping = severe_clipping(&signal_quality);

    if severe_clipping {
        lock_state = LockState::ClippedMic;
        confidence = confidence.min(0.34);
        primary_bpm = None;
    } else if signal_quality.clipping {
        confidence = confidence.min(0.69);
        if matches!(lock_state, LockState::Stable) {
            lock_state = LockState::Locking;
        }
    } else if signal_quality.breakdown_likely {
        lock_state = LockState::Breakdown;
        confidence = confidence.min(0.42);
        primary_bpm = None;
    } else if periodicity < 0.24 || prominence < 0.10 || onset_strength < 0.002 {
        lock_state = LockState::NoiseOnly;
        confidence = confidence.min(0.28);
        primary_bpm = None;
    } else if confidence >= 0.72 && duration_sec >= config.lock_min_seconds {
        lock_state = LockState::Stable;
        timing.first_lock_time_sec = Some(config.lock_min_seconds.min(round_3(duration_sec)));
    } else if confidence < 0.45 {
        lock_state = LockState::Unstable;
    }

    candidates.truncate(10);
    DspResult {
        primary_bpm,
        confidence: round_3(confidence),
        lock_state,
        signal_quality,
        candidates,
        timing,
    }
}

pub fn analyze_candidates(
    raw_candidates: &[(f32, f32)],
    analysis_time_sec: f32,
    config: DspConfig,
) -> DspResult {
    let raw_peaks: Vec<RawPeak> = raw_candidates
        .iter()
        .filter_map(|&(bpm, score)| {
            if bpm.is_finite() && score.is_finite() && bpm > 0.0 {
                Some(RawPeak {
                    bpm,
                    score: score.clamp(0.0, 1.0),
                })
            } else {
                None
            }
        })
        .collect();
    let mut candidates = build_candidates(&raw_peaks, config);
    candidates = dedupe_candidates(candidates);
    candidates = mark_primary_candidate(candidates, config);
    let signal_quality = default_signal_quality(raw_candidates.is_empty());

    if raw_candidates.is_empty() {
        return empty_result(LockState::Searching, signal_quality, analysis_time_sec, config);
    }

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
    let raw_peaks: Vec<RawPeak> = raw_candidates
        .iter()
        .filter_map(|&(bpm, score)| {
            if bpm.is_finite() && score.is_finite() && bpm > 0.0 {
                Some(RawPeak {
                    bpm,
                    score: score.clamp(0.0, 1.0),
                })
            } else {
                None
            }
        })
        .collect();
    mark_primary_candidate(dedupe_candidates(build_candidates(&raw_peaks, config)), config)
}

fn build_candidates(raw_peaks: &[RawPeak], config: DspConfig) -> Vec<TempoCandidate> {
    let mut candidates = Vec::new();
    for peak in raw_peaks {
        let raw_score = peak.score.clamp(0.0, 1.0);
        candidates.push(candidate(
            peak.bpm,
            TempoRelation::Raw,
            raw_score,
            raw_score,
            None,
            config,
        ));

        if peak.bpm < 130.0 {
            candidates.push(candidate(
                peak.bpm * 2.0,
                TempoRelation::NormalizedFromHalf,
                (raw_score * 0.98).clamp(0.0, 1.0),
                raw_score,
                Some(peak.bpm),
                config,
            ));
        }

        if peak.bpm > 260.0 {
            candidates.push(candidate(
                peak.bpm / 2.0,
                TempoRelation::NormalizedFromDouble,
                (raw_score * 0.98).clamp(0.0, 1.0),
                raw_score,
                Some(peak.bpm),
                config,
            ));
        }
    }

    candidates.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    if let Some(primary) = candidates.first().cloned() {
        candidates.push(candidate(
            primary.bpm / 2.0,
            TempoRelation::HalfTime,
            primary.raw_score * 0.62,
            primary.raw_score,
            Some(primary.bpm),
            config,
        ));
        candidates.push(candidate(
            primary.bpm * 2.0,
            TempoRelation::DoubleTime,
            primary.raw_score * 0.48,
            primary.raw_score,
            Some(primary.bpm),
            config,
        ));
    }

    candidates
}

fn dedupe_candidates(mut candidates: Vec<TempoCandidate>) -> Vec<TempoCandidate> {
    candidates.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let mut deduped = Vec::new();
    let mut seen: Vec<(i32, TempoRelation)> = Vec::new();
    for candidate in candidates {
        let key = (candidate.bpm.round() as i32, candidate.relation);
        if seen.contains(&key) {
            continue;
        }
        seen.push(key);
        deduped.push(candidate);
    }
    deduped
}

fn mark_primary_candidate(candidates: Vec<TempoCandidate>, config: DspConfig) -> Vec<TempoCandidate> {
    let Some(primary) = candidates.first() else {
        return Vec::new();
    };
    let mut main = candidate(
        primary.bpm,
        TempoRelation::Main,
        primary.score,
        primary.raw_score,
        primary.source_bpm,
        config,
    );
    main.score = primary.score;
    main.raw_score = primary.raw_score;
    main.stability_score = primary.stability_score;
    main.range_score = primary.range_score;
    main.confidence_factors = primary.confidence_factors.clone();

    let mut marked = Vec::with_capacity(candidates.len() + 1);
    marked.push(main);
    marked.extend(candidates);
    marked
}

fn apply_signal_quality_factor(
    mut candidates: Vec<TempoCandidate>,
    signal_factor_value: f32,
) -> Vec<TempoCandidate> {
    for candidate in &mut candidates {
        candidate.confidence_factors.signal_quality = round_6(signal_factor_value);
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
        score: round_6(score),
        raw_score: round_6(raw_score),
        stability_score: round_6(raw_score.clamp(0.0, 1.0)),
        range_score: round_6(range_score),
        source_bpm: source_bpm.map(round_3),
        confidence_factors: ConfidenceFactors {
            onset_clarity: round_6(raw_score),
            peak_prominence: round_6(evidence_score),
            harmonic_support: if source_bpm.is_some() { 0.82 } else { 0.68 },
            recent_stability: round_6(raw_score),
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

fn measure_signal(samples: &[f32], sample_rate: u32) -> SignalQuality {
    let count = samples.len();
    let peak = samples
        .iter()
        .map(|sample| sample.abs())
        .fold(0.0_f32, f32::max);
    let rms = if count == 0 {
        0.0
    } else {
        (samples
            .iter()
            .map(|sample| {
                let value = *sample as f64;
                value * value
            })
            .sum::<f64>()
            / count as f64)
            .sqrt() as f32
    };
    let full_scale_ratio = if count == 0 {
        0.0
    } else {
        samples
            .iter()
            .filter(|sample| (**sample).abs() >= 0.985)
            .count() as f32
            / count as f32
    };
    let flat_top_sample_ratio = if count == 0 {
        0.0
    } else {
        samples
            .iter()
            .filter(|sample| peak > 0.7 && (**sample).abs() >= peak * 0.995)
            .count() as f32
            / count as f32
    };
    let flat_top_frame_ratio = flat_top_frame_ratio(samples, sample_rate, peak);
    let clipping = full_scale_ratio > 0.01 || flat_top_sample_ratio > 0.015;
    let clipped_frame_ratio = if full_scale_ratio > 0.01 {
        full_scale_ratio.max(flat_top_frame_ratio)
    } else if flat_top_sample_ratio > 0.015 {
        flat_top_sample_ratio.max(flat_top_frame_ratio)
    } else {
        full_scale_ratio.max(flat_top_sample_ratio)
    };
    let silence = rms < 0.0002 || peak < 0.001;
    let tail_samples = (sample_rate as usize).saturating_mul(3);
    let tail_start = count.saturating_sub(tail_samples);
    let tail = &samples[tail_start..];
    let tail_rms = if tail.is_empty() {
        0.0
    } else {
        (tail
            .iter()
            .map(|sample| {
                let value = *sample as f64;
                value * value
            })
            .sum::<f64>()
            / tail.len() as f64)
            .sqrt() as f32
    };
    let breakdown_likely =
        !silence && sample_rate > 0 && count >= sample_rate as usize * 6 && tail_rms < 0.004_f32.max(rms * 0.18);
    let crest_db = if rms > 0.0 && peak > 0.0 {
        Some(20.0 * (peak.max(1e-12) / rms).log10())
    } else {
        None
    };
    let noise_level = if silence {
        NoiseLevel::Low
    } else if crest_db.is_some_and(|value| value < 8.0) && rms > 0.03 {
        NoiseLevel::NoiseOnly
    } else if rms > 0.14 && peak < 0.6 {
        NoiseLevel::NoiseOnly
    } else if crest_db.is_some_and(|value| value < 10.0) {
        NoiseLevel::High
    } else if rms < 0.035 {
        NoiseLevel::Low
    } else if rms < 0.18 {
        NoiseLevel::Medium
    } else {
        NoiseLevel::High
    };

    SignalQuality {
        input_level_dbfs: dbfs(rms),
        peak_dbfs: dbfs(peak),
        clipping,
        clipped_frame_ratio: round_6(clipped_frame_ratio),
        noise_level,
        snr_estimate_db: None,
        silence,
        breakdown_likely,
    }
}

fn flat_top_frame_ratio(samples: &[f32], sample_rate: u32, peak: f32) -> f32 {
    if samples.is_empty() || sample_rate == 0 || peak < 0.7 {
        return 0.0;
    }
    let frame_size = ((sample_rate as f32 * 0.010) as usize).max(1);
    let mut frames = 0;
    let mut clipped_frames = 0;
    for frame in samples.chunks(frame_size) {
        if frame.is_empty() {
            continue;
        }
        frames += 1;
        if frame.iter().any(|sample| sample.abs() >= peak * 0.995) {
            clipped_frames += 1;
        }
    }
    if frames == 0 {
        0.0
    } else {
        clipped_frames as f32 / frames as f32
    }
}

fn onset_envelope(samples: &[f32], sample_rate: u32) -> (Vec<f32>, f32) {
    if sample_rate == 0 {
        return (Vec::new(), 0.0);
    }
    let hop_size = ((sample_rate as f32 * 0.0025) as usize).max(1);
    let frame_size = hop_size.max((sample_rate as f32 * 0.010) as usize);
    let mut frame_rms = Vec::new();
    let mut start = 0;
    let end = samples.len().saturating_sub(frame_size);
    while start < end {
        let frame = &samples[start..start + frame_size];
        let rms = (frame
            .iter()
            .map(|sample| {
                let value = *sample as f64;
                value * value
            })
            .sum::<f64>()
            / frame.len() as f64)
            .sqrt() as f32;
        frame_rms.push(rms);
        start += hop_size;
    }

    if frame_rms.len() < 4 {
        return (Vec::new(), hop_size as f32 / sample_rate as f32);
    }

    let mut flux = Vec::with_capacity(frame_rms.len());
    flux.push(0.0);
    for idx in 1..frame_rms.len() {
        flux.push((frame_rms[idx] - frame_rms[idx - 1]).max(0.0));
    }

    let floor = median(&flux);
    let mut envelope: Vec<f32> = flux.into_iter().map(|value| (value - floor).max(0.0)).collect();
    let peak = envelope.iter().copied().fold(0.0_f32, f32::max);
    if peak > 0.0 {
        for value in &mut envelope {
            *value /= peak;
        }
    }
    (envelope, hop_size as f32 / sample_rate as f32)
}

fn tail_onset_breakdown(envelope: &[f32], hop_sec: f32) -> bool {
    if hop_sec <= 0.0 {
        return false;
    }
    let tail_frames = ((3.0 / hop_sec) as usize).max(1);
    if envelope.len() < tail_frames * 2 {
        return false;
    }
    let split = envelope.len() - tail_frames;
    let history = &envelope[..split];
    let tail = &envelope[split..];
    if history.is_empty() {
        return false;
    }
    let history_mean = history.iter().sum::<f32>() / history.len() as f32;
    let tail_mean = tail.iter().sum::<f32>() / tail.len() as f32;
    let history_peak = history.iter().copied().fold(0.0_f32, f32::max);
    let tail_peak = tail.iter().copied().fold(0.0_f32, f32::max);
    history_peak > 0.45 && tail_peak < 0.20 && tail_mean < 0.003_f32.max(history_mean * 0.95)
}

fn tempo_autocorrelation(envelope: &[f32], hop_sec: f32, min_bpm: f32, max_bpm: f32) -> Vec<RawPeak> {
    if envelope.len() < 4 || hop_sec <= 0.0 || min_bpm <= 0.0 || max_bpm <= 0.0 {
        return Vec::new();
    }
    let min_lag = ((60.0 / max_bpm / hop_sec).floor() as usize).max(1);
    let max_lag = (envelope.len() - 2).min((60.0 / min_bpm / hop_sec).ceil() as usize);
    if max_lag <= min_lag {
        return Vec::new();
    }

    let mut scores = Vec::with_capacity(max_lag - min_lag + 1);
    for lag in min_lag..=max_lag {
        let mut current_energy = 0.0_f64;
        let mut shifted_energy = 0.0_f64;
        let mut numerator = 0.0_f64;
        for idx in lag..envelope.len() {
            let current = envelope[idx] as f64;
            let shifted = envelope[idx - lag] as f64;
            numerator += current * shifted;
            current_energy += current * current;
            shifted_energy += shifted * shifted;
        }
        let denom = (current_energy * shifted_energy).sqrt();
        let score = if denom > 0.0 { numerator / denom } else { 0.0 };
        scores.push((lag, score as f32));
    }

    let mut peaks = Vec::new();
    for idx in 1..scores.len().saturating_sub(1) {
        let (lag, score) = scores[idx];
        if score >= scores[idx - 1].1 && score >= scores[idx + 1].1 {
            peaks.push(RawPeak {
                bpm: 60.0 / (lag as f32 * hop_sec),
                score,
            });
        }
    }
    peaks.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    peaks.truncate(16);
    peaks
}

fn peak_prominence(raw_peaks: &[RawPeak]) -> f32 {
    if raw_peaks.is_empty() {
        return 0.0;
    }
    let scores: Vec<f32> = raw_peaks.iter().map(|peak| peak.score).collect();
    (scores[0] - median(&scores)).clamp(0.0, 1.0)
}

fn harmonic_ambiguity(candidates: &[TempoCandidate]) -> f32 {
    if candidates.len() < 2 {
        return 0.0;
    }
    let primary = &candidates[0];
    if primary.bpm <= 0.0 {
        return 0.0;
    }
    for candidate in &candidates[1..] {
        let relative_distance = (candidate.bpm - primary.bpm).abs() / primary.bpm;
        if relative_distance > 0.015 {
            return (candidate.score / primary.score.max(0.0001)).clamp(0.0, 1.0);
        }
    }
    0.0
}

fn signal_factor(signal_quality: &SignalQuality) -> f32 {
    if signal_quality.silence || signal_quality.breakdown_likely {
        return 0.0;
    }
    if signal_quality.clipping && severe_clipping(signal_quality) {
        return 0.0;
    }
    if signal_quality.clipping {
        return 0.62;
    }
    match signal_quality.noise_level {
        NoiseLevel::NoiseOnly => 0.28,
        NoiseLevel::High => 0.68,
        NoiseLevel::Medium => 0.92,
        _ => 1.0,
    }
}

fn severe_clipping(signal_quality: &SignalQuality) -> bool {
    signal_quality.clipped_frame_ratio >= 0.05
}

fn resample_linear(samples: &[f32], source_rate: u32, target_rate: u32) -> Vec<f32> {
    if samples.is_empty() || source_rate == 0 || target_rate == 0 || source_rate == target_rate {
        return samples.to_vec();
    }
    let output_len = ((samples.len() as f64 * target_rate as f64) / source_rate as f64)
        .round()
        .max(1.0) as usize;
    let ratio = source_rate as f64 / target_rate as f64;
    let mut output = Vec::with_capacity(output_len);
    for idx in 0..output_len {
        let source_index = idx as f64 * ratio;
        let left = source_index.floor() as usize;
        let right = (left + 1).min(samples.len() - 1);
        let frac = (source_index - left as f64) as f32;
        output.push(samples[left] * (1.0 - frac) + samples[right] * frac);
    }
    output
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

fn round_1(value: f32) -> f32 {
    (value * 10.0).round() / 10.0
}

fn round_6(value: f32) -> f32 {
    (value * 1_000_000.0).round() / 1_000_000.0
}

fn dbfs(value: f32) -> Option<f32> {
    if value <= 0.0 {
        None
    } else {
        Some(round_3(20.0 * value.min(1.0).log10()))
    }
}

fn median(values: &[f32]) -> f32 {
    if values.is_empty() {
        return 0.0;
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(|left, right| {
        left.partial_cmp(right)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let middle = sorted.len() / 2;
    if sorted.len() % 2 == 0 {
        (sorted[middle - 1] + sorted[middle]) / 2.0
    } else {
        sorted[middle]
    }
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
