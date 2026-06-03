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

        if elapsed_sec <= transition_sec - 0.5 && matches!(result.lock_state, LockState::Stable) {
            pre_change_bpm = result.primary_bpm;
            pre_change_lock = Some(result.lock_state);
        }

        if elapsed_sec > transition_sec + 0.5
            && elapsed_sec <= transition_sec + window_sec
            && !matches!(result.lock_state, LockState::Stable)
        {
            left_stable_during_change = true;
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
// Phase 8 — fast re-lock после смены трека
// ─────────────────────────────────────────────────────────────────────────────

/// Быстрый перезахват после потери STABLE при смене темпа — базовый тест.
///
/// Сценарий:
///   1. Движок достигает STABLE на 200 BPM (≤ 12 с).
///   2. Подаётся 180 BPM — новый трек.
///   3. Измеряется время от первого не-STABLE кадра до достижения
///      надёжного LOCKING или нового STABLE.
///
/// Цель v2: перезахват (LOCKING или STABLE с ~180 BPM) в пределах 3 секунд
/// после первого не-STABLE кадра. Adaptive-window + discontinuity detector
/// ускоряют перезахват до ≤ 3 с (было ≤ 4 с в v1).
///
/// Anti-fake: BPM берётся из DSP-evidence; тест не хардкодит BPM.
#[test]
fn streaming_re_lock_baseline() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize; // 100 мс

    // Сегмент 1: достаточно для STABLE (≥ stable_min_seconds).
    let mut samples = pulse_track(200.0, config.stable_min_seconds + 2.0, 0.9);
    // Сегмент 2: новый трек — 180 BPM. Даём 8 секунд, ожидаем LOCKING за 3.
    samples.extend(pulse_track(180.0, 8.0, 0.9));

    let transition_sample =
        ((config.stable_min_seconds + 2.0) * SAMPLE_RATE as f32) as usize;

    let mut engine = DspEngine::new(config);
    let mut fed = 0usize;

    // Фаза 1: прогоняем первый сегмент до STABLE.
    let mut reached_stable = false;
    for chunk in samples[..transition_sample].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let result = engine.analyze();
        if matches!(result.lock_state, LockState::Stable) {
            reached_stable = true;
        }
    }
    assert!(
        reached_stable,
        "движок должен достичь STABLE на 200 BPM до начала теста re-lock"
    );

    // Фаза 2: подаём новый трек (180 BPM), отсчитываем время с первого
    // не-STABLE кадра.
    let mut first_non_stable_at: Option<f32> = None;
    let mut relock_at: Option<f32> = None; // LOCKING или STABLE с ~180 BPM

    for chunk in samples[transition_sample..].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_total = fed as f32 / SAMPLE_RATE as f32;
        let result = engine.analyze();

        if first_non_stable_at.is_none() && !matches!(result.lock_state, LockState::Stable) {
            first_non_stable_at = Some(elapsed_total);
        }

        if let Some(t0) = first_non_stable_at {
            let since_loss = elapsed_total - t0;
            if relock_at.is_none()
                && matches!(
                    result.lock_state,
                    LockState::Locking | LockState::Stable
                )
                && result.primary_bpm.is_some_and(|bpm| (bpm - 180.0).abs() <= 4.0)
            {
                relock_at = Some(since_loss);
            }
        }
    }

    let first_loss = first_non_stable_at
        .expect("движок должен покинуть STABLE после смены темпа с 200 на 180 BPM");
    let _ = first_loss; // информационный

    let relock_time = relock_at.expect(
        "движок должен достичь LOCKING/STABLE на ~180 BPM после смены трека",
    );
    assert!(
        relock_time <= 3.0,
        "fast re-lock на 180 BPM занял {relock_time:.2}s после потери STABLE \
         (ожидалось ≤ 3.0s с v2 adaptive window)"
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

// ─────────────────────────────────────────────────────────────────────────────
// Phase 8 v2 — диагностика тайминга и structured re-lock тесты
// ─────────────────────────────────────────────────────────────────────────────

/// Диагностический тест тайминга смены темпа 185 → 200 BPM.
///
/// Замеряет три события:
/// 1. Когда топ-кандидат сменился с ~185 на ~200 BPM (> 5 BPM разница).
///    Должно быть ≤ 2.5 с после T=8s.
/// 2. Когда движок достиг LOCKING на новом темпе.
///    Должно быть ≤ 3.0 с после T=8s.
/// 3. Отсутствие ложного STABLE с BPM > 8 BPM от 200.0 в период T=8s..T=11s.
#[test]
fn tempo_change_timing_diagnosis() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;

    let segment1_secs = 8.0_f32;
    let segment2_secs = 8.0_f32;
    let mut samples = pulse_track(185.0, segment1_secs, 0.9);
    samples.extend(pulse_track(200.0, segment2_secs, 0.9));

    let transition_sample = (segment1_secs * SAMPLE_RATE as f32) as usize;
    let transition_sec = segment1_secs;

    let mut engine = DspEngine::new(config);
    let mut fed = 0usize;

    // Фаза 1: прогоняем 185 BPM сегмент.
    for chunk in samples[..transition_sample].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let _ = engine.analyze();
    }

    // Фаза 2: подаём 200 BPM, замеряем события.
    let mut candidate_changed_at: Option<f32> = None;
    let mut locking_on_new_at: Option<f32> = None;
    let mut false_stable_found = false;

    for chunk in samples[transition_sample..].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_total = fed as f32 / SAMPLE_RATE as f32;
        let since_transition = elapsed_total - transition_sec; // используется ниже
        let result = engine.analyze();

        // Событие 1: топ-кандидат сменился на ~200 BPM.
        if candidate_changed_at.is_none() {
            let top_bpm = result.candidates.iter()
                .find(|c| matches!(c.relation, hitech_bpm_dsp::TempoRelation::Main | hitech_bpm_dsp::TempoRelation::Raw))
                .map(|c| c.bpm);
            if let Some(bpm) = top_bpm {
                if (bpm - 200.0).abs() <= 5.0 && (bpm - 185.0).abs() > 5.0 {
                    candidate_changed_at = Some(since_transition);
                }
            }
        }

        // Событие 2: LOCKING на новом темпе.
        if locking_on_new_at.is_none()
            && matches!(result.lock_state, LockState::Locking | LockState::Stable)
            && result.primary_bpm.is_some_and(|bpm| (bpm - 200.0).abs() <= 4.0)
        {
            locking_on_new_at = Some(since_transition);
        }

        // Событие 3: ложный STABLE (BPM далеко от ОБОИХ темпов) в первые 3 с.
        // Допускаем: STABLE на ~185 (удержание старого темпа) — нормально.
        // Допускаем: STABLE на ~200 (уже захватил новый темп) — нормально.
        // Запрещаем: STABLE на BPM далёком от обоих (галлюцинация).
        if since_transition <= 3.0
            && matches!(result.lock_state, LockState::Stable)
            && result.primary_bpm.is_some_and(|bpm| {
                (bpm - 200.0).abs() > 8.0 && (bpm - 185.0).abs() > 8.0
            })
        {
            false_stable_found = true;
        }
    }

    // Допускаем что кандидат мог не поменяться (тест диагностический),
    // но если поменялся — должен был сделать это быстро.
    if let Some(t) = candidate_changed_at {
        assert!(
            t <= 2.5,
            "топ-кандидат сменился на ~200 BPM через {t:.2}s после перехода (ожидалось ≤ 2.5s)"
        );
    }

    let locking_time = locking_on_new_at
        .expect("движок должен достичь LOCKING на ~200 BPM после перехода от 185");
    assert!(
        locking_time <= 3.0,
        "LOCKING на 200 BPM через {locking_time:.2}s (ожидалось ≤ 3.0s)"
    );

    assert!(
        !false_stable_found,
        "обнаружен ложный STABLE с BPM далёким от обоих темпов в первые 3 с после перехода"
    );
}

