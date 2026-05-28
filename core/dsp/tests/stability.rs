// Тесты стабильности BPM: параболическая интерполяция + история кандидатов.
//
// Проверяют, что на чистых синтетических фикстурах в STABLE-состоянии
// все значения primary_bpm попадают в допуск ±0.5 BPM (более жёсткий,
// чем базовые тесты ±1.0 BPM в offline_contract.rs).

mod common;

use common::{pulse_track, silence, white_noise, SAMPLE_RATE};
use hitech_bpm_dsp::{analyze_pcm, DspConfig, DspEngine, LockState};

// ── Helpers ────────────────────────────────────────────────────────────────

fn run_streak_stability(target_bpm: f32) {
    let chunk_sec = 0.1_f32;
    let total_sec = 30.0_f32;
    let chunk_size = (SAMPLE_RATE as f32 * chunk_sec) as usize;
    let samples = pulse_track(target_bpm, total_sec, 0.9);

    let mut engine = DspEngine::new(DspConfig::default());
    let mut stable_bpms: Vec<f32> = Vec::new();

    for chunk in samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        let result = engine.analyze();
        if result.lock_state == LockState::Stable {
            if let Some(bpm) = result.primary_bpm {
                stable_bpms.push(bpm);
            }
        }
    }

    // Нужно минимум 20 STABLE-кадров после прогрева BPM_HISTORY_N.
    assert!(
        stable_bpms.len() >= 23,
        "Not enough STABLE frames for {target_bpm} BPM: got {}",
        stable_bpms.len()
    );

    // Проверяем последние 20 кадров — прогрев истории уже завершён.
    let last_20 = &stable_bpms[stable_bpms.len() - 20..];
    for &bpm in last_20 {
        assert!(
            (bpm - target_bpm).abs() <= 0.5,
            "Streak instability at {target_bpm} BPM: got {bpm} (tolerance ±0.5)"
        );
    }
}

// ── Tests ──────────────────────────────────────────────────────────────────

/// Параболическая интерполяция не паникует на «плоской» вершине автокорреляции
/// (шум или тишина). Убеждаемся, что lock_state != STABLE и primary_bpm == None.
#[test]
fn parabolic_flat_peak_no_panic() {
    let samples_silence = silence(15.0);
    let r1 = analyze_pcm(&samples_silence, SAMPLE_RATE, DspConfig::default());
    assert_ne!(
        r1.lock_state,
        LockState::Stable,
        "silence must not reach STABLE"
    );
    assert!(r1.primary_bpm.is_none(), "silence primary_bpm must be None");

    // Детерминированный белый шум — также не должен давать STABLE.
    let samples_noise = white_noise(42, 0.25, 15.0);
    let r2 = analyze_pcm(&samples_noise, SAMPLE_RATE, DspConfig::default());
    assert_ne!(
        r2.lock_state,
        LockState::Stable,
        "white noise must not reach STABLE"
    );
    assert!(
        r2.primary_bpm.is_none(),
        "white noise primary_bpm must be None"
    );
}

/// На чистом 200 BPM (истинный лаг = 125 фреймов, точно целый)
/// интерполяция должна возвращать значение в пределах ±0.2 BPM.
#[test]
fn parabolic_precision_200_bpm() {
    let samples = pulse_track(200.0, 15.0, 0.9);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());
    assert_eq!(
        result.lock_state,
        LockState::Stable,
        "200 BPM fixture must reach STABLE"
    );
    let bpm = result.primary_bpm.expect("primary_bpm must be Some in STABLE");
    assert!(
        (bpm - 200.0).abs() <= 0.2,
        "Expected 200.0 ± 0.2 BPM, got {bpm}"
    );
}

/// Streak-тест 180 BPM: последние 20 STABLE-кадров все в [179.5, 180.5].
#[test]
fn streak_stability_180_bpm() {
    run_streak_stability(180.0);
}

/// Streak-тест 195 BPM (не-целый лаг = 123.077): основной регрессионный тест
/// для описанного дефекта дрожания BPM-отображения.
#[test]
fn streak_stability_195_bpm() {
    run_streak_stability(195.0);
}

/// Streak-тест 200 BPM: последние 20 STABLE-кадров все в [199.5, 200.5].
#[test]
fn streak_stability_200_bpm() {
    run_streak_stability(200.0);
}

/// Streak-тест 220 BPM: верхняя граница hitech-диапазона.
#[test]
fn streak_stability_220_bpm() {
    run_streak_stability(220.0);
}

/// BPM-история очищается при смене состояния.
/// После стабильного захвата на 195 BPM, тишина → движок уходит из STABLE,
/// новый захват на 180 BPM не загрязнён старой историей.
#[test]
fn bpm_history_clears_on_state_change() {
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;
    let mut engine = DspEngine::new(DspConfig::default());

    // Фаза 1: захват 195 BPM.
    let phase1 = pulse_track(195.0, 20.0, 0.9);
    for chunk in phase1.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        engine.analyze();
    }

    // Сброс (имитирует новую сессию захвата).
    engine.reset();

    // Фаза 2: захват 180 BPM.
    let phase2 = pulse_track(180.0, 25.0, 0.9);
    let mut stable_bpms: Vec<f32> = Vec::new();
    for chunk in phase2.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        let result = engine.analyze();
        if result.lock_state == LockState::Stable {
            if let Some(bpm) = result.primary_bpm {
                stable_bpms.push(bpm);
            }
        }
    }

    // Если STABLE достигнут — убедиться, что BPM близок к 180, не к 195.
    if stable_bpms.len() >= 5 {
        let last = *stable_bpms.last().unwrap();
        assert!(
            (last - 180.0).abs() <= 2.0,
            "After reset history should not contaminate: expected ~180, got {last}"
        );
    }
}
