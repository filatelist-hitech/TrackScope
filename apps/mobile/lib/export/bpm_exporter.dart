// BPM history export — pure builders and IO functions.
//
// `buildCsv` and `buildJson` are pure functions (no platform dependencies),
// unit-tested with mock samples. The IO functions `exportCsv` and `exportJson`
// use `share_plus` + `path_provider` and are only called from Pro tier.

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../history/bpm_history.dart';

/// Build CSV string from BPM samples. Pure — no platform deps.
///
/// Format: `timestamp,bpm,lock_state` header + one row per sample.
String buildCsv(List<BpmSample> samples) {
  final buf = StringBuffer('timestamp,bpm,lock_state\n');
  for (final s in samples) {
    buf.writeln('${s.timestamp.toIso8601String()},${s.bpm},${s.lockState.name}');
  }
  return buf.toString();
}

/// Build JSON string from BPM samples. Pure — no platform deps.
///
/// Shape: `{app, exported_at, samples: [{timestamp, bpm, lock_state}]}`.
String buildJson(List<BpmSample> samples) {
  final sampleList = samples.map((s) => s.toJson()).toList();
  final json = <String, dynamic>{
    'app': 'hitech_bpm_radar',
    'exported_at': DateTime.now().toIso8601String(),
    'samples': sampleList,
  };
  // Use manual encoding to avoid dart:convert import at top level.
  return _encodeJson(json);
}

/// Export samples as CSV file and share via platform share sheet.
Future<void> exportCsv(List<BpmSample> samples) async {
  final content = buildCsv(samples);
  final file = await _writeTempFile('bpm_history.csv', content);
  await Share.shareXFiles(
    [XFile(file.path)],
    text: 'BPM History (CSV)',
  );
}

/// Export samples as JSON file and share via platform share sheet.
Future<void> exportJson(List<BpmSample> samples) async {
  final content = buildJson(samples);
  final file = await _writeTempFile('bpm_history.json', content);
  await Share.shareXFiles(
    [XFile(file.path)],
    text: 'BPM History (JSON)',
  );
}

Future<File> _writeTempFile(String name, String content) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  return file.writeAsString(content);
}

/// Minimal JSON encoder — no `dart:convert` import to keep the file
/// importable from web-safe trees. Handles string, num, bool, null,
/// List, and Map recursively.
String _encodeJson(dynamic value) {
  if (value == null) return 'null';
  if (value is bool) return value ? 'true' : 'false';
  if (value is num) return value.toString();
  if (value is String) return _encodeString(value);
  if (value is List) {
    final items = value.map(_encodeJson).join(',');
    return '[$items]';
  }
  if (value is Map) {
    final entries = value.entries
        .map((e) => '${_encodeString(e.key)}:${_encodeJson(e.value)}')
        .join(',');
    return '{$entries}';
  }
  return 'null';
}

String _encodeString(String s) {
  final escaped = s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r')
      .replaceAll('\t', '\\t');
  return '"$escaped"';
}
