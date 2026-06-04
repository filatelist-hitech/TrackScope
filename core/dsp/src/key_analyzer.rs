/// Real-time key detector using HPCP + Krumhansl-Schmuckler profiles.
///
/// Phase 2.1 implementation.
///
/// Алгоритм:
/// 1. STFT-фреймы → хроматический профиль 12-bin (HPCP).
/// 2. Accumulate HPCP в скользящем буфере ~8 сек.
/// 3. Correlate с Krumhansl-Schmuckler мажорными/минорными профилями.
/// 4. Выбрать тональность с максимальной корреляцией.
/// 5. Эмитить `KeyResult` с `camelot` и `confidence`.
use rustfft::{num_complex::Complex, Fft, FftPlanner};
use serde::Serialize;
use std::collections::VecDeque;
use std::sync::Arc;

// ── Алгоритмические константы ──────────────────────────────────────────────

/// Число хроматических бинов (полутонов).
const HPCP_BINS: usize = 12;

/// Размер FFT-фрейма: ~85 мс при 48 kHz.
const FRAME_SIZE: usize = 4096;

/// Шаг между фреймами: 50% overlap.
const HOP_SIZE: usize = 2048;

/// Скользящее окно накопления HPCP (секунды).
const KEY_WINDOW_SECS: f32 = 8.0;

/// Нижняя граница уверенности. Ниже → key = None (не фейкаем ключ).
const KEY_CONFIDENCE_THRESHOLD: f32 = 0.25;

/// Нижняя частотная граница анализируемого спектра (Hz).
///
/// 200 Hz: исключает фундаменталы kick drum (50–80 Hz) и фундаменталы
/// баслайна (80–200 Hz). Гармоники баслайна выше 200 Hz по-прежнему
/// включаются. Диапазон 200–5000 Hz покрывает гармонический и мелодический
/// контент треков hitech/psytrance.
///
/// Обоснование перехода 100 → 200 Hz (Phase 13.2):
/// При FREQ_MIN=100 Hz первый анализируемый бин (k=9, freq≈105.5 Hz)
/// отображается на pitch class Ab (8). Это в сочетании с 1/f-нормализацией
/// (которая убрана в этом же фиксе) давало максимальный вес Ab и вызывало
/// систематический вывод 4A/4B. При FREQ_MIN=200 Hz структурное смещение
/// снижается с 2.2% до < 0.7% (измерено на равномерном спектре).
const FREQ_MIN: f32 = 200.0;

/// Ширина Гауссовой функции для pitch class weighting (центы).
///
/// Стандартная HPCP (Gómez 2006): σ=14 центов. Для FFT-бинов при
/// частоте ≥200 Hz и SR=48 kHz ширина бина ≈10–78 центов; σ=25 центов
/// обеспечивает плавное распределение для низкочастотных бинов.
const SIGMA_CENTS: f32 = 25.0;

/// Верхняя частотная граница анализируемого спектра (Hz).
const FREQ_MAX: f32 = 5000.0;

/// Опорная частота C4 (Hz) для pitch class расчёта.
const C4_HZ: f32 = 261.63;

// ── Тональные профили ─────────────────────────────────────────────────────

/// Krumhansl-Schmuckler профили (1990).
/// Индекс 0 = тоника, 1 = минорная 2-я, 2 = мажорная 2-я, …
const MAJOR_PROFILE: [f32; 12] =
    [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];

const MINOR_PROFILE: [f32; 12] =
    [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

/// Temperley (2001) профили — лучший баланс минорной терции.
/// MINOR_PROFILE[3] = 5.38 → 4.5 устраняет избыточный вес minor 3rd
/// (который в паре с Ab-bias давал F minor (4A) систематический буст).
/// Используются параллельно с K-S: выбирается профиль с максимальной
/// корреляцией Пирсона.
const TEMPERLEY_MAJOR: [f32; 12] =
    [5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0];

const TEMPERLEY_MINOR: [f32; 12] =
    [5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0];

// ── Публичные типы ─────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum MusicalKey {
    C,
    Db,
    D,
    Eb,
    E,
    F,
    Gb,
    G,
    Ab,
    A,
    Bb,
    B,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum KeyMode {
    Major,
    Minor,
}

/// Camelot-нотация для гармонического микса.
/// number: 1–12, letter: 'A' (minor) или 'B' (major).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct CamelotKey {
    pub number: u8,
    pub letter: char,
}

