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

`package:record` 6.x — pure Dart, поддерживает `startStream(RecordConfig)`, возвращающий `Stream<Uint8List>` с PCM-байтами на каждой поддерживаемой платформе (Android, iOS, macOS, Linux, Web). Плагин держит собственный нативный поток захвата (AudioRecord на Android, AVAudioEngine на iOS), поэтому callback Dart-стрима получает буферы уже не на UI-потоке. Мы не пишем собственных platform channels — мост остаётся свободным от UI.

Версии зависимостей: `record: ^6.0.0` (→ 6.2.1 resolved), `permission_handler: ^12.0.0` (→ 12.0.1). Версии 5.x/11.x не совместимы с текущими `record_platform_interface` и требованиями iOS compile-time flags.

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

## Сборка нативной библиотеки для iOS

iOS требует статической `.a`-библиотеки — динамические `.dylib` не разрешены App Store. Скрипт `scripts/build_ios_native.sh` автоматизирует кросс-компиляцию Rust для `aarch64-apple-ios`.

### Предварительные требования

1. Xcode установлен (не только Command Line Tools): `xcode-select -s /Applications/Xcode.app/Contents/Developer`
2. rustup установлен через Homebrew: `brew install rustup && rustup-init`

**Важно:** если на машине два Rust-тулчейна (Homebrew-rustc в PATH + rustup-управляемый `~/.rustup`), скрипт явно переставляет PATH на `~/.rustup/toolchains/stable-aarch64-apple-darwin/bin`, чтобы cargo использовал rustup-тулчейн с iOS-таргетом, а не Homebrew-rustc.

### Команда сборки

```sh
bash scripts/build_ios_native.sh          # release (дефолт)
bash scripts/build_ios_native.sh debug    # debug
```

Скрипт копирует `libhitech_bpm_ffi.a` в `apps/mobile/ios/Frameworks/`.

### Xcode-конфигурация (однократно)

1. **Link Binary With Libraries**: `Runner → Build Phases → Link Binary With Libraries → + → Add Other → Add Files → apps/mobile/ios/Frameworks/libhitech_bpm_ffi.a`.
2. **Library Search Paths**: `Build Settings → Library Search Paths → добавь $(PROJECT_DIR)/Frameworks`.
3. **`-force_load` в `OTHER_LDFLAGS`**: iOS линкер по умолчанию выкидывает неиспользованные символы из `.a` через dead-code stripping. `DynamicLibrary.process()` ищет символы через `dlsym(RTLD_DEFAULT, …)` — они должны быть в процессе. Без `-force_load` получим `symbol not found` при запуске.

   В `project.pbxproj` для обеих конфигураций (Debug и Release):
   ```
   OTHER_LDFLAGS = (
       "$(inherited)",
       "-force_load $(PROJECT_DIR)/Frameworks/libhitech_bpm_ffi.a",
   );
   ```

### Загрузка библиотеки на iOS

На iOS нативная `.a` статически вшита в бинарник `Runner`. Путь к файлу не нужен — `DspEngine.open(libraryPath: null)` вызывает `DynamicLibrary.process()`:

```dart
ffi.DynamicLibrary _openLibrary(String? libraryPath) {
  if (libraryPath != null) return ffi.DynamicLibrary.open(libraryPath);
  if (Platform.isIOS) return ffi.DynamicLibrary.process();
  // ...
}
```

## Политика разрешений

- Android: `<uses-permission android:name="android.permission.RECORD_AUDIO" />` в `apps/mobile/android/app/src/main/AndroidManifest.xml`. Runtime-запрос через `package:permission_handler` на первом запуске.
- iOS: `NSMicrophoneUsageDescription` в `apps/mobile/ios/Runner/Info.plist` с понятным пользователю текстом про обработку на устройстве и отсутствие записи/отправки аудио.
- Путь отказа: `PermissionDeniedScreen` показывает пояснение и либо повторно запрашивает (`Permission.microphone.request()`) при мягком отказе, либо открывает системные настройки (`openAppSettings()`) при постоянном отказе. Приложение никогда тихо не подменяет вход синтетическим аудио-источником.

### Podfile: активация разрешения микрофона на iOS

`permission_handler` 12.x использует compile-time флаги для включения разрешений. Без явного флага `Permission.microphone.request()` молча возвращает `denied`, и системный диалог никогда не появляется.

В `apps/mobile/ios/Podfile` в секции `post_install` обязательно:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'PERMISSION_MICROPHONE=1'
    end
  end
