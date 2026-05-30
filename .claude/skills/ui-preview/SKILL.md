---
name: ui-preview
description: >
  Use this skill ALWAYS after editing any Flutter UI file in
  apps/mobile/lib/ (.dart files: widgets, painters, screens, colors,
  design tokens, layout). After the edit, confirm the web preview at
  localhost:7654 reflects the change. Triggers on: waveform changes,
  color/theme changes, layout changes, painter edits, screen redesigns,
  BPM/confidence/badge rendering tweaks. Use PROACTIVELY after every UI edit.
---

# UI preview at localhost:7654

The Flutter Web preview serves `lib/main_web.dart`, which renders the real
`MainScreen` driven by `MockDspStream` (simulated `DspResult`, **not** a real
detector — Rust/FFI is unavailable in the browser). A "PREVIEW · MOCK" banner
is shown so mock numbers are never mistaken for real capture.

## After each UI-file edit

1. Save the file (Edit/Write done).
2. Flutter hot-reload applies automatically (~1 s) while `run_preview.sh` runs.
3. Confirm the preview is live and reflects the change using the **built-in
   Claude Preview MCP tools** (no extra server needed):
   - `preview_start` on `http://localhost:7654` (if not already started).
   - `preview_screenshot` (visual changes) or `preview_snapshot` (structure).
   - `preview_console_logs` if something looks broken.
4. Tell the user: "Превью обновлено: http://localhost:7654".
5. If the preview server is not running:
   > «Сервер превью не запущен. Запусти в отдельном терминале:
   > `./apps/mobile/run_preview.sh`»

The `.mcp.json` `mockup` server (Python `uvx mcp-server-fetch`) is an optional
secondary fetch path; the built-in Preview tools above are the primary one.

## Don't

- Don't run `flutter run` yourself — it's long-lived; the user owns the server.
- Don't restart the server — only notify.
- Don't present `MockDspStream` values as a real BPM detection.
- Don't import `mock/` from `lib/main.dart` (production mobile path).