impl CamelotKey {
    pub fn label(self) -> String {
        format!("{}{}", self.number, self.letter)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct KeyResult {
    pub key: Option<MusicalKey>,
    pub mode: Option<KeyMode>,
    pub camelot: Option<CamelotKey>,
    pub confidence: f32,
}

impl Default for KeyResult {
    fn default() -> Self {
        Self {
            key: None,
            mode: None,
            camelot: None,
            confidence: 0.0,
        }
    }
}

// ── KeyAnalyzer ────────────────────────────────────────────────────────────

pub struct KeyAnalyzer {
    sample_rate: f32,
    fft: Arc<dyn Fft<f32>>,
    pcm_pending: Vec<f32>,
    hpcp_buffer: VecDeque<[f32; HPCP_BINS]>,
    buffer_capacity: usize,
    scratch: Vec<Complex<f32>>,
    window: Vec<f32>,
}

impl std::fmt::Debug for KeyAnalyzer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("KeyAnalyzer")
            .field("sample_rate", &self.sample_rate)
            .field("buffer_capacity", &self.buffer_capacity)
            .field("hpcp_frames", &self.hpcp_buffer.len())
            .finish()
    }
}

impl Clone for KeyAnalyzer {
    fn clone(&self) -> Self {
        // FftPlanner не реализует Clone — создаём новый план того же размера.
        let mut planner = FftPlanner::<f32>::new();
        let fft = planner.plan_fft_forward(FRAME_SIZE);
        let scratch_len = fft.get_inplace_scratch_len();
        Self {
            sample_rate: self.sample_rate,
            fft,
            pcm_pending: self.pcm_pending.clone(),
            hpcp_buffer: self.hpcp_buffer.clone(),
            buffer_capacity: self.buffer_capacity,
            scratch: vec![Complex::new(0.0, 0.0); scratch_len],
            window: self.window.clone(),
        }
    }
}

impl KeyAnalyzer {
    pub fn new(sample_rate: f32) -> Self {
        let mut planner = FftPlanner::<f32>::new();
        let fft = planner.plan_fft_forward(FRAME_SIZE);
        let scratch_len = fft.get_inplace_scratch_len();

        // Ёмкость буфера: сколько HPCP-фреймов помещается в KEY_WINDOW_SECS.
        let frames_per_sec = if sample_rate > 0.0 {
            sample_rate / HOP_SIZE as f32
        } else {
            1.0
        };
        let buffer_capacity = ((KEY_WINDOW_SECS * frames_per_sec).ceil() as usize).max(1);

        // Hanning-окно длиной FRAME_SIZE.
        let window: Vec<f32> = (0..FRAME_SIZE)
            .map(|i| {
                0.5 * (1.0
                    - (2.0 * std::f32::consts::PI * i as f32 / (FRAME_SIZE - 1) as f32).cos())
            })
            .collect();

        Self {
            sample_rate,
            fft,
            pcm_pending: Vec::with_capacity(FRAME_SIZE + HOP_SIZE),
            hpcp_buffer: VecDeque::with_capacity(buffer_capacity + 1),
            buffer_capacity,
            scratch: vec![Complex::new(0.0, 0.0); scratch_len],
            window,
        }
    }

    /// Добавить PCM-сэмплы, извлечь HPCP-кадры.
    pub fn push_samples(&mut self, samples: &[f32]) {
        self.pcm_pending.extend_from_slice(samples);
        while self.pcm_pending.len() >= FRAME_SIZE {
            let hpcp = extract_hpcp_frame(
                &self.pcm_pending[..FRAME_SIZE],
                self.sample_rate,
                &*self.fft,
                &mut self.scratch,
                &self.window,
            );
            if self.hpcp_buffer.len() >= self.buffer_capacity {
                self.hpcp_buffer.pop_front();
            }
            self.hpcp_buffer.push_back(hpcp);
            self.pcm_pending.drain(..HOP_SIZE);
        }
    }