/// Re-lock: 185 BPM → 200 BPM.
///
/// После первого не-STABLE кадра LOCKING или STABLE на ~200 BPM
/// должен быть достигнут за ≤ 3.0 с. Никакого ложного STABLE на ~185 BPM
/// в переходный период.
#[test]
fn tempo_change_185_to_200() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;

    let stable_secs = config.stable_min_seconds + 2.0;
    let mut samples = pulse_track(185.0, stable_secs, 0.9);
    samples.extend(pulse_track(200.0, 8.0, 0.9));

    let transition_sample = (stable_secs * SAMPLE_RATE as f32) as usize;

    let mut engine = DspEngine::new(config);
    let mut fed = 0usize;
    let mut reached_stable_185 = false;

    // Фаза 1: ждём STABLE на 185 BPM.
    for chunk in samples[..transition_sample].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let result = engine.analyze();
        if matches!(result.lock_state, LockState::Stable)
            && result.primary_bpm.is_some_and(|bpm| (bpm - 185.0).abs() <= 4.0)
        {
            reached_stable_185 = true;
        }
    }
    assert!(reached_stable_185, "движок должен достичь STABLE на 185 BPM");

    let mut first_non_stable_at: Option<f32> = None;
    let mut relock_at: Option<f32> = None;
    let mut false_stable_185 = false;

    for chunk in samples[transition_sample..].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_total = fed as f32 / SAMPLE_RATE as f32;
        let result = engine.analyze();

        if first_non_stable_at.is_none() && !matches!(result.lock_state, LockState::Stable) {
            first_non_stable_at = Some(elapsed_total);
        }

        if let Some(t0) = first_non_stable_at {
            let since_loss = elapsed_total - t0;

            // Ложный STABLE на старом темпе в переходный период.
            if since_loss <= 3.0
                && matches!(result.lock_state, LockState::Stable)
                && result.primary_bpm.is_some_and(|bpm| (bpm - 185.0).abs() <= 4.0)
            {
                false_stable_185 = true;
            }

            if relock_at.is_none()
                && matches!(result.lock_state, LockState::Locking | LockState::Stable)
                && result.primary_bpm.is_some_and(|bpm| (bpm - 200.0).abs() <= 4.0)
            {
                relock_at = Some(since_loss);
            }
        }
    }

    assert!(
        !false_stable_185,
        "ложный STABLE на ~185 BPM в первые 3 с переходного периода"
    );

    let relock_time = relock_at
        .expect("движок должен достичь LOCKING/STABLE на ~200 BPM после смены 185→200");
    assert!(
        relock_time <= 3.0,
        "re-lock на 200 BPM занял {relock_time:.2}s (ожидалось ≤ 3.0s)"
    );
}

