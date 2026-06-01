// WaveformColumn — one time-slice of band-split energy for the bar waveform.
//
// Computed from the FFT magnitudes already produced by VizController for the
// spectrogram, so no extra FFT pass is needed.
//
// Band boundaries (48 kHz, FFT 1024 → bin_hz ≈ 46.875 Hz):
//   bass : bins  0– 6  (  0– 328 Hz)  kick / sub-bass
//   mid  : bins  7–63  (329–2953 Hz)  body / snare
//   high : bins 64–127 (2954–5953 Hz)  hats / transients  (capped at _kDisplayBins)

class WaveformColumn {
  const WaveformColumn({
    required this.amplitude,
    required this.bassWeight,
    required this.midWeight,
    required this.highWeight,
  });

  /// Normalised column amplitude in [0, 1] (adaptive-peak normalised energy).
  final double amplitude;

  /// Fraction of total energy in bass bins (0–6). Range [0, 1].
  final double bassWeight;

  /// Fraction of total energy in mid bins (7–63). Range [0, 1].
  final double midWeight;

  /// Fraction of total energy in high bins (64–127). Range [0, 1].
  final double highWeight;

  static const WaveformColumn empty = WaveformColumn(
    amplitude: 0,
    bassWeight: 0,
    midWeight: 0,
    highWeight: 0,
  );
}
