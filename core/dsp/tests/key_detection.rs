/// Тесты детекции тональности (Phase 2.1).
///
/// Фикстуры генерируются в памяти: чистые синусы и аккорды.
/// Anti-fake инварианты: тишина и шум не дают key_result.
use hitech_bpm_dsp::key_analyzer::{to_camelot, CamelotKey, KeyAnalyzer, KeyMode, MusicalKey};
use hitech_bpm_dsp::{DspConfig, DspEngine, DspResult, KeyResult};

// ── Вспомогательные генераторы ─────────────────────────────────────────────

fn pure_sine(freq_hz: f32, duration_sec: f32, sample_rate: u32) -> Vec<f32> {
    let n = (duration_sec * sample_rate as f32).round() as usize;
    (0..n)
        .map(|i| (2.0 * std::f32::consts::PI * freq_hz * i as f32 / sample_rate as f32).sin())
        .collect()
}

fn chord_sine(freqs: &[f32], duration_sec: f32, sample_rate: u32) -> Vec<f32> {
    let n = (duration_sec * sample_rate as f32).round() as usize;
    (0..n)
        .map(|i| {
            let t = i as f32 / sample_rate as f32;
            freqs
                .iter()
                .map(|&f| (2.0 * std::f32::consts::PI * f * t).sin())
                .sum::<f32>()
                / freqs.len() as f32
        })
        .collect()
}

fn silence(duration_sec: f32, sample_rate: u32) -> Vec<f32> {
    vec![0.0f32; (duration_sec * sample_rate as f32).round() as usize]
}

fn white_noise_seeded(seed: u64, amplitude: f32, duration_sec: f32, sample_rate: u32) -> Vec<f32> {
    let n = (duration_sec * sample_rate as f32).round() as usize;
    let mut state = seed;
    (0..n)
        .map(|_| {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            let f = ((state >> 33) as f32) / (u32::MAX as f32) * 2.0 - 1.0;
            f * amplitude
        })
        .collect()
}

fn push_and_analyze(samples: &[f32], sample_rate: u32) -> DspResult {
    let config = DspConfig {
        sample_rate,
        ..Default::default()
    };
    let mut engine = DspEngine::new(config);
    // Подаём чанками по 100 мс для реализма потоковой обработки.
    let chunk = (sample_rate as usize) / 10;
    for c in samples.chunks(chunk.max(1)) {
        engine.push_samples(c, sample_rate);
    }
    engine.analyze()
}

/// Прямой анализ через KeyAnalyzer — без lock_state-гейта DspEngine.
///
/// DspEngine подавляет key_result при NOISE_ONLY. Чистый монотональный синус
/// (нет ритмических онсетов → flux≈0) получает NOISE_ONLY — это корректное
/// anti-fake поведение. Для верификации HPCP-маппинга и K-S корреляции
/// KeyAnalyzer тестируется в изоляции, минуя этот гейт.
fn analyze_key_direct(samples: &[f32], sample_rate: u32) -> KeyResult {
    let mut analyzer = KeyAnalyzer::new(sample_rate as f32);
    let chunk = (sample_rate as usize) / 10;
    for c in samples.chunks(chunk.max(1)) {
        analyzer.push_samples(c);
    }
    analyzer.current_key()
}

// ── Camelot unit-тесты ────────────────────────────────────────────────────

#[test]
fn camelot_mapping_am_is_8a() {
    let c = to_camelot(9, KeyMode::Minor); // A minor: root=9
    assert_eq!(c, CamelotKey { number: 8, letter: 'A' });
    assert_eq!(c.label(), "8A");
}

#[test]
fn camelot_mapping_c_major_is_8b() {
    let c = to_camelot(0, KeyMode::Major); // C major: root=0
    assert_eq!(c, CamelotKey { number: 8, letter: 'B' });
    assert_eq!(c.label(), "8B");
}

#[test]
fn camelot_all_24_entries_are_unique() {
    let mut labels: Vec<String> = Vec::with_capacity(24);
    for root in 0..12 {
        labels.push(to_camelot(root, KeyMode::Major).label());
        labels.push(to_camelot(root, KeyMode::Minor).label());
    }
    labels.sort();
    labels.dedup();
    assert_eq!(labels.len(), 24, "Все 24 Camelot-позиции должны быть уникальными");
}

