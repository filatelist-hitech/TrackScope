// Dart-обёртка над C ABI hitech-bpm-ffi.
//
// Обязанности:
//   - Владеть нативным handle `HitechBpmEngine*` на всё время жизни.
//   - Маршалить PCM-кадры `Float32List` в закреплённую нативную память
//     и передавать их в `hitech_bpm_engine_push_samples`.
//   - Опрашивать `hitech_bpm_engine_analyze_json` по таймеру UI-частоты
//     (по умолчанию 20 Гц) и эмитить распарсенные снапшоты [DspResult]
//     в broadcast-поток.
//
// Чего этот файл НЕ делает:
//   - Никаких вычислений BPM. Все решения о темпе, уверенности и
//     состоянии захвата остаются в Rust-DSP — этот слой чисто
//     транзитный.
//   - Никакого захвата с микрофона. Микрофонный вход — это следующий
//     патч; пока PCM поставляет вызывающий (тест или будущий
//     аудио-мост).

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pffi;

import 'bindings.dart';
import 'dsp_result.dart';

/// Имя файла shared library по умолчанию на каждой платформе. Ищется
/// относительно пути поиска процесса, если [DspEngine.open] не получил
/// явный путь.
String defaultLibraryName() {
  if (Platform.isMacOS) return 'libhitech_bpm_ffi.dylib';
  if (Platform.isIOS) return 'hitech_bpm_ffi.framework/hitech_bpm_ffi';
  if (Platform.isAndroid) return 'libhitech_bpm_ffi.so';
  if (Platform.isLinux) return 'libhitech_bpm_ffi.so';
  if (Platform.isWindows) return 'hitech_bpm_ffi.dll';
  throw UnsupportedError('Неподдерживаемая платформа: ${Platform.operatingSystem}');
}

/// Владеет одним экземпляром нативного DSP-движка и отдаёт его
/// скользящее состояние как broadcast [Stream] из снапшотов [DspResult].
class DspEngine {
  DspEngine._(this._ffi, this._handle, {required Duration pollInterval})
      : _pollInterval = pollInterval {
    _resultController = StreamController<DspResult>.broadcast(
      onListen: _startPolling,
      onCancel: _stopPollingIfIdle,
    );
  }

  /// Открывает shared library по пути [libraryPath] (или по дефолтному
  /// пути поиска платформы) и выделяет новый handle движка.
  factory DspEngine.open({
    String? libraryPath,
    Duration pollInterval = const Duration(milliseconds: 50),
  }) {
    final dylib = libraryPath != null
        ? ffi.DynamicLibrary.open(libraryPath)
        : ffi.DynamicLibrary.open(defaultLibraryName());
    return DspEngine.fromBindings(HitechBpmFfi(dylib),
        pollInterval: pollInterval);
  }

  /// Создание из уже разрешённых привязок. Полезно для тестов, которые
  /// делят одну dylib между несколькими экземплярами движка.
  factory DspEngine.fromBindings(
    HitechBpmFfi bindings, {
    Duration pollInterval = const Duration(milliseconds: 50),
  }) {
    final handle = bindings.engineNew();
    if (handle == ffi.nullptr) {
      throw StateError('hitech_bpm_engine_new вернул null');
    }
    return DspEngine._(bindings, handle, pollInterval: pollInterval);
  }

  final HitechBpmFfi _ffi;
  ffi.Pointer<HitechBpmEngine> _handle;
  final Duration _pollInterval;
  late final StreamController<DspResult> _resultController;
  Timer? _pollTimer;
  bool _disposed = false;

  /// Broadcast-поток скользящих снапшотов [DspResult]. Поток эмитит с
  /// частотой [pollInterval]; подписчики получают последнее состояние
  /// движка, а не покадровую трассу.
  Stream<DspResult> get results => _resultController.stream;

  /// Сбрасывает скользящее DSP-состояние на месте. Handle остаётся
  /// валидным.
  void reset() {
    _ensureAlive();
    _ffi.engineReset(_handle);
  }

  /// Кладёт моно Float32 PCM-кадр с частотой [sampleRate]. Цена аллокаций
  /// — один закреплённый нативный буфер за вызов; вызывающий может
  /// пушить так быстро, как приходят аудио-кадры.
  ///
  /// Возвращает `false`, если FFI отверг вход (нулевая длина, нулевая
  /// частота дискретизации и т.п.); Rust-сторона никогда не паникует на
  /// плохом входе.
  bool pushSamples(Float32List samples, int sampleRate) {
    _ensureAlive();
    if (samples.isEmpty) return false;
    final buffer = pffi.calloc<ffi.Float>(samples.length);
    try {
      final asFloats = buffer.asTypedList(samples.length);
      asFloats.setAll(0, samples);
      return _ffi.enginePushSamples(
          _handle, buffer, samples.length, sampleRate);
    } finally {
      pffi.calloc.free(buffer);
    }
  }

  /// Синхронно опрашивает текущий скользящий [DspResult]. Обёрнутый
  /// поток вызывает это по таймеру; тесты могут вызывать напрямую.
  DspResult analyze() => DspResult.parse(analyzeJson());

  /// То же, что [analyze], но возвращает сырую JSON-строку, которую
  /// эмитит FFI. Полезно для изолята DSP-воркера, который пересылает
  /// JSON главному изоляту, минуя предварительный round-trip через
  /// типизированный объект.
  String analyzeJson() {
    _ensureAlive();
    final cstr = _ffi.engineAnalyzeJson(_handle);
    if (cstr == ffi.nullptr) {
      throw StateError('hitech_bpm_engine_analyze_json вернул null');
    }
    try {
      return _readCString(cstr);
    } finally {
      _ffi.stringFree(cstr);
    }
  }

  /// Останавливает опрос, освобождает нативный handle, закрывает поток.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_handle != ffi.nullptr) {
      _ffi.engineFree(_handle);
      _handle = ffi.nullptr;
    }
    await _resultController.close();
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(_pollInterval, (_) {
      if (_disposed) return;
      try {
        final snapshot = analyze();
        if (!_resultController.isClosed) {
          _resultController.add(snapshot);
        }
      } catch (e, st) {
        if (!_resultController.isClosed) {
          _resultController.addError(e, st);
        }
      }
    });
  }

  void _stopPollingIfIdle() {
    if (!_resultController.hasListener) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _ensureAlive() {
    if (_disposed || _handle == ffi.nullptr) {
      throw StateError('DspEngine уже освобождён');
    }
  }

  static String _readCString(ffi.Pointer<ffi.Char> ptr) {
    final bytes = <int>[];
    final raw = ptr.cast<ffi.Uint8>();
    var i = 0;
    while (true) {
      final byte = raw[i];
      if (byte == 0) break;
      bytes.add(byte);
      i++;
    }
    return utf8.decode(bytes);
  }
}