end
```

После изменения Podfile запустить `pod install` из `apps/mobile/ios/`.

## Anti-fake гарантии

- В `apps/mobile/lib/` нет хардкодных BPM-литералов (проверено grep). Единственное BPM-подобное значение в продакшен-коде — `bpm == null ? '— —' : bpm.toStringAsFixed(1)` в `main_screen.dart`, и оно читает из `DspResult.primaryBpm`.
- Если `record` не стартует, `_LiveCaptureScaffold` показывает исключение через помеченный экран ошибки — изолят воркера не просят фабриковать кадры.
- Если в воркере не загружается FFI dylib, воркер эмитит `WorkerError("failed to open native DSP: …")` через SendPort. `CaptureBridge` перепосылает это по своему `errors`-стриму, а `MainScreen` рендерит баннер ошибки; воркер выходит чисто.
- UI подписан только на `CaptureBridge.results`. Никакого параллельного состояния, никакого fallback-таймера, никакого демо-источника.

## Реальное устройство: результаты Phase 3

Подтверждённый запуск на iPhone 11 (iOS 26.3.1), 2026-05-26.

| Метрика | Значение |
| --- | --- |
| Треки | hitech-psytrance, 192 / 200 / 207 BPM (известные BPM) |
| Определённый BPM | ~187–196 BPM |
| Ошибка | ~±5–8 BPM через комнатный микрофон (~1 м от колонки) |
| Уровень входа | -10 до -12 dBFS |
| Состояние захвата | `LOCKING` при 52–62% уверенности |
| `STABLE` | не достигнут через комнатный микрофон — ожидаемо |

Вывод: пайплайн конца в конец работает корректно. Точность ±5–8 BPM — за пределами цели ±2–4 BPM при шуме помещения и реверберации. Задача Phase 4 — сократить этот разрыв через адаптивные пороги, сглаживание и noise-floor компенсацию.

## Требования к отладочному режиму

Отладочный экран (`apps/mobile/lib/ui/debug_screen.dart`) рендерит:

- полный список `candidates[]` с `bpm`, `relation` (включая `main`, `raw`, `half_time`, `double_time`, `normalized_from_half`, `normalized_from_double`), `score` и `source_bpm` — half- и double-time кандидаты всегда видимы;
- все поля `signal_quality` (`input_level_dbfs`, `peak_dbfs`, `clipping`, `clipped_frame_ratio`, `noise_level`, `snr_estimate_db`, `silence`, `breakdown_likely`);
- `DspTiming` (analysis time, window, hop, first-lock time).

Оба экрана используют один и тот же `Stream<DspResult>`, питаемый `CaptureBridge.results`; ни один экран не поллит engine сам.

## Dart-side визуализации (Phase 5)

### Источники данных

Главный экран (`apps/mobile/lib/ui/main_screen.dart`) содержит **спектрограмму** и **волноформу**, которые питаются исключительно реальным PCM из `CaptureBridge.rawPcm` — отдельным broadcast-стримом, форкнутым от `MicrophoneSource` до отправки в DSP-воркер. Если разрешение на микрофон ещё не выдано или `rawPcm == null` — спектрограмма показывает плейсхолдер «Ожидание микрофона…», без анимации.

Никакого вычисления BPM на Dart-стороне нет. `VizController` не видит `DspResult` — только сырые PCM-байты.

### Изолятная топология

```
MicrophoneSource (Stream<Uint8List>) ─────────────────────────────┐
                                                                   │
CaptureBridge:                                                     │
  ├── sendPort.send(PushPcm) ──────► DSP Worker Isolate           │
  └── _rawPcmCtrl.add(chunk) ──────► VizController (UI isolate)   │
                                           │                       │
                              ┌────────────┘                       │
                              │ every ~2400 samples (~50 ms)       │
                              ▼                                    │
                  compute(_fftWorker) ──► новый Dart изолят        │
                     ▲                   (fftea FFT, 1024 pt)      │
                     │                          │                  │
              Hann-windowed                     │                  │
              Float64List (8 KB)        Float64List мощностей      │
                                               │                   │
                                 VizController._specCols.add()     │
                                               │                   │
                                      notifyListeners()            │
                                               │                   │
                               SpectrogramPainter / WaveformPainter│
                               (RepaintBoundary — не трогают таблицу)
```

### FFT-параметры

| Параметр | Значение |
|---|---|
| Размер FFT | 1024 сэмпла |
| Оконная функция | Hann (вычисляется в UI-изоляте перед отправкой в compute()) |
| Шаг (hop) | ~2400 сэмпла (~50 мс при 48 кГц) |
| Отображаемых бинов | 128 (0–6 кГц) |
| Колонок в кольце | 200 (~4–5 с истории) |
| Нормализация | логарифмическая, пол −60 дБ, reference 256 |

### Цветовая схема спектрограммы (LUT, 256 записей)

LUT предвычисляется при инициализации `VizController` из 7 контрольных точек:

| t | Цвет | Hex |
|---|------|-----|
| 0.000 | тихое — тёмно-синий | `#0D0221` |
| 0.167 | слабое — синий | `#1A1AFF` |
| 0.333 | среднее — циан | `#00FFFF` |
| 0.500 | активное — зелёный | `#00FF88` |
| 0.667 | сильное — жёлтый | `#FFE600` |
| 0.833 | пик — оранжево-красный | `#FF4400` |
| 1.000 | транзиент — белый | `#FFFFFF` |

Все 256 `Paint`-объектов создаются один раз в конструкторе `VizController.lutPaints`. В методе `paint()` используется прямое обращение `lutPaints[lutIdx]` — `Color.lerp` никогда не вызывается в горячем пути рендеринга.

### RepaintBoundary

- `RepaintBoundary` обёрнут вокруг `SpectrogramPainter` и `WaveformPainter`.
- Изменение `DspResult` (таблица, badge) не вызывает `paint()` визуализаций.
- Изменение `VizController` (новый FFT-столбец) не вызывает rebuild таблицы.

### Ограничения

- `compute()` спавнит новый Dart-изолят при каждом FFT-вызове (~20/с). На слабых устройствах возможна задержка обновления спектрограммы; при необходимости — замена на персистентный viz-изолят (паттерн аналогичен `dsp_worker.dart`).
- iOS-симулятор не поддерживает захват микрофона — визуализации будут показывать плейсхолдер; тестировать на реальном устройстве.
- Волноформа использует поточечную выборку без RMS-усреднения — может выглядеть «зубчато» на очень тихом сигнале.
