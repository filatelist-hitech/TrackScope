/// Real-time key detector using HPCP + Krumhansl-Schmuckler profiles.
///
/// Phase 2 implementation target. Phase 1 scaffold: types are defined,
/// методы возвращают `todo!()` и не вызываются в production-пути.
///
/// Алгоритм (Phase 2):
/// 1. STFT-фреймы → хроматический профиль 12-bin (HPCP).
/// 2. Accumulate HPCP в скользящем буфере ~8 сек.
/// 3. Correlate с Krumhansl-Schmuckler мажорными/минорными профилями.
/// 4. Выбрать тональность с максимальной корреляцией.
/// 5. Эмитить `KeyResult` с `camelot` и `confidence`.
use serde::Serialize;

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

pub struct KeyAnalyzer {
    _sample_rate: f32,
}

impl KeyAnalyzer {
    #[allow(dead_code)]
    pub fn new(sample_rate: f32) -> Self {
        let _ = sample_rate;
        todo!("Phase 2: KeyAnalyzer::new — HPCP accumulator not yet implemented")
    }

    #[allow(dead_code)]
    pub fn push_samples(&mut self, _samples: &[f32]) {
        todo!("Phase 2: KeyAnalyzer::push_samples — HPCP extraction not yet implemented")
    }

    #[allow(dead_code)]
    pub fn current_key(&self) -> KeyResult {
        todo!("Phase 2: KeyAnalyzer::current_key — Krumhansl-Schmuckler profile match not yet implemented")
    }

    #[allow(dead_code)]
    pub fn reset(&mut self) {
        todo!("Phase 2: KeyAnalyzer::reset — not yet implemented")
    }
}

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
}
