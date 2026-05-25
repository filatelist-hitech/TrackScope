use hitech_bpm_dsp::{analyze_pcm, DspConfig, DspEngine, LockState, TempoRelation};

const SAMPLE_RATE: u32 = 48_000;
const DURATION_SEC: f32 = 14.0;

#[test]
fn clean_hitech_fixtures_lock_within_one_bpm() {
    for bpm in [170.0, 180.0, 190.0, 200.0, 220.0] {
        let samples = pulse_samples(bpm, DURATION_SEC, 0.9);
        let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

        assert_eq!(result.lock_state, LockState::Stable, "{bpm} BPM");
        assert_bpm(result.primary_bpm, bpm, 1.0);
        assert!(result.confidence >= 0.72, "{bpm} confidence {}", result.confidence);
        assert_candidate_near(&result.candidates, bpm, 1.0, None);
    }
}

#[test]
fn half_time_trap_preserves_raw_and_normalized_candidates() {
    let samples = pulse_samples(100.0, DURATION_SEC, 0.9);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

    assert_eq!(result.lock_state, LockState::Stable);
    assert_bpm(result.primary_bpm, 200.0, 1.0);
    assert_candidate_near(&result.candidates, 100.0, 1.0, Some(TempoRelation::Raw));
    assert_candidate_near(
        &result.candidates,
        200.0,
        1.0,
        Some(TempoRelation::NormalizedFromHalf),
    );
    assert_source_candidate(&result.candidates, 200.0, TempoRelation::NormalizedFromHalf, 100.0);
    assert_candidate_near(&result.candidates, 200.0, 1.0, Some(TempoRelation::Main));
}

#[test]
fn double_time_trap_preserves_raw_and_normalized_candidates() {
    let samples = pulse_samples(400.0, DURATION_SEC, 0.9);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

    assert_eq!(result.lock_state, LockState::Stable);
    assert_bpm(result.primary_bpm, 200.0, 1.0);
    assert_candidate_near(&result.candidates, 400.0, 1.0, Some(TempoRelation::Raw));
    assert_candidate_near(
        &result.candidates,
        200.0,
        1.0,
        Some(TempoRelation::NormalizedFromDouble),
    );
    assert_source_candidate(&result.candidates, 200.0, TempoRelation::NormalizedFromDouble, 400.0);
    assert_candidate_near(&result.candidates, 200.0, 1.0, Some(TempoRelation::Main));
}

#[test]
fn main_tempo_preserves_half_and_double_time_interpretations() {
    let samples = pulse_samples(200.0, DURATION_SEC, 0.9);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

    assert_eq!(result.lock_state, LockState::Stable);
    assert_candidate_near(&result.candidates, 100.0, 1.0, Some(TempoRelation::HalfTime));
    assert_candidate_near(&result.candidates, 400.0, 2.0, Some(TempoRelation::DoubleTime));
}

#[test]
fn silence_and_noise_do_not_invent_stable_bpm() {
    let fixtures = [
        silence(),
        white_noise(170_170, 0.28),
        pink_noise(220_220, 0.32),
    ];

    for samples in fixtures {
        let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());
        assert_eq!(result.primary_bpm, None);
        assert_ne!(result.lock_state, LockState::Stable);
        assert!(result.confidence < 0.5, "confidence {}", result.confidence);
    }
}

#[test]
fn clipped_microphone_suppresses_final_bpm() {
    let samples: Vec<f32> = pulse_samples(200.0, DURATION_SEC, 1.8)
        .into_iter()
        .map(|sample| (sample * 2.8).clamp(-0.78, 0.78))
        .collect();
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

    assert_eq!(result.primary_bpm, None);
    assert_eq!(result.lock_state, LockState::ClippedMic);
    assert!(result.signal_quality.clipping);
    assert!(result.signal_quality.clipped_frame_ratio > 0.05);
    assert!(result.confidence < 0.6);
    assert_candidate_near(&result.candidates, 200.0, 2.0, None);
}

