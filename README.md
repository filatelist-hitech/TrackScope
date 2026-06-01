# hitech-bpm-radar

DSP-first определение BPM для hitech / psytrance — автоматический темп с микрофона в диапазоне **155–230 BPM**. Без tap-tempo, без хардкоженых значений.

Rust DSP-ядро → Flutter FFI-мост → живой экран BPM. Все вычисления темпа — в Rust; Flutter только рендерит DSP-контракт.

## Продуктовый контракт

Продукт обязан сообщать:

- определённый BPM, либо `null`, если сигналу нельзя доверять;
- уверенность от `0.0` до `1.0`;
- состояние захвата (`lock state`);
- BPM-кандидаты со score;
- связи half-time и double-time;
- предупреждения о качестве сигнала;
- историю сессий.

Продакшен-логика никогда не хардкодит демо-значения BPM и не выдумывает темп для тишины, шума-без-сигнала, перегруженного микрофона или брейкдаунов.

## Структура репозитория

```text
apps/mobile/       Flutter-оболочка, сценарий выдачи разрешений микрофона, аудио-мост и рендер результата.
core/dsp/          Rust DSP-ядро + текущий Python/Node-прототип офлайн-анализатора, используемый тестами Phase 1.
core/ffi/          Граница нативного моста для интеграции с Flutter / мобильным шеллом.
core/tests/        Синтетические фикстуры, регрессионные тесты, приёмочные DSP-тесты.
tools/offline-lab/ Python-офлайн-анализатор, генератор фикстур, отчёты сравнения алгоритмов.
datasets/          Хранилище синтетических и реальных аудио-фикстур.
docs/              Архитектура, DSP-алгоритм, QA-матрица, roadmap, заметки по мобильному аудио, релизный чеклист.
.codex/            Конфиг Codex, role-агенты, шаблон планов.
.agents/skills/    Переиспользуемые навыки проекта для локальных воркфлоу с агентами.
```

## Статус проекта

### Завершённые фазы

| Фаза | Содержание |
|---|---|
| Phase 1 | Офлайн-DSP-лаборатория: Python-референс, синтетические фикстуры, CLI офлайн-анализатора |
| Phase 2 | Потоковое Rust DSP-ядро: кольцевой буфер, история онсетов, first-lock <6 с, stable-lock <12 с |
| Phase 3 | Flutter мобильный мост: iOS (static `.a`) + Android (`.so`), FFI-изолят, debug-экран, iPhone 11 ✓ |
| Phase 4 | Закалка: SNR-оценка, BpmSmoother (медиана+EMA+гистерезис), 21 реальная hitech-фикстура |
| Phase 5 | UI: VizController, SpectrogramPainter, WaveformPainter, live-spectrum, rawPcm-стрим |
| Phase 6 | Точность BPM: параболическая интерполяция (±0.2 BPM), BPM candidate history N=3, BpmDisplay EMA |
| Phase 7 | UI redesign: SpectrogramPainter с метрическими осями, LiveSpectrumPainter, AppTheme design tokens |
| Phase 7.1 | Осциллограф вместо спектрограммы на главном экране |
| Phase 8 | DSP fast re-lock v2: адаптивное окно по состоянию, детектор прыжка темпа, re-lock ≤3 с |
| Phase 8.1 | Fix first-lock: `has_ever_been_stable` — полная история при первом захвате |
| Phase 8.2 | Расширение диапазона 170→**155 BPM**, абсолютный гейт точности в `parity.py` |
| Phase 9 | Android APK: `build_android_native.sh` готов, ожидает установки Android Studio + NDK |
| Phase 10 | Freemium: RevenueCat IAP, Free/Pro tier, PaywallScreen, экспорт, история 24 ч |
| Phase 11 | **Design System v2**: Tab Bar, BPM Hero 72 px, ConfidenceBar 7 px, Signal Analyzer, Settings |

### В процессе

В процессе: финализация Android APK (Phase 9) и web preview визуализации.

### Ключевые характеристики

- Детекция BPM: **155–230 BPM** (hitech / psytrance), поиск в диапазоне 80–460
- Параболическая интерполяция пика автокорреляции — точность ±0.2 BPM на синтетике
- Адаптивное окно онсетов по состоянию захвата; re-lock ≤ 3 с
- 7 состояний: `SEARCHING` → `LOCKING` → `STABLE` / `UNSTABLE` / `BREAKDOWN` / `CLIPPED_MIC` / `NOISE_ONLY`
- Half-time / double-time кандидаты всегда видны; никогда не скрываются
- Anti-fake: нет хардкоженых BPM, нет фейкового пульса по таймеру
- SNR-оценка и гейтинг качества сигнала
- 43 Rust-теста + 21 Python-тест + 126 Flutter-тестов, 21 реальная hitech-фикстура (180–210 BPM)

## Design v2

Design System v2 (Phase 11) обновляет весь Flutter UI:

