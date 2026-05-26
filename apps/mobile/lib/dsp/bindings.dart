// Dart bindings for the hitech-bpm-ffi C ABI.
//
// Mirrors `core/ffi/include/hitech_bpm_ffi.h`. The intent is that this
// file is regenerable with package:ffigen (see the `ffigen:` block in
// `pubspec.yaml`); it is hand-checked-in so contributors can build
// without needing libclang locally. Keep the shape compatible with
// ffigen output — if you regenerate, the only churn should be comment
// formatting.
//
// ignore_for_file: camel_case_types, non_constant_identifier_names

import 'dart:ffi' as ffi;

final class HitechBpmEngine extends ffi.Opaque {}

typedef _engine_new_c = ffi.Pointer<HitechBpmEngine> Function();
typedef HitechBpmEngineNew = ffi.Pointer<HitechBpmEngine> Function();

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

/// Resolved function table for the loaded `libhitech_bpm_ffi` library.
///
/// Construct once with a `DynamicLibrary` obtained via
/// [DynamicLibrary.process], [DynamicLibrary.executable], or
/// [DynamicLibrary.open] — the [DspEngine] wrapper hides that choice
/// from UI code.
final class HitechBpmFfi {
  HitechBpmFfi(ffi.DynamicLibrary dylib)
      : engineNew = dylib
            .lookup<ffi.NativeFunction<_engine_new_c>>('hitech_bpm_engine_new')
            .asFunction<HitechBpmEngineNew>(),
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
  final HitechBpmEngineFree engineFree;
  final HitechBpmEngineReset engineReset;
  final HitechBpmEnginePushSamples enginePushSamples;
  final HitechBpmEngineAnalyzeJson engineAnalyzeJson;
  final HitechBpmStringFree stringFree;
}
