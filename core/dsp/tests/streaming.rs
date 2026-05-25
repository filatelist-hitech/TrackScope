mod common;

use common::{pulse_track, SAMPLE_RATE};
use hitech_bpm_dsp::{DspConfig, DspEngine, LockState};

/// First-lock timing — once a clean 200 BPM pulse has been fed
/// frame-by-frame, the engine must leave `SEARCHING` within
/// `config.lock_min_seconds` (default 6 s) of audio.
#[test]
fn streaming_first_lock_under_six_seconds_for_200_bpm() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize; // 100 ms
    let samples = pulse_track(200.0, config.lock_min_seconds, 0.9);

    let mut engine = DspEngine::new(config);
    let mut first_non_searching_at: Option<f32> = None;
    let mut fed = 0usize;

    for chunk in samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_sec = fed as f32 / SAMPLE_RATE as f32;
        let result = engine.analyze();
        if !matches!(result.lock_state, LockState::Searching) && first_non_searching_at.is_none() {
            first_non_searching_at = Some(elapsed_sec);
        }
    }

    let lock_time = first_non_searching_at
        .expect("engine must leave SEARCHING on a clean 200 BPM pulse");
    assert!(
        lock_time <= config.lock_min_seconds,
        "first usable lock at {lock_time:.2}s exceeded lock_min_seconds={}s",
        config.lock_min_seconds
    );
}

/// Stable-lock timing — feed up to `stable_min_seconds` of audio and
/// require the engine to reach `STABLE` with `primary_bpm` within ±2 BPM
/// of the truth.
#[test]
fn streaming_stable_lock_under_twelve_seconds_for_200_bpm() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;
    let samples = pulse_track(200.0, config.stable_min_seconds, 0.9);

    let mut engine = DspEngine::new(config);
    let mut stable_at: Option<f32> = None;
    let mut fed = 0usize;
    let mut last_bpm: Option<f32> = None;

    for chunk in samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_sec = fed as f32 / SAMPLE_RATE as f32;
        let result = engine.analyze();
        last_bpm = result.primary_bpm;
        if matches!(result.lock_state, LockState::Stable) && stable_at.is_none() {
            stable_at = Some(elapsed_sec);
        }
    }

    let stable_time =
        stable_at.expect("engine must reach STABLE on a clean 200 BPM pulse within the window");
    assert!(
        stable_time <= config.stable_min_seconds,
        "stable lock at {stable_time:.2}s exceeded stable_min_seconds={}s",
        config.stable_min_seconds
    );
    let bpm = last_bpm.expect("primary_bpm should be reported at the end of the stable run");
    assert!(
        (bpm - 200.0).abs() <= 2.0,
        "primary_bpm {bpm} drifted from 200.0 by more than 2 BPM"
    );
}

/// Mid-stream tempo change — concatenate 12 s of 180 BPM pulse with 12 s
/// of 200 BPM pulse and feed the whole 24-second stream frame-by-frame.
///
/// Asserts:
/// 1. By the end of the first segment the engine reports ~180 BPM and
///    STABLE.
/// 2. After the transition, `primary_bpm` reaches ~200 BPM within one
///    analysis window (`analysis_window_seconds`).
/// 3. The lock state transitions through a non-STABLE state during the
///    change — the engine does not silently swap one BPM for another
///    while remaining STABLE.
#[test]
fn streaming_reflects_mid_stream_tempo_change_within_one_window() {
    let config = DspConfig::default();
    let window_sec = config.analysis_window_seconds;
    let segment_sec = window_sec; // 12 s of each tempo
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;

    let mut samples = pulse_track(180.0, segment_sec, 0.9);
    samples.extend(pulse_track(200.0, segment_sec, 0.9));

    let transition_sample = (segment_sec * SAMPLE_RATE as f32) as usize;
    let transition_sec = transition_sample as f32 / SAMPLE_RATE as f32;

    let mut engine = DspEngine::new(config);
    let mut fed = 0usize;
    let mut pre_change_bpm: Option<f32> = None;
    let mut pre_change_lock: Option<LockState> = None;
    let mut left_stable_during_change = false;
    let mut bpm_caught_up_at: Option<f32> = None;

    for chunk in samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_sec = fed as f32 / SAMPLE_RATE as f32;
        let result = engine.analyze();

        if elapsed_sec <= transition_sec - 0.5 {
            if matches!(result.lock_state, LockState::Stable) {
                pre_change_bpm = result.primary_bpm;
                pre_change_lock = Some(result.lock_state);
            }
        }

        if elapsed_sec > transition_sec + 0.5 && elapsed_sec <= transition_sec + window_sec {
            if !matches!(result.lock_state, LockState::Stable) {
                left_stable_during_change = true;
            }
        }

        if elapsed_sec > transition_sec
            && bpm_caught_up_at.is_none()
            && result.primary_bpm.is_some_and(|bpm| (bpm - 200.0).abs() <= 2.0)
        {
            bpm_caught_up_at = Some(elapsed_sec - transition_sec);
        }
    }

    let pre_bpm = pre_change_bpm.expect("engine must lock to 180 BPM before the transition");
    assert!(
        (pre_bpm - 180.0).abs() <= 2.0,
        "pre-change primary_bpm {pre_bpm} drifted from 180.0 by more than 2 BPM"
    );
    assert_eq!(
        pre_change_lock,
        Some(LockState::Stable),
        "engine must reach STABLE on the first segment"
    );

    assert!(
        left_stable_during_change,
        "engine must transition through a non-STABLE state during a mid-stream tempo change \
         (cannot silently swap 180 -> 200 while remaining STABLE)"
    );

    let catch_up = bpm_caught_up_at
        .expect("primary_bpm must reflect the new tempo within one analysis window");
    assert!(
        catch_up <= window_sec,
        "primary_bpm caught up to ~200 BPM {catch_up:.2}s after the transition, exceeding the \
         analysis window of {window_sec}s"
    );
}
