// Лист-модуль: тип ошибки захвата без ffi/io/isolate-зависимостей.
//
// Вынесен из `capture_bridge.dart`, чтобы UI-слой (`MainScreen`) мог
// ссылаться на `CaptureError`, не втягивая транзитивно `dart:ffi` /
// `dart:io` / `dart:isolate` через DSP-воркер. Это позволяет собирать
// UI под Flutter Web (preview), где нативный DSP недоступен.
//
// `capture_bridge.dart` ре-экспортирует этот символ, поэтому существующий
// код, импортирующий `capture_bridge.dart` ради `CaptureError`, не меняется.

/// Выносится в UI, когда путь захвата или DSP-воркер сталкивается с
/// невосстановимой ошибкой. UI обязан её показать — никогда не глотать
/// её молча и никогда не подменять синтетическим аудио.
class CaptureError {
  const CaptureError(this.message, [this.stackTrace]);
  final String message;
  final StackTrace? stackTrace;

  @override
  String toString() => 'CaptureError($message)';
}
