// Dart-привязки к C ABI hitech-bpm-ffi.
//
// Зеркалит `core/ffi/include/hitech_bpm_ffi.h`. Идея в том, что этот
// файл регенерируется через package:ffigen (см. блок `ffigen:` в
// `pubspec.yaml`); он закоммичен вручную, чтобы контрибьюторы могли
// собирать без локально установленного libclang. Сохраняйте структуру
// совместимой с выводом ffigen — при регенерации меняться должно
// только форматирование комментариев.
//
// ignore_for_file: camel_case_types, non_constant_identifier_names

import 'dart:ffi' as ffi;

final class HitechBpmEngine extends ffi.Opaque {}

typedef _engine_new_c = ffi.Pointer<HitechBpmEngine> Function();
typedef HitechBpmEngineNew = ffi.Pointer<HitechBpmEngine> Function();

typedef _engine_new_with_min_bpm_c = ffi.Pointer<HitechBpmEngine> Function(ffi.Float);
typedef HitechBpmEngineNewWithMinBpm = ffi.Pointer<HitechBpmEngine> Function(double);

typedef _engine_free_c = ffi.Void Function(ffi.Pointer<HitechBpmEngine>);
typedef HitechBpmEngineFree = void Function(ffi.Pointer<HitechBpmEngine>);

typedef _engine_reset_c = ffi.Void Function(ffi.Pointer<HitechBpmEngine>);
typedef HitechBpmEngineReset = void Function(ffi.Pointer<HitechBpmEngine>);

typedef _engine_push_samples_c = ffi.Bool Function(
  ffi.Pointer<HitechBpmEngine>,
  ffi.Pointer<ffi.Float>,
  ffi.Size,
  ffi.Uint32,
);
typedef HitechBpmEnginePushSamples = bool Function(
  ffi.Pointer<HitechBpmEngine>,
  ffi.Pointer<ffi.Float>,
  int,
  int,
);

typedef _engine_analyze_json_c = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<HitechBpmEngine>,
);
typedef HitechBpmEngineAnalyzeJson = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<HitechBpmEngine>,
);

typedef _string_free_c = ffi.Void Function(ffi.Pointer<ffi.Char>);
typedef HitechBpmStringFree = void Function(ffi.Pointer<ffi.Char>);

/// Разрешённая таблица функций загруженной библиотеки
/// `libhitech_bpm_ffi`.
///
/// Создавать один раз из `DynamicLibrary`, полученного через
/// [DynamicLibrary.process], [DynamicLibrary.executable] или
/// [DynamicLibrary.open] — обёртка [DspEngine] скрывает этот выбор от
/// UI-кода.
final class HitechBpmFfi {
  HitechBpmFfi(ffi.DynamicLibrary dylib)
      : engineNew = dylib
            .lookup<ffi.NativeFunction<_engine_new_c>>('hitech_bpm_engine_new')
            .asFunction<HitechBpmEngineNew>(),
        engineNewWithMinBpm = dylib
            .lookup<ffi.NativeFunction<_engine_new_with_min_bpm_c>>(
                'hitech_bpm_engine_new_with_min_bpm')
            .asFunction<HitechBpmEngineNewWithMinBpm>(),
        engineFree = dylib
            .lookup<ffi.NativeFunction<_engine_free_c>>('hitech_bpm_engine_free')
            .asFunction<HitechBpmEngineFree>(),
        engineReset = dylib
            .lookup<ffi.NativeFunction<_engine_reset_c>>('hitech_bpm_engine_reset')
            .asFunction<HitechBpmEngineReset>(),
        enginePushSamples = dylib
            .lookup<ffi.NativeFunction<_engine_push_samples_c>>(
                'hitech_bpm_engine_push_samples')
            .asFunction<HitechBpmEnginePushSamples>(),
        engineAnalyzeJson = dylib
            .lookup<ffi.NativeFunction<_engine_analyze_json_c>>(
                'hitech_bpm_engine_analyze_json')
            .asFunction<HitechBpmEngineAnalyzeJson>(),
        stringFree = dylib
            .lookup<ffi.NativeFunction<_string_free_c>>('hitech_bpm_string_free')
            .asFunction<HitechBpmStringFree>();

  final HitechBpmEngineNew engineNew;
  final HitechBpmEngineNewWithMinBpm engineNewWithMinBpm;
  final HitechBpmEngineFree engineFree;
  final HitechBpmEngineReset engineReset;
  final HitechBpmEnginePushSamples enginePushSamples;
  final HitechBpmEngineAnalyzeJson engineAnalyzeJson;
  final HitechBpmStringFree stringFree;
}
