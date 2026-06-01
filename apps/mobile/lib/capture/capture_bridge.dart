// Оркестратор на главном изоляте. Спавнит изолят DSP-воркера, пересылает
// сырые куски PCM-байтов из переданного вызывающим аудио-источника в
// воркер через SendPort и заново эмитит распарсенные снапшоты `DspResult`
// в broadcast-поток, на который подписывается UI.
//
// Этот класс никогда не инспектирует аудио-байты. Он никогда не выводит
// BPM. Вся детекция выполняется в воркере; UI видит только типизированный
// `DspResult`.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'dart:io' show Platform;

import '../dsp/dsp_result.dart';
import 'bpm_smoother.dart';
import 'capture_error.dart';
import 'capture_messages.dart';
import 'dsp_worker.dart';

// `CaptureError` вынесен в лист-модуль `capture_error.dart` (без ffi/io/
// isolate), чтобы UI собирался под web. Ре-экспортируем его здесь, чтобы
// существующие `import 'capture_bridge.dart'` продолжали видеть тип.
export 'capture_error.dart';

class CaptureBridge {
  CaptureBridge({
    this.libraryPath,
    this.pollInterval = const Duration(milliseconds: 50),
    this.minBpm,
  });

  final String? libraryPath;
  final Duration pollInterval;
  final double? minBpm;

  Isolate? _worker;
  SendPort? _workerInbox;
  ReceivePort? _fromWorker;
  StreamSubscription<dynamic>? _pcmSub;
  final StreamController<DspResult> _resultsCtrl =
      StreamController<DspResult>.broadcast();
  final StreamController<CaptureError> _errorsCtrl =
      StreamController<CaptureError>.broadcast();
  // Raw PCM bytes (PCM-16 LE mono) forked from the mic stream before the
  // DSP-worker isolate. Used by VizController on the main isolate for the
  // Dart-side spectrogram / waveform. Never contains computed BPM.
  final StreamController<Uint8List> _rawPcmCtrl =
      StreamController<Uint8List>.broadcast();
  Completer<void>? _readyCompleter;
  bool _disposed = false;

  // Сглаживающий слой: медианный фильтр BPM + EMA уверенности +
  // гистерезис выхода из STABLE. Находится здесь, а не в воркере,
  // чтобы сохранялась parity-тестируемость Rust DSP без UI-биасов.
  final BpmSmoother _smoother = BpmSmoother();

  /// Broadcast-поток скользящих снапшотов `DspResult`. UI подписывается
  /// сюда; никаких других источников состояния не допускается.
  Stream<DspResult> get results => _resultsCtrl.stream;

  /// Raw PCM-16 LE mono bytes, forked from the mic source.
  /// For Dart-side visualisation only — do not compute BPM here.
  Stream<Uint8List> get rawPcm => _rawPcmCtrl.stream;

  /// Broadcast-поток ошибок захвата / воркера. UI обязан их показывать
  /// (например, баннером) — тихий откат на синтетический источник явно
  /// запрещён правилами anti-fake.
  Stream<CaptureError> get errors => _errorsCtrl.stream;

  bool get isRunning => _worker != null;

  /// Спавнит воркер, если он ещё не запущен, и привязывает [pcmStream]
  /// как живой аудио-источник. Мост пересылает каждый кусок в воркер;
  /// кодировка анонсируется явно, чтобы воркер отвергал неожиданные
  /// форматы вместо угадывания.
  Future<void> start({
    required Stream<Uint8List> pcmStream,
    required int sampleRate,
    String encoding = 'pcm16',
  }) async {
    _ensureAlive();
    if (_worker == null) {
      await _spawnWorker(sampleRate: sampleRate);
    }
    // Сбрасываем предыдущий источник, если был.
    await _pcmSub?.cancel();
    _pcmSub = pcmStream.listen(
      (chunk) {
        final inbox = _workerInbox;
        if (inbox == null || chunk.isEmpty) return;
        inbox.send(
            PushPcm(chunk, sampleRate: sampleRate, encoding: encoding));
        // Fork raw bytes to the visualisation stream.
        if (!_rawPcmCtrl.isClosed) _rawPcmCtrl.add(chunk);
      },
      onError: (Object e, StackTrace st) =>
          _errorsCtrl.add(CaptureError('ошибка аудио-источника: $e', st)),
      cancelOnError: false,
    );
  }

