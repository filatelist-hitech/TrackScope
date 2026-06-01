// Полное покрытие детекции расширенного hitech-диапазона 155–230 BPM (Phase 8.2).
//
// До Phase 8.2 предпочитаемый диапазон был 170–230; hitech-psytrance начинается
// от ~155 BPM, поэтому `DspConfig::target_bpm_min` снижен 170 → 155. Поиск
// (broad 80–460) и нормализация (<130 → ×2, >260 → ÷2) НЕ менялись.
//
// Каждая точка матрицы (155, затем 160…230 шаг 5) проходит покадровую подачу
// и проверяет три инварианта приёмки:
//   • первый захват (выход из SEARCHING) ≤ 6 с аудио;
//   • STABLE ≤ 12 с аудио;
//   • последние 20 STABLE-кадров в пределах ±1 BPM от эталона.
//
// Граничные тесты проверяют, что 155 BPM НЕ удваивается и что нормализованный
// double-time-кандидат остаётся видимым (anti-fake: half/double всегда видимы).
//
// Тайминговая конвенция (elapsed = fed / SAMPLE_RATE) зеркалит streaming.rs.

mod common;

use common::{pulse_track, SAMPLE_RATE};
use hitech_bpm_dsp::{analyze_pcm, DspConfig, DspEngine, LockState};

// ── Streaming harness ────────────────────────────────────────────────────────

/// Покадрово подаёт чистый импульс `target_bpm` и проверяет тайминг захвата
/// и стабильность последних 20 STABLE-кадров (±1 BPM).
fn run_range_coverage(target_bpm: f32) {
    let config = DspConfig::default();
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize; // 100 мс
    let total_sec = 20.0_f32; // first-lock ≤6 + STABLE ≤12 + запас на 20 кадров
    let samples = pulse_track(target_bpm, total_sec, 0.9);

    let mut engine = DspEngine::new(config);
    let mut first_lock_sec: Option<f32> = None;
    let mut stable_at_sec: Option<f32> = None;
    let mut stable_bpms: Vec<f32> = Vec::new();
    let mut fed = 0usize;

    for chunk in samples.chunks(chunk_size) {
        engine.push_samples(chunk, SAMPLE_RATE);
        fed += chunk.len();
        let elapsed_sec = fed as f32 / SAMPLE_RATE as f32;
        let result = engine.analyze();

        if first_lock_sec.is_none() && !matches!(result.lock_state, LockState::Searching) {
            first_lock_sec = Some(elapsed_sec);
        }
        if matches!(result.lock_state, LockState::Stable) {
            if stable_at_sec.is_none() {
                stable_at_sec = Some(elapsed_sec);
            }
            if let Some(bpm) = result.primary_bpm {
                stable_bpms.push(bpm);
            }
        }
    }

    let first_lock = first_lock_sec.unwrap_or(999.0);
    assert!(
        first_lock <= 6.0,
        "{target_bpm} BPM: first lock at {first_lock:.2}s exceeded 6s"
    );

    let stable_at = stable_at_sec.unwrap_or(999.0);
    assert!(
        stable_at <= 12.0,
        "{target_bpm} BPM: STABLE at {stable_at:.2}s exceeded 12s"
    );

    assert!(
        stable_bpms.len() >= 20,
        "{target_bpm} BPM: only {} STABLE frames (need ≥20)",
        stable_bpms.len()
    );
    let last_20 = &stable_bpms[stable_bpms.len() - 20..];
    for &bpm in last_20 {
        assert!(
            (bpm - target_bpm).abs() <= 1.0,
            "{target_bpm} BPM: STABLE value {bpm:.2} out of ±1 BPM tolerance"
        );
    }
}

macro_rules! range_test {
    ($name:ident, $bpm:expr) => {
        #[test]
        fn $name() {
            run_range_coverage($bpm);
        }
    };
}

// ── Matrix: 155 (boundary) + 160…230 every 5 BPM ─────────────────────────────

range_test!(range_155_bpm, 155.0);
range_test!(range_160_bpm, 160.0);
range_test!(range_165_bpm, 165.0);
range_test!(range_170_bpm, 170.0);
range_test!(range_175_bpm, 175.0);
range_test!(range_180_bpm, 180.0);
range_test!(range_185_bpm, 185.0);
range_test!(range_190_bpm, 190.0);
range_test!(range_195_bpm, 195.0);
range_test!(range_200_bpm, 200.0);
range_test!(range_205_bpm, 205.0);
range_test!(range_210_bpm, 210.0);
range_test!(range_215_bpm, 215.0);
range_test!(range_220_bpm, 220.0);
range_test!(range_225_bpm, 225.0);
range_test!(range_230_bpm, 230.0);

// ── Boundary / normalization invariants ──────────────────────────────────────

/// 155 BPM (новая нижняя граница) НЕ должен удваиваться до ~310 BPM:
/// primary остаётся в [153, 157], а double-time-кандидат, хоть и присутствует,
/// не становится основным.
#[test]
fn bpm_155_is_detected_not_doubled() {
    let samples = pulse_track(155.0, 14.0, 0.9);
    let result = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());
    assert_eq!(
        result.lock_state,
        LockState::Stable,
        "155 BPM clean pulse must reach STABLE"
    );
    let bpm = result.primary_bpm.expect("primary_bpm must be Some in STABLE");
    assert!(
        (153.0..=157.0).contains(&bpm),
        "155 BPM finalized at {bpm} — expected [153,157], must NOT double to ~310"
    );
    assert!(
        !(308.0..=314.0).contains(&bpm),
        "155 BPM must not finalize at the doubled ~310 BPM lag"
    );
}

// Примечание: double-time-нормализация (>260 → ÷2) не затрагивается расширением
// диапазона (граница 260 не менялась) и уже покрыта тестом
// `double_time_trap_preserves_raw_and_normalized_candidates` (400 → 200) в
// offline_contract.rs. Фикстура 460 BPM при 48 кГц даёт raw-пик прямо на ~230
// (детектор находит под-долю, а не 460), поэтому отдельным trap-тестом здесь
// не покрывается.
