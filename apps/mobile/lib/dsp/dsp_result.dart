// Типизированное представление JSON-`DspResult`, который Rust-DSP
// эмитит через границу FFI. Зеркалит контракт, описанный в
// `docs/DSP_ALGORITHM.md`. Никаких вычислений BPM в этом файле — он
// только парсит то, что Rust уже решил.

import 'dart:convert';

enum LockState {
  searching,
  locking,
  stable,
  unstable,
  breakdown,
  clippedMic,
  noiseOnly,
  unknown;

  static LockState parse(String? raw) {
    switch (raw) {
      case 'SEARCHING':
        return LockState.searching;
      case 'LOCKING':
        return LockState.locking;
      case 'STABLE':
        return LockState.stable;
      case 'UNSTABLE':
        return LockState.unstable;
      case 'BREAKDOWN':
        return LockState.breakdown;
      case 'CLIPPED_MIC':
        return LockState.clippedMic;
      case 'NOISE_ONLY':
        return LockState.noiseOnly;
      default:
        return LockState.unknown;
    }
  }

  String get wireName {
    switch (this) {
      case LockState.searching:
        return 'SEARCHING';
      case LockState.locking:
        return 'LOCKING';
      case LockState.stable:
        return 'STABLE';
      case LockState.unstable:
        return 'UNSTABLE';
      case LockState.breakdown:
        return 'BREAKDOWN';
      case LockState.clippedMic:
        return 'CLIPPED_MIC';
      case LockState.noiseOnly:
        return 'NOISE_ONLY';
      case LockState.unknown:
        return 'UNKNOWN';
    }
  }
}

class SignalQuality {
  const SignalQuality({
    required this.inputLevelDbfs,
    required this.peakDbfs,
    required this.clipping,
    required this.clippedFrameRatio,
    required this.noiseLevel,
    required this.snrEstimateDb,
    required this.silence,
    required this.breakdownLikely,
  });

  final double? inputLevelDbfs;
  final double? peakDbfs;
  final bool clipping;
  final double clippedFrameRatio;
  final String noiseLevel;
  final double? snrEstimateDb;
  final bool silence;
  final bool breakdownLikely;

  factory SignalQuality.fromJson(Map<String, dynamic> json) => SignalQuality(
        inputLevelDbfs: _asDoubleOrNull(json['input_level_dbfs']),
        peakDbfs: _asDoubleOrNull(json['peak_dbfs']),
        clipping: json['clipping'] as bool? ?? false,
        clippedFrameRatio:
            _asDoubleOrNull(json['clipped_frame_ratio']) ?? 0.0,
        noiseLevel: json['noise_level'] as String? ?? 'unknown',
        snrEstimateDb: _asDoubleOrNull(json['snr_estimate_db']),
        silence: json['silence'] as bool? ?? false,
        breakdownLikely: json['breakdown_likely'] as bool? ?? false,
      );
}

class TempoCandidate {
  const TempoCandidate({
    required this.bpm,
    required this.relation,
    required this.score,
    required this.rawScore,
    required this.stabilityScore,
    required this.rangeScore,
    required this.sourceBpm,
  });

  final double bpm;
  final String relation;
  final double score;
  final double rawScore;
  final double stabilityScore;
  final double rangeScore;
  final double? sourceBpm;

  factory TempoCandidate.fromJson(Map<String, dynamic> json) => TempoCandidate(
        bpm: _asDoubleOrNull(json['bpm']) ?? 0.0,
        relation: json['relation'] as String? ?? 'raw',
        score: _asDoubleOrNull(json['score']) ?? 0.0,
        rawScore: _asDoubleOrNull(json['raw_score']) ?? 0.0,
        stabilityScore: _asDoubleOrNull(json['stability_score']) ?? 0.0,
        rangeScore: _asDoubleOrNull(json['range_score']) ?? 0.0,
        sourceBpm: _asDoubleOrNull(json['source_bpm']),
      );
}

class DspTiming {
  const DspTiming({
    required this.analysisTimeSec,
    required this.windowTimeSec,
    required this.hopTimeSec,
    required this.firstLockTimeSec,
  });

  final double analysisTimeSec;
  final double windowTimeSec;
  final double hopTimeSec;
  final double? firstLockTimeSec;

  factory DspTiming.fromJson(Map<String, dynamic> json) => DspTiming(
        analysisTimeSec: _asDoubleOrNull(json['analysis_time_sec']) ?? 0.0,
        windowTimeSec: _asDoubleOrNull(json['window_time_sec']) ?? 0.0,
        hopTimeSec: _asDoubleOrNull(json['hop_time_sec']) ?? 0.0,
        firstLockTimeSec: _asDoubleOrNull(json['first_lock_time_sec']),
      );
}

/// Диагностические поля, эмитируемые Rust-DSP вместе с каждым DspResult.
///
/// Все значения вычисляются как побочный продукт обычного анализа —
/// без дополнительных CPU-затрат. Никакой BPM-математики здесь нет.
class DspDebug {
  const DspDebug({
    required this.onsetRateHz,
    required this.onsetStrength,
    required this.tempoPeakProminence,
    required this.harmonicAmbiguity,
    required this.stabilityScore,
    required this.warnings,
  });

  /// Число значимых темповых пиков в секунду в текущем окне.
  final double onsetRateHz;

  /// Средняя амплитуда огибающей онсетов (spectral flux) по окну.
  final double onsetStrength;

  /// Prominence главного темпового пика нормализованной автокорреляции.
  final double tempoPeakProminence;

  /// Мера конкурирующих кандидатов за темповое пространство. 0 = нет конкуренции.
  final double harmonicAmbiguity;

  /// stability_score основного кандидата на момент снапшота.
  final double stabilityScore;

