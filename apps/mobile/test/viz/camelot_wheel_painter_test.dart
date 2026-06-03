// Unit tests for camelotNeighbors() — the pure function in CamelotWheelPainter.
//
// Verifies: correct neighbor set, wrap-around at positions 1 and 12,
// cross-ring neighbor (A↔B), and invalid input handling.

import 'package:flutter_test/flutter_test.dart';

import 'package:TrackScope/viz/camelot_wheel_painter.dart';

void main() {
  group('camelotNeighbors', () {
    test('mid-wheel position returns two adjacent + cross-ring', () {
      final n = camelotNeighbors('8A');
      expect(n, containsAll(['7A', '9A', '8B']));
      expect(n.length, 3);
    });

    test('position 1 wraps backward to 12', () {
      final n = camelotNeighbors('1A');
      expect(n, containsAll(['12A', '2A', '1B']));
      expect(n.length, 3);
    });

    test('position 12 wraps forward to 1', () {
      final n = camelotNeighbors('12B');
      expect(n, containsAll(['11B', '1B', '12A']));
      expect(n.length, 3);
    });

    test('invalid input returns empty list', () {
      expect(camelotNeighbors(''), isEmpty);
      expect(camelotNeighbors('X'), isEmpty);
      expect(camelotNeighbors('13A'), isEmpty);
      expect(camelotNeighbors('0B'), isEmpty);
      expect(camelotNeighbors('8C'), isEmpty);
    });
  });
}