#[test]
fn breakdown_without_kick_does_not_finish_stable() {
    let mut samples = pulse_samples(200.0, 6.0, 0.9);
    samples.extend(low_rumble(8.0, 0xBEEFDA, 0.08));
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

    assert_eq!(result.primary_bpm, None);
    assert_ne!(result.lock_state, LockState::Stable);
    assert!(matches!(
        result.lock_state,
        LockState::Breakdown | LockState::Unstable | LockState::Locking | LockState::Searching
    ));
    assert!(result.confidence < 0.7);
    assert_candidate_near(&result.candidates, 200.0, 2.0, None);
}

#[test]
fn dense_hitech_bassline_prefers_main_beat() {
    let mut samples = pulse_samples(200.0, DURATION_SEC, 0.82);
    add_rolling_bassline(&mut samples, 200.0);
    let samples = normalize(samples, 0.92);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

    assert_eq!(result.lock_state, LockState::Stable);
    assert_bpm(result.primary_bpm, 200.0, 2.0);
    assert_candidate_near(&result.candidates, 200.0, 2.0, None);
}

#[test]
fn unstable_club_simulation_keeps_uncertainty_visible() {
    let result = analyze_pcm(
        &unstable_club_simulation(),
        SAMPLE_RATE,
        DspConfig::default(),
    );

    assert_eq!(result.primary_bpm, None);
    assert_ne!(result.lock_state, LockState::Stable);
    assert!(result.confidence < 0.5, "confidence {}", result.confidence);
}

#[test]
fn streaming_engine_matches_batch_analysis() {
    let samples = pulse_samples(190.0, DURATION_SEC, 0.9);
    let batch = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());
    let mut engine = DspEngine::default();
    for chunk in samples.chunks(SAMPLE_RATE as usize) {
        engine.push_samples(chunk, SAMPLE_RATE);
    }
    let streamed = engine.analyze();

    assert_eq!(streamed.lock_state, batch.lock_state);
    assert_bpm(streamed.primary_bpm, batch.primary_bpm.unwrap(), 0.1);
}

fn assert_bpm(actual: Option<f32>, expected: f32, tolerance: f32) {
    let Some(actual) = actual else {
        panic!("expected {expected} BPM, got None");
    };
    assert!(
        (actual - expected).abs() <= tolerance,
        "expected {expected} +/- {tolerance}, got {actual}"
    );
}

fn assert_candidate_near(
    candidates: &[hitech_bpm_dsp::TempoCandidate],
    bpm: f32,
    tolerance: f32,
    relation: Option<TempoRelation>,
) {
    assert!(
        candidates.iter().any(|candidate| {
            (candidate.bpm - bpm).abs() <= tolerance
                && relation.map_or(true, |relation| candidate.relation == relation)
        }),
        "missing candidate near {bpm} BPM relation {relation:?}: {candidates:?}"
    );
}

fn assert_source_candidate(
    candidates: &[hitech_bpm_dsp::TempoCandidate],
    bpm: f32,
    relation: TempoRelation,
    source_bpm: f32,
) {
    assert!(
        candidates.iter().any(|candidate| {
            (candidate.bpm - bpm).abs() <= 1.0
                && candidate.relation == relation
                && candidate
                    .source_bpm
                    .is_some_and(|source| (source - source_bpm).abs() <= 1.0)
        }),
        "missing source candidate {relation:?} {bpm} from {source_bpm}: {candidates:?}"
    );
}

fn pulse_samples(bpm: f32, duration_sec: f32, amplitude: f32) -> Vec<f32> {
    let mut samples = vec![0.0; sample_count(duration_sec)];
    let beat_period = 60.0 / bpm;
    let mut beat = 0.0;
    while beat < duration_sec {
        add_kick(&mut samples, (beat * SAMPLE_RATE as f32).round() as usize, amplitude);
        beat += beat_period;
    }
    normalize(samples, 0.88)
}

fn add_kick(samples: &mut [f32], start: usize, amplitude: f32) {
    let length = (0.055 * SAMPLE_RATE as f32) as usize;
    let transient_len = ((0.003 * SAMPLE_RATE as f32) as usize).max(1);
    for offset in 0..length {
        let idx = start + offset;
        if idx >= samples.len() {
            return;
        }
        let t = offset as f32 / SAMPLE_RATE as f32;
        let envelope = (-72.0 * t).exp();
        let tone = (2.0 * std::f32::consts::PI * 72.0 * t).sin();
        let click = if offset < transient_len {
            1.0 - (offset as f32 / transient_len as f32)
        } else {
            0.0
        };
        samples[idx] += amplitude * ((0.72 * tone * envelope) + (0.55 * click * envelope));
    }
}

