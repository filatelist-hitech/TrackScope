/// Energy level 1–10 via RMS + spectral flux + onset density.
///
/// Получает уже вычисленный spectral flux из DspEngine через `push_flux()`,
/// избегая дублирования CPU. RMS вычисляется из собственного PCM-буфера 3 сек.
///
/// Веса: RMS 40% + flux 35% + onset density 25%.
/// Квантизация: взвешенная сумма [0, 1] → ceil(sum * 10).clamp(1, 10).
use std::collections::VecDeque;

use serde::Serialize;

// ── Калибровочные константы для hitech 155–230 BPM ───────────────────────────
// Выбраны консервативно на синтетических фикстурах clean_200.
// Потребуют fine-tuning после реальных тестов (Phase 2.2.1).

/// Нижняя граница RMS dBFS: сигнал практически тихий.
const RMS_DBFS_MIN: f32 = -50.0;
/// Верхняя граница RMS dBFS: громкий hitech (close mic или бустированный).
const RMS_DBFS_MAX: f32 = -6.0;
/// Нижняя граница spectral flux (среднее по окну); ≈ нет транзиентов.
const FLUX_MIN: f32 = 0.0;
/// Верхняя граница spectral flux на плотном hitech-пульсе.
/// Подобрано по clean_200: onset_strength ≈ 0.10–0.14 в STABLE.
const FLUX_MAX: f32 = 0.15;
/// Нижняя граница плотности онсетов (онсетов/сек) — редкий пульс.
const DENSITY_MIN: f32 = 0.5;
/// Верхняя граница плотности онсетов — плотный hitech kick + суб-онсеты.
/// Phase 2.2.2: density вычисляется через count_flux_peaks() — реальные
/// локальные максимумы flux_history выше среднего. Диапазон hitech: ~3–8 Hz.
const DENSITY_MAX: f32 = 8.0;
/// Абсолютный минимальный порог flux для пика — отсекает шумовые флуктуации.
/// Белый шум amplitude=0.28 даёт max flux ≈ 0.008; kick-барабан >> 0.01.
const FLUX_ABSOLUTE_FLOOR: f32 = 0.01;

/// Веса трёх компонент. Сумма = 1.0.
const WEIGHT_RMS: f32 = 0.40;
const WEIGHT_FLUX: f32 = 0.35;
const WEIGHT_DENSITY: f32 = 0.25;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct EnergyResult {
    /// 1 (очень тихо) — 10 (очень интенсивно), Mixed In Key-стиль.
    /// 0 зарезервирован для «нет данных» (не отправляется в UI).
    pub level: u8,
    /// RMS-уровень в dBFS за скользящее окно.
    pub rms_dbfs: f32,
    /// Средний spectral flux за скользящее окно (из onset_history DspEngine).
    pub spectral_flux: f32,
    /// Плотность онсетов (онсетов/сек).
    pub onset_density_hz: f32,
}