- **Tab Bar**: три вкладки Радар / История / Настройки через `IndexedStack` (CaptureBridge не пересоздаётся).
- **BPM Hero**: 72 px IBM Plex Mono, три режима (idle → «— — —» dim, detecting → accent, unstable → amber).
- **ConfidenceBar**: 7 px, цвет по порогу (red < 30 %, yellow 30–70 %, teal > 70 %).
- **Signal Analyzer**: Pro-экран с BPM-кандидатами, качеством сигнала, таймингами.
- **Settings**: 5 секций, SharedPreferences, Keep Screen On (WakelockPlus).
- **Paywall v2**: value headline, column headers FREE/PRO, CTA-иерархия, Roadmap card.

## Текущая фаза

**Phases 1–11 завершены.** Проект готовится к первому production-APK.

Последний подтверждённый запуск на реальном устройстве — iPhone 11, iOS 26.3.1, 2026-05-26.
Целевой диапазон расширен до **155–230 BPM** (Phase 8.2: поддержка раннего hitech от 155 BPM).

Rust-крейт в `core/dsp/` — продакшен-источник истины: извлечение онсетов, оценка темпа
автокорреляцией, hitech-нормализация кандидатов, скоринг уверенности и классификация
состояния захвата на нативном Rust. `core/dsp/tempo.py` и `core/dsp/synthetic.py`
остаются как читаемая алгоритмическая референс-реализация.

### Android APK (macOS, без физического устройства)

Требования: Android Studio с NDK 27.x, rustup.

```sh
# 1. Задать путь к Android SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$(ls $ANDROID_HOME/ndk | sort -V | tail -1)"

# 2. Добавить Rust Android таргеты (однократно)
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

# 3. Собрать нативную библиотеку для Android
bash scripts/build_android_native.sh
# → apps/mobile/android/app/src/main/jniLibs/<abi>/libhitech_bpm_ffi.so

# 4. Debug APK (не требует подписи)
cd apps/mobile && flutter build apk --debug
# → build/app/outputs/flutter-apk/app-debug.apk

# 5. Запустить в эмуляторе AVD
flutter emulators --launch <emulator_id>
flutter run
```

**Release APK** (нужен keystore):
```sh
# Сгенерировать keystore (однократно):
keytool -genkey -v -keystore apps/mobile/android/android-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias hitech-bpm

# Создать apps/mobile/android/key.properties из шаблона и заполнить пароли
cp apps/mobile/android/key.properties.template apps/mobile/android/key.properties

cd apps/mobile && flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

Подробности: [docs/ANDROID_TEST_PLAN.md](docs/ANDROID_TEST_PLAN.md)

### Запуск мобильного приложения (macOS Desktop / тесты)

```sh
# 1. Собрать Rust FFI dylib
/opt/homebrew/opt/rust/bin/cargo build --release -p hitech-bpm-ffi

# 2. Подтянуть Flutter-зависимости
cd apps/mobile
/opt/homebrew/bin/flutter pub get

# 3. Статика + юнит-тесты
/opt/homebrew/bin/flutter analyze
/opt/homebrew/bin/flutter test

# 4. Запуск (macOS desktop)
/opt/homebrew/bin/flutter run
```

### Запуск на физическом iPhone

Требования: Xcode, rustup (через `brew install rustup`), iPhone в Developer Mode.

```sh
# 1. Собрать статическую библиотеку для iOS
bash scripts/build_ios_native.sh

# 2. Однократная Xcode-конфигурация (первый раз):
#    - Link Binary With Libraries → добавить apps/mobile/ios/Frameworks/libhitech_bpm_ffi.a
#    - Build Settings → Library Search Paths → $(PROJECT_DIR)/Frameworks
#    - Build Settings → OTHER_LDFLAGS → -force_load $(PROJECT_DIR)/Frameworks/libhitech_bpm_ffi.a
#    - Signing & Capabilities → Team → выбрать Apple ID

# 3. Подтянуть CocoaPods
cd apps/mobile
flutter pub get
cd ios && pod install && cd ..

