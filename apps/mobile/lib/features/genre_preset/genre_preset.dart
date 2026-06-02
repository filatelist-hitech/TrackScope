// Dart mirror of core/dsp/src/genre_preset.rs.
// BPM ranges and labels only — no DSP math here.
//
// Phase 1: only minBpm is passed to FFI via the existing
// hitech_bpm_engine_new_with_min_bpm knob (ADR-003).
// Phase 2: add normalization thresholds via hitech_bpm_engine_new_with_config.

enum GenrePreset {
  hitechPsy,
  psytrance,
  darkpsy,
  drumAndBass,
  techno,
  hardstyle,
  hardcore;

  /// (minBpm, maxBpm) for this genre.
  (double, double) get bpmRange => switch (this) {
    hitechPsy   => (155.0, 230.0),
    psytrance   => (130.0, 160.0),
    darkpsy     => (145.0, 180.0),
    drumAndBass => (160.0, 185.0),
    techno      => (125.0, 145.0),
    hardstyle   => (138.0, 160.0),
    hardcore    => (155.0, 185.0),
  };

  String get label => switch (this) {
    hitechPsy   => 'Hitech / Psy',
    psytrance   => 'Psytrance',
    darkpsy     => 'Darkpsy',
    drumAndBass => 'Drum & Bass',
    techno      => 'Techno',
    hardstyle   => 'Hardstyle',
    hardcore    => 'Hardcore',
  };

  bool get isProRequired => switch (this) {
    hitechPsy || psytrance || darkpsy => false,
    _ => true,
  };

  static const List<GenrePreset> freePresets = [
    hitechPsy,
    psytrance,
    darkpsy,
  ];

  static const List<GenrePreset> allPresets = GenrePreset.values;
}
