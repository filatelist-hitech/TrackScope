import '../../dsp/dsp_result.dart';

/// Одна запись в сетлисте: момент времени + BPM-снапшот.
class SetlistEntry {
  const SetlistEntry({
    required this.timestamp,
    required this.bpm,
    required this.lockState,
    required this.confidence,
    required this.inputLevelDbfs,
    this.camelotKey,
    this.energyLevel,
  });

  final DateTime timestamp;
  final double bpm;
  final LockState lockState;
  final double confidence;
  final double inputLevelDbfs;

  /// Camelot-тональность из KeyAnalyzer, например «8A». null если не определена.
  final String? camelotKey;

  /// Уровень энергии 1–10 из EnergyAnalyzer. null если не определён.
  final int? energyLevel;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'bpm': bpm,
        'lock_state': lockState.wireName,
        'confidence': confidence,
        'input_level_dbfs': inputLevelDbfs,
        if (camelotKey != null) 'camelot_key': camelotKey,
        if (energyLevel != null) 'energy_level': energyLevel,
      };

  String toCsvRow() =>
      '${timestamp.toIso8601String()},$bpm,${lockState.wireName},$confidence,$inputLevelDbfs'
      ',${camelotKey ?? ''},${energyLevel ?? ''}';
}

const String setlistCsvHeader =
    'timestamp,bpm,lock_state,confidence,input_level_dbfs,camelot_key,energy_level';