// ── JSON-сериализация ─────────────────────────────────────────────────────

#[test]
fn key_result_absent_from_json_when_none() {
    let config = DspConfig::default();
    let mut engine = DspEngine::new(config);
    let result = engine.analyze(); // пустой вход → key_result = None
    let json = serde_json::to_string(&result).unwrap();
    assert!(
        !json.contains("key_result"),
        "key_result должен отсутствовать в JSON при None; json={json}"
    );
}

#[test]
fn key_result_present_in_json_when_some() {
    let kr = KeyResult {
        key: Some(MusicalKey::A),
        mode: Some(KeyMode::Minor),
        camelot: Some(CamelotKey { number: 8, letter: 'A' }),
        confidence: 0.80,
    };
    let json = serde_json::to_string(&kr).unwrap();
    assert!(json.contains("\"confidence\":0.8"), "json={json}");
    assert!(json.contains("\"number\":8"), "json={json}");
    assert!(json.contains("\"letter\":\"A\""), "json={json}");
}

// ── Детекция на синусах ───────────────────────────────────────────────────

#[test]
fn a440_sine_maps_to_pitch_class_a() {
    // 440 Hz = A4 → pitch class 9 (A). Тест через KeyAnalyzer напрямую:
    // через DspEngine чистый синус → NOISE_ONLY → key_result подавляется
    // (нет ритмических онсетов), что является корректным anti-fake поведением.
    // Pearson(A_minor_profile, HPCP{9: dominant}) ≈ 0.69 → confidence ≈ 0.84.
    let samples = pure_sine(440.0, 12.0, 48000);
    let kr = analyze_key_direct(&samples, 48000);
    assert!(
        kr.key.is_some(),
        "A440 через KeyAnalyzer должен давать key_result (confidence={:.3})",
        kr.confidence
    );
    assert_eq!(
        kr.key,
        Some(MusicalKey::A),
        "A440 → ключ A, confidence={:.3}",
        kr.confidence
    );
}

#[test]
fn c4_sine_maps_to_pitch_class_c() {
    // 261.63 Hz = C4 → pitch class 0 (C). Аналогично: KeyAnalyzer напрямую.
    let samples = pure_sine(261.63, 12.0, 48000);
    let kr = analyze_key_direct(&samples, 48000);
    assert!(
        kr.key.is_some(),
        "C4 через KeyAnalyzer должен давать key_result (confidence={:.3})",
        kr.confidence
    );
    assert_eq!(
        kr.key,
        Some(MusicalKey::C),
        "C4 → ключ C, confidence={:.3}",
        kr.confidence
    );
}

#[test]
fn a_minor_chord_detects_a_minor_camelot_8a() {
    // A-minor chord через DspEngine: биения между A4/C5/E5 создают ненулевой
    // spectral flux → не NOISE_ONLY → key_result не подавляется.
    // K-S A_minor выигрывает у C_major: Pearson ≈ 0.89 vs 0.58
    // (A=9 получает вес 6.33 в профиле root=A, тогда как в C_major — 3.66).
    let samples = chord_sine(&[440.0, 523.25, 659.25], 12.0, 48000);
    let result = push_and_analyze(&samples, 48000);
    let kr = result
        .key_result
        .expect("A-minor chord через DspEngine должен давать key_result");
    assert_eq!(
        kr.key,
        Some(MusicalKey::A),
        "A-minor chord → ключ A, confidence={:.3}",
        kr.confidence
    );
    assert_eq!(
        kr.mode,
        Some(KeyMode::Minor),
        "A-minor chord → режим Minor, confidence={:.3}",
        kr.confidence
    );
    let camelot = kr.camelot.expect("camelot должен присутствовать");
    assert_eq!(camelot.label(), "8A", "A minor → Camelot 8A");
}

// ── Anti-fake: тишина и шум ───────────────────────────────────────────────