    /// Вернуть текущий результат детекции тональности.
    ///
    /// Anti-fake: возвращает `KeyResult::default()` (key=None) если:
    /// - буфер пуст;
    /// - уверенность < KEY_CONFIDENCE_THRESHOLD.
    pub fn current_key(&self) -> KeyResult {
        if self.hpcp_buffer.is_empty() {
            return KeyResult::default();
        }

        // Усреднить HPCP по всем кадрам буфера.
        let mut avg_hpcp = [0.0f32; HPCP_BINS];
        for frame in &self.hpcp_buffer {
            for (i, v) in frame.iter().enumerate() {
                avg_hpcp[i] += v;
            }
        }
        let n = self.hpcp_buffer.len() as f32;
        for v in &mut avg_hpcp {
            *v /= n;
        }

        // Перебрать 48 профилей: K-S (1990) + Temperley (2001), 12 major + 12 minor каждый.
        // Temperley снижает вес minor 3rd (4.5 vs K-S 5.38), что уменьшает
        // избыточный буст F minor (4A) при остаточном Ab-bias.
        let mut best_corr = f32::NEG_INFINITY;
        let mut best_root = 0usize;
        let mut best_mode = KeyMode::Major;

        for root in 0..12usize {
            // ── Krumhansl-Schmuckler (1990) ────────────────────────────────
            let maj_corr = pearson_correlation(&avg_hpcp, &rotate_profile(&MAJOR_PROFILE, root));
            if maj_corr > best_corr {
                best_corr = maj_corr;
                best_root = root;
                best_mode = KeyMode::Major;
            }

            let min_corr = pearson_correlation(&avg_hpcp, &rotate_profile(&MINOR_PROFILE, root));
            if min_corr > best_corr {
                best_corr = min_corr;
                best_root = root;
                best_mode = KeyMode::Minor;
            }

            // ── Temperley (2001) ───────────────────────────────────────────
            let tmaj_corr =
                pearson_correlation(&avg_hpcp, &rotate_profile(&TEMPERLEY_MAJOR, root));
            if tmaj_corr > best_corr {
                best_corr = tmaj_corr;
                best_root = root;
                best_mode = KeyMode::Major;
            }

            let tmin_corr =
                pearson_correlation(&avg_hpcp, &rotate_profile(&TEMPERLEY_MINOR, root));
            if tmin_corr > best_corr {
                best_corr = tmin_corr;
                best_root = root;
                best_mode = KeyMode::Minor;
            }
        }

        // Нормализовать корреляцию Пирсона [-1,1] → [0,1].
        let confidence = ((best_corr + 1.0) / 2.0).clamp(0.0, 1.0);

        if confidence < KEY_CONFIDENCE_THRESHOLD {
            return KeyResult::default();
        }

        let key = root_to_musical_key(best_root);
        let camelot = to_camelot(best_root, best_mode);

        KeyResult {
            key: Some(key),
            mode: Some(best_mode),
            camelot: Some(camelot),
            confidence,
        }
    }

    /// Сбросить накопленное состояние.
    pub fn reset(&mut self) {
        self.pcm_pending.clear();
        self.hpcp_buffer.clear();
    }

    /// Вернуть усреднённый HPCP по всем накопленным кадрам.
    ///
    /// Метод предназначен для тестирования структурной равномерности (flatness)
    /// HPCP при равномерном входном спектре. Не скрыт через `#[cfg(test)]` —
    /// integration tests не имеют доступа к cfg(test)-методам крейта.
    /// Не вызывается в production-путях.
    #[doc(hidden)]
    pub fn averaged_hpcp_for_test(&self) -> Option<[f32; HPCP_BINS]> {
        if self.hpcp_buffer.is_empty() {
            return None;
        }
        let mut avg = [0.0f32; HPCP_BINS];
        for frame in &self.hpcp_buffer {
            for (i, v) in frame.iter().enumerate() {
                avg[i] += v;
            }
        }
        let n = self.hpcp_buffer.len() as f32;
        for v in &mut avg {
            *v /= n;
        }
        Some(avg)
    }
}

