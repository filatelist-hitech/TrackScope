/// Energy level 1–10 via RMS + spectral flux + onset density.
///
/// Phase 2 implementation target. Phase 1 scaffold: типы определены,
/// методы возвращают `todo!()` и не вызываются в production-пути.
///
/// Алгоритм (Phase 2):
/// 1. RMS в скользящем окне 3 сек → input_level_dbfs (уже в DspResult).
/// 2. Spectral flux среднее по горизонту → мера динамики.
/// 3. Onset density (onsets/сек из onset_history).
/// 4. Нормализация трёх компонент, взвешенная сумма → 0..1.
/// 5. Квантизация в 1–10 (Mixed In Key-стиль).
use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct EnergyResult {
    /// 1 (очень тихо) — 10 (очень интенсивно), Mixed In Key-стиль.
    pub level: u8,
    /// RMS-уровень в dBFS (ссылка на input_level_dbfs из SignalQuality).
    pub rms_dbfs: f32,
    /// Средний spectral flux за скользящее окно.
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

pub struct EnergyAnalyzer {
    _sample_rate: f32,
}

impl EnergyAnalyzer {
    #[allow(dead_code)]
    pub fn new(sample_rate: f32) -> Self {
        let _ = sample_rate;
        todo!("Phase 2: EnergyAnalyzer::new — not yet implemented")
    }

    #[allow(dead_code)]
    pub fn push_samples(&mut self, _samples: &[f32]) {
        todo!("Phase 2: EnergyAnalyzer::push_samples — not yet implemented")
    }

    #[allow(dead_code)]
    pub fn current_energy(&self) -> EnergyResult {
        todo!("Phase 2: EnergyAnalyzer::current_energy — not yet implemented")
    }

    #[allow(dead_code)]
    pub fn reset(&mut self) {
        todo!("Phase 2: EnergyAnalyzer::reset — not yet implemented")
    }
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
}