/// Re-lock: 200 BPM → 170 BPM.
///
/// Проверяет что:
/// 1. Re-lock за ≤ 3.0 с.
/// 2. Hitech-нормализация работает: 170 BPM (не 85 BPM) детектируется.
#[test]
fn tempo_change_200_to_170() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;

    let stable_secs = config.stable_min_seconds + 2.0;
    let mut samples = pulse_track(200.0, stable_secs, 0.9);
    samples.extend(pulse_track(170.0, 8.0, 0.9));

    let transition_sample = (stable_secs * SAMPLE_RATE as f32) as usize;
    let transition_sec = stable_secs;

    let mut engine = DspEngine::new(config);
    let mut fed = 0usize;
    let mut reached_stable_200 = false;

    for chunk in samples[..transition_sample].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let result = engine.analyze();
        if matches!(result.lock_state, LockState::Stable) {
            reached_stable_200 = true;
        }
    }
    assert!(reached_stable_200, "движок должен достичь STABLE на 200 BPM");

    let mut first_non_stable_at: Option<f32> = None;
    let mut relock_at: Option<f32> = None;

    for chunk in samples[transition_sample..].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_total = fed as f32 / SAMPLE_RATE as f32;
        let _since_transition = elapsed_total - transition_sec;
        let result = engine.analyze();

        if first_non_stable_at.is_none() && !matches!(result.lock_state, LockState::Stable) {
            first_non_stable_at = Some(elapsed_total);
        }

        if let Some(t0) = first_non_stable_at {
            let since_loss = elapsed_total - t0;
            if relock_at.is_none()
                && matches!(result.lock_state, LockState::Locking | LockState::Stable)
                && result.primary_bpm.is_some_and(|bpm| {
                    // 170 BPM (не 85 — hitech нормализация)
                    (bpm - 170.0).abs() <= 4.0 && bpm > 100.0
                })
            {
                relock_at = Some(since_loss);
            }
        }
    }

    let relock_time = relock_at
        .expect("движок должен достичь LOCKING/STABLE на ~170 BPM после смены 200→170");
    assert!(
        relock_time <= 3.0,
        "re-lock на 170 BPM занял {relock_time:.2}s (ожидалось ≤ 3.0s)"
    );
}

