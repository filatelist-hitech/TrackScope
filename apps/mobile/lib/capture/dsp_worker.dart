// Точка входа фонового изолята.
//
// Владеет FFI-handle `DspEngine` и преобразованием PCM → f32, которое
// НЕ должно выполняться на UI-потоке. Получает сырые куски PCM-байтов
// от главного изолята, преобразует их в моно `Float32List`, кладёт в
// движок, опрашивает скользящие JSON-снапшоты `DspResult` и отправляет
// их обратно главному изоляту, который декодирует их в типизированные
// объекты для UI.
//
// Этот файл импортирует `dsp/engine.dart` напрямую, потому что каждый
// Dart-изолят может открыть одну и ту же shared library — `DspEngine.open`
// безопасно вызывать по одному разу на изолят.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../dsp/engine.dart';
import 'capture_messages.dart';

/// Точка входа, передаваемая в `Isolate.spawn`. Init-сообщение несёт
/// reply-порт главного изолята и конфигурацию библиотеки.
void dspWorkerEntry(WorkerInit init) {
  final ReceivePort inbox = ReceivePort();
  final SendPort reply = init.replyPort as SendPort;
  reply.send(inbox.sendPort);

  late final DspEngine engine;
  try {
    engine = DspEngine.open(
      libraryPath: init.libraryPath,
      // Воркер сам опрашивает FFI, так что встроенный таймер потока
      // движка отключаем длинным интервалом — мы на него не подписываемся.
      pollInterval: const Duration(hours: 1),
      minBpm: init.minBpm,
    );
  } catch (e, st) {
    reply.send(WorkerError('не удалось открыть нативный DSP: $e', st));
    inbox.close();
    return;
  }

  // Воркер задаёт свой ритм опроса и пересылает сырой JSON. Так мы
  // избегаем парсинга на воркере и повторной сериализации на провод:
  // парсинг происходит однократно, в главном изоляте, когда UI его
  // потребляет.
  Timer? poll;
  void startPolling() {
    poll ??= Timer.periodic(Duration(milliseconds: init.pollIntervalMs),
        (_) {
      try {
        reply.send(DspResultMessage(engine.analyzeJson()));
      } catch (e, st) {
        reply.send(WorkerError('сбой анализа: $e', st));
      }
    });
  }

  reply.send(const WorkerReady());
  startPolling();

  inbox.listen((message) async {
    if (message is PushPcm) {
      try {
        final samples = _decodeMono(message);
        if (samples.isNotEmpty) {
          engine.pushSamples(samples, message.sampleRate);
        }
      } catch (e, st) {
        reply.send(WorkerError('сбой push: $e', st));
      }
    } else if (message is ResetEngine) {
      try {
        engine.reset();
      } catch (e, st) {
        reply.send(WorkerError('сбой reset: $e', st));
      }
    } else if (message is StopWorker) {
      poll?.cancel();
      poll = null;
      await engine.dispose();
      inbox.close();
    }
  });
}

/// Декодирует входящий сырой PCM-кусок в моно `Float32List`, готовый
/// для `DspEngine.pushSamples`. Кодировка `pcm16bits` плагина `record`
/// — это signed little-endian 16-bit interleaved сэмплы; моно-захват
/// делает interleaving бессодержательным. Новые кодировки можно
/// добавлять здесь, не трогая DSP.
Float32List _decodeMono(PushPcm chunk) {
  switch (chunk.encoding) {
    case 'pcm16':
    case 'pcm16bits':
      return _decodePcm16Mono(chunk.bytes);
    case 'pcm_f32le':
      return _decodeF32(chunk.bytes);
    default:
      throw ArgumentError('неподдерживаемая кодировка PCM: ${chunk.encoding}');
  }
}

Float32List _decodePcm16Mono(Uint8List bytes) {
  // Округляем вниз до целых сэмпл-пар на случай, если платформа выдала
  // нечётный хвост (для pcm16 маловероятно, но защита дешёвая).
  final sampleCount = bytes.length ~/ 2;
  final out = Float32List(sampleCount);
  final view = ByteData.sublistView(bytes, 0, sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final s = view.getInt16(i * 2, Endian.little);
    out[i] = s / 32768.0;
  }
  return out;
}

Float32List _decodeF32(Uint8List bytes) {
  final sampleCount = bytes.length ~/ 4;
  final out = Float32List(sampleCount);
  final view = ByteData.sublistView(bytes, 0, sampleCount * 4);
  for (var i = 0; i < sampleCount; i++) {
    out[i] = view.getFloat32(i * 4, Endian.little);
  }
  return out;
}
