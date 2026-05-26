# Заметки по мобильному аудио

Phase 3 шаг 2 вводит в эфир пайплайн живого захвата: `package:record` отдаёт PCM в выделенный изолят DSP-воркера, который владеет Rust-FFI-хэндлом, парсит скользящие снэпшоты `DspResult` и отправляет их обратно в UI-изолят для рендера через `StreamBuilder`.

## Пайплайн (end-to-end)

```
┌────────── главный (UI) изолят ──────────┐    ┌──── изолят DSP-воркера ────┐
│                                         │    │                            │
│ AudioRecorder (package:record)          │    │ DspEngine (FFI handle)     │
│   ↓ Stream<Uint8List> pcm16 mono 48 kHz │    │   pushSamples(Float32List, sr)│
│ MicrophoneSource                        │    │   analyzeJson() @ 20 Hz   │
│   ↓                                     │    │     ↓ JSON-строка         │
│ CaptureBridge.start(pcmStream, sr, enc) │    │                            │
│   sendPort.send(PushPcm(bytes, sr, enc))├───►│ ReceivePort listener       │
│                                         │    │   _decodePcm16Mono(bytes)  │
│ ReceivePort listener:                   │    │   engine.pushSamples(...)  │
│   DspResultMessage(json) → DspResult    │◄───┤ Timer.periodic → sendPort  │
│   WorkerError(message) → CaptureError   │    │   StopWorker → dispose()   │
│                                         │    │                            │
│ Stream<DspResult> results               │    │                            │
│   → StreamBuilder<DspResult> в UI       │    │                            │
└─────────────────────────────────────────┘    └────────────────────────────┘
```

## Выбор пакета захвата

`package:record` 5.x — pure Dart, поддерживает `startStream(RecordConfig)`, возвращающий `Stream<Uint8List>` с PCM-байтами на каждой поддерживаемой платформе (Android, iOS, macOS, Linux, Web). Плагин держит собственный нативный поток захвата (AudioRecord на Android, AVAudioEngine на iOS), поэтому callback Dart-стрима получает буферы уже не на UI-потоке. Мы не пишем собственных platform channels — мост остаётся свободным от UI.

## Изолятная модель

Используется **выделенный изолят DSP-воркера**, не отдельный изолят захвата. Обоснование: platform channels плагина `package:record` не рассчитаны на инициализацию в фоновом Dart-изоляте; открытие рекордера там грозит ошибками «no implementation found» на первом вызове. Сам захват уже идёт вне UI-потока (на нативной стороне); работа, выигрывающая от изоляции, — это поллинг FFI, сериализация JSON и конверсия PCM16 → f32 — она уезжает в воркер.

Жизненный цикл запуска:

1. `CaptureBridge.start()` вызывается из `_LiveCaptureScaffold.initState` после выдачи разрешения.
2. `Isolate.spawn(dspWorkerEntry, WorkerInit{replyPort, libraryPath, sampleRate, pollIntervalMs})`.
3. Воркер открывает собственный `DspEngine` через `DspEngine.open(libraryPath:)` — каждому изоляту нужна своя загрузка dylib в своей VM, но ABI FFI разделяется на уровне процесса.
4. Воркер шлёт `WorkerReady`; main стартует, подписываясь на локальный стрим `package:record` и пересылая `PushPcm` через SendPort.
5. Воркер крутит собственный `Timer.periodic` с вызовом `engine.analyzeJson()` и шлёт обратно `DspResultMessage(json)`. Внутренний поллинг engine отключён в этой конфигурации (poll interval выставлен в 1 час) — каденс владеет воркер.
6. `CaptureBridge.dispose()` шлёт `StopWorker`, воркер освобождает хэндл, и мост убивает изолят.

## Согласование формата кадров

| Платформа | Выход `package:record`  | Конверсия в мосте                          | Вход DSP    |
| --------- | ----------------------- | ------------------------------------------ | ----------- |
| Android   | PCM16 signed LE, mono   | `s / 32768.0` → Float32                    | f32 mono    |
| iOS       | PCM16 signed LE, mono   | `s / 32768.0` → Float32                    | f32 mono    |
| macOS     | PCM16 signed LE, mono   | `s / 32768.0` → Float32                    | f32 mono    |
| Linux     | PCM16 signed LE, mono   | `s / 32768.0` → Float32                    | f32 mono    |