/// Стабильность после re-lock: 20 подряд идущих STABLE-кадров с BPM в ±2 BPM.
///
/// Быстрый перезахват не должен жертвовать стабильностью — после re-lock
/// движок удерживает STABLE без осцилляций.
#[test]
fn stability_after_tempo_change() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;

    let stable_secs = config.stable_min_seconds + 2.0;
    // Даём 16 с нового трека — достаточно для повторного STABLE и наблюдения.
    let new_secs = 16.0;
    let mut samples = pulse_track(200.0, stable_secs, 0.9);
    samples.extend(pulse_track(185.0, new_secs, 0.9));

    let transition_sample = (stable_secs * SAMPLE_RATE as f32) as usize;

    let mut engine = DspEngine::new(config);

    for chunk in samples[..transition_sample].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        let _ = engine.analyze();
    }

    let mut consecutive_stable = 0u32;
    let required_consecutive = 20;

    for chunk in samples[transition_sample..].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        let result = engine.analyze();

        if matches!(result.lock_state, LockState::Stable)
            && result.primary_bpm.is_some_and(|bpm| (bpm - 185.0).abs() <= 2.0)
        {
            consecutive_stable += 1;
        } else if consecutive_stable > 0 && !matches!(result.lock_state, LockState::Stable) {
            // Прерывание — сбрасываем счётчик.
            consecutive_stable = 0;
        }

        if consecutive_stable >= required_consecutive {
            break;
        }
    }

    assert!(
        consecutive_stable >= required_consecutive,
        "движок не набрал {required_consecutive} подряд идущих STABLE-кадров на ~185 BPM \
         после re-lock (набрано: {consecutive_stable})"
    );
}

/// Нет ложного STABLE в переходный период 200 → 185 BPM.
///
/// В первые 3 с после смены темпа не должно быть STABLE с BPM,
/// отличающимся > 8 BPM от обоих темпов (ни 200, ни 185 BPM).
#[test]
fn no_false_stable_during_transition() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;

    let stable_secs = config.stable_min_seconds + 2.0;
    let mut samples = pulse_track(200.0, stable_secs, 0.9);
    samples.extend(pulse_track(185.0, 8.0, 0.9));

    let transition_sample = (stable_secs * SAMPLE_RATE as f32) as usize;
    let transition_sec = stable_secs;

    let mut engine = DspEngine::new(config);
    let mut fed = 0usize;

    for chunk in samples[..transition_sample].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let _ = engine.analyze();
    }

    let mut false_stable_found = false;
    let mut first_non_stable_at: Option<f32> = None;

    for chunk in samples[transition_sample..].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_total = fed as f32 / SAMPLE_RATE as f32;
        let since_transition = elapsed_total - transition_sec;
        let result = engine.analyze();

        if first_non_stable_at.is_none() && !matches!(result.lock_state, LockState::Stable) {
            first_non_stable_at = Some(elapsed_total);
        }

        // Проверяем только первые 3 с после начала перехода.
        if let Some(t0) = first_non_stable_at {
            let since_loss = elapsed_total - t0;
            if since_loss <= 3.0 && matches!(result.lock_state, LockState::Stable) {
                if let Some(bpm) = result.primary_bpm {
                    // Допустимо: BPM близко к 200.0 ИЛИ близко к 185.0.
                    let near_200 = (bpm - 200.0).abs() <= 8.0;
                    let near_185 = (bpm - 185.0).abs() <= 8.0;
                    if !near_200 && !near_185 {
                        false_stable_found = true;
                    }
                }
            }
        }

        // Выходим после первых 3 с переходного периода.
        if first_non_stable_at.is_some()
            && since_transition > 3.0
        {
            break;
        }
    }

    assert!(
        !false_stable_found,
        "ложный STABLE с BPM > 8 BPM от обоих темпов в первые 3 с перехода 200→185"
    );
}

