# tools/offline-lab

Граница офлайн-анализатора и генератора фикстур.

Офлайн-лаб обязан подавать аудио в тот же движок `core/dsp`, который использует mobile. Он может декодировать файлы, генерировать фикстуры и писать отчёты, но не должен реализовывать отдельный BPM-детектор.

## Команды

Сгенерировать детерминированный набор WAV-фикстур:

```sh
python3 tools/offline-lab/offline_lab.py generate-suite --out-dir datasets/synthetic/offline-lab
```

Проанализировать одну 16-битную PCM-WAV-фикстуру:

```sh
python3 tools/offline-lab/offline_lab.py analyze datasets/synthetic/offline-lab/pulse_200bpm.wav
```

Запустить in-memory QA-отчёт по обязательной матрице первого лаба:

```sh
python3 tools/offline-lab/offline_lab.py report
```

Каждая строка отчёта содержит имя фикстуры, ожидаемый BPM, определённый BPM, ошибку BPM, уверенность, состояние захвата, качество сигнала, список кандидатов (с relation и source_bpm для half/double), pass/fail и заметки. Завершается с не-нулевым кодом, если какая-либо строка падает.

### Команда `snapshot` — захват снапшотов реальных фикстур

Команда `snapshot` анализирует аудиофайлы (.wav .aiff .aif .flac) через Python и Rust и сохраняет JSON-снапшоты в `<input_dir>/snapshots/`. Снапшоты коммитятся в git; аудиофайлы не коммитятся.

```sh
python3 tools/offline-lab/offline_lab.py snapshot --input datasets/hitech/
```

Флаги:

| Флаг | По умолчанию | Описание |
| --- | --- | --- |
| `--input DIR` | обязателен | Директория с аудиофайлами |
| `--force` | нет | Перезаписать существующие снапшоты |
| `--duration SECS` | 30.0 | Секунд аудио для анализа на файл |
| `--cargo PATH` | `/opt/homebrew/opt/rust/bin/cargo` | Путь к cargo |
| `--release` | нет | Сборка Rust-анализатора в release-режиме |

После завершения команда обновляет `datasets/fixture_manifest.json` записями о новых снапшотах.

**Формат снапшота** (`datasets/hitech/snapshots/hitech_real_01.json`):

```json
{
  "captured_at": "2026-05-26T14:00:00Z",
  "category": "real",
  "expected_bpm_hint": 180.0,
  "fixture_sha256": "<sha256 of 30-sec WAV window>",
  "python": { "primary_bpm": 180.2, "confidence": 0.62, "lock_state": "LOCKING", ... },
  "rust":   { "primary_bpm": 180.2, "confidence": 0.62, "lock_state": "LOCKING", ... },
  "source_file": "1 Unknown Artist - ... (180).wav"
}
```

Поля `python` и `rust` содержат полный `DspResult` (включая `debug`, `signal_quality`, `candidates`).

## Команды parity

### `parity.py` — кросс-языковая проверка Python ↔ Rust

#### Режим по умолчанию (все manifest-фикстуры):

```sh
python3 tools/offline-lab/parity.py
```

Читает `datasets/fixture_manifest.json`, для каждой фикстуры загружает снапшот и сравнивает `python.primary_bpm` vs `rust.primary_bpm` с допуском `bpm_tolerance`. Работает в CI без аудиофайлов.

#### Только synthetic (legacy-режим, live-генерация):

```sh
python3 tools/offline-lab/parity.py --fixture-set synthetic
```

Генерирует синтетические фикстуры на лету, прогоняет Python и Rust на одних и тех же WAV-байтах. Поведение идентично прежнему baseline.

#### Только real fixtures (snapshot-based):

```sh
python3 tools/offline-lab/parity.py --fixture-set real
```

Читает только фикстуры с `category: real` из манифеста.

#### Live-режим — перезапуск текущего Rust на аудиофайлах:

```sh
python3 tools/offline-lab/parity.py --fixture-set real --live --input datasets/hitech/
```

Перезапускает текущий Rust-анализатор на аудиофайлах (нужны локально), сравнивает с Python из снапшота. Используется после изменений DSP: если delta вышла за tolerance, нужно обновить снапшоты через `snapshot --force`.

#### Флаги:

| Флаг | По умолчанию | Описание |
| --- | --- | --- |
| `--fixture-set {all,synthetic,real}` | all | Набор фикстур |
| `--live` | нет | Перезапуск live-анализа (требует `--input`) |
| `--input DIR` | нет | Директория с аудиофайлами (для `--live`) |
| `--cargo PATH` | `/opt/homebrew/opt/rust/bin/cargo` | Путь к cargo |
| `--release` | нет | Сборка Rust в release-режиме |
| `--json` | нет | Вывод в JSON вместо таблицы |

Завершается с exit 0, если все фикстуры в допуске; с exit 1, если есть провалы.

## Fixture manifest

`datasets/fixture_manifest.json` — единый список фикстур с per-fixture tolerances:

```json
{
  "fixtures": [
    {
      "name": "hitech_real_01",
      "snapshot": "datasets/hitech/snapshots/hitech_real_01.json",
      "category": "real",
      "bpm_tolerance": 4.0,
      "lock_state_must_match": false
    }
  ]
}
```

Допуск `bpm_tolerance` задаёт максимально допустимый `|python_bpm - rust_bpm|` для данной фикстуры. Для реальных записей минимум 4.0 BPM (структурный предел из-за разности float-арифметики Python vs Rust в цепочке автокорреляции). Для синтетических — 1–2 BPM.

Manifest обновляется автоматически командой `snapshot`. Ручное редактирование допустимо для изменения tolerances.

## Требования

- Python 3.9+, ffmpeg (для конвертации AIFF/FLAC)
- Rust toolchain (`/opt/homebrew/opt/rust/bin/cargo`)
- `core/dsp` Python-модуль в PYTHONPATH (автоматически через REPO_ROOT)
