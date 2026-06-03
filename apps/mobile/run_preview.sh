#!/bin/bash
# Запускает Flutter Web превью UI на localhost:8888 с горячей перезагрузкой.
# Использует MockDspStream (lib/main_web.dart) — только для UI-разработки,
# не реальный детектор. Rust/FFI в браузере недоступны.
#
# Автоматически дождётся инициализации сервера, затем откроет браузер
# на мобильном разрешении (375×812).
# Горячая перезагрузка: нажми 'r' в этом терминале после правки .dart

set -e

cd "$(dirname "$0")" || exit 1

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎛  hitech-bpm-radar — UI Preview"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📱 Разрешение:        375 × 812 (mobile)"
echo "🔗 URL:               http://localhost:8888"
echo "🔄 Hot-reload:        нажми 'r' после правки .dart"
echo "🎮 Кнопки режимов:    IDLE, ACTIVE, UNSTABLE в AppBar"
echo "🔐 Pro-функции:       включены в превью"
echo ""
echo "⏳ Инициализация сервера..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Запустим flutter run в фоне и дождёмся инициализации
flutter run \
  -d web-server \
  --web-port 8888 \
  --web-hostname localhost \
  --target lib/main_web.dart 2>&1 | while IFS= read -r line; do
  echo "$line"

  # Ждём сообщения о том, что сервер запущен
  if [[ "$line" == *"is being served at http://localhost:8888"* ]]; then
    echo ""
    echo "✓ Сервер инициализирован!"
    echo "⏳ Открытие браузера..."
    sleep 3

    # Определяем браузер для открытия
    if command -v open &> /dev/null; then
      # macOS
      open "http://localhost:8888" &
    elif command -v xdg-open &> /dev/null; then
      # Linux
      xdg-open "http://localhost:8888" &
    elif command -v start &> /dev/null; then
      # Windows
      start http://localhost:8888 &
    fi

    echo "🎉 Браузер открыт на http://localhost:8888"
    echo ""
    echo "Горячая перезагрузка: нажми 'r' в этом терминале"
    echo "Выход: Ctrl+C"
    echo ""
  fi
done