impl Default for EnergyResult {
    fn default() -> Self {
        Self {
            level: 0,
            rms_dbfs: f32::NEG_INFINITY,
            spectral_flux: 0.0,
            onset_density_hz: 0.0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct EnergyAnalyzer {
    #[allow(dead_code)]
    sample_rate: f32,
    /// Реальный hop-шаг (сек), переданный из DspEngine при создании.
    hop_sec: f32,
    /// Скользящий PCM-буфер для вычисления RMS (3 сек).
    rms_window: VecDeque<f32>,
    rms_capacity: usize,
    /// Spectral flux кадров, полученных из DspEngine через push_flux().
    flux_history: VecDeque<f32>,
    flux_capacity: usize,
}

impl EnergyAnalyzer {
    pub fn new(sample_rate: f32, hop_sec: f32) -> Self {
        let sr = if sample_rate > 0.0 { sample_rate } else { 48_000.0 };
        let hop = hop_sec.max(0.001);
        let rms_capacity = (sr * 3.0) as usize;
        let flux_capacity = ((3.0 / hop) as usize).max(8);
        Self {
            sample_rate: sr,
            hop_sec: hop,
            rms_window: VecDeque::with_capacity(rms_capacity),
            rms_capacity,
            flux_history: VecDeque::with_capacity(flux_capacity),
            flux_capacity,
        }
    }

    /// Добавить PCM-сэмплы в скользящий RMS-буфер.
    pub fn push_samples(&mut self, samples: &[f32]) {
        for &s in samples {
            if self.rms_window.len() >= self.rms_capacity && self.rms_capacity > 0 {
                self.rms_window.pop_front();
            }
            self.rms_window.push_back(s);
        }
    }

    /// Принять уже вычисленный spectral flux из DspEngine (не пересчитывать).
    pub fn push_flux(&mut self, flux: f32) {
        if self.flux_history.len() >= self.flux_capacity && self.flux_capacity > 0 {
            self.flux_history.pop_front();
        }
        self.flux_history.push_back(flux);
    }

    /// Считает значимые пики flux_history — реальные удары, а не шумовые флуктуации.
    ///
    /// Условия для пика:
    /// - локальный максимум (больше соседей);
    /// - выше порога max(mean + 2·σ, FLUX_ABSOLUTE_FLOOR=0.01) — отсекает шум;
    /// - расстояние ≥ MIN_PEAK_GAP кадров от предыдущего пика (~100 мс).
    fn count_flux_peaks(&self) -> usize {
        let flux: Vec<f32> = self.flux_history.iter().copied().collect();
        if flux.len() < 3 {
            return 0;
        }
        let mean = flux.iter().sum::<f32>() / flux.len() as f32;
        if mean <= 0.0 {
            return 0;
        }
        let variance =
            flux.iter().map(|&x| (x - mean) * (x - mean)).sum::<f32>() / flux.len() as f32;
        let std_dev = variance.sqrt();
        // Порог = max(mean + 2σ, абсолютный пол). Белый шум (max flux ≈ 0.008)
        // не дотягивается до 0.01; реальные удары дают пики >> 0.01.
        let threshold = (mean + 2.0 * std_dev).max(FLUX_ABSOLUTE_FLOOR);
        // 100 мс минимального зазора, динамически из hop_sec.
        let min_peak_gap = (0.1 / self.hop_sec).round() as usize;
        let mut count = 0usize;
        let mut last_peak_idx = 0usize;
        for i in 1..flux.len() - 1 {
            if flux[i] > flux[i - 1]
                && flux[i] > flux[i + 1]
                && flux[i] > threshold
                && (count == 0 || i - last_peak_idx >= min_peak_gap)
            {
                count += 1;
                last_peak_idx = i;
            }
        }
        count
    }

    /// Вычислить текущий уровень энергии.
    pub fn current_energy(&self) -> EnergyResult {
        // ── RMS ──────────────────────────────────────────────────────────────
        let rms_dbfs = if self.rms_window.is_empty() {
            f32::NEG_INFINITY
        } else {
            let mean_sq: f64 = self
                .rms_window
                .iter()
                .map(|&s| (s as f64) * (s as f64))
                .sum::<f64>()
                / self.rms_window.len() as f64;
            let rms = mean_sq.sqrt() as f32;
            if rms > 0.0 {
                20.0 * rms.log10()
            } else {
                f32::NEG_INFINITY
            }
        };

        // ── Spectral flux ─────────────────────────────────────────────────────
        let spectral_flux = if self.flux_history.is_empty() {
            0.0
        } else {
            self.flux_history.iter().sum::<f32>() / self.flux_history.len() as f32
        };

        // ── Onset density (Phase 2.2.2) ───────────────────────────────────────
        // Используем реальные пики flux, а не длину буфера.
        let window_secs = self.flux_history.len() as f32 * self.hop_sec;
        let peak_count = self.count_flux_peaks();
        let onset_density_hz = if window_secs > 0.0 {
            peak_count as f32 / window_secs
        } else {
            0.0
        };

        // ── Нормализация [0, 1] ───────────────────────────────────────────────
        let rms_norm = if rms_dbfs.is_finite() {
            ((rms_dbfs - RMS_DBFS_MIN) / (RMS_DBFS_MAX - RMS_DBFS_MIN)).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let flux_norm = ((spectral_flux - FLUX_MIN) / (FLUX_MAX - FLUX_MIN)).clamp(0.0, 1.0);
        let density_norm =
            ((onset_density_hz - DENSITY_MIN) / (DENSITY_MAX - DENSITY_MIN)).clamp(0.0, 1.0);

        // ── Взвешенная сумма → level 1–10 ────────────────────────────────────
        let weighted = WEIGHT_RMS * rms_norm + WEIGHT_FLUX * flux_norm + WEIGHT_DENSITY * density_norm;
        let level = (weighted * 10.0).ceil().clamp(1.0, 10.0) as u8;

        EnergyResult {
            level,
            rms_dbfs: round3(rms_dbfs),
            spectral_flux: round6(spectral_flux),
            onset_density_hz: round3(onset_density_hz),
        }
    }

    pub fn reset(&mut self) {
        self.rms_window.clear();
        self.flux_history.clear();
    }
}

fn round3(v: f32) -> f32 {
    (v * 1000.0).round() / 1000.0
}

fn round6(v: f32) -> f32 {
    (v * 1_000_000.0).round() / 1_000_000.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn energy_result_default_level_is_zero() {
        let r = EnergyResult::default();
        assert_eq!(r.level, 0);
        assert_eq!(r.spectral_flux, 0.0);
    }

    #[test]
    fn energy_result_serializes() {
        let r = EnergyResult {
            level: 7,
            rms_dbfs: -12.5,
            spectral_flux: 0.43,
            onset_density_hz: 3.2,
        };
        let json = serde_json::to_string(&r).unwrap();
        assert!(json.contains("\"level\":7"));
        assert!(json.contains("\"onset_density_hz\":3.2"));
    }

    #[test]
    fn energy_reset_clears_state() {
        let mut ea = EnergyAnalyzer::new(48_000.0, 0.0025);
        let samples: Vec<f32> = (0..480).map(|i| (i as f32 * 0.01).sin() * 0.5).collect();
        ea.push_samples(&samples);
        ea.push_flux(0.05);
        ea.reset();
        assert!(ea.rms_window.is_empty());
        assert!(ea.flux_history.is_empty());
    }

    #[test]
    fn energy_level_silence_returns_low() {
        // Тишина (нули) → level = 1 (минимум шкалы).
        let mut ea = EnergyAnalyzer::new(48_000.0, 0.0025);
        let silence: Vec<f32> = vec![0.0; 48_000 * 3];
        ea.push_samples(&silence);
        ea.push_flux(0.0);
        let result = ea.current_energy();
        assert_eq!(result.level, 1, "silence should yield level=1");
    }

    #[test]
    fn energy_level_loud_pulse_above_five() {
        // Громкий синтетический пульс 200 BPM с нормализованным сигналом.
        // RMS ≈ -12 dBFS, flux 0.10, density 3.5 /s → level ≥ 5.
        let sr = 48_000_usize;
        let mut ea = EnergyAnalyzer::new(sr as f32, 0.0025);

        // Заполнить RMS-буфер сигналом амплитудой 0.25 (≈ -12 dBFS).
        let samples: Vec<f32> = (0..sr * 3).map(|i| 0.25 * ((i as f32 * 0.01).sin())).collect();
        ea.push_samples(&samples);

        // Flux ≈ 0.10 — типичный для чистого hitech-пульса.
        for _ in 0..1200 {
            ea.push_flux(0.10);
        }

        // Onset density вычисляется через count_flux_peaks() внутри.
        let result = ea.current_energy();
        assert!(
            result.level >= 5,
            "loud pulse should yield level >= 5, got {}",
            result.level
        );
    }
}
