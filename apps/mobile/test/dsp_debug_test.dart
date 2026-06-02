// Tests for DspDebug + KeyResult Dart contracts.
//
// Verifies: DspDebug.fromJson parses all fields correctly;
// DspResult.fromJson includes debug and key_result fields;
// missing debug key → zero defaults; KeyResult parsing from nested JSON.

import 'package:flutter_test/flutter_test.dart';

import 'package:hitech_bpm_radar/dsp/dsp_result.dart';

void main() {
  group('DspDebug.fromJson', () {
    test('parses all fields from full JSON', () {
      final json = {
        'onset_rate_hz': 3.25,
        'onset_strength': 0.0312,
        'tempo_peak_prominence': 0.4820,
        'harmonic_ambiguity': 0.08,
        'stability_score': 0.85,
        'warnings': ['clipping', 'breakdown_likely'],
      };

      final debug = DspDebug.fromJson(json);

      expect(debug.onsetRateHz, closeTo(3.25, 0.001));
      expect(debug.onsetStrength, closeTo(0.0312, 0.0001));
      expect(debug.tempoPeakProminence, closeTo(0.4820, 0.0001));
      expect(debug.harmonicAmbiguity, closeTo(0.08, 0.001));
      expect(debug.stabilityScore, closeTo(0.85, 0.001));
      expect(debug.warnings, equals(['clipping', 'breakdown_likely']));
    });

    test('returns zero defaults for empty JSON', () {
      final debug = DspDebug.fromJson(const {});

      expect(debug.onsetRateHz, 0.0);
      expect(debug.onsetStrength, 0.0);
      expect(debug.tempoPeakProminence, 0.0);
      expect(debug.harmonicAmbiguity, 0.0);
      expect(debug.stabilityScore, 0.0);
      expect(debug.warnings, isEmpty);
    });

    test('warnings list is empty when key absent', () {
      final debug = DspDebug.fromJson({'onset_rate_hz': 1.0});
      expect(debug.warnings, isEmpty);
    });

    test('integer numbers coerce to double', () {
      final debug = DspDebug.fromJson({
        'onset_rate_hz': 3,
        'onset_strength': 0,
        'stability_score': 1,
      });
      expect(debug.onsetRateHz, 3.0);
      expect(debug.onsetStrength, 0.0);
      expect(debug.stabilityScore, 1.0);
    });
  });

  group('DspResult.fromJson includes debug', () {
    const minimalResult = '''
    {
      "primary_bpm": 200.0,
      "confidence": 0.87,
      "lock_state": "STABLE",
      "signal_quality": {
        "clipping": false, "clipped_frame_ratio": 0.0,
        "noise_level": "low", "silence": false, "breakdown_likely": false
      },
      "candidates": [],
      "timing": {
        "analysis_time_sec": 12.0, "window_time_sec": 12.0,
        "hop_time_sec": 0.0025
      },
      "debug": {
        "onset_rate_hz": 3.33,
        "onset_strength": 0.0285,
        "tempo_peak_prominence": 0.51,
        "harmonic_ambiguity": 0.06,
        "stability_score": 0.82,
        "warnings": []
      }
    }
    ''';

    test('parses debug field from full DspResult JSON', () {
      final result = DspResult.parse(minimalResult);
      expect(result.debug.onsetRateHz, closeTo(3.33, 0.01));
      expect(result.debug.tempoPeakProminence, closeTo(0.51, 0.01));
      expect(result.debug.warnings, isEmpty);
    });

    test('parses key_result when present', () {
      const withKey = '''
      {
        "primary_bpm": 190.0,
        "confidence": 0.75,
        "lock_state": "STABLE",
        "signal_quality": {
          "clipping": false, "clipped_frame_ratio": 0.0,
          "noise_level": "low", "silence": false, "breakdown_likely": false
        },
        "candidates": [],
        "timing": {
          "analysis_time_sec": 12.0, "window_time_sec": 12.0,
          "hop_time_sec": 0.0025
        },
        "debug": {
          "onset_rate_hz": 3.0, "onset_strength": 0.03,
          "tempo_peak_prominence": 0.4, "harmonic_ambiguity": 0.1,
          "stability_score": 0.8, "warnings": []
        },
        "key_result": {
          "key": "A",
          "mode": "Minor",
          "camelot": { "number": 8, "letter": "A" },
          "confidence": 0.73
        }
      }
      ''';
      final result = DspResult.parse(withKey);
      expect(result.keyResult, isNotNull);
      expect(result.keyResult!.key, equals('A'));
      expect(result.keyResult!.mode, equals('Minor'));
      expect(result.keyResult!.camelot, equals('8A'));
      expect(result.keyResult!.confidence, closeTo(0.73, 0.001));
    });

    test('key_result absent when not in JSON', () {
      final result = DspResult.parse(minimalResult);
      expect(result.keyResult, isNull);
    });

    test('energy_result parses from JSON', () {
      const withEnergy = '''
      {
        "primary_bpm": 200.0,
        "confidence": 0.85,
        "lock_state": "STABLE",
        "signal_quality": {
          "clipping": false, "clipped_frame_ratio": 0.0,
          "noise_level": "low", "silence": false, "breakdown_likely": false
        },
        "candidates": [],
        "timing": {
          "analysis_time_sec": 12.0, "window_time_sec": 12.0,
          "hop_time_sec": 0.0025
        },
        "debug": {
          "onset_rate_hz": 3.0, "onset_strength": 0.03,
          "tempo_peak_prominence": 0.4, "harmonic_ambiguity": 0.1,
          "stability_score": 0.8, "warnings": []
        },
        "energy_result": {
          "level": 7,
          "rms_dbfs": -14.2,
          "spectral_flux": 0.083,
          "onset_density_hz": 3.15
        }
      }
      ''';
      final result = DspResult.parse(withEnergy);
      expect(result.energyResult, isNotNull);
      expect(result.energyResult!.level, equals(7));
      expect(result.energyResult!.rmsDbfs, closeTo(-14.2, 0.01));
      expect(result.energyResult!.spectralFlux, closeTo(0.083, 0.001));
      expect(result.energyResult!.onsetDensityHz, closeTo(3.15, 0.01));
    });

    test('energy_result absent when not in JSON', () {
      final result = DspResult.parse(minimalResult);
      expect(result.energyResult, isNull);
    });

    test('missing debug key → zero DspDebug', () {
      const noDebug = '''
      {
        "primary_bpm": null,
        "confidence": 0.0,
        "lock_state": "SEARCHING",
        "signal_quality": {
          "clipping": false, "clipped_frame_ratio": 0.0,
          "noise_level": "unknown", "silence": true, "breakdown_likely": false
        },
        "candidates": [],
        "timing": {
          "analysis_time_sec": 0.0, "window_time_sec": 12.0,
          "hop_time_sec": 0.0025
        }
      }
      ''';
      final result = DspResult.parse(noDebug);
      expect(result.debug.onsetRateHz, 0.0);
      expect(result.debug.onsetStrength, 0.0);
      expect(result.debug.warnings, isEmpty);
    });
  });
}
