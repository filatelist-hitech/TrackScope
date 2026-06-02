import '../../dsp/dsp_result.dart';

/// Одна запись в сетлисте: момент времени + BPM-снапшот.
///
/// Phase 2: добавить `camelotKey` и `energyLevel`, когда KeyAnalyzer готов.
class SetlistEntry {
  const SetlistEntry({
    required this.timestamp,
    required this.bpm,
    required this.lockState,
    required this.confidence,
    required this.inputLevelDbfs,
  });

  final DateTime timestamp;
  final double bpm;
  final LockState lockState;
  final double confidence;
  final double inputLevelDbfs;

  // Phase 2 placeholders — не null после Phase 2 KeyAnalyzer
  // final String? camelotKey;
  // final int? energyLevel;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'bpm': bpm,
        'lock_state': lockState.wireName,
        'confidence': confidence,
        'input_level_dbfs': inputLevelDbfs,
      };

  String toCsvRow() =>
      '${timestamp.toIso8601String()},$bpm,${lockState.wireName},$confidence,$inputLevelDbfs';
}

const String setlistCsvHeader =
    'timestamp,bpm,lock_state,confidence,input_level_dbfs';