  /// Текстовые предупреждения (clipping, breakdown_likely, harmonic_ambiguity).
  final List<String> warnings;

  factory DspDebug.fromJson(Map<String, dynamic> json) => DspDebug(
        onsetRateHz: _asDoubleOrNull(json['onset_rate_hz']) ?? 0.0,
        onsetStrength: _asDoubleOrNull(json['onset_strength']) ?? 0.0,
        tempoPeakProminence:
            _asDoubleOrNull(json['tempo_peak_prominence']) ?? 0.0,
        harmonicAmbiguity:
            _asDoubleOrNull(json['harmonic_ambiguity']) ?? 0.0,
        stabilityScore: _asDoubleOrNull(json['stability_score']) ?? 0.0,
        warnings: ((json['warnings'] as List?) ?? const [])
            .whereType<String>()
            .toList(growable: false),
      );
}

/// Детектированная тональность (Phase 2.1).
///
/// `key`, `mode` и `camelot` — `null` если уверенность ниже порога
/// Уровень энергии 1–10 (Mixed In Key-стиль).
/// `null` при тишине или CLIPPED_MIC — anti-fake: нет уровня без сигнала.
class EnergyResult {
  const EnergyResult({
    required this.level,
    required this.rmsDbfs,
    required this.spectralFlux,
    required this.onsetDensityHz,
  });

  /// 1 (очень тихо) — 10 (очень интенсивно).
  final int level;

  /// RMS-уровень в dBFS за скользящее окно.
  final double rmsDbfs;

  /// Средний spectral flux за скользящее окно.
  final double spectralFlux;

  /// Плотность онсетов (онсетов/сек).
  final double onsetDensityHz;

  factory EnergyResult.fromJson(Map<String, dynamic> json) => EnergyResult(
        level: (json['level'] as num?)?.toInt() ?? 0,
        rmsDbfs: _asDoubleOrNull(json['rms_dbfs']) ?? double.negativeInfinity,
        spectralFlux: _asDoubleOrNull(json['spectral_flux']) ?? 0.0,
        onsetDensityHz: _asDoubleOrNull(json['onset_density_hz']) ?? 0.0,
      );
}

/// или DSP находится в CLIPPED_MIC / тишине. Никогда не содержит
/// хардкодных значений — только результат Rust HPCP + K-S алгоритма.
class KeyResult {
  const KeyResult({
    this.key,
    this.mode,
    this.camelot,
    required this.confidence,
  });

  /// Нотное имя тональности: "C", "Db", "D", …, "B". Null если нет данных.
  final String? key;

  /// "Major" | "Minor". Null если нет данных.
  final String? mode;

  /// Camelot-нотация: "8A", "8B", …, "12A". Null если нет данных.
  final String? camelot;

  /// Уверенность 0.0–1.0 (нормализованный коэффициент Пирсона).
  final double confidence;

  factory KeyResult.fromJson(Map<String, dynamic> json) {
    final camelotRaw = json['camelot'];
    String? camelotStr;
    if (camelotRaw is Map) {
      final number = camelotRaw['number'];
      final letter = camelotRaw['letter'];
      if (number != null && letter != null) {
        camelotStr = '$number$letter';
      }
    } else if (camelotRaw is String) {
      camelotStr = camelotRaw;
    }
    return KeyResult(
      key: json['key'] as String?,
      mode: json['mode'] as String?,
      camelot: camelotStr,
      confidence: _asDoubleOrNull(json['confidence']) ?? 0.0,
    );
  }
}

class DspResult {
  const DspResult({
    required this.primaryBpm,
    required this.confidence,
    required this.lockState,
    required this.signalQuality,
    required this.candidates,
    required this.timing,
    required this.debug,
    this.keyResult,
    this.energyResult,
  });

  /// `null`, когда DSP не перешагнул порог захвата. UI ОБЯЗАН отрисовать
  /// это как «нет значения» — никогда не выдумывать плейсхолдерный BPM.
  final double? primaryBpm;
  final double confidence;
  final LockState lockState;
  final SignalQuality signalQuality;
  final List<TempoCandidate> candidates;
  final DspTiming timing;

  /// Диагностика алгоритма. Содержит реальные значения из Rust DSP.
  final DspDebug debug;

  /// Детектированная тональность. `null` при тишине, клиппинге или низкой уверенности.
  final KeyResult? keyResult;

  /// Уровень энергии 1–10. `null` при тишине или клиппинге.
  final EnergyResult? energyResult;

  factory DspResult.fromJson(Map<String, dynamic> json) => DspResult(
        primaryBpm: _asDoubleOrNull(json['primary_bpm']),
        confidence: _asDoubleOrNull(json['confidence']) ?? 0.0,
        lockState: LockState.parse(json['lock_state'] as String?),
        signalQuality: SignalQuality.fromJson(
            (json['signal_quality'] as Map?)?.cast<String, dynamic>() ??
                const {}),
        candidates: ((json['candidates'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => TempoCandidate.fromJson(m.cast<String, dynamic>()))
            .toList(growable: false),
        timing: DspTiming.fromJson(
            (json['timing'] as Map?)?.cast<String, dynamic>() ?? const {}),
        debug: DspDebug.fromJson(
            (json['debug'] as Map?)?.cast<String, dynamic>() ?? const {}),
        keyResult: json['key_result'] == null
            ? null
            : KeyResult.fromJson(
                (json['key_result'] as Map).cast<String, dynamic>()),
        energyResult: json['energy_result'] == null
            ? null
            : EnergyResult.fromJson(
                (json['energy_result'] as Map).cast<String, dynamic>()),
      );

  static DspResult parse(String json) =>
      DspResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

double? _asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return null;
}
