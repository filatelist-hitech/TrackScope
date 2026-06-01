/// BPM-диапазоны для разных жанров электронной музыки.
///
/// Диапазон определяет `target_bpm_min` / `target_bpm_max` в `DspConfig`.
/// Пороги нормализации (<threshold_low → ×2, >threshold_high → ÷2)
/// подобраны под специфику каждого жанра, чтобы минимизировать
/// half-time / double-time ошибки.
use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum GenrePreset {
    HitechPsy,
    Psytrance,
    Darkpsy,
    DrumAndBass,
    Techno,
    Hardstyle,
    Hardcore,
    Custom(f32, f32),
}

impl Default for GenrePreset {
    fn default() -> Self {
        Self::HitechPsy
    }
}

impl GenrePreset {
    pub fn bpm_range(self) -> (f32, f32) {
        match self {
            Self::HitechPsy => (155.0, 230.0),
            Self::Psytrance => (130.0, 160.0),
            Self::Darkpsy => (145.0, 180.0),
            Self::DrumAndBass => (160.0, 185.0),
            Self::Techno => (125.0, 145.0),
            Self::Hardstyle => (138.0, 160.0),
            Self::Hardcore => (155.0, 185.0),
            Self::Custom(a, b) => (a, b),
        }
    }

    /// Порог нормализации: (ниже → ×2, выше → ÷2).
    /// Позволяет избегать half/double ловушек для жанров с нестандартными
    /// диапазонами относительно дефолтных hitech-порогов (<130, >260).
    pub fn normalization_thresholds(self) -> (f32, f32) {
        match self {
            Self::DrumAndBass => (80.0, 240.0),
            Self::Techno => (65.0, 200.0),
            Self::Psytrance => (65.0, 200.0),
            _ => (130.0, 260.0),
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::HitechPsy => "Hitech / Psy",
            Self::Psytrance => "Psytrance",
            Self::Darkpsy => "Darkpsy",
            Self::DrumAndBass => "Drum & Bass",
            Self::Techno => "Techno",
            Self::Hardstyle => "Hardstyle",
            Self::Hardcore => "Hardcore",
            Self::Custom(_, _) => "Custom",
        }
    }

    pub fn is_pro_required(self) -> bool {
        matches!(self, Self::Custom(_, _))
    }

    /// Жанры, доступные в Free-tier (без Pro).
    pub fn free_presets() -> &'static [GenrePreset] {
        &[
            GenrePreset::HitechPsy,
            GenrePreset::Psytrance,
            GenrePreset::Darkpsy,
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hitech_range() {
        assert_eq!(GenrePreset::HitechPsy.bpm_range(), (155.0, 230.0));
    }

    #[test]
    fn psytrance_range() {
        assert_eq!(GenrePreset::Psytrance.bpm_range(), (130.0, 160.0));
    }

    #[test]
    fn dnb_normalization_threshold() {
        let (lo, hi) = GenrePreset::DrumAndBass.normalization_thresholds();
        assert_eq!(lo, 80.0);
        assert_eq!(hi, 240.0);
        // DnB 170 BPM не должен удваиваться: 170 > 80 (нет ×2)
        assert!(170.0 > lo);
    }

    #[test]
    fn custom_requires_pro() {
        assert!(GenrePreset::Custom(140.0, 180.0).is_pro_required());
    }

    #[test]
    fn non_custom_does_not_require_pro() {
        for preset in [
            GenrePreset::HitechPsy,
            GenrePreset::Psytrance,
            GenrePreset::DrumAndBass,
        ] {
            assert!(!preset.is_pro_required(), "{:?} should be free", preset);
        }
    }

    #[test]
    fn free_presets_are_not_pro() {
        for p in GenrePreset::free_presets() {
            assert!(!p.is_pro_required());
        }
    }

    #[test]
    fn default_is_hitech() {
        assert_eq!(GenrePreset::default(), GenrePreset::HitechPsy);
    }
}