  /// Отвязывает аудио-источник и просит воркер сбросить скользящее
  /// состояние. Сам воркер остаётся живым, чтобы последующий `start`
  /// был быстрым. Сглаживающий буфер тоже сбрасывается — иначе
  /// старое BPM «просочится» в новую сессию.
  Future<void> stop() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    _smoother.reset();
    _workerInbox?.send(const ResetEngine());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _pcmSub?.cancel();
    _pcmSub = null;
    _workerInbox?.send(const StopWorker());
    // Даём воркеру короткое окно, чтобы он успел корректно освободить
    // свой FFI-handle.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _fromWorker?.close();
    _fromWorker = null;
    _workerInbox = null;
    await _resultsCtrl.close();
    await _errorsCtrl.close();
    await _rawPcmCtrl.close();
  }

  Future<void> _spawnWorker({required int sampleRate}) async {
    _readyCompleter = Completer<void>();
    _fromWorker = ReceivePort();
    _fromWorker!.listen(_handleWorkerMessage);
    final init = WorkerInit(
      replyPort: _fromWorker!.sendPort,
      libraryPath: libraryPath ?? _platformDefaultLibrary(),
      captureSampleRate: sampleRate,
      pollIntervalMs: pollInterval.inMilliseconds,
      minBpm: minBpm,
    );
    _worker = await Isolate.spawn<WorkerInit>(
      dspWorkerEntry,
      init,
      debugName: 'hitech-bpm-dsp-worker',
      errorsAreFatal: true,
    );
    await _readyCompleter!.future
        .timeout(const Duration(seconds: 5), onTimeout: () {
      throw StateError('DSP-воркер не сообщил о готовности за 5 с');
    });
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is SendPort) {
      _workerInbox = message;
    } else if (message is WorkerReady) {
      if (!(_readyCompleter?.isCompleted ?? true)) {
        _readyCompleter!.complete();
      }
    } else if (message is DspResultMessage) {
      try {
        final parsed = DspResult.parse(message.json);
        // Применяем сглаживание перед передачей в UI-стрим.
        // `_smoother` не изменяет `candidates` и `signalQuality` — они
        // передаются as-is для debug-экрана.
        final smoothed = _smoother.smooth(parsed);
        if (!_resultsCtrl.isClosed) _resultsCtrl.add(smoothed);
      } catch (e, st) {
        _errorsCtrl.add(CaptureError('не удалось распарсить DspResult: $e', st));
      }
    } else if (message is WorkerError) {
      _errorsCtrl.add(CaptureError(message.message, message.stackTrace));
      if (!(_readyCompleter?.isCompleted ?? true)) {
        _readyCompleter!.completeError(StateError(message.message));
      }
    }
  }

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('CaptureBridge уже освобождён');
    }
  }

  // На iOS нативная .a статически вшита в бинарник Runner — путь к
  // библиотеке не нужен, DspEngine.open(libraryPath: null) вызовет
  // DynamicLibrary.process() на стороне воркера.
  String? _platformDefaultLibrary() {
    if (Platform.isIOS) return null;
    if (Platform.isMacOS) return 'libhitech_bpm_ffi.dylib';
    if (Platform.isAndroid) return 'libhitech_bpm_ffi.so';
    if (Platform.isLinux) return 'libhitech_bpm_ffi.so';
    if (Platform.isWindows) return 'hitech_bpm_ffi.dll';
    return null;
  }
}