// ── Приватные вспомогательные функции ─────────────────────────────────────

/// Извлечь HPCP-фрейм из одного PCM-окна.
///
/// 1. Применить Hanning-окно.
/// 2. FFT.
/// 3. Для каждого бина: pitch class accumulation по мощности.
/// 4. L2-нормализация.
fn extract_hpcp_frame(
    frame: &[f32],
    sample_rate: f32,
    fft: &dyn Fft<f32>,
    scratch: &mut Vec<Complex<f32>>,
    window: &[f32],
) -> [f32; HPCP_BINS] {
    debug_assert_eq!(frame.len(), FRAME_SIZE);
    debug_assert_eq!(window.len(), FRAME_SIZE);

    // Применить окно и скопировать в комплексный буфер.
    let mut buf: Vec<Complex<f32>> = frame
        .iter()
        .zip(window.iter())
        .map(|(&s, &w)| Complex::new(s * w, 0.0))
        .collect();

    // in-place FFT.
    fft.process_with_scratch(&mut buf, scratch);

    // HPCP-аккумуляция: Gaussian pitch-class weighting (без 1/f).
    //
    // ── Почему старый подход (1/f) давал 4A/4B ────────────────────────────
    // Первый анализируемый бин (k=9, freq≈105.5 Hz при старом FREQ_MIN=100)
    // отображался на pitch class Ab (8) и получал максимальный вес 1/f = 0.00948.
    // Это создавало систематический Ab-bias (+1.70% от идеальных 8.33%), а
    // K-S MINOR_PROFILE[3]=5.38 для F minor (root=5) давал ему двойной буст —
    // почти всегда побеждали 4A (F minor) или 4B (Ab major).
    //
    // ── Новый подход (Phase 13.2) ─────────────────────────────────────────
    // 1. RAW power (без 1/f): вес бина ≡ его реальная мощность сигнала.
    // 2. Gaussian weighting (σ=25 центов, Gómez 2006): плавное распределение
    //    мощности между ближайшим и соседним полутоном. Устраняет ступенчатые
    //    артефакты от жёсткого round()-назначения; особенно важно для бинов
    //    в нижнем частотном диапазоне (200–500 Hz), где ширина бина ≈ ширине
    //    полутона (~40–80 центов).
    //
    // ВАЖНО: count-normalization намеренно НЕ применяется.
    // Она делила бы HPCP[pc] на суммарное число бинов данного pitch class
    // ВО ВСЁМ диапазоне [200, 5000 Hz], в том числе на частотах, где сигнал
    // равен нулю. Это искажает соотношение высоких тонов (больше октав →
    // больше знаменатель → ниже нормализованное значение) и ломает детекцию
    // на реальных аккордах.
    let mut hpcp = [0.0f32; HPCP_BINS];
    let n_bins = FRAME_SIZE / 2; // только положительные частоты

    for k in 1..n_bins {
        let freq = k as f32 * sample_rate / FRAME_SIZE as f32;
        if freq < FREQ_MIN || freq > FREQ_MAX {
            continue;
        }

        let power = buf[k].norm_sqr(); // raw power, без 1/f

        // Непрерывный индекс полутона от C4 (C4=0.0, C#4=1.0, …).
        let semitones = 12.0 * (freq / C4_HZ).log2();
        let nearest = semitones.round() as i32;
        let cents_off = (semitones - nearest as f32) * 100.0;

        // Gaussian вес на ближайший полутон.
        let w = (-cents_off * cents_off / (2.0 * SIGMA_CENTS * SIGMA_CENTS)).exp();
        let pc = nearest.rem_euclid(12) as usize;
        hpcp[pc] += power * w;

        // Gaussian хвост на соседний полутон — только если вес значим
        // (для σ=25c: при |cents_off|>70c хвост w_adj < 0.14).
        let adj = if cents_off > 0.0 { nearest + 1 } else { nearest - 1 };
        let cents_adj = (semitones - adj as f32) * 100.0;
        let w_adj = (-cents_adj * cents_adj / (2.0 * SIGMA_CENTS * SIGMA_CENTS)).exp();
        if w_adj > 1e-4 {
            let pc_adj = adj.rem_euclid(12) as usize;
            hpcp[pc_adj] += power * w_adj;
        }
    }

    // L2-нормализация (без изменений).
    let l2: f32 = hpcp.iter().map(|v| v * v).sum::<f32>().sqrt();
    if l2 > 0.0 {
        for v in &mut hpcp {
            *v /= l2;
        }
    }

    hpcp
}