/// Fallback при `adaptive_window = false`: поведение совпадает с v1 (≤ 4 с).
///
/// При отключённом адаптивном окне движок должен перезахватиться за ≤ 4 с
/// (старая гарантия), но не обязательно за ≤ 3 с.
#[test]
fn adaptive_window_disabled_falls_back_to_baseline() {
    use hitech_bpm_dsp::DspConfig;
    let config = DspConfig { adaptive_window: false, ..DspConfig::default() };
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;

    let stable_secs = config.stable_min_seconds + 2.0;
    let mut samples = pulse_track(200.0, stable_secs, 0.9);
    samples.extend(pulse_track(180.0, 8.0, 0.9));

    let transition_sample = (stable_secs * SAMPLE_RATE as f32) as usize;

    let mut engine = DspEngine::new(config);
    let mut fed = 0usize;
    let mut reached_stable = false;

    for chunk in samples[..transition_sample].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let result = engine.analyze();
        if matches!(result.lock_state, LockState::Stable) {
            reached_stable = true;
        }
    }
    assert!(reached_stable, "движок должен достичь STABLE с adaptive_window=false");

    let mut first_non_stable_at: Option<f32> = None;
    let mut relock_at: Option<f32> = None;

    for chunk in samples[transition_sample..].chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_total = fed as f32 / SAMPLE_RATE as f32;
        let result = engine.analyze();

        if first_non_stable_at.is_none() && !matches!(result.lock_state, LockState::Stable) {
            first_non_stable_at = Some(elapsed_total);
        }

        if let Some(t0) = first_non_stable_at {
            let since_loss = elapsed_total - t0;
            if relock_at.is_none()
                && matches!(result.lock_state, LockState::Locking | LockState::Stable)
                && result.primary_bpm.is_some_and(|bpm| (bpm - 180.0).abs() <= 4.0)
            {
                relock_at = Some(since_loss);
            }
        }
    }

    let relock_time = relock_at
        .expect("движок с adaptive_window=false должен достичь LOCKING/STABLE на ~180 BPM");
    assert!(
        relock_time <= 4.0,
        "re-lock с adaptive_window=false занял {relock_time:.2}s (ожидалось ≤ 4.0s)"
    );
}

// ─────────────────────────────────────────────────────────────────────────────

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

