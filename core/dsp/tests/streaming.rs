mod common;

use common::{noisy_pulse, pulse_track, unstable_club_simulation, SAMPLE_RATE};
use hitech_bpm_dsp::{DspConfig, DspEngine, LockState, NoiseLevel};

/// Тайминг первого захвата — после покадровой подачи чистого импульса 200 BPM
/// движок обязан покинуть `SEARCHING` в течение `config.lock_min_seconds`
/// (по умолчанию 6 с) аудио.
#[test]
fn streaming_first_lock_under_six_seconds_for_200_bpm() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize; // 100 мс
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

/// Тайминг стабильного захвата — подать до `stable_min_seconds` аудио и
/// потребовать от движка достижения `STABLE` с `primary_bpm` в пределах ±2 BPM
/// от эталона.
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

/// Смена темпа на середине стрима — конкатенировать 12 с импульса 180 BPM
/// с 12 с импульса 200 BPM и покадрово подать весь 24-секундный стрим.
///
/// Проверяет:
/// 1. К концу первого сегмента движок сообщает ~180 BPM и STABLE.
/// 2. После перехода `primary_bpm` достигает ~200 BPM в течение одного
///    окна анализа (`analysis_window_seconds`).
/// 3. Состояние захвата проходит через не-STABLE состояние во время
///    изменения — движок не меняет молча один BPM на другой,
///    оставаясь при этом в STABLE.
#[test]
fn streaming_reflects_mid_stream_tempo_change_within_one_window() {
    let config = DspConfig::default();
    let window_sec = config.analysis_window_seconds;
    let segment_sec = window_sec; // 12 с каждого темпа
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

// ─────────────────────────────────────────────────────────────────────────────
// Phase 4.2 — тесты адаптивного сглаживания огибающей (club-mic low-pass)
// ─────────────────────────────────────────────────────────────────────────────

/// Фикстура `noisy_pulse` имеет `noise_level == High` (а не NoiseOnly или Medium).
/// Это предусловие для адаптивного сглаживания: тест проверяет, что фикстура
/// создана с правильной амплитудой шума.
#[test]
fn noisy_pulse_fixture_has_high_noise_level() {
    use hitech_bpm_dsp::analyze_pcm;
    // noise_amplitude=0.60: после нормализации к 0.9 peak, RMS > 0.18 → High.
    let samples = noisy_pulse(200.0, 14.0, 0.60, 0xABCD);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());
    assert_eq!(
        result.signal_quality.noise_level,
        NoiseLevel::High,
        "noisy_pulse(0.60) должен давать noise_level=High, получено {:?}",
        result.signal_quality.noise_level
    );
}

/// Потоковый движок должен достичь STABLE на шумном консистентном темпе
/// внутри 16 секунд (допуск +4 с сверх стандартного stable_min_seconds=12 с
/// для шумного входа). Это проверяет, что адаптивное сглаживание не только
/// не ломает детекцию, но и позволяет движку сохранять захват в условиях шума.
#[test]
fn streaming_noisy_consistent_tempo_reaches_stable() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;
    // noise_amplitude=0.60 → noise_level=High → активирует адаптивное
    // сглаживание огибающей после первого LOCKING.
    let samples = noisy_pulse(200.0, 18.0, 0.60, 0xCAFE_1234);

    let mut engine = DspEngine::new(config);
    let mut stable_at: Option<f32> = None;
    let mut final_bpm: Option<f32> = None;
    let mut fed = 0usize;

    for chunk in samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_sec = fed as f32 / SAMPLE_RATE as f32;
        let result = engine.analyze();
        final_bpm = result.primary_bpm;
        if matches!(result.lock_state, LockState::Stable) && stable_at.is_none() {
            stable_at = Some(elapsed_sec);
        }
    }

    // Шумной фикстуре разрешаем +4 с сверх стандартного stable_min_seconds.
    let max_stable_sec = config.stable_min_seconds + 4.0;
    let stable_time = stable_at.expect(
        "потоковый движок должен достичь STABLE на шумном 200 BPM в пределах окна",
    );
    assert!(
        stable_time <= max_stable_sec,
        "STABLE на шумной фикстуре получен в {stable_time:.2}s, ожидалось <= {max_stable_sec}s"
    );
    // BPM должен быть в ±3 BPM (шире допуска ±1 для чистой синтетики).
    let bpm = final_bpm.expect("primary_bpm должен быть установлен при STABLE");
    assert!(
        (bpm - 200.0).abs() <= 3.0,
        "noisy 200 BPM: primary_bpm={bpm:.1}, ожидалось 200 ±3"
    );
}

/// Антифейк-инвариант Phase 4.2: `unstable_club_simulation` через потоковый
/// движок никогда не должна достигать STABLE — даже если `prev_lock_state`
/// гипотетически становится LOCKING при первых вызовах.
///
/// Сглаживание гейтировано на `noise_level == High`. Нестабильная симуляция
/// имеет случайный темп → `prev_lock_state` никогда не достигает LOCKING/STABLE
/// → сглаживание не применяется → anti-fake-инвариант сохраняется.
#[test]
fn streaming_unstable_club_simulation_never_reaches_stable() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;
    let samples = unstable_club_simulation(18.0);

    let mut engine = DspEngine::new(config);
    let mut ever_stable = false;
    let mut ever_locking = false;

    for chunk in samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        let result = engine.analyze();
        if matches!(result.lock_state, LockState::Stable) {
            ever_stable = true;
        }
        if matches!(result.lock_state, LockState::Locking) {
            ever_locking = true;
        }
    }

    assert!(!ever_stable,
        "unstable_club_simulation не должна достигать STABLE в потоковом режиме — \
         сглаживание могло создать ложную периодичность"
    );
    // Движок может кратко видеть LOCKING — это допустимо при случайном
    // совпадении двух ударов, но не STABLE.
    let _ = ever_locking; // информационный, не assertion
}

/// `DspEngine::reset()` сбрасывает `prev_lock_state`, чтобы следующая сессия
/// начинала без истории предыдущей. Если не сбросить, сглаживание может
/// применяться на чистом старте, когда нет доказательства темпа.
#[test]
fn streaming_reset_clears_prev_lock_state() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;
    let mut engine = DspEngine::new(config);

    // Накапливаем историю: доводим до LOCKING/STABLE.
    for chunk in pulse_track(200.0, 14.0, 0.9).chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        let _ = engine.analyze();
    }

    // После reset — новая сессия с чистым состоянием.
    engine.reset();

    // Сразу после reset анализ на пустом буфере должен вернуть SEARCHING,
    // что означает prev_lock_state = None и нет сглаживания.
    let result = engine.analyze();
    assert_eq!(
        result.lock_state,
        LockState::Searching,
        "после reset() движок обязан вернуться в SEARCHING"
    );
    assert_eq!(result.primary_bpm, None, "после reset() primary_bpm должен быть null");
}
