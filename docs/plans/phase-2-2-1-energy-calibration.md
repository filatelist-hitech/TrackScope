# Plan: Phase 2.2.1 — EnergyAnalyzer calibration + ground truth актуализация

## 1. Task classification

- complexity: **low**
- domains: **dsp, qa**

---

## Краткое резюме (5 строк)

Задача состоит из двух частей:
1. **Ground truth update** — добавить `expected_key` (Camelot) в `fixture_manifest.json` для всех 21 реальных фикстур + добавить 4 новые фикстуры (real_22–25) из DJ-списка треков 20, 22, 23, 24.
2. **EnergyAnalyzer calibration** — запустить `offline_lab.py snapshot --input` на 4 новых треках, собрать `energy_result` из снапшотов, оценить соответствие уровней 1–10 реальному hitech и при необходимости скорректировать `FLUX_MAX`/`DENSITY_MAX` в `energy_analyzer.rs`.

---

## 2. Agents

- **@qaman** — валидация манифеста и проверка что `parity.py --fixture-set real` проходит после изменений.
- **@dspman** — если потребуется изменение констант в `energy_analyzer.rs`.
- **@docman** — обновить QA_MATRIX.md с новыми фикстурами.

---

## 3. Files to inspect

```
datasets/fixture_manifest.json
datasets/hitech/snapshots/hitech_real_*.json          (все 21)
core/dsp/src/energy_analyzer.rs                       (константы)
tools/offline-lab/offline_lab.py                      (команда snapshot)
tools/offline-lab/parity.py                           (expected_key gate если потребуется)
docs/QA_MATRIX.md
```

---

## 4. Current behavior