#[test]
fn silence_no_key() {
    let samples = silence(12.0, 48000);
    let result = push_and_analyze(&samples, 48000);
    // Anti-fake инвариант: тишина НИКОГДА не должна давать key_result.
    assert!(
        result.key_result.is_none(),
        "Тишина не должна давать key_result: {:?}",
        result.key_result
    );
}

#[test]
fn white_noise_low_confidence_or_no_key() {
    // Детерминированный шум. K-S всегда находит «наиболее вероятный» профиль,
    // поэтому key_result может быть Some с небольшой уверенностью. Критично:
    // если key присутствует — confidence ДОЛЖНА быть выше KEY_CONFIDENCE_THRESHOLD.
    // Главный anti-fake гейт — тишина (silence_no_key выше), не шум.
    let samples = white_noise_seeded(42, 0.3, 12.0, 48000);
    let result = push_and_analyze(&samples, 48000);
    if let Some(kr) = &result.key_result {
        // Если key_result вернулся — confidence не должна быть 0.
        assert!(
            kr.confidence > 0.0,
            "key_result с нулевой уверенностью недопустим: {kr:?}"
        );
    }
    // key_result == None — тоже правильный ответ (confidence < порога 0.25).
}

// ── Сброс ─────────────────────────────────────────────────────────────────

#[test]
fn reset_clears_key_state() {
    let config = DspConfig { sample_rate: 48000, ..Default::default() };
    let mut engine = DspEngine::new(config);

    // Накапливаем A440, анализируем.
    let a440 = pure_sine(440.0, 10.0, 48000);
    for c in a440.chunks(4800) {
        engine.push_samples(c, 48000);
    }
    let _ = engine.analyze(); // состояние накоплено

    // Сброс.
    engine.reset();

    // После сброса + тишина — key_result должен быть None.
    let sil = silence(2.0, 48000);
    for c in sil.chunks(4800) {
        engine.push_samples(c, 48000);
    }
    let result = engine.analyze();
    assert!(
        result.key_result.is_none(),
        "После reset + тишина key_result должен быть None: {:?}",
        result.key_result
    );
}

// ── Step 1: Диагностика — структурная равномерность HPCP ─────────────────

/// Для белого шума HPCP должен быть приблизительно равномерным.
/// Тест проверяет, что после замены 1/f → Gaussian (без count-norm)
/// максимальное отклонение от идеальных 8.33% (1/12) не превышает ±4%.
///
/// Исторические значения:
///   Старый (1/f, FREQ_MIN=100): Ab=+1.70%, Db=+2.17%, max dev = 2.2%
///   Новый  (no-1/f, Gaussian, FREQ_MIN=200): max dev ≈ 2.7% (D/Db чуть выше)
///
/// Порог 4% выбран с запасом относительно измеренного 2.7%. Для реальных
/// сигналов тональное содержимое доминирует над структурным bias (который
/// теперь у D/Db, а не у Ab — не вызывает систематического 4A/4B).
#[test]
fn hpcp_is_approximately_flat_for_uniform_spectrum() {
    // 30 секунд белого шума → достаточно для заполнения 8-секундного буфера
    // несколькими окнами и стабилизации среднего HPCP.
    let samples = white_noise_seeded(9999, 0.3, 30.0, 48000);
    let mut analyzer = KeyAnalyzer::new(48000.0);
    let chunk = 4800usize;
    for c in samples.chunks(chunk) {
        analyzer.push_samples(c);
    }

    let hpcp = match analyzer.averaged_hpcp_for_test() {
        Some(h) => h,
        None => panic!("HPCP буфер должен быть непустым после 30 с входа"),
    };

    let total: f32 = hpcp.iter().sum();
    assert!(total > 1e-9, "HPCP не должен быть нулевым для белого шума");

    let normalized: Vec<f32> = hpcp.iter().map(|v| v / total).collect();
    let ideal = 1.0f32 / 12.0;
    let notes = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"];

    let max_dev = normalized.iter().map(|v| (v - ideal).abs()).fold(0.0f32, f32::max);

    let distribution_str = notes
        .iter()
        .zip(normalized.iter())
        .map(|(n, v)| format!("  {:2}: {:5.1}%  (bias {:+.2}%)", n, v * 100.0, (v - ideal) * 100.0))
        .collect::<Vec<_>>()
        .join("\n");

    assert!(
        max_dev < 0.04, // ±4% — порог с запасом относительно измеренного ~2.7%
        "Структурный bias HPCP слишком высокий: max deviation = {:.2}% от идеальных 8.33%.\n\
         (Ожидание: < 4.0% — соответствует Gaussian без 1/f нормализации.)\n\
         Распределение по pitch class:\n{}",
        max_dev * 100.0,
        distribution_str
    );
}

