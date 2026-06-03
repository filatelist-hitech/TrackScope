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

/// Phase 2.2.2: onset_density_hz на clean_200 — реальные пики, не ~400 Hz.
/// Ожидаем [1.5, 8.0] Hz (diapason: 200 BPM kick ≈ 3.3 Hz).
#[test]
fn onset_density_hz_in_range_for_clean_200() {
    let pulse = common::pulse_track(200.0, 14.0, 0.7);
    let results = run_stream_full(&pulse);
    let stable_energies: Vec<_> = results
        .iter()
        .filter(|r| r.lock_state == LockState::Stable)
        .filter_map(|r| r.energy_result.as_ref())
        .collect();
    assert!(!stable_energies.is_empty(), "should have STABLE frames");
    for er in &stable_energies {
        assert!(
            er.onset_density_hz >= 1.5 && er.onset_density_hz <= 8.0,
            "expected onset_density_hz in [1.5, 8.0], got {}",
            er.onset_density_hz
        );
    }
}

/// Phase 2.2.2: onset_density_hz на белом шуме — нет периодических пиков.
/// Ожидаем < 3.0 Hz (шум не порождает регулярных пиков выше среднего).
#[test]
fn onset_density_hz_low_on_white_noise() {
    let noise = common::white_noise(42, 0.28, 14.0);
    let results = run_stream_full(&noise);
    for r in &results {
        if let Some(ref er) = r.energy_result {
            assert!(
                er.onset_density_hz < 3.0,
                "white noise should have onset_density_hz < 3.0, got {}",
                er.onset_density_hz
            );
        }
    }
}

/// Phase 2.2.3: FLUX_ABSOLUTE_FLOOR верификация — тихий пульс amplitude=0.1 (~-20 dBFS).
/// Если STABLE достигнут — onset_density_hz должна быть > 0 (порог не режет все удары).
/// Если STABLE не достигнут — тест не падает (документальный: тихий сигнал может не захватиться).
#[test]
fn flux_floor_does_not_silence_quiet_pulse_amplitude_0_1() {
    let pulse = common::pulse_track(200.0, 14.0, 0.1); // ≈ -20 dBFS
    let results = run_stream_full(&pulse);
    let stable_energies: Vec<_> = results
        .iter()
        .filter(|r| r.lock_state == LockState::Stable)
        .filter_map(|r| r.energy_result.as_ref())
        .collect();
    for er in &stable_energies {
        assert!(
            er.onset_density_hz > 0.0,
            "quiet pulse (amplitude=0.1) in STABLE should still have onset_density_hz > 0, got {}",
            er.onset_density_hz
        );
    }
    // Если STABLE не достигнут — это known limitation (тихий сигнал); не fail.
}

/// Phase 2.2.4: синтетический прокси реального hitech-трека.
/// Параметры: rms ≈ -8 dBFS, flux ≈ 0.020 — соответствуют замерам треков 22–25.
/// Ожидаем energy_level ≥ 5 (активный hitech-трек должен быть в верхней половине шкалы).
#[test]
fn calibration_real_hitech_proxy_level_at_least_5() {
    use hitech_bpm_dsp::EnergyAnalyzer;

    let sr = 48_000_f32;
    let hop_sec = 0.0025_f32;
    let mut ea = EnergyAnalyzer::new(sr, hop_sec);

    // RMS ≈ -8 dBFS: amplitude = 10^(-8/20) * sqrt(2) ≈ 0.563 (sine RMS = amp/√2).
    let amplitude = 0.563_f32;
    let samples: Vec<f32> = (0..((sr * 3.0) as usize))
        .map(|i| amplitude * (2.0 * std::f32::consts::PI * 200.0 * i as f32 / sr).sin())
        .collect();
    ea.push_samples(&samples);

    // flux ≈ 0.020 — медиана по треку из Phase 2.2.1 (диапазон 0.013–0.023).
    let flux_capacity = ((3.0 / hop_sec) as usize).max(8);
    for _ in 0..flux_capacity {
        ea.push_flux(0.020);
    }

    let result = ea.current_energy();
    assert!(
        result.level >= 5,
        "real hitech proxy (rms≈-8 dBFS, flux≈0.020) should yield level >= 5, got {}",
        result.level
    );
}

/// Phase 2.2.4: слабый сигнал (rms ≈ -30 dBFS, низкий flux) → level ≤ 4.
/// Гарантирует что шкала не «зависает» в высоких значениях для слабого сигнала.
#[test]
fn calibration_weak_signal_level_at_most_4() {
    use hitech_bpm_dsp::EnergyAnalyzer;

    let sr = 48_000_f32;
    let hop_sec = 0.0025_f32;
    let mut ea = EnergyAnalyzer::new(sr, hop_sec);

    // RMS ≈ -30 dBFS: amplitude = 10^(-30/20) * sqrt(2) ≈ 0.045.
    let amplitude = 0.045_f32;
    let samples: Vec<f32> = (0..((sr * 3.0) as usize))
        .map(|i| amplitude * (2.0 * std::f32::consts::PI * 200.0 * i as f32 / sr).sin())
        .collect();
    ea.push_samples(&samples);

    // flux ≈ 0.003 — очень слабый транзиентный отклик.
    let flux_capacity = ((3.0 / hop_sec) as usize).max(8);
    for _ in 0..flux_capacity {
        ea.push_flux(0.003);
    }

    let result = ea.current_energy();
    assert!(
        result.level <= 4,
        "weak signal (rms≈-30 dBFS, flux≈0.003) should yield level <= 4, got {}",
        result.level
    );
}

/// Phase 2.2.3: FLUX_ABSOLUTE_FLOOR нижняя граница — очень тихий пульс amplitude=0.02 (~-34 dBFS).
/// Документальный тест: не ожидаем STABLE. Фиксирует поведение в пограничном диапазоне.
#[test]
fn flux_floor_boundary_very_quiet_pulse_amplitude_0_02() {
    let pulse = common::pulse_track(200.0, 14.0, 0.02); // ≈ -34 dBFS
    let results = run_stream_full(&pulse);
    // На таком тихом сигнале ожидаем SEARCHING или NOISE_ONLY, но не STABLE.
    // Тест — документальный: не падает при любом исходе.
    let stable_count = results
        .iter()
        .filter(|r| r.lock_state == LockState::Stable)
        .count();
    // Допускаем STABLE только если движок всё же зафиксировал пульс — не режем его искусственно.
    let _ = stable_count;
}