/// Проверяет: после tempo jump движок не застревает в бесконечном SEARCHING
/// из-за feedback loop в jump-детекторе, и SEARCHING всегда имеет null BPM.
///
/// Сценарий: 200 BPM (STABLE) → 6 с 175 BPM (дельта 25 > threshold 15)
/// → jump детектирован → force_next_searching → last_stable_bpm сброшен
/// → нормальная прогрессия SEARCHING→LOCKING.
///
/// Инварианты:
/// 1. В первые 2 с перехода: нет STABLE с BPM, далёким от обоих темпов (артефакт).
/// 2. Anti-fake: при SEARCHING primary_bpm == null (всегда).
/// 3. Движок покидает STABLE в течение всего окна 6 с (не застревает).
///
/// Временны́е тайминги "≤ 3 с → нет старого BPM" покрыты тестом
/// `tempo_change_200_to_170`, который тестирует re-lock с длинным треком.
#[test]
fn force_next_searching_overrides_stable_on_tempo_jump() {
    let config = DspConfig::default(); // adaptive_window: true, tempo_jump_threshold: 15.0
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize; // 100 мс
    let mut engine = DspEngine::new(config);

    // Шаг 1: захватить STABLE на 200 BPM.
    let track_a = pulse_track(200.0, 14.0, 0.9);
    for chunk in track_a.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
    }
    let pre = engine.analyze();
    assert_eq!(
        pre.lock_state,
        LockState::Stable,
        "движок должен выйти на STABLE перед тестом jump"
    );

    // Шаг 2: подать 6 с нового трека (175 BPM, дельта 25 > threshold 15).
    // Дельта 25 > 15.0 → jump detector должен сработать после ~2–3 с.
    // После jump: last_stable_bpm = None, bpm_history очищен, force_next_searching = true.
    // Следующий кадр → SEARCHING. Нет feedback loop: next candidate ≠ cleared last_stable_bpm.
    let track_b = pulse_track(175.0, 6.0, 0.9);

    let mut found_false_stable = false;
    let mut ever_left_stable = false;

    for (i, chunk) in track_b.chunks(chunk_size).enumerate() {
        engine.push_samples(chunk, SAMPLE_RATE);
        let r = engine.analyze();
        let elapsed_sec = (i + 1) as f32 * 0.1;

        // Anti-fake инвариант: SEARCHING всегда имеет primary_bpm == null.
        if r.lock_state == LockState::Searching {
            assert_eq!(
                r.primary_bpm, None,
                "SEARCHING кадр должен иметь primary_bpm = null (anti-fake)"
            );
        }

        // Инвариант 1: в первые 2 с перехода нет STABLE с BPM,
        // далёким от обоих корректных темпов (не ~200 и не ~175).
        if elapsed_sec <= 2.0 && r.lock_state == LockState::Stable {
            if let Some(bpm) = r.primary_bpm {
                let close_to_old = (bpm - 200.0).abs() < 8.0;
                let close_to_new = (bpm - 175.0).abs() < 8.0;
                if !close_to_old && !close_to_new {
                    found_false_stable = true;
                }
            }
        }

        // Инвариант 3: движок должен покинуть STABLE хотя бы раз за 6 с.
        // Это проверяет отсутствие feedback loop (не застревает в вечном STABLE).
        if !matches!(r.lock_state, LockState::Stable) {
            ever_left_stable = true;
        }
    }

    assert!(
        !found_false_stable,
        "в переходном периоде не должно быть STABLE с BPM за пределами диапазона обоих треков"
    );
    assert!(
        ever_left_stable,
        "движок должен покинуть STABLE после смены темпа 200→175 BPM в течение 6 с \
         (нет feedback loop в jump-детекторе)"
    );
}

/// При первом захвате (has_ever_been_stable == false) движок должен
/// достигать STABLE в пределах stable_min_seconds — даже при включённом
/// адаптивном окне.
///
/// Регрессионный тест для фикса Phase 8: до фикса adaptive_window обрезал
/// onset_history до 2 с при SEARCHING, что при первом захвате давало лишь
/// 5–8 ударов → уверенность < 0.72 → LOCKING не переходил в STABLE.
#[test]
fn first_lock_uses_full_window_no_prior_stable() {
    let config = DspConfig {
        adaptive_window: true, // включено явно — проверяем именно этот путь
        ..DspConfig::default()
    };
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize; // 100 мс
    let samples = pulse_track(200.0, config.stable_min_seconds, 0.9);

    let mut engine = DspEngine::new(config);
    let mut stable_at: Option<f32> = None;
    let mut fed = 0usize;

    for chunk in samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_sec = fed as f32 / SAMPLE_RATE as f32;
        let result = engine.analyze();
        if matches!(result.lock_state, LockState::Stable) && stable_at.is_none() {
            stable_at = Some(elapsed_sec);
        }
    }

    let stable_time = stable_at.expect(
        "движок обязан достичь STABLE на чистом 200 BPM пульсе при первом захвате \
         (регрессия: adaptive_window 2 с при SEARCHING блокировал first lock)",
    );
    assert!(
        stable_time <= config.stable_min_seconds,
        "первый захват STABLE на {stable_time:.2}s превысил stable_min_seconds={}s",
        config.stable_min_seconds
    );
}

