// Test-only helper that locates (or builds) the hitech-bpm-ffi shared
// library so widget/unit tests can drive the real Rust DSP through FFI.
//
// Build path: workspace root → `target/release/libhitech_bpm_ffi.<ext>`.
// If the dylib is missing, this helper invokes `cargo build --release -p
// hitech-bpm-ffi` from the workspace root. The test runner caches the
// build via Cargo, so subsequent runs are near-instant.

import 'dart:io';

class NativeLibrary {
  NativeLibrary._(this.path);
  final String path;

  static NativeLibrary? _cached;

  static Future<NativeLibrary> ensureBuilt() async {
    if (_cached != null) return _cached!;
    final workspaceRoot = _findWorkspaceRoot();
    final libPath = _expectedLibPath(workspaceRoot);
    if (!File(libPath).existsSync()) {
      await _buildRelease(workspaceRoot);
    }
    if (!File(libPath).existsSync()) {
      throw StateError(
          'Could not locate libhitech_bpm_ffi after cargo build at $libPath');
    }
    _cached = NativeLibrary._(libPath);
    return _cached!;
  }

  static String _expectedLibPath(String workspaceRoot) {
    final dir = '$workspaceRoot/target/release';
    if (Platform.isMacOS) return '$dir/libhitech_bpm_ffi.dylib';
    if (Platform.isLinux) return '$dir/libhitech_bpm_ffi.so';
    if (Platform.isWindows) return '$dir/hitech_bpm_ffi.dll';
    throw UnsupportedError('Test host not supported: ${Platform.operatingSystem}');
  }

  static String _findWorkspaceRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      if (File('${dir.path}/Cargo.toml').existsSync() &&
          Directory('${dir.path}/core/dsp').existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    throw StateError(
        'Could not locate workspace root (Cargo.toml with core/dsp) from '
        '${Directory.current.path}');
  }

  static Future<void> _buildRelease(String workspaceRoot) async {
    const cargo = '/opt/homebrew/opt/rust/bin/cargo';
    final exe = File(cargo).existsSync() ? cargo : 'cargo';
    final proc = await Process.run(
      exe,
      ['build', '--release', '-p', 'hitech-bpm-ffi'],
      workingDirectory: workspaceRoot,
    );
    if (proc.exitCode != 0) {
      throw StateError(
          'cargo build failed (exit ${proc.exitCode}):\n${proc.stdout}\n${proc.stderr}');
    }
  }
}