# 4. Запустить на подключённом iPhone
flutter run --release
```

Подробности в [docs/MOBILE_AUDIO.md](docs/MOBILE_AUDIO.md) и [docs/MANUAL_TEST_CHECKLIST.md](docs/MANUAL_TEST_CHECKLIST.md).

### Воркфлоу тестов

- `cargo test --workspace` — **герметичный**: не вызывает `python3`. Регрессионное покрытие на Rust лежит в `core/dsp/tests/offline_contract.rs` и использует общий модуль фикстур `core/dsp/tests/common/mod.rs`.
- `python3 -m unittest discover core/tests` — Python-референс-сьют.
- `node --test core/dsp/index.test.js` — Node-офлайн-анализатор.
- `python3 tools/offline-lab/offline_lab.py report` — детерминированный офлайн-QA-отчёт.
- `python3 tools/offline-lab/parity.py` — опциональная сверка дрифта Python ↔ Rust (вызывает Rust-бинарь `analyze_wav`; не входит в `cargo test`).

## Критерии приёмки

- Чистые синтетические фикстуры: ±1 BPM на 155, 170, 180, 190, 200 и 220 BPM.
- Шумный микрофонный вход: ±2–4 BPM при адекватном качестве сигнала.
- Первый рабочий захват: до 6 секунд.
- Стабильный захват: до 12 секунд.
- Тишина и шум-без-сигнала не должны достигать `STABLE`.
- В hitech-режиме half-time-кандидат 100 BPM не должен побеждать более сильного нормализованного кандидата 200 BPM.

## Документация

- [Архитектура](docs/ARCHITECTURE.md)
- [DSP-алгоритм](docs/DSP_ALGORITHM.md)
- [QA-матрица](docs/QA_MATRIX.md)
- [Roadmap](docs/ROADMAP.md)
- [Заметки по мобильному аудио](docs/MOBILE_AUDIO.md)
- [Ручной тест-чеклист (mobile)](docs/MANUAL_TEST_CHECKLIST.md)
- [Релизный чеклист](docs/RELEASE_CHECKLIST.md)
- [Android тест-план](docs/ANDROID_TEST_PLAN.md)
- [Глоссарий терминов](docs/GLOSSARY.md)

## Работа с Claude Code

Репозиторий настроен под нативный Claude Code параллельно с легаси-окружением Codex.

Где смотреть:

- `CLAUDE.md` — память проекта: DSP-контракт, правила hitech-нормализации, anti-fake правила, воркфлоу, команды сборки и тестов.
- `.claude/agents/` — 7 субагентов (`archman`, `dspman`, `mobileman`, `qaman`, `perfman`, `reviewman`, `docman`), зеркалирующие роли Codex `.codex/agents/*.toml`.
- `.claude/skills/` — 5 навыков (`project-bootstrap`, `dsp-tempo-analysis`, `mobile-audio-input`, `qa-audio-dataset`, `review-gate`), зеркалирующие `.agents/skills/*/SKILL.md`.
- `.claude/commands/` — slash-команды: `/plan`, `/qa-report`, `/parity`, `/review-gate`, `/bootstrap-task`.
- `.claude/settings.json` — разрешения и хуки проекта. Личные оверрайды — в `.claude/settings.local.json` (gitignore).

Типичные воркфлоу:

- Любую нетривиальную задачу начинаем с `/bootstrap-task <описание>` — она читает `AGENTS.md` + `CLAUDE.md`, классифицирует сложность, подбирает релевантных субагентов и навыки и скаффолдит план для medium/high-задач.
- `/plan <название>` генерирует полный execution-plan по шаблону `.codex/plans/PLANS.md`.
- `/qa-report` запускает `python3 tools/offline-lab/offline_lab.py report` и суммирует регрессии и нарушения состояний захвата.
- `/parity` гоняет parity-тесты Rust + Python и репортит дрифт `primary_bpm` / `confidence`.
- `/review-gate` запускает субагент `reviewman` по staged + unstaged-диффу перед мерджем.

Субагенты и навыки сопоставляются по `description` и активируются автоматически по триггерам; их также можно вызвать явно через `@agent-name` или сослаться на навык по имени.

> `.codex/` и `.agents/` сохранены как легаси-референс из исходного окружения OpenAI Codex. Не удаляйте и не модифицируйте их. Маппинг агентов Codex → субагентов Claude Code описан внизу `CLAUDE.md`.

## Монетизация (Free / Pro)

Приложение использует двухуровневую модель с RevenueCat IAP:

| Фича | Free | Pro |
|---|---|---|
| BPM Range | 170–230 | 155–230 |
| Debug Screen | ✕ (paywall) | ✓ |
| History | 30 сек | 24 ч |
| Export CSV/JSON | ✕ (paywall) | ✓ |
| Lock-screen Widget | Скоро | Скоро |

### Monetization Setup

1. Скопируйте `apps/mobile/lib/monetization/config.dart.template` → `config.dart` (gitignored).
2. Заполните RevenueCat API keys.
3. Либо передайте ключи через `--dart-define`:

```sh
flutter run --dart-define=REVENUECAT_IOS_KEY=your_ios_key --dart-define=REVENUECAT_ANDROID_KEY=your_android_key
```

Если оба ключа пусты, приложение работает полностью в Free tier (offline / keyless).

#### Полная версия для локального теста (без покупки)

Чтобы прогнать все Pro-фичи (диапазон 155–230, debug-экран, история 24 ч, экспорт)
на своём устройстве без настройки App Store / RevenueCat sandbox, соберите с флагом
`FORCE_PRO`:

```sh
flutter run --release --dart-define=FORCE_PRO=true
```

Флаг переключает только тир подписки — он **не** трогает DSP/BPM-математику. По
умолчанию `false`, поэтому обычная стор-сборка (без флага) остаётся Free. Не
передавайте `FORCE_PRO=true` в сборку для публикации.