fn add_rolling_bassline(samples: &mut [f32], bpm: f32) {
    let step = 60.0 / (bpm * 4.0);
    let pulse_len = (0.045 * SAMPLE_RATE as f32) as usize;
    let mut position = step / 2.0;
    while position < DURATION_SEC {
        let start = (position * SAMPLE_RATE as f32).round() as usize;
        for offset in 0..pulse_len {
            let idx = start + offset;
            if idx >= samples.len() {
                break;
            }
            let t = offset as f32 / SAMPLE_RATE as f32;
            let envelope = (-38.0 * t).exp();
            let tone = (2.0 * std::f32::consts::PI * 98.0 * t).sin();
            samples[idx] += 0.18 * tone * envelope;
        }
        position += step;
    }
}

fn silence() -> Vec<f32> {
    vec![0.0; sample_count(DURATION_SEC)]
}

fn white_noise(seed: u64, amplitude: f32) -> Vec<f32> {
    let mut rng = Lcg::new(seed);
    (0..sample_count(DURATION_SEC))
        .map(|_| rng.uniform(-amplitude, amplitude))
        .collect()
}

fn pink_noise(seed: u64, amplitude: f32) -> Vec<f32> {
    let mut rng = Lcg::new(seed);
    let mut value = 0.0;
    let mut samples = Vec::with_capacity(sample_count(DURATION_SEC));
    for _ in 0..sample_count(DURATION_SEC) {
        value = (0.985 * value) + (0.015 * rng.uniform(-1.0, 1.0));
        samples.push(value);
    }
    normalize(samples, amplitude)
}

fn low_rumble(duration_sec: f32, seed: u64, amplitude: f32) -> Vec<f32> {
    let mut rng = Lcg::new(seed);
    let mut samples = Vec::with_capacity(sample_count(duration_sec));
    for idx in 0..sample_count(duration_sec) {
        let t = idx as f32 / SAMPLE_RATE as f32;
        let rumble = (2.0 * std::f32::consts::PI * 37.0 * t).sin() * 0.7;
        let drift = (2.0 * std::f32::consts::PI * 0.21 * t).sin() * 0.2;
        samples.push(amplitude * (rumble + drift + rng.uniform(-0.08, 0.08)));
    }
    samples
}

fn unstable_club_simulation() -> Vec<f32> {
    let mut rng = Lcg::new(0x5150);
    let mut samples = vec![0.0; sample_count(DURATION_SEC)];
    let mut beat_time = 0.0;
    while beat_time < DURATION_SEC {
        let bpm = rng.uniform(175.0, 245.0);
        beat_time += 60.0 / bpm;
        if rng.next_f32() < 0.22 {
            continue;
        }
        add_kick(
            &mut samples,
            (beat_time * SAMPLE_RATE as f32).round() as usize,
            rng.uniform(0.25, 0.75),
        );
    }

    for (idx, sample) in samples.iter_mut().enumerate() {
        let t = idx as f32 / SAMPLE_RATE as f32;
        let rumble = 0.09 * (2.0 * std::f32::consts::PI * 43.0 * t).sin();
        *sample += rumble + rng.uniform(-0.32, 0.32);
    }
    normalize(samples, 0.9)
}

fn normalize(samples: Vec<f32>, peak: f32) -> Vec<f32> {
    let current_peak = samples.iter().map(|sample| sample.abs()).fold(0.0, f32::max);
    if current_peak == 0.0 {
        return samples;
    }
    let scale = peak / current_peak;
    samples.into_iter().map(|sample| sample * scale).collect()
}

fn sample_count(duration_sec: f32) -> usize {
    (duration_sec * SAMPLE_RATE as f32).round() as usize
}

struct Lcg {
    state: u64,
}

impl Lcg {
    fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn next_f32(&mut self) -> f32 {
        self.state = self.state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        ((self.state & 0xffff_ffff) as f32) / u32::MAX as f32
    }

    fn uniform(&mut self, min: f32, max: f32) -> f32 {
        min + (max - min) * self.next_f32()
    }
}
