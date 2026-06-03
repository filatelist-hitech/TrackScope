// Конверты сообщений, которыми обмениваются главный изолят и изолят
// DSP-воркера. Сознательно простые, чтобы проходить через SendPort без
// своих кодеков.
//
// Изолят воркера владеет FFI-handle и циклом опроса движка. Он никогда
// не видит Flutter-виджетов, а главный изолят никогда не видит сырой
// PCM после того, как отправил байты через `sendPort.send`.

import 'dart:typed_data';

/// Отправляется main → worker однократно сразу после спавна. Сообщает
/// воркеру, где искать нативную библиотеку, и reply-порт главного
/// изолята.
class WorkerInit {
  const WorkerInit({
    required this.replyPort,
    required this.libraryPath,
    required this.captureSampleRate,
    required this.pollIntervalMs,
    this.minBpm,
    this.maxBpm,
  });

  /// Куда воркер должен слать снапшоты `DspResultMessage` и события
  /// `WorkerError`.
  final dynamic replyPort; // SendPort, но типизирован как dynamic, чтобы файл оставался без UI-зависимостей.
  final String? libraryPath;
  final int captureSampleRate;
  final int pollIntervalMs;
  /// Минимальный BPM для hitech-диапазона (Free: 170, Pro: 155).
  /// Если null, используется дефолт Rust (155).
  final double? minBpm;
  /// Максимальный BPM. Если задан вместе с minBpm — вызывается new_with_range
  /// (Custom preset). Если null — new_with_min_bpm или new.
  final double? maxBpm;
}

/// Main → worker: принять сырой кусок PCM-байтов. Формат сэмплов
/// считается соответствующим конфигу захвата, согласованному при старте.
class PushPcm {
  const PushPcm(this.bytes, {required this.sampleRate, this.encoding = 'pcm16'});
  final Uint8List bytes;
  final int sampleRate;
  /// Либо `pcm16` (little-endian signed 16-bit), либо `pcm_f32le`.
  /// `record` 5.x по умолчанию выдаёт `pcm16bits` на Android/iOS; держим
  /// поле явным, чтобы воркер отвергал любую неожиданную кодировку.
  final String encoding;
}

/// Main → worker: сбросить скользящее DSP-состояние на месте.
/// Используется при перезапуске захвата или сбросе сессии.
class ResetEngine {
  const ResetEngine();
}

/// Main → worker: остановиться. Воркер освобождает handle движка и
/// завершает работу.
class StopWorker {
  const StopWorker();
}

/// Worker → main: распарсенный снапшот `DspResult`. JSON-строка
/// пересылается как есть, чтобы типизированное представление строилось
/// в главном изоляте, где живёт UI-код.
class DspResultMessage {
  const DspResultMessage(this.json);
  final String json;
}

/// Worker → main: воркер жив и готов принимать PCM.
class WorkerReady {
  const WorkerReady();
}

/// Worker → main: воркер столкнулся с невосстановимой ошибкой (сбой
/// загрузки FFI, неподдерживаемая кодировка и т.п.). Цикл захвата
/// должен остановиться и на главной стороне.
class WorkerError {
  const WorkerError(this.message, [this.stackTrace]);
  final String message;
  final StackTrace? stackTrace;
}
