// Tests for BpmSmoothing enum: windowSize and label mappings.

import 'package:flutter_test/flutter_test.dart';
import 'package:hitech_bpm_radar/settings/app_settings.dart';

void main() {
  group('BpmSmoothing.windowSize', () {
    test('none → 1 (pass-through)', () {
      expect(BpmSmoothing.none.windowSize, 1);
    });
    test('light → 3', () {
      expect(BpmSmoothing.light.windowSize, 3);
    });
    test('moderate → 5 (default)', () {
      expect(BpmSmoothing.moderate.windowSize, 5);
    });
    test('heavy → 9', () {
      expect(BpmSmoothing.heavy.windowSize, 9);
    });
    test('all values have non-zero windowSize', () {
      for (final v in BpmSmoothing.values) {
        expect(v.windowSize, greaterThanOrEqualTo(1));
      }
    });
    test('windowSizes are strictly increasing', () {
      final sizes = BpmSmoothing.values.map((v) => v.windowSize).toList();
      for (int i = 1; i < sizes.length; i++) {
        expect(sizes[i], greaterThan(sizes[i - 1]),
            reason: 'Each smoothing level should have a larger window');
      }
    });
  });

  group('BpmSmoothing.label', () {
    test('all values have non-empty label', () {
      for (final v in BpmSmoothing.values) {
        expect(v.label, isNotEmpty);
      }
    });
  });
}
