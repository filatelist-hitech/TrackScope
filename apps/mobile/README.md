# apps/mobile

Граница Flutter-мобильного приложения.

Это приложение владеет разрешениями микрофона, интеграцией нативного аудио-моста, рендером живого результата, отладочным выводом и историей сессий. Оно не должно считать BPM вне `core/dsp`.

## Текущее состояние (Phase 3, шаг 1)

- `pubspec.yaml` задаёт Flutter-оболочку и конфиг `ffigen`, регенерирующий Dart-биндинги из `core/ffi/include/hitech_bpm_ffi.h`.
- `lib/main.dart` рендерит placeholder без фейкового BPM, ограниченный контрактом.
- `lib/dsp/bindings.dart` отдаёт C ABI как `HitechBpmFfi`.
- `lib/dsp/dsp_result.dart` — типизированный взгляд на JSON-снэпшот, который эмитит Rust DSP — никакой BPM-математики здесь.
- `lib/dsp/engine.dart` владеет нативным хэндлом, принимает моно `Float32List` PCM и отдаёт broadcast-`Stream<DspResult>`, опрашиваемый на UI-частоте.
- Захват микрофона и платформенный код плагинов намеренно ещё не сгенерированы — они приходят на шаге 2.

## Запуск FFI-теста

Flutter-тест-сьют гоняет настоящий Rust DSP через FFI-слой:

```sh
# из корня воркспейса собрать shared library один раз
/opt/homebrew/opt/rust/bin/cargo build --release -p hitech-bpm-ffi

# из apps/mobile/
/opt/homebrew/bin/flutter pub get
/opt/homebrew/bin/flutter test
```

`test/helpers/native_library.dart` сам вызывает `cargo build --release -p hitech-bpm-ffi`, если dylib отсутствует, поэтому голого `flutter test` достаточно на чистом чек-ауте (при условии, что Rust-тулчейн установлен по пути из `AGENTS.md`).

## Регенерация биндингов

`lib/dsp/bindings.dart` закоммичен, чтобы контрибьюторам не приходилось ставить libclang локально просто для сборки. Чтобы перегенерировать после изменения C-хедера:

```sh
# из apps/mobile/
/opt/homebrew/bin/flutter pub run ffigen --config pubspec.yaml
```

## Следующий мобильный патч

1. Сгенерировать платформенные файлы Android/iOS через Flutter.
2. Добавить разрешения микрофона (`NSMicrophoneUsageDescription`, `RECORD_AUDIO`).
3. Подключить нативный захват аудио к `DspEngine.pushSamples`.
4. Рендерить только проверенные значения `DspResult` из Rust (главный + отладочный экраны).
