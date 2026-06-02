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
const FREQ_MIN: f32 = 50.0;

/// Верхняя частотная граница анализируемого спектра (Hz).
const FREQ_MAX: f32 = 5000.0;

/// Опорная частота C4 (Hz) для pitch class расчёта.
const C4_HZ: f32 = 261.63;

// ── Krumhansl-Schmuckler профили (1990) ────────────────────────────────────

const MAJOR_PROFILE: [f32; 12] =
    [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];

const MINOR_PROFILE: [f32; 12] =
    [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

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

        // Перебрать 24 профиля (12 major + 12 minor), найти лучший.
        let mut best_corr = f32::NEG_INFINITY;
        let mut best_root = 0usize;
        let mut best_mode = KeyMode::Major;

        for root in 0..12usize {
            let maj_profile = rotate_profile(&MAJOR_PROFILE, root);
            let maj_corr = pearson_correlation(&avg_hpcp, &maj_profile);
            if maj_corr > best_corr {
                best_corr = maj_corr;
                best_root = root;
                best_mode = KeyMode::Major;
            }

            let min_profile = rotate_profile(&MINOR_PROFILE, root);
            let min_corr = pearson_correlation(&avg_hpcp, &min_profile);
            if min_corr > best_corr {
                best_corr = min_corr;
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

    // Аккумуляция мощности по pitch class.
    let mut hpcp = [0.0f32; HPCP_BINS];
    let n_bins = FRAME_SIZE / 2; // только положительные частоты

    for k in 1..n_bins {
        let freq = k as f32 * sample_rate / FRAME_SIZE as f32;
        if freq < FREQ_MIN || freq > FREQ_MAX {
            continue;
        }
        // Pitch class: C4=0, C#4=1, …, B4=11 (и все октавы).
        let semitones = 12.0 * (freq / C4_HZ).log2();
        let pitch_class = (semitones.round() as i32).rem_euclid(12) as usize;
        let power = buf[k].norm_sqr();
        hpcp[pitch_class] += power;
    }

    // L2-нормализация.
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