- **Частота дискретизации:** запрашиваем у платформы 48 kHz; ресэмплинг не делаем. Если устройство не может выдать 48 kHz, `package:record` округлит до ближайшей поддерживаемой частоты — воркер пробрасывает заявленную частоту в `pushSamples`, поэтому DSP видит реальную частоту.
- **Каналы:** mono через `RecordConfig(numChannels: 1)`. Микширования делать не надо; мост отвергает чанк, чей объявленный encoding ему неизвестен, а не гадает.
- **dtype/порядок байт:** `pcm16bits` — signed 16-bit little-endian. Конверсия живёт в `apps/mobile/lib/capture/dsp_worker.dart::_decodePcm16Mono`, в изоляте воркера. DSP-крейт никогда не должен иметь дело с целочисленными сэмплами.

Мост также поддерживает `pcm_f32le` для будущих портов, которые уже отдают f32; encoding согласуется явно через `PushPcm.encoding`, поэтому сюрприз-формат даст `WorkerError`, а не тихую ошибку счёта.

## Политика задержек

- Аудио-callback'и не аллоцируют ничего, кроме `Float32List` на чанк (пренебрежимо — 100 мс чанк на 48 kHz это 9600 сэмплов = 38 КБ).
- UI-изолят не видит сырых аудио-байт; до дерева виджетов доходят только типизированные `DspResult`-снэпшоты.
- Интервал поллинга воркера — 50 мс по умолчанию (~20 Hz). Регулируется через `CaptureBridge(pollInterval:)`.
- Приёмочный тайминг первого и стабильного захвата (до 6 с / до 12 с на чистом сигнале) обеспечивается `core/dsp/tests/streaming.rs` и проигрывается end-to-end через FFI в `apps/mobile/test/dsp_engine_test.dart`.

## Политика разрешений

- Android: `<uses-permission android:name="android.permission.RECORD_AUDIO" />` в `apps/mobile/android/app/src/main/AndroidManifest.xml`. Runtime-запрос через `package:permission_handler` на первом запуске.
- iOS: `NSMicrophoneUsageDescription` в `apps/mobile/ios/Runner/Info.plist` с понятным пользователю текстом про обработку на устройстве и отсутствие записи/отправки аудио.
- Путь отказа: `PermissionDeniedScreen` показывает пояснение и либо повторно запрашивает (`Permission.microphone.request()`) при мягком отказе, либо открывает системные настройки (`openAppSettings()`) при постоянном отказе. Приложение никогда тихо не подменяет вход синтетическим аудио-источником.

## Anti-fake гарантии

- В `apps/mobile/lib/` нет хардкодных BPM-литералов (проверено grep). Единственное BPM-подобное значение в продакшен-коде — `bpm == null ? '— —' : bpm.toStringAsFixed(1)` в `main_screen.dart`, и оно читает из `DspResult.primaryBpm`.
- Если `record` не стартует, `_LiveCaptureScaffold` показывает исключение через помеченный экран ошибки — изолят воркера не просят фабриковать кадры.
- Если в воркере не загружается FFI dylib, воркер эмитит `WorkerError("failed to open native DSP: …")` через SendPort. `CaptureBridge` перепосылает это по своему `errors`-стриму, а `MainScreen` рендерит баннер ошибки; воркер выходит чисто.
- UI подписан только на `CaptureBridge.results`. Никакого параллельного состояния, никакого fallback-таймера, никакого демо-источника.

## Требования к отладочному режиму

Отладочный экран (`apps/mobile/lib/ui/debug_screen.dart`) рендерит:

- полный список `candidates[]` с `bpm`, `relation` (включая `main`, `raw`, `half_time`, `double_time`, `normalized_from_half`, `normalized_from_double`), `score` и `source_bpm` — half- и double-time кандидаты всегда видимы;
- все поля `signal_quality` (`input_level_dbfs`, `peak_dbfs`, `clipping`, `clipped_frame_ratio`, `noise_level`, `snr_estimate_db`, `silence`, `breakdown_likely`);
- `DspTiming` (analysis time, window, hop, first-lock time).

Оба экрана используют один и тот же `Stream<DspResult>`, питаемый `CaptureBridge.results`; ни один экран не поллит engine сам.
