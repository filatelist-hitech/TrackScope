// App-wide user settings backed by SharedPreferences.
//
// ChangeNotifier — listen for UI rebuilds.
// Call load() once at startup; changes persist immediately via save().

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/genre_preset/genre_preset.dart';

enum BpmSmoothing { none, light, moderate, heavy }

extension BpmSmoothingLabel on BpmSmoothing {
  String get label {
    switch (this) {
      case BpmSmoothing.none:     return 'Нет';
      case BpmSmoothing.light:    return 'Лёгкое';
      case BpmSmoothing.moderate: return 'Умеренное';
      case BpmSmoothing.heavy:    return 'Сильное';
    }
  }

  /// Median-window size passed to BpmSmoother.
  /// none=1 (pass-through), light=3, moderate=5, heavy=9.
  int get windowSize {
    switch (this) {
      case BpmSmoothing.none:     return 1;
      case BpmSmoothing.light:    return 3;
      case BpmSmoothing.moderate: return 5;
      case BpmSmoothing.heavy:    return 9;
    }
  }
}

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final instance = AppSettings._();

  static const _kShowWaveform     = 'showWaveform';
  static const _kShowSpectrum     = 'showSpectrum';
  static const _kKeepScreenOn     = 'keepScreenOn';
  static const _kInputSensitivity = 'inputSensitivity';
  static const _kBpmSmoothing     = 'bpmSmoothing';
  static const _kSelectedGenre    = 'selectedGenre';
  static const _kCustomMinBpm     = 'custom_min_bpm';
  static const _kCustomMaxBpm     = 'custom_max_bpm';

  bool showWaveform    = true;
  bool showSpectrum    = true;
  bool keepScreenOn    = true;
  double inputSensitivity = 0.0;          // dB, range –6..+6
  BpmSmoothing bpmSmoothing = BpmSmoothing.moderate;
  GenrePreset selectedGenre = GenrePreset.hitechPsy;
  double customMin = 155.0;
  double customMax = 230.0;

  /// Effective BPM range accounting for Custom preset.
  /// For Custom: returns (customMin, customMax).
  /// For any other preset: returns preset.bpmRange.
  (double, double) get effectiveBpmRange {
    if (selectedGenre == GenrePreset.custom) return (customMin, customMax);
    return selectedGenre.bpmRange;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    showWaveform       = prefs.getBool(_kShowWaveform) ?? true;
    showSpectrum       = prefs.getBool(_kShowSpectrum) ?? true;
    keepScreenOn       = prefs.getBool(_kKeepScreenOn) ?? true;
    inputSensitivity   = prefs.getDouble(_kInputSensitivity) ?? 0.0;
    final si           = prefs.getInt(_kBpmSmoothing) ?? 2;
    bpmSmoothing       = BpmSmoothing.values[si.clamp(0, BpmSmoothing.values.length - 1)];
    final gi           = prefs.getInt(_kSelectedGenre) ?? 0;
    selectedGenre      = GenrePreset.values[gi.clamp(0, GenrePreset.values.length - 1)];
    customMin          = prefs.getDouble(_kCustomMinBpm) ?? 155.0;
    customMax          = prefs.getDouble(_kCustomMaxBpm) ?? 230.0;
    notifyListeners();
  }

  Future<void> setShowWaveform(bool v) async {
    showWaveform = v; notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowWaveform, v);
  }

  Future<void> setShowSpectrum(bool v) async {
    showSpectrum = v; notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowSpectrum, v);
  }

  Future<void> setKeepScreenOn(bool v) async {
    keepScreenOn = v; notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeepScreenOn, v);
  }

  Future<void> setInputSensitivity(double v) async {
    inputSensitivity = v; notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kInputSensitivity, v);
  }

  Future<void> setBpmSmoothing(BpmSmoothing v) async {
    bpmSmoothing = v; notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBpmSmoothing, v.index);
  }

  Future<void> setSelectedGenre(GenrePreset v) async {
    selectedGenre = v; notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSelectedGenre, v.index);
  }

  /// Set custom BPM range. Ignored if min >= max, min < 80, or max > 300.
  Future<void> setCustomRange(double min, double max) async {
    if (min < 80 || max > 300 || min >= max) return;
    customMin = min;
    customMax = max;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kCustomMinBpm, min);
    await prefs.setDouble(_kCustomMaxBpm, max);
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    showWaveform     = true;
    showSpectrum     = true;
    keepScreenOn     = true;
    inputSensitivity = 0.0;
    bpmSmoothing     = BpmSmoothing.moderate;
    selectedGenre    = GenrePreset.hitechPsy;
    customMin        = 155.0;
    customMax        = 230.0;
    notifyListeners();
  }
}