/// Циклический сдвиг профиля вправо на `root` позиций.
fn rotate_profile(profile: &[f32; 12], root: usize) -> [f32; 12] {
    let mut rotated = [0.0f32; 12];
    for i in 0..12 {
        rotated[(i + root) % 12] = profile[i];
    }
    rotated
}

/// Нормализованная корреляция Пирсона двух 12-элементных векторов.
/// Возвращает 0.0 если std == 0.
fn pearson_correlation(a: &[f32; 12], b: &[f32; 12]) -> f32 {
    let n = 12.0f32;
    let mean_a = a.iter().sum::<f32>() / n;
    let mean_b = b.iter().sum::<f32>() / n;

    let mut cov = 0.0f32;
    let mut var_a = 0.0f32;
    let mut var_b = 0.0f32;

    for i in 0..12 {
        let da = a[i] - mean_a;
        let db = b[i] - mean_b;
        cov += da * db;
        var_a += da * da;
        var_b += db * db;
    }

    let denom = (var_a * var_b).sqrt();
    if denom < 1e-9 {
        return 0.0;
    }
    (cov / denom).clamp(-1.0, 1.0)
}

/// Преобразовать pitch class index (0=C, 1=Db, …, 11=B) в `MusicalKey`.
fn root_to_musical_key(root: usize) -> MusicalKey {
    match root % 12 {
        0 => MusicalKey::C,
        1 => MusicalKey::Db,
        2 => MusicalKey::D,
        3 => MusicalKey::Eb,
        4 => MusicalKey::E,
        5 => MusicalKey::F,
        6 => MusicalKey::Gb,
        7 => MusicalKey::G,
        8 => MusicalKey::Ab,
        9 => MusicalKey::A,
        10 => MusicalKey::Bb,
        11 => MusicalKey::B,
        _ => MusicalKey::C, // unreachable
    }
}

/// Taблица Camelot.
///
/// ```text
/// Major: C=8B, Db=3B, D=10B, Eb=5B, E=12B, F=7B, Gb=2B, G=9B, Ab=4B, A=11B, Bb=6B, B=1B
/// Minor: C=5A, Db=12A, D=7A, Eb=2A, E=9A, F=4A, Gb=11A, G=6A, Ab=1A, A=8A, Bb=3A, B=10A
/// ```
pub fn to_camelot(root: usize, mode: KeyMode) -> CamelotKey {
    let number = match mode {
        KeyMode::Major => match root % 12 {
            0 => 8,  // C
            1 => 3,  // Db
            2 => 10, // D
            3 => 5,  // Eb
            4 => 12, // E
            5 => 7,  // F
            6 => 2,  // Gb
            7 => 9,  // G
            8 => 4,  // Ab
            9 => 11, // A
            10 => 6, // Bb
            11 => 1, // B
            _ => 8,
        },
        KeyMode::Minor => match root % 12 {
            0 => 5,  // Cm
            1 => 12, // Dbm
            2 => 7,  // Dm
            3 => 2,  // Ebm
            4 => 9,  // Em
            5 => 4,  // Fm
            6 => 11, // Gbm
            7 => 6,  // Gm
            8 => 1,  // Abm
            9 => 8,  // Am
            10 => 3, // Bbm
            11 => 10, // Bm
            _ => 5,
        },
    };
    let letter = match mode {
        KeyMode::Major => 'B',
        KeyMode::Minor => 'A',
    };
    CamelotKey { number, letter }
}

