// Feature flags, производные от Pro-статуса и жанрового пресета.
//
// Централизует все гейты Free vs Pro: BPM-диапазон, доступ к debug-экрану,
// экспорту, виджету, лимиты истории, жанровый пикер. UI и бизнес-логика
// зависят только от этого класса, а не от `ProStatusService` напрямую.

import '../features/genre_preset/genre_preset.dart';

class FeatureFlags {
  const FeatureFlags({
    required this.isPro,
    this.selectedGenre = GenrePreset.hitechPsy,
  });

  final bool isPro;
  final GenrePreset selectedGenre;

  // BPM range — derived from selectedGenre, clamped to tier.
  // Free tier: genre must be in freePresets; Pro: any genre.
  // Phase 1: only minBpm is passed to FFI (ADR-003).
  GenrePreset get _effectiveGenre =>
      (!isPro && selectedGenre.isProRequired) ? GenrePreset.hitechPsy : selectedGenre;

  double get minBpm {
    final genre = _effectiveGenre;
    // hitechPsy Free: 155–170 range is Pro-gated (original tier gate preserved).
    if (!isPro && genre == GenrePreset.hitechPsy) return 170.0;
    return genre.bpmRange.$1;
  }

  double get maxBpm => _effectiveGenre.bpmRange.$2;

  // Feature access gates
  bool get canAccessDebugScreen  => isPro;
  bool get canExport             => isPro;
  bool get canAccessWidget       => isPro;
  bool get canAccessSetlist      => isPro;
  bool get canAccessGenrePicker  => true;  // picker visible to all; Pro presets gated in UI

  // Genre presets available to this tier
  List<GenrePreset> get availablePresets =>
      isPro ? GenrePreset.allPresets : GenrePreset.freePresets;

  // History limits
  Duration get maxHistoryDuration => isPro
      ? const Duration(hours: 24) // Pro: unlimited (24h cap as safety)
      : const Duration(seconds: 30); // Free: 30 seconds

  int get maxHistorySamples => isPro
      ? 86400 // Pro: 24h at 1 Hz
      : 30; // Free: 30 samples at 1 Hz
}
