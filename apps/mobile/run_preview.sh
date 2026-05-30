#!/bin/bash
# Запускает Flutter Web превью UI на localhost:7654.
# Использует MockDspStream (lib/main_web.dart) — только для UI-разработки,
# не реальный детектор. Rust/FFI в браузере недоступны.

cd "$(dirname "$0")" || exit 1

echo "🎛  hitech-bpm-radar UI preview"
echo "    http://localhost:7654"
echo "    Hot-reload: нажми 'r' в этом терминале после правки .dart"
echo ""

flutter run \
  -d web-server \
  --web-port 7654 \
  --web-hostname localhost \
  --target lib/main_web.dart