// ── Встроенные unit-тесты ──────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn camelot_label_format() {
        let k = CamelotKey { number: 8, letter: 'A' };
        assert_eq!(k.label(), "8A");
        let k2 = CamelotKey { number: 12, letter: 'B' };
        assert_eq!(k2.label(), "12B");
    }

    #[test]
    fn key_result_default_has_no_key() {
        let r = KeyResult::default();
        assert!(r.key.is_none());
        assert!(r.camelot.is_none());
        assert_eq!(r.confidence, 0.0);
    }

    #[test]
    fn key_result_serializes_to_json() {
        let r = KeyResult {
            key: Some(MusicalKey::A),
            mode: Some(KeyMode::Minor),
            camelot: Some(CamelotKey { number: 8, letter: 'A' }),
            confidence: 0.87,
        };
        let json = serde_json::to_string(&r).unwrap();
        assert!(json.contains("\"confidence\":0.87"));
        assert!(json.contains("\"number\":8"));
    }

    #[test]
    fn camelot_am_is_8a() {
        // A minor: root=9, mode=Minor → 8A
        let c = to_camelot(9, KeyMode::Minor);
        assert_eq!(c.number, 8);
        assert_eq!(c.letter, 'A');
        assert_eq!(c.label(), "8A");
    }

    #[test]
    fn camelot_c_major_is_8b() {
        // C major: root=0, mode=Major → 8B
        let c = to_camelot(0, KeyMode::Major);
        assert_eq!(c.number, 8);
        assert_eq!(c.letter, 'B');
        assert_eq!(c.label(), "8B");
    }

    #[test]
    fn empty_analyzer_returns_no_key() {
        let analyzer = KeyAnalyzer::new(48000.0);
        let result = analyzer.current_key();
        assert!(result.key.is_none());
        assert_eq!(result.confidence, 0.0);
    }

    #[test]
    fn rotate_profile_identity_at_zero() {
        let rotated = rotate_profile(&MAJOR_PROFILE, 0);
        assert_eq!(rotated, MAJOR_PROFILE);
    }

    #[test]
    fn rotate_profile_shifts_by_one() {
        let rotated = rotate_profile(&MAJOR_PROFILE, 1);
        // Элемент 0 исходного профиля оказывается на позиции 1.
        assert_eq!(rotated[1], MAJOR_PROFILE[0]);
        assert_eq!(rotated[0], MAJOR_PROFILE[11]);
    }

    #[test]
    fn pearson_correlation_identical_is_one() {
        let corr = pearson_correlation(&MAJOR_PROFILE, &MAJOR_PROFILE);
        assert!((corr - 1.0).abs() < 1e-5, "identical profiles: corr={corr}");
    }

    #[test]
    fn pearson_correlation_uniform_is_zero() {
        let uniform = [1.0f32; 12];
        let corr = pearson_correlation(&MAJOR_PROFILE, &uniform);
        assert!(corr.abs() < 1e-5, "uniform profile: corr={corr}");
    }

    #[test]
    fn hpcp_frame_a440_peak_at_class_9() {
        // A440 Hz → pitch class 9 (A).
        let sr = 48000.0f32;
        let freq = 440.0f32;
        let frame: Vec<f32> = (0..FRAME_SIZE)
            .map(|i| (2.0 * std::f32::consts::PI * freq * i as f32 / sr).sin())
            .collect();

        let mut planner = FftPlanner::<f32>::new();
        let fft = planner.plan_fft_forward(FRAME_SIZE);
        let scratch_len = fft.get_inplace_scratch_len();
        let mut scratch = vec![Complex::new(0.0, 0.0); scratch_len];
        let window: Vec<f32> = (0..FRAME_SIZE)
            .map(|i| {
                0.5 * (1.0
                    - (2.0 * std::f32::consts::PI * i as f32 / (FRAME_SIZE - 1) as f32).cos())
            })
            .collect();

        let hpcp = extract_hpcp_frame(&frame, sr, &*fft, &mut scratch, &window);
        let peak_class = hpcp
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
            .map(|(i, _)| i)
            .unwrap();
        assert_eq!(peak_class, 9, "A440 should map to pitch class 9, got {peak_class}");
    }
}
