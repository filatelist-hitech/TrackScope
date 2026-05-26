# core/ffi

Граница нативного моста для интеграции с Flutter / мобильным шеллом.

Ответственности:

- владеть C ABI-хэндлами `DspEngine`;
- принимать указатели на PCM-кадры из платформенного аудио-кода;
- пробрасывать аудио в Rust DSP без вычисления BPM самостоятельно;
- отдавать сериализованные снэпшоты `DspResult` через `hitech_bpm_engine_analyze_json` (вызывающий освобождает через `hitech_bpm_string_free`).

## Поверхность C ABI

| Функция | Назначение |
| --- | --- |
| `hitech_bpm_engine_new()` | Аллоцирует потоковый движок с hitech-дефолтами. Возвращает непрозрачный `*mut HitechBpmEngine`. |
| `hitech_bpm_engine_free(engine)` | Освобождает движок. Безопасна на null. |
| `hitech_bpm_engine_reset(engine)` | Сбрасывает скользящее состояние без переаллокации буферов. |
| `hitech_bpm_engine_push_samples(engine, samples, len, sample_rate) -> bool` | Дописывает PCM. Аллокационно лёгкая; безопасна для вызова из аудио-потока. Возвращает `false` на null/нулевую длину. |
| `hitech_bpm_engine_analyze_json(engine) -> *mut c_char` | Сериализует текущий скользящий `DspResult` как UTF-8 JSON. Буфером владеет вызывающий. Рассчитан на поллинг на UI-частоте (~10–30 Hz), не из аудио-потока. Возвращает null на невалидном хэндле. |
| `hitech_bpm_string_free(ptr)` | Освобождает строку, вернутую `analyze_json`. Безопасна на null. |

Ключи JSON соответствуют контракту `DspResult`, описанному в `docs/DSP_ALGORITHM.md`: `primary_bpm`, `confidence`, `lock_state`, `signal_quality`, `candidates`, `timing`.

Этот слой должен оставаться тонким. Ранжирование кандидатов, уверенность, клиппинг и состояние захвата живут в `core/dsp`.
