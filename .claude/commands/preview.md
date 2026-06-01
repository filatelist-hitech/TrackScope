---
description: "Открыть UI превью в браузере на localhost:7654. Подсказать run_preview.sh если сервер не запущен."
allowed-tools: Bash(curl:*), Bash(open:*)
---

Проверить, что preview-сервер доступен, и открыть его в браузере.

```bash
if curl -s --max-time 2 http://localhost:7654 > /dev/null; then
  echo "✅ Сервер работает: http://localhost:7654"
  open "http://localhost:7654"  # macOS
else
  echo "❌ Сервер не запущен."
  echo "Запусти в отдельном терминале:"
  echo "  ./apps/mobile/run_preview.sh"
fi
```