- `fixture_manifest.json` содержит 21 реальную фикстуру с `expected_bpm` (все верны, проверены по DJ-списку).
- Поле `expected_key` **отсутствует** в манифесте — ключ нигде не проверяется.
- 4 трека из DJ-списка (##20, 22, 23, 24) **не имеют** соответствующих снапшотов.
- `source_file` хранится только в `datasets/hitech/snapshots/*.json`, не в манифесте — сопоставление ненаглядно.
- `EnergyAnalyzer` откалиброван на синтетике (`FLUX_MAX=0.15`, `DENSITY_MAX=6.0`); поведение на реальных треках неизвестно.
- `hitech_real_10` (196 BPM) — `known_fail` (детектируется 146.7 BPM) актуален.

---

## 5. Target behavior

- `fixture_manifest.json`: каждая реальная фикстура имеет поля `expected_key` (Camelot, напр. `"6A"`) и `expected_key_source: "dj_software_screenshot"`.
- 4 новых фикстуры (`hitech_real_22` … `hitech_real_25`) добавлены с полным BPM + key ground truth.
- `EnergyAnalyzer` выдаёт реалистичные уровни (≥5 для активного hitech, ≤3 для тихих секций) на реальных треках.
- `parity.py --fixture-set real` завершается с кодом 0.

---

## 6. Data contracts

**Новое поле в `fixture_manifest.json`:**
```json
{
  "expected_key": "6A",
  "expected_key_source": "dj_software_screenshot",
  "key_tolerance": 0
}
```

**EnergyAnalyzer константы (в `energy_analyzer.rs`):**
```rust
const FLUX_MAX: f32    = 0.15;   // may need tuning
const DENSITY_MAX: f32 = 6.0;    // may need tuning
```

**`parity.py`**: поле `expected_key` будет использоваться опционально — если присутствует, проверять `key_result.camelot == expected_key` как информационный (не fail) гейт на первом проходе.

---

## 7. Implementation steps

### Step 1: Сопоставление ground truth — обновить `fixture_manifest.json`

Маппинг DJ-список → фикстура:

| fixture       | DJ # | expected_bpm  | expected_key | source_file (снапшот) |
|---------------|------|---------------|--------------|----------------------|
| hitech_real_01 | 1  | 180.000       | 6A (Gm)      | 1 Unknown Artist - DarkWeb... Molecular (180).wav |
| hitech_real_02 | 2  | 182.022       | 9B (G)       | 2 ... Calabi Yau - Trance Del Plata.wav |
| hitech_real_03 | 3  | 184.000       | 8A (Am)      | 3 CATAR RECORDS ... One Truth (184 Bpm).aiff |
| hitech_real_04 | 4  | 186.014       | 3B (C#)      | 4 ... Dugguh - Cruise Control 186bpm.wav |
| hitech_real_05 | 5  | 188.008       | 5A (Cm)      | 5 Space Alchemist ... Heals.aiff |
| hitech_real_06 | 6  | 188.000       | 4A (Fm)      | 6 SPANK RECORDS ... DARKNESS.aiff |
| hitech_real_07 | 7  | 190.000       | 4B (G#)      | 7 ... KiLLATK - Dynavision.wav |
| hitech_real_08 | 8  | 192.000       | 3A (A#m)     | 8 Dugguh - Alternate reality.aiff |
| hitech_real_09 | 9  | 194.000       | 1A (G#m)     | 9 ... Wordsalad - Unlock.wav |
| hitech_real_10 | 10 | 196.000       | 4A (Fm)      | 10 ... Sekorsky - Sintanta (196 bpm).wav |
| hitech_real_11 | 11 | 198.023       | 10A (Bm)     | 11 ... Inner Coma vs Spiral - Silo.wav |
| hitech_real_12 | 12 | 200.000       | 4A (Fm)      | 12 ... Mimic Vat - Beauty And The Beast.wav |
| hitech_real_13 | —  | 200.000       | 6A (Gm) *    | 13 ... Pairidaeza 200.wav (другая копия DJ#13) |
| hitech_real_14 | 13 | 200.007       | 6A (Gm)      | 14 ... Pairidaeza (_filamast).wav |
| hitech_real_15 | 14 | 200.000       | 8A (Am)      | 15 Inner Coma - The Dream.flac |
| hitech_real_16 | 15 | 200.050       | 7B (F)       | 16 ERF - Shadow Realm.aiff |
| hitech_real_17 | 16 | 202.013       | 10A (Bm)     | 17 ... Yucatec - Fantasy.wav |
| hitech_real_18 | 17 | 204.005       | 12A (C#m)    | 18 Spiral ... Intercepting Your World.flac |
| hitech_real_19 | 18 | 205.394       | 11A (F#m)    | 19 ... Sonic System - I Will Kill U (206).wav |
| hitech_real_20 | 19 | 208.608       | 8A (Am)      | 20 Killatk ... Way2hi.wav |
| hitech_real_21 | 21 | 210.027       | 8B (C)       | 21 ... Yucatec - Burna.wav |

*real_13: та же песня что DJ#13 — ключ инферен как 6A/Gm, источник = "inferred_same_song".

Действие: добавить `expected_key`, `expected_key_source` в каждую запись манифеста.

### Step 2: Добавить 4 новые фикстуры в манифест

Треки из DJ-списка, отсутствующие в 21 фикстуре:

| fixture новый | DJ # | BPM      | Key | audio path |
|---------------|------|----------|-----|-----------|
| hitech_real_22 | 20 | 210.000  | 2A (D#m) | /Users/filatelist/Music/060524/compiled by Metaforik - Rumble/Fractaly Noise - Rumble - 11 Assimilation (210).aiff |
| hitech_real_23 | 22 | 210.000  | Bm (→ 10A) | /Users/filatelist/Music/190326/VA - Wired Brains .../09. Freak Engine & Narxz & Ketek - Nostalgia is Dead -210-.wav |
| hitech_real_24 | 23 | 212.001  | D# (→ 3B) | /Users/filatelist/Music/190326/VA - Wired Brains .../10. Yucatec & Nyotech - Neural Networks -212-.wav |
| hitech_real_25 | 24 | 212.030  | 8B (C)   | /Users/filatelist/Music/190326/Spirituvel and Friends - Psyber Roots/...Binary Oracle - 212 bpm.aiff |

Примечание по Camelot для DJ #22/23 (только Key Text, без Camelot):
- Bm → 10A
- D# (D#maj) → 3B

Действие: для каждого трека запустить `python3 tools/offline-lab/offline_lab.py snapshot --input <path>` и добавить запись в манифест.

### Step 3: EnergyAnalyzer — замер на реальных снапшотах

Запустить Rust-анализ на 25 треках (через parity.py --live если аудио доступно), собрать `energy_result.level` и `energy_result.rms_dbfs/flux/density` для каждого. Цель:

- Активные hitech треки в STABLE должны давать уровень ≥ 5
- Трек с breakdown/тихим началом — уровень ≤ 4
- hitech_real_06 (известный NOISE_ONLY) — energy=None корректно

Если уровни систематически занижены (≤3 на активных треках), скорректировать:
- `FLUX_MAX` уменьшить (если реальный flux ниже синтетического)
- `DENSITY_MAX` скорректировать под реальную плотность онсетов

### Step 4: Обновить тесты energy.rs и QA_MATRIX.md

- Проверить что `calibration_clean_200_in_range` покрывает [4,8] — не менять если всё ок.
- Если константы изменились — пересоздать тест `calibration_real_hitech_in_range` (level ≥ 5 для реального трека).

---

## 8. Tests

```sh
# После обновления манифеста
python3 tools/offline-lab/parity.py --fixture-set real

# После snapshot 4 новых треков
python3 tools/offline-lab/parity.py --fixture-set real

# После изменения констант energy_analyzer.rs
/opt/homebrew/opt/rust/bin/cargo test --workspace

# Flutter (не затрагивается, но проверить)
flutter test
```

---

## 9. Risks

| Риск | Вероятность | Fallback |
|------|-------------|----------|
| Аудио треков 22–24 не декодируется ffmpeg (AIFF 24-bit) | низкая | конвертировать `ffmpeg -i input.aiff -ar 48000 -ac 1 out.wav` перед snapshot |
| real_10 (known_fail 196 BPM) — константы energy тоже неверны | средняя | отметить в манифесте отдельно, не используем для energy-калибровки |
| Изменение констант energy ломает тест `calibration_clean_200` | средняя | расширить диапазон теста до [3,9] вместо [4,8] с обоснованием |
| Key detection на реальных треках расходится с DJ-данными | высокая | поле `expected_key` информационное, не валит exit-code на первом проходе |

---

## 10. Done when

- [ ] `fixture_manifest.json` содержит `expected_key` + `expected_key_source` для всех 21 записей.
- [ ] 4 новых фикстуры (real_22–25) добавлены в манифест со снапшотами.
- [ ] `python3 tools/offline-lab/parity.py --fixture-set real` → exit code 0.
- [ ] `/opt/homebrew/opt/rust/bin/cargo test --workspace` → все зелёные.
- [ ] EnergyAnalyzer уровни на реальных треках задокументированы (в комментарии к манифесту или в отдельной секции QA_MATRIX).
- [ ] `docs/QA_MATRIX.md` обновлён с 4 новыми строками фикстур.

---

## Порядок выполнения

```
Step 1 → обновить manifest.json (21 фикстура, expected_key)
Step 2 → snapshot 4 новых треков + добавить в manifest
Step 3 → замер energy на реальных треках
Step 4 → корректировка констант если нужно + тесты
```