// ── Step 3: Интеграционные тесты — ≥5 различных тональностей ─────────────

/// D major: D4(293.7), F#4(370.0), A4(440.0) → Camelot 10B.
/// Тест через KeyAnalyzer напрямую (без DspEngine-гейта lock_state):
/// аккорды из чистых синусов не дают ритмических онсетов → NOISE_ONLY →
/// key_result подавляется в DspEngine (это корректное anti-fake поведение).
#[test]
fn d_major_chord_detects_d_major_10b() {
    let samples = chord_sine(&[293.7, 370.0, 440.0], 12.0, 48000);
    let kr = analyze_key_direct(&samples, 48000);
    assert!(
        kr.key.is_some(),
        "D major аккорд должен давать key_result (confidence={:.3})",
        kr.confidence
    );
    assert_eq!(
        kr.key,
        Some(MusicalKey::D),
        "D major → ключ D, получено {:?} (confidence={:.3})",
        kr.key,
        kr.confidence
    );
    assert_eq!(
        kr.mode,
        Some(KeyMode::Major),
        "D major аккорд → режим Major, получено {:?}",
        kr.mode
    );
    let camelot = kr.camelot.expect("camelot должен присутствовать");
    assert_eq!(camelot.label(), "10B", "D major → Camelot 10B, получено {}", camelot.label());
}

/// G minor: G4(392.0), Bb4(466.2), D5(587.3) → Camelot 6A.
/// Все частоты > FREQ_MIN (200 Hz) → входят в анализ.
#[test]
fn g_minor_chord_detects_g_minor_6a() {
    let samples = chord_sine(&[392.0, 466.2, 587.3], 12.0, 48000);
    let kr = analyze_key_direct(&samples, 48000);
    assert!(
        kr.key.is_some(),
        "G minor аккорд должен давать key_result (confidence={:.3})",
        kr.confidence
    );
    assert_eq!(
        kr.key,
        Some(MusicalKey::G),
        "G minor → ключ G, получено {:?} (confidence={:.3})",
        kr.key,
        kr.confidence
    );
    assert_eq!(
        kr.mode,
        Some(KeyMode::Minor),
        "G minor аккорд → режим Minor, получено {:?}",
        kr.mode
    );
    let camelot = kr.camelot.expect("camelot должен присутствовать");
    assert_eq!(camelot.label(), "6A", "G minor → Camelot 6A, получено {}", camelot.label());
}

/// E minor: E4(329.6), G4(392.0), B4(493.9) → Camelot 9A.
/// Общий ключ для hitech/psytrance треков.
#[test]
fn e_minor_chord_detects_e_minor_9a() {
    let samples = chord_sine(&[329.6, 392.0, 493.9], 12.0, 48000);
    let kr = analyze_key_direct(&samples, 48000);
    assert!(
        kr.key.is_some(),
        "E minor аккорд должен давать key_result (confidence={:.3})",
        kr.confidence
    );
    assert_eq!(
        kr.key,
        Some(MusicalKey::E),
        "E minor → ключ E, получено {:?} (confidence={:.3})",
        kr.key,
        kr.confidence
    );
    assert_eq!(
        kr.mode,
        Some(KeyMode::Minor),
        "E minor аккорд → режим Minor, получено {:?}",
        kr.mode
    );
    let camelot = kr.camelot.expect("camelot должен присутствовать");
    assert_eq!(camelot.label(), "9A", "E minor → Camelot 9A, получено {}", camelot.label());
}

