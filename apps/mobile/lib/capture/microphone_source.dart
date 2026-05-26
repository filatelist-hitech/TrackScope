// Боевой аудио-источник: открывает `package:record` и отдаёт сырой
// PCM-байтовый поток, который `CaptureBridge` пересылает в DSP-воркер.
//
// Согласование форматов (см. docs/MOBILE_AUDIO.md):
//   - Android: `record` использует AudioRecord, выдаёт PCM 16-bit signed
//     little-endian моно на запрошенной частоте дискретизации (здесь
//     48 кГц).
//   - iOS: `record` использует AVAudioEngine с тем же wire-форматом.
//   - DSP ожидает моно f32 в [-1, 1]; воркер моста конвертирует
//     PCM16 → f32 как `s / 32768.0` для каждого сэмпла. Ресемплинг не
//     нужен, потому что у платформы запрашивается предпочитаемая DSP
//     частота 48 кГц.
//
// Этот файл не импортирует ни UI, ни DSP-код — это тонкая обёртка над
// recorder-пакетом, чтобы мост оставался без UI-зависимостей.

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

class MicrophoneSource {
  MicrophoneSource({this.sampleRate = 48000});

  final int sampleRate;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  StreamController<Uint8List>? _ctrl;

  /// Реальная wire-кодировка, которую должен ожидать воркер. Хранится
  /// здесь, чтобы мост согласовывал кодировку, а не хардкодил её.
  static const String encoding = 'pcm16';

  /// Запускает захват. Вызывающий обязан заранее проверить разрешение
  /// на микрофон — этот метод его НЕ запрашивает, потому что UI для
  /// разрешений живёт в слое виджетов.
  Future<Stream<Uint8List>> start() async {
    if (_ctrl != null) {
      throw StateError('MicrophoneSource уже запущен');
    }
    final ctrl = StreamController<Uint8List>(
      onCancel: () async => stop(),
    );
    _ctrl = ctrl;
    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
    );
    final raw = await _recorder.startStream(config);
    _sub = raw.listen(
      ctrl.add,
      onError: ctrl.addError,
      onDone: ctrl.close,
    );
    return ctrl.stream;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {
      // Recorder уже мог быть остановлен — больше делать нечего.
    }
    await _ctrl?.close();
    _ctrl = null;
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