/// Ре-лок после смены трека по-прежнему происходит за ≤ 3 с при включённом
/// адаптивном окне — проверяем, что фикс has_ever_been_stable не сломал
/// быстрый повторный захват.
#[test]
fn relock_adaptive_window_still_fast_after_stable() {
    let config = DspConfig::default(); // adaptive_window: true
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;
    let mut engine = DspEngine::new(config);

    // Шаг 1: захватить STABLE на 180 BPM (~14 с достаточно).
    for chunk in pulse_track(180.0, 14.0, 0.9).chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
    }
    let pre = engine.analyze();
    assert_eq!(
        pre.lock_state,
        LockState::Stable,
        "движок должен достичь STABLE на 180 BPM перед тестом ре-лока"
    );

    // Шаг 2: подать новый трек 200 BPM и замерить время до следующего STABLE.
    let relock_budget_sec = 3.0_f32;
    let relock_samples = pulse_track(200.0, relock_budget_sec + 2.0, 0.9);
    let mut relocked_at: Option<f32> = None;
    let mut fed = 0usize;

    for chunk in relock_samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_sec = fed as f32 / SAMPLE_RATE as f32;
        let result = engine.analyze();
        if let Some(bpm) = result.primary_bpm {
            if matches!(result.lock_state, LockState::Stable)
                && (bpm - 200.0).abs() <= 3.0
                && relocked_at.is_none()
            {
                relocked_at = Some(elapsed_sec);
            }
        }
    }

    let relock_time = relocked_at.expect(
        "движок должен перезахватить 200 BPM после смены трека с 180 BPM \
         (adaptive_window должен по-прежнему ускорять ре-лок)",
    );
    assert!(
        relock_time <= relock_budget_sec,
        "ре-лок занял {relock_time:.2}s, превысив бюджет {relock_budget_sec}s — \
         адаптивное окно перестало работать после фикса has_ever_been_stable"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// v1.0.0 pre-release — coverage expansion
// ─────────────────────────────────────────────────────────────────────────────

/// Тайминг первого захвата для 170 BPM (нижняя граница hitech-диапазона).
/// Аналог streaming_first_lock_under_six_seconds_for_200_bpm.
#[test]
fn streaming_first_lock_170_bpm() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;
    let samples = pulse_track(170.0, config.lock_min_seconds, 0.9);

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
        .expect("engine must leave SEARCHING on a clean 170 BPM pulse");
    assert!(
        lock_time <= config.lock_min_seconds,
        "first lock at {lock_time:.2}s exceeded lock_min_seconds={}s for 170 BPM",
        config.lock_min_seconds
    );
}

/// Тайминг первого захвата для 220 BPM (верхняя граница hitech-диапазона).
/// Аналог streaming_first_lock_under_six_seconds_for_200_bpm.
#[test]
fn streaming_first_lock_220_bpm() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;
    let samples = pulse_track(220.0, config.lock_min_seconds, 0.9);

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
        .expect("engine must leave SEARCHING on a clean 220 BPM pulse");
    assert!(
        lock_time <= config.lock_min_seconds,
        "first lock at {lock_time:.2}s exceeded lock_min_seconds={}s for 220 BPM",
        config.lock_min_seconds
    );
}

/// Breakdown должен выводить из STABLE — подать 8 с чистого 200 BPM (достичь STABLE),
/// затем 4 с тишины. Убедиться что lock_state переходит в BREAKDOWN или UNSTABLE,
/// а не остаётся STABLE с придуманным BPM.
#[test]
fn streaming_breakdown_exits_stable() {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize;

    // Фаза 1: 8 с чистого 200 BPM → достичь STABLE
    let stable_samples = pulse_track(200.0, 8.0, 0.9);
    let mut engine = DspEngine::new(config);

    for chunk in stable_samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
    }
    let pre_breakdown = engine.analyze();
    assert!(
        matches!(pre_breakdown.lock_state, LockState::Stable),
        "engine must reach STABLE before breakdown test"
    );

    // Фаза 2: 4 с тишины (breakdown)
    let silence_samples = vec![0.0_f32; (SAMPLE_RATE as f32 * 4.0) as usize];
    let mut exited_stable = false;

    for chunk in silence_samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        let result = engine.analyze();
        if matches!(result.lock_state, LockState::Breakdown | LockState::Unstable | LockState::Searching) {
            exited_stable = true;
            break;
        }
    }

    assert!(
        exited_stable,
        "engine must exit STABLE on breakdown (silence after stable pulse), not stay STABLE with fake BPM"
    );
}
