// App-wide user settings backed by SharedPreferences.
//
// ChangeNotifier — listen for UI rebuilds.
// Call load() once at startup; changes persist immediately via save().

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final instance = AppSettings._();

  static const _kShowWaveform = 'showWaveform';
  static const _kShowSpectrum = 'showSpectrum';
  static const _kKeepScreenOn = 'keepScreenOn';
  static const _kInputSensitivity = 'inputSensitivity';

  bool showWaveform = true;
  bool showSpectrum = true;
  bool keepScreenOn = true;
  double inputSensitivity = 0.0; // dB, range –6..+6

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    showWaveform = prefs.getBool(_kShowWaveform) ?? true;
    showSpectrum = prefs.getBool(_kShowSpectrum) ?? true;
    keepScreenOn = prefs.getBool(_kKeepScreenOn) ?? true;
    inputSensitivity = prefs.getDouble(_kInputSensitivity) ?? 0.0;
    notifyListeners();
  }

  Future<void> setShowWaveform(bool v) async {
    showWaveform = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowWaveform, v);
  }

  Future<void> setShowSpectrum(bool v) async {
    showSpectrum = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowSpectrum, v);
  }

  Future<void> setKeepScreenOn(bool v) async {
    keepScreenOn = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeepScreenOn, v);
  }

  Future<void> setInputSensitivity(double v) async {
    inputSensitivity = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kInputSensitivity, v);
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    showWaveform = true;
    showSpectrum = true;
    keepScreenOn = true;
    inputSensitivity = 0.0;
    notifyListeners();
  }
}
