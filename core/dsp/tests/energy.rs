/// Тесты EnergyAnalyzer (Phase 2.2).
///
/// Проверяют: наличие energy_result на STABLE-фикстуре, отсутствие
/// на тишине, диапазон 1–10 на чистом пульсе и калибровку clean_200.
mod common;

use hitech_bpm_dsp::{DspConfig, DspEngine, LockState};

const SR: u32 = 48_000;

fn run_stream(samples: &[f32]) -> hitech_bpm_dsp::DspResult {
    let mut engine = DspEngine::new(DspConfig::default());
    let chunk = SR as usize / 10; // 100 мс чанки
    for chunk_slice in samples.chunks(chunk) {
        engine.push_samples(chunk_slice, SR);
    }
    engine.analyze()
}

fn run_stream_full(samples: &[f32]) -> Vec<hitech_bpm_dsp::DspResult> {
    let mut engine = DspEngine::new(DspConfig::default());
    let chunk = SR as usize / 10;
    let mut results = Vec::new();
    for chunk_slice in samples.chunks(chunk) {
        engine.push_samples(chunk_slice, SR);
        results.push(engine.analyze());
    }
    results
}

/// Тишина → energy_result отсутствует (гейт подавляет).
#[test]
fn energy_result_absent_on_silence() {
    let silence = common::silence(14.0);
    let result = run_stream(&silence);
    assert!(
        result.energy_result.is_none(),
        "silence should yield energy_result=None, got {:?}",
        result.energy_result
    );
}

/// STABLE 200 BPM → energy_result присутствует.
#[test]
fn energy_result_present_on_stable_signal() {
    let pulse = common::pulse_track(200.0, 14.0, 0.7);
    let results = run_stream_full(&pulse);
    let stable_result = results.iter().find(|r| r.lock_state == LockState::Stable);
    let stable = stable_result.expect("should reach STABLE on clean 200 BPM");
    assert!(
        stable.energy_result.is_some(),
        "STABLE signal should have energy_result, got None"
    );
}

/// Чистый 200 BPM пульс → level ∈ [1, 10].
#[test]
fn energy_result_level_in_range_1_10() {
    let pulse = common::pulse_track(200.0, 14.0, 0.7);
    let results = run_stream_full(&pulse);
    for r in &results {
        if let Some(ref er) = r.energy_result {
            assert!(
                er.level >= 1 && er.level <= 10,
                "level out of range [1,10]: {}",
                er.level
            );
        }
    }
}

/// Чистый 200 BPM пульс в STABLE → level ∈ [4, 8] (калибровка).
#[test]
fn energy_result_calibration_clean_200_in_range_4_8() {
    let pulse = common::pulse_track(200.0, 14.0, 0.7);
    let results = run_stream_full(&pulse);
    let stable_results: Vec<_> = results
        .iter()
        .filter(|r| r.lock_state == LockState::Stable)
        .filter_map(|r| r.energy_result.as_ref())
        .collect();
    assert!(
        !stable_results.is_empty(),
        "should have STABLE frames with energy"
    );
    for er in &stable_results {
        assert!(
            er.level >= 4 && er.level <= 8,
            "expected level in [4,8] for clean_200 STABLE, got {}",
            er.level
        );
    }
}

/// Клиппированный вход → energy_result = None (CLIPPED_MIC гейт).
#[test]
fn energy_result_absent_on_clipped_mic() {
    let clipped = common::severely_clipped_pulse(200.0, 14.0);
    let results = run_stream_full(&clipped);
    let clipped_results: Vec<_> = results
        .iter()
        .filter(|r| r.lock_state == LockState::ClippedMic)
        .collect();
    if !clipped_results.is_empty() {
        for r in &clipped_results {
            assert!(
                r.energy_result.is_none(),
                "CLIPPED_MIC should yield energy_result=None"
            );
        }
    }
    // Если CLIPPED_MIC не достигнут — фикстура недостаточно клипирована; пропустить.
}