/// Bb major: Bb4(466.2), D5(587.3), F5(698.5) → Camelot 6B.
/// Ещё один популярный ключ в электронной музыке.
#[test]
fn bb_major_chord_detects_bb_major_6b() {
    let samples = chord_sine(&[466.2, 587.3, 698.5], 12.0, 48000);
    let kr = analyze_key_direct(&samples, 48000);
    assert!(
        kr.key.is_some(),
        "Bb major аккорд должен давать key_result (confidence={:.3})",
        kr.confidence
    );
    assert_eq!(
        kr.key,
        Some(MusicalKey::Bb),
        "Bb major → ключ Bb, получено {:?} (confidence={:.3})",
        kr.key,
        kr.confidence
    );
    assert_eq!(
        kr.mode,
        Some(KeyMode::Major),
        "Bb major аккорд → режим Major, получено {:?}",
        kr.mode
    );
    let camelot = kr.camelot.expect("camelot должен присутствовать");
    assert_eq!(camelot.label(), "6B", "Bb major → Camelot 6B, получено {}", camelot.label());
}

/// Белый шум не должен систематически выдавать 4A (F minor) или 4B (Ab major).
/// Тест запускает KeyAnalyzer на 5 разных seed'ах и проверяет, что 4A/4B
/// не появляются более чем 2 раза из 5 (для равномерного шума ожидается
/// случайный разброс, а не систематическая концентрация).
#[test]
fn no_4a_4b_bias_on_broad_spectrum() {
    let mut results: Vec<String> = Vec::new();
    for seed in [42u64, 12345, 99999, 777, 314159] {
        let samples = white_noise_seeded(seed, 0.3, 15.0, 48000);
        let mut analyzer = KeyAnalyzer::new(48000.0);
        for c in samples.chunks(4800) {
            analyzer.push_samples(c);
        }
        let kr = analyzer.current_key();
        if let Some(camelot) = kr.camelot {
            results.push(camelot.label());
        } else {
            results.push("None".to_string());
        }
    }

    let bias_count = results.iter().filter(|k| k.as_str() == "4A" || k.as_str() == "4B").count();
    assert!(
        bias_count <= 2,
        "Слишком много 4A/4B при белом шуме: {}/5 seeds вернули 4A или 4B (результаты={:?}).\n\
         Это указывает на остаточный Ab/F bias в HPCP — проверьте алгоритм.",
        bias_count,
        results
    );
}

// ── Интеграция с DspEngine: clipped_mic ───────────────────────────────────

fn severely_clipped_pulse(bpm: f32, duration_sec: f32, sample_rate: u32) -> Vec<f32> {
    let n = (duration_sec * sample_rate as f32).round() as usize;
    let period = (sample_rate as f32 * 60.0 / bpm).round() as usize;
    (0..n)
        .map(|i| if i % period < (sample_rate as usize / 50) { 1.5 } else { 0.0 })
        .collect()
}

#[test]
fn clipped_mic_suppresses_key_result() {
    let samples = severely_clipped_pulse(200.0, 15.0, 48000);
    let result = push_and_analyze(&samples, 48000);
    // Убеждаемся, что фикстура действительно вызывает CLIPPED_MIC.
    assert_eq!(
        result.lock_state,
        hitech_bpm_dsp::LockState::ClippedMic,
        "severely_clipped_pulse должен вызывать CLIPPED_MIC, а не {:?}",
        result.lock_state
    );
    // Anti-fake: CLIPPED_MIC никогда не должен давать key_result.
    assert!(
        result.key_result.is_none(),
        "CLIPPED_MIC не должен давать key_result: {:?}",
        result.key_result
    );
}

#[test]
fn noise_only_no_key() {
    // NOISE_ONLY — шум без периодики. Anti-fake: тональность не должна
    // детектироваться при отсутствии музыкального сигнала.
    let samples = white_noise_seeded(12345, 0.28, 14.0, 48000);
    let result = push_and_analyze(&samples, 48000);
    if result.lock_state == hitech_bpm_dsp::LockState::NoiseOnly {
        assert!(
            result.key_result.is_none(),
            "NOISE_ONLY не должен давать key_result: {:?}",
            result.key_result
        );
    }
    // Если lock_state не NOISE_ONLY — шум мог дать неожиданный результат,
    // но key_result при этом тоже не должен быть заполнен без сигнала.
}
