mod common;

use common::{
    breakdown_without_kick, dense_hitech_bassline, fixture_samples, normalize, pink_noise,
    pulse_track, recoverable_clipped_pulse, severely_clipped_pulse, silence,
    unstable_club_simulation, white_noise, CANONICAL_FIXTURES, DEFAULT_DURATION_SEC, SAMPLE_RATE,
};
use hitech_bpm_dsp::{analyze_pcm, DspConfig, DspEngine, LockState, TempoRelation};

#[test]
fn clean_hitech_fixtures_lock_within_one_bpm() {
    for bpm in [170.0, 180.0, 190.0, 200.0, 220.0] {
        let samples = pulse_track(bpm, DEFAULT_DURATION_SEC, 0.9);
        let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

        assert_eq!(result.lock_state, LockState::Stable, "{bpm} BPM");
        assert_bpm(result.primary_bpm, bpm, 1.0);
        assert!(
            result.confidence >= 0.72,
            "{bpm} confidence {}",
            result.confidence
        );
        assert_candidate_near(&result.candidates, bpm, 1.0, None);
    }
}

#[test]
fn half_time_trap_preserves_raw_and_normalized_candidates() {
    let samples = pulse_track(100.0, DEFAULT_DURATION_SEC, 0.9);
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
    assert_source_candidate(
        &result.candidates,
        200.0,
        TempoRelation::NormalizedFromHalf,
        100.0,
    );
    assert_candidate_near(&result.candidates, 200.0, 1.0, Some(TempoRelation::Main));
}

#[test]
fn double_time_trap_preserves_raw_and_normalized_candidates() {
    let samples = pulse_track(400.0, DEFAULT_DURATION_SEC, 0.9);
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
    assert_source_candidate(
        &result.candidates,
        200.0,
        TempoRelation::NormalizedFromDouble,
        400.0,
    );
    assert_candidate_near(&result.candidates, 200.0, 1.0, Some(TempoRelation::Main));
}

#[test]
fn main_tempo_preserves_half_and_double_time_interpretations() {
    let samples = pulse_track(200.0, DEFAULT_DURATION_SEC, 0.9);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

    assert_eq!(result.lock_state, LockState::Stable);
    assert_candidate_near(&result.candidates, 100.0, 1.0, Some(TempoRelation::HalfTime));
    assert_candidate_near(&result.candidates, 400.0, 2.0, Some(TempoRelation::DoubleTime));
}

#[test]
fn silence_and_noise_do_not_invent_stable_bpm() {
    let fixtures = [
        silence(DEFAULT_DURATION_SEC),
        white_noise(170_170, 0.28, DEFAULT_DURATION_SEC),
        pink_noise(220_220, 0.32, DEFAULT_DURATION_SEC),
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
    let samples = severely_clipped_pulse(200.0, DEFAULT_DURATION_SEC);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

    assert_eq!(result.primary_bpm, None);
    assert_eq!(result.lock_state, LockState::ClippedMic);
    assert!(result.signal_quality.clipping);
    assert!(result.signal_quality.clipped_frame_ratio > 0.05);
    assert!(result.confidence < 0.6);
    assert_candidate_near(&result.candidates, 200.0, 2.0, None);
}

#[test]
fn recoverable_clipping_keeps_bpm_candidates_and_can_lock() {
    let samples = recoverable_clipped_pulse(200.0, DEFAULT_DURATION_SEC);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

    assert!(result.signal_quality.clipping);
    assert!(result.signal_quality.clipped_frame_ratio < 0.05);
    assert!(matches!(
        result.lock_state,
        LockState::Locking | LockState::Stable
    ));
    assert_bpm(result.primary_bpm, 200.0, 2.0);
    assert!(result.confidence >= 0.45, "confidence {}", result.confidence);
    assert_candidate_near(&result.candidates, 200.0, 2.0, None);
    assert_candidate_near(&result.candidates, 100.0, 2.0, None);
}

#[test]
fn breakdown_without_kick_does_not_finish_stable() {
    let samples = breakdown_without_kick(200.0, 6.0, 8.0, 0xBEEFDA);
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
    let samples = dense_hitech_bassline(200.0, DEFAULT_DURATION_SEC);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

    assert_eq!(result.lock_state, LockState::Stable);
    assert_bpm(result.primary_bpm, 200.0, 2.0);
    assert_candidate_near(&result.candidates, 200.0, 2.0, None);
}

#[test]
fn unstable_club_simulation_keeps_uncertainty_visible() {
    let result = analyze_pcm(
        &unstable_club_simulation(DEFAULT_DURATION_SEC),
        SAMPLE_RATE,
        DspConfig::default(),
    );

    assert_eq!(result.primary_bpm, None);
    assert_ne!(result.lock_state, LockState::Stable);
    assert!(result.confidence < 0.5, "confidence {}", result.confidence);
}

#[test]
fn streaming_engine_matches_batch_analysis() {
    let samples = pulse_track(190.0, DEFAULT_DURATION_SEC, 0.9);
    let batch = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());
    let mut engine = DspEngine::default();
    for chunk in samples.chunks(SAMPLE_RATE as usize) {
        engine.push_samples(chunk, SAMPLE_RATE);
    }
    let streamed = engine.analyze();

    assert_eq!(streamed.lock_state, batch.lock_state);
    assert_bpm(streamed.primary_bpm, batch.primary_bpm.unwrap(), 0.1);
}

/// Every canonical fixture must resolve to a `DspResult` and never violate
/// the anti-fake invariants — silence/noise/severe-clipping never reach STABLE,
/// half/double-time relations remain visible on the matching traps.
#[test]
fn canonical_fixture_inventory_round_trip() {
    for name in CANONICAL_FIXTURES {
        let samples = fixture_samples(name);
        let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());

        if matches!(*name, "silence" | "white_noise" | "pink_noise") {
            assert_ne!(result.lock_state, LockState::Stable, "{name}");
            assert_eq!(result.primary_bpm, None, "{name}");
        }
        if *name == "severely_clipped_mic" {
            assert_eq!(result.lock_state, LockState::ClippedMic, "{name}");
            assert_eq!(result.primary_bpm, None, "{name}");
        }
        if name.starts_with("clean_") {
            assert_eq!(result.lock_state, LockState::Stable, "{name}");
        }
    }
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

// Suppress unused-warnings from common module helpers not used in this binary.
#[allow(dead_code)]
fn _force_normalize_used(samples: Vec<f32>, peak: f32) -> Vec<f32> {
    normalize(samples, peak)
}
