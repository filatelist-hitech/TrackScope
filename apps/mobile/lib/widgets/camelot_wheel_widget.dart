// CamelotWheelWidget — stateless wrapper around CamelotWheelPainter.
//
// When [keyResult] is null the wheel renders with all segments unlit (no active
// highlight), providing a visual placeholder.  RepaintBoundary isolates
// repaints from the surrounding ListView.

import 'package:flutter/material.dart';

import '../dsp/dsp_result.dart';
import '../viz/camelot_wheel_painter.dart';

class CamelotWheelWidget extends StatelessWidget {
  const CamelotWheelWidget({
    super.key,
    required this.keyResult,
    this.size = 180,
  });

  /// DSP key detection result. Null → wheel shown without active highlight.
  final KeyResult? keyResult;

  /// Diameter of the wheel in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: CamelotWheelPainter(
            activeKey: keyResult?.camelot,
          ),
        ),
      ),
    );
  }
}
