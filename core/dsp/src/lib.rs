//! Контракт Rust DSP-ядра для hitech-bpm-radar.
//!
//! Текущая реализация намеренно начинается с публичной модели данных,
//! гейтов качества сигнала и hitech-нормализации кандидатов. Realtime-детекция
//! онсетов и оценка кандидатов заполнят эту границу в Phase 2.

pub mod energy_analyzer;
pub mod genre_preset;
pub mod key_analyzer;

pub use energy_analyzer::EnergyResult;
pub use genre_preset::GenrePreset;
pub use key_analyzer::KeyResult;

use std::collections::VecDeque;

use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum LockState {
    Searching,
    Locking,
    Stable,
    Unstable,
    Breakdown,
    ClippedMic,
    NoiseOnly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TempoRelation {
    Raw,
    Main,
    HalfTime,
    DoubleTime,
    NormalizedFromHalf,
    NormalizedFromDouble,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DspConfig {
    pub sample_rate: u32,
    pub target_bpm_min: f32,
    pub target_bpm_max: f32,
    pub broad_bpm_min: f32,
    pub broad_bpm_max: f32,
    pub analysis_window_seconds: f32,
    pub lock_min_seconds: f32,
    pub stable_min_seconds: f32,
    /// Включить адаптивное окно анализа по состоянию захвата.
    ///
    /// Когда `true`, `analyze()` берёт только хвостовой срез `onset_history`
    /// для автокорреляции (буфер не усекается, только слайс для анализа):
    ///   STABLE           → полная история (без изменений)
    ///   LOCKING          → min(полная, 4.0 с)
    ///   SEARCHING/UNSTABLE → min(полная, 2.0 с)
    ///
    /// Это ускоряет реакцию на смену темпа: новый темп начинает доминировать
    /// в коротком хвосте быстрее, чем в полном окне.
    /// Default: `true`.
    pub adaptive_window: bool,
    /// Порог BPM-разрыва для детектора резкой смены темпа.
    ///
    /// Если `|top_candidate_bpm - last_stable_bpm| > tempo_jump_threshold`
    /// И `tempo_shift_counter >= RELOCK_CONFIRM_FRAMES` — это «темповый прыжок»
    /// (новый трек, не джиттер). В таком случае дополнительно сбрасывается
    /// `bpm_history` и следующее состояние форсируется в SEARCHING.
    ///
    /// 15 BPM выбрано как безопасный гейт выше любого шумового флуктуации
    /// (джиттер в STABLE < 2 BPM после параболической интерполяции,
    /// брейкдаун не меняет BPM-кандидата). Default: `15.0`.
    pub tempo_jump_threshold: f32,
}

impl Default for DspConfig {
    fn default() -> Self {
        Self {
            sample_rate: 48_000,
            target_bpm_min: 155.0,
            target_bpm_max: 230.0,
            broad_bpm_min: 80.0,
            broad_bpm_max: 460.0,
            analysis_window_seconds: 12.0,
            lock_min_seconds: 6.0,
            stable_min_seconds: 12.0,
            adaptive_window: true,
            tempo_jump_threshold: 15.0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct SignalQuality {
    pub input_level_dbfs: Option<f32>,
    pub peak_dbfs: Option<f32>,
    pub clipping: bool,
    pub clipped_frame_ratio: f32,
    pub noise_level: NoiseLevel,
    pub snr_estimate_db: Option<f32>,
    pub silence: bool,
    pub breakdown_likely: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum NoiseLevel {
    Low,
    Medium,
    High,
    NoiseOnly,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ConfidenceFactors {
    pub onset_clarity: f32,
    pub peak_prominence: f32,
    pub harmonic_support: f32,
    pub recent_stability: f32,
    pub signal_quality: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct TempoCandidate {
    pub bpm: f32,
    pub relation: TempoRelation,
    pub score: f32,
    pub raw_score: f32,
    pub stability_score: f32,
    pub range_score: f32,
    pub source_bpm: Option<f32>,
    pub confidence_factors: ConfidenceFactors,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DspTiming {
    pub analysis_time_sec: f32,
    pub window_time_sec: f32,
    pub hop_time_sec: f32,
    pub first_lock_time_sec: Option<f32>,
}

/// Диагностические поля, эмитируемые вместе с каждым `DspResult`.
///
/// Все значения вычисляются в `analyze_from_envelope` как побочный продукт
/// обычного анализа — без дополнительной CPU-стоимости.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DspDebug {
    /// Количество значимых темповых пиков (онсет-событий) в секунду в текущем
    /// окне анализа. Вычисляется как `raw_peaks.len() / duration_sec`.
    pub onset_rate_hz: f32,
    /// Среднее значение огибающей онсетов по всему окну анализа (spectral flux).
    pub onset_strength: f32,
    /// Prominence главного темпового пика в нормализованной автокорреляции.
    /// Чем выше — тем чище пик, тем убедительнее темп.
    pub tempo_peak_prominence: f32,
    /// Мера неоднозначности: насколько сильно конкурирующие кандидаты
    /// претендуют на то же темповое пространство. 0 = нет конкуренции.
    pub harmonic_ambiguity: f32,
    /// stability_score основного кандидата на момент снапшота.
    pub stability_score: f32,
    /// Текстовые предупреждения: клиппинг, брейкдаун, неоднозначность.
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DspResult {
    pub primary_bpm: Option<f32>,
    pub confidence: f32,
    pub lock_state: LockState,
    pub signal_quality: SignalQuality,
    pub candidates: Vec<TempoCandidate>,
    pub timing: DspTiming,
    /// Жанровый пресет, использованный при анализе. Default = HitechPsy.
    /// Присутствует в JSON для диагностики; Dart-парсер игнорирует неизвестные поля.
    pub genre_preset: GenrePreset,
    /// Результат определения тональности. None в Phase 1 (Phase 2 skeleton).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key_result: Option<KeyResult>,
    /// Результат анализа энергии 1–10. None в Phase 1 (Phase 2 skeleton).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub energy_result: Option<EnergyResult>,
    /// Диагностика алгоритма — присутствует в каждом снапшоте.
    pub debug: DspDebug,
}

/// Скользящее состояние онсетов, поддерживаемое `DspEngine::push_samples`.
///
/// Каждый вызов `push_samples` добавляет новый PCM в ограниченное кольцо,
/// сливает полные кадры онсетов в `onset_history` и отбрасывает самые
/// старые сэмплы онсетов, выпадающие за пределов окна анализа. Поэтому
/// CPU-стоимость на вызов пропорциональна размеру *нового* PCM-чанка,
/// а не длительности стрима — анализ стрима, работающего уже час, стоит
/// столько же, сколько анализ после первого push.
///
/// `prev_lock_state` сохраняет результат предыдущего `analyze()` и
/// используется для адаптивного сглаживания огибающей онсетов: если движок
/// уже находился в `LOCKING` или `STABLE`, значит, в окне было консистентное
/// темповое свидетельство — и тогда лёгкий low-pass на огибающей безопасен.
/// Без этой истории (первые вызовы, новая сессия, батч-путь) сглаживание
/// не применяется, чтобы не создавать ложную периодичность в чистом шуме.
#[derive(Debug, Clone)]
pub struct DspEngine {
    config: DspConfig,
    observed_samples: u64,
    pcm_window: VecDeque<f32>,
    pcm_pending: Vec<f32>,
    onset_history: VecDeque<f32>,
    prev_frame_rms: Option<f32>,
    /// Состояние захвата из предыдущего вызова `analyze()`.
    /// `None` в начале сессии и после `reset()`.
    prev_lock_state: Option<LockState>,
    /// Скользящий буфер последних BPM_HISTORY_N значений `primary_bpm`
    /// в состоянии STABLE. Медиана буфера заменяет мгновенное значение,
    /// сглаживая остаточный джиттер после параболической интерполяции.
    /// Очищается при любом не-STABLE кадре.
    bpm_history: VecDeque<f32>,
    /// BPM, зафиксированный при последнем устойчивом STABLE-захвате.
    /// Используется fast re-lock: если текущий топ-кандидат расходится
    /// с этим значением > RELOCK_BPM_SHIFT_THRESHOLD BPM на
    /// RELOCK_CONFIRM_FRAMES подряд — onset_history усекается до
    /// RELOCK_WINDOW_SECS секунд для ускорения нового захвата.
    last_stable_bpm: Option<f32>,
    /// Счётчик подряд идущих кадров с детектированным темповым сдвигом.
    /// Сбрасывается при возврате в STABLE или при отсутствии сдвига.
    tempo_shift_counter: u32,
    /// Флаг форсированного перехода в SEARCHING при детектировании
    /// «темпового прыжка» (v2 tempo discontinuity detector).
    /// При `true` следующий `analyze()` форсирует SEARCHING вместо UNSTABLE,
    /// независимо от текущего скора кандидата. Сбрасывается после применения.
    force_next_searching: bool,
    /// Выставляется в `true` при первом достижении STABLE и никогда не
    /// сбрасывается в `false` (в отличие от `last_stable_bpm`).
    /// Используется для гейтирования адаптивного окна: при первом захвате
    /// (флаг `false`) всегда берётся полная onset-история — 8–12 сек
    /// (~25–50 ударов) дают надёжный пик автокорреляции и уверенность ≥ 0.70.
    /// После первого STABLE флаг становится `true`, и адаптивное окно
    /// начинает работать штатно для ускорения повторного захвата.
    has_ever_been_stable: bool,
    hop_size: usize,
    frame_size: usize,
    pcm_capacity: usize,
    onset_capacity: usize,
    hop_sec: f32,
}

/// Ёмкость скользящего BPM-буфера в `DspEngine`.
/// N=3 охватывает ~150 мс при интервале опроса 50 мс — достаточно,
/// чтобы подавить остаточный джиттер без заметной задержки смены темпа.
const BPM_HISTORY_N: usize = 3;

/// Fast re-lock (v1): длительность сохраняемой onset-истории после
/// детектированного темпового сдвига. 2 сек onset-данных ≈ 5–8 периодов
/// для 155–230 BPM (лаг 104–155 onset-кадров при hop=2.5 мс) — достаточно
/// для надёжного autocorr-пика. После усечения новые онсеты нового темпа
/// вытеснят остатки за ~1–2 сек, что даёт итоговый перезахват ~3–4 сек.
const RELOCK_WINDOW_SECS: f32 = 2.0;

/// Минимальный BPM-разрыв между текущим топ-кандидатом и последним
/// стабильным BPM для активации fast re-lock.
const RELOCK_BPM_SHIFT_THRESHOLD: f32 = 10.0;

/// Количество подряд идущих кадров с темповым сдвигом, требуемое для
/// активации fast re-lock. 1 кадр (~50 мс) достаточно: порог
/// RELOCK_BPM_SHIFT_THRESHOLD = 10 BPM уже отфильтровывает шумовые
/// выбросы. 1-кадровая задержка сокращает время реакции до ~50 мс.
///
/// Счёт начинается с первого кадра, где prev_lock_state != None и
/// BPM-расхождение > RELOCK_BPM_SHIFT_THRESHOLD. Это включает кадр
/// сразу после выхода из STABLE (prev_lock_state = Some(Stable)).
const RELOCK_CONFIRM_FRAMES: u32 = 1;

// ─────────────────────────────────────────────────────────────────────────────
// Adaptive window constants (v2) — размеры хвостовых срезов onset_history
// по состоянию захвата. Используются только при `config.adaptive_window == true`.
// ─────────────────────────────────────────────────────────────────────────────

/// Размер хвостового среза в LOCKING: 6 секунд.
/// Совпадает с lock_min_seconds (default 6.0). 6 с = ~20 ударов при 200 BPM →
/// достаточно для уверенности ≥ 0.70 и перехода в STABLE. Было 4.0 с в Phase 4.5 —
/// регрессия: только ~13 ударов → confidence ~0.68, застревание в LOCKING.
const ADAPTIVE_WINDOW_LOCKING_SECS: f32 = 6.0;

/// Размер хвостового среза в SEARCHING/UNSTABLE: 2 секунды.
/// Совпадает с RELOCK_WINDOW_SECS — обеспечивает согласованность:
/// v1-дренаж onset_history и v2-срез дают одинаковый горизонт анализа.
const ADAPTIVE_WINDOW_SEARCHING_SECS: f32 = 2.0;

impl DspEngine {
    pub fn new(config: DspConfig) -> Self {
        let (hop_size, frame_size) = frame_geometry(config.sample_rate);
        let pcm_capacity = ((config.analysis_window_seconds.max(0.0)
            * config.sample_rate as f32)
            .round() as usize)
            .max(frame_size);
        let onset_capacity = (pcm_capacity / hop_size).max(8);
        let hop_sec = if config.sample_rate == 0 {
            0.0
        } else {
            hop_size as f32 / config.sample_rate as f32
        };
        Self {
            config,
            observed_samples: 0,
            pcm_window: VecDeque::with_capacity(pcm_capacity),
            pcm_pending: Vec::with_capacity(frame_size + hop_size),
            onset_history: VecDeque::with_capacity(onset_capacity),
            prev_frame_rms: None,
            prev_lock_state: None,
            bpm_history: VecDeque::with_capacity(BPM_HISTORY_N + 1),
            last_stable_bpm: None,
            tempo_shift_counter: 0,
            force_next_searching: false,
            has_ever_been_stable: false,
            hop_size,
            frame_size,
            pcm_capacity,
            onset_capacity,
            hop_sec,
        }
    }

    pub fn config(&self) -> DspConfig {
        self.config
    }

    pub fn push_samples(&mut self, samples: &[f32], sample_rate: u32) {
        if sample_rate == 0 || samples.is_empty() {
            return;
        }

        let resampled_owned: Vec<f32>;
        let normalized: &[f32] = if sample_rate == self.config.sample_rate {
            samples
        } else {
            resampled_owned = resample_linear(samples, sample_rate, self.config.sample_rate);
            // SAFETY: `resampled_owned` живёт до конца этой функции.
            // Заимствуем его на время вызова.
            // (Нельзя вернуть заимствование, привязанное к локальной переменной,
            // поэтому делаем небольшой трюк: считываем всё прямо сейчас.)
            return self.push_normalized(&resampled_owned);
        };

        self.push_normalized(normalized);
    }

    fn push_normalized(&mut self, normalized: &[f32]) {
        self.observed_samples = self
            .observed_samples
            .saturating_add(normalized.len() as u64);

        // Ограниченное PCM-кольцо: O(новых) работы, не растёт выше pcm_capacity.
        for &sample in normalized {
            if self.pcm_window.len() >= self.pcm_capacity && self.pcm_capacity > 0 {
                self.pcm_window.pop_front();
            }
            self.pcm_window.push_back(sample);
        }

        // Извлечение онсетов только по только что пришедшему PCM. Цикл
        // по кадрам несёт границу в `pcm_pending`, поэтому кадр,
        // оседлавший два push'а, всё равно эмитится ровно один раз.
        self.pcm_pending.extend_from_slice(normalized);
        while self.pcm_pending.len() >= self.frame_size {
            let rms = frame_rms(&self.pcm_pending[..self.frame_size]);
            let flux = match self.prev_frame_rms {
                Some(prev) => (rms - prev).max(0.0),
                None => 0.0,
            };
            self.prev_frame_rms = Some(rms);
            if self.onset_history.len() >= self.onset_capacity && self.onset_capacity > 0 {
                self.onset_history.pop_front();
            }
            self.onset_history.push_back(flux);
            self.pcm_pending.drain(0..self.hop_size);
        }
    }

    pub fn analyze_raw_candidates(&self, raw_candidates: &[(f32, f32)]) -> DspResult {
        analyze_candidates(raw_candidates, self.observed_seconds(), self.config)
    }

    /// Вычислить текущий `DspResult` по скользящей истории онсетов.
    ///
    /// Принимает `&mut self`: после вычисления сохраняет `lock_state`
    /// результата в `self.prev_lock_state`, чтобы следующий вызов мог
    /// применить адаптивное сглаживание огибающей при необходимости.
    pub fn analyze(&mut self) -> DspResult {
        // Rearrange the ring buffer in-place so it is contiguous (no heap alloc).
        // The &mut borrow ends here; as_slices() then creates a plain &[f32].
        self.pcm_window.make_contiguous();
        let pcm: &[f32] = self.pcm_window.as_slices().0;
        if pcm.is_empty() || self.config.sample_rate == 0 {
            let signal_quality = measure_signal(pcm, self.config.sample_rate);
            // Пустой вход не обновляет prev_lock_state.
            return empty_result(LockState::Searching, signal_quality, 0.0, self.config);
        }

        // ─────────────────────────────────────────────────────────────────
        // Tempo discontinuity detector (v2) + fast re-lock (v1 дренаж)
        //
        // Шаг 1 — детектируем сдвиг по хвостовому срезу onset_history.
        //   Хвост (последние RELOCK_WINDOW_SECS) накапливает новый темп в
        //   первую очередь; топ-кандидат там меняется через ~1–2 с.
        //
        // Шаг 2 — накапливаем счётчик подряд идущих кадров со сдвигом.
        //   При >= RELOCK_CONFIRM_FRAMES активируем fast re-lock.
        //
        // Шаг 3 (v1 дренаж, `adaptive_window == false`) — физически
        //   обрезаем onset_history до RELOCK_WINDOW_SECS.
        //
        // Шаг 4 (v2 tempo jump, `adaptive_window == true`) — если сдвиг
        //   >= tempo_jump_threshold BPM, это «прыжок», не джиттер:
        //   - сбрасываем bpm_history (медианный буфер кандидатов)
        //   - выставляем force_next_searching = true
        //   Adaptive-window срез (п. ниже) уже даёт чистый горизонт.
        //
        // Anti-fake: любая операция работает только с реальными onset-данными.
        // ─────────────────────────────────────────────────────────────────
        if self.hop_sec > 0.0 {
            let relock_frames = (RELOCK_WINDOW_SECS / self.hop_sec).round() as usize;
            let tail_start = self.onset_history.len().saturating_sub(relock_frames);
            let raw_snapshot: Vec<f32> = self.onset_history
                .iter()
                .skip(tail_start)
                .copied()
                .collect();
            let snap_envelope = finalize_envelope(raw_snapshot);
            let snap_peaks = if !snap_envelope.is_empty() {
                tempo_autocorrelation(
                    &snap_envelope,
                    self.hop_sec,
                    self.config.broad_bpm_min,
                    self.config.broad_bpm_max,
                )
            } else {
                Vec::new()
            };
            let current_top_bpm = snap_peaks.first().map(|p| p.bpm);

            let shift_detected = match (self.last_stable_bpm, current_top_bpm) {
                (Some(last), Some(cur)) => {
                    let was_or_is_not_stable = self.prev_lock_state.is_some();
                    // Нормализуем cur относительно last: cur, cur*2, cur/2.
                    // Это предотвращает ложный детект от half/double гармоники.
                    let diff_direct = (cur - last).abs();
                    let diff_double = (cur * 2.0 - last).abs();
                    let diff_half = (cur / 2.0 - last).abs();
                    let min_diff = diff_direct.min(diff_double).min(diff_half);
                    was_or_is_not_stable && min_diff > RELOCK_BPM_SHIFT_THRESHOLD
                }
                _ => false,
            };

            if shift_detected {
                self.tempo_shift_counter += 1;
            } else {
                self.tempo_shift_counter = 0;
            }

            if self.tempo_shift_counter >= RELOCK_CONFIRM_FRAMES {
                if !self.config.adaptive_window {
                    // v1 дренаж: физически обрезаем onset_history.
                    if self.onset_history.len() > relock_frames {
                        let keep_from = self.onset_history.len() - relock_frames;
                        self.onset_history.drain(0..keep_from);
                    }
                    // Сбросить счётчик после усечения.
                    self.tempo_shift_counter = 0;
                } else {
                    // v2 tempo jump detector: если расхождение >= tempo_jump_threshold,
                    // это не джиттер — принудительно обнуляем состояние захвата.
                    let jump_detected = match (self.last_stable_bpm, current_top_bpm) {
                        (Some(last), Some(cur)) => {
                            let diff_direct = (cur - last).abs();
                            let diff_double = (cur * 2.0 - last).abs();
                            let diff_half = (cur / 2.0 - last).abs();
                            let min_diff = diff_direct.min(diff_double).min(diff_half);
                            min_diff > self.config.tempo_jump_threshold
                        }
                        _ => false,
                    };
                    if jump_detected {
                        // Темп резко сменился — сбрасываем медианный буфер,
                        // форсируем SEARCHING на следующем кадре.
                        self.bpm_history.clear();
                        self.force_next_searching = true;
                    }
                    // В v2 не дренируем onset_history физически;
                    // вместо этого adaptive_window-срез (ниже) берёт только хвост.
                    // Сбрасываем счётчик, чтобы не срабатывать каждый кадр.
                    self.tempo_shift_counter = 0;
                }
            }
        }

        // ─────────────────────────────────────────────────────────────────
        // Adaptive-window срез onset_history для анализа (v2).
        //
        // При `config.adaptive_window == true` выбираем эффективную длину
        // хвоста по prev_lock_state (состоянию предыдущего кадра):
        //   STABLE                  → полная история (без изменений)
        //   LOCKING                 → min(полная, ADAPTIVE_WINDOW_LOCKING_SECS)
        //   SEARCHING / UNSTABLE    → min(полная, ADAPTIVE_WINDOW_SEARCHING_SECS)
        //   None (start / after reset) → полная история
        //
        // Важно: onset_history не модифицируется — берётся только срез
        // (`tail`). Это исключает realloc и сохраняет историю для возврата
        // к STABLE после кратковременного UNSTABLE.
        // ─────────────────────────────────────────────────────────────────
        let raw_envelope: Vec<f32> = if self.config.adaptive_window && self.hop_sec > 0.0 {
            let effective_secs: Option<f32> = if !self.has_ever_been_stable {
                // Первый захват: ни разу не достигали STABLE.
                // Используем полную историю — 8–12 с даёт ~25–50 ударов для
                // надёжного пика автокорреляции и уверенности ≥ 0.70.
                // Адаптивное усечение в 2 с при SEARCHING сломало бы первый
                // захват: только 5–8 ударов → слабый пик → confidence < 0.70.
                None
            } else {
                // Повторный захват после смены трека: адаптивное окно
                // ограничивает анализ свежими онсетами нового темпа.
                match self.prev_lock_state {
                    Some(LockState::Stable) | None => None,
                    Some(LockState::Locking) => Some(ADAPTIVE_WINDOW_LOCKING_SECS),
                    Some(_) => Some(ADAPTIVE_WINDOW_SEARCHING_SECS),
                }
            };
            if let Some(secs) = effective_secs {
                let tail_frames = (secs / self.hop_sec).round() as usize;
                let tail_start = self.onset_history.len().saturating_sub(tail_frames);
                self.onset_history.iter().skip(tail_start).copied().collect()
            } else {
                self.onset_history.iter().copied().collect()
            }
        } else {
            self.onset_history.iter().copied().collect()
        };

        let envelope = finalize_envelope(raw_envelope);

        // Применяем force_next_searching: если флаг выставлен, форсируем
        // SEARCHING вместо UNSTABLE на этом кадре. Флаг сбрасывается здесь же.
        let force_searching = self.force_next_searching;
        if force_searching {
            self.force_next_searching = false;
        }

        let mut result = analyze_from_envelope(
            pcm,
            self.config.sample_rate,
            &envelope,
            self.hop_sec,
            self.config,
            self.prev_lock_state,
        );

        // Применяем форсированное состояние: если это «прыжок темпа», делаем
        // SEARCHING вместо любого не-критического состояния. CLIPPED_MIC и
        // BREAKDOWN не трогаем — они сигнализируют о проблеме входного сигнала,
        // а не о смене темпа; их пробрасываем немедленно без задержки.
        //
        // STABLE включён намеренно: если analyze_from_envelope вернул STABLE в
        // тот же кадр где был детектирован tempo jump (onset-история ещё содержит
        // смешанные данные двух треков), пропускать STABLE опасно — он обновит
        // last_stable_bpm переходным BPM. Форсируем SEARCHING, чтобы движок
        // начал чистый захват с нуля.
        if force_searching
            && matches!(
                result.lock_state,
                LockState::Unstable
                    | LockState::Locking
                    | LockState::NoiseOnly
                    | LockState::Stable
            )
        {
            result.lock_state = LockState::Searching;
            result.primary_bpm = None;
            // Сбросить якорный BPM, чтобы jump-детектор не продолжал
            // срабатывать на каждом последующем кадре (пока last_stable_bpm
            // содержит старое значение, а новый кандидат ≠ last_stable_bpm —
            // детектор переводил бы force_next_searching в true бесконечно).
            // После сброса нормальная прогрессия SEARCHING→LOCKING→STABLE
            // обновит last_stable_bpm при первом новом STABLE.
            self.last_stable_bpm = None;
        }

        // BPM candidate history — медиана N=BPM_HISTORY_N значений в STABLE.
        // Снижает остаточный джиттер после параболической интерполяции без
        // заметной задержки смены темпа: буфер очищается на первом не-STABLE
        // кадре, поэтому новый захват начинается с нуля.
        if result.lock_state == LockState::Stable {
            self.has_ever_been_stable = true;
            if let Some(bpm) = result.primary_bpm {
                self.bpm_history.push_back(bpm);
                while self.bpm_history.len() > BPM_HISTORY_N {
                    self.bpm_history.pop_front();
                }
                let mut sorted: Vec<f32> = self.bpm_history.iter().copied().collect();
                sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
                result.primary_bpm = Some(sorted[sorted.len() / 2]);
            }
            // Обновляем last_stable_bpm при каждом STABLE-кадре,
            // сбрасываем счётчик сдвига.
            self.last_stable_bpm = result.primary_bpm;
            self.tempo_shift_counter = 0;
        } else {
            self.bpm_history.clear();
        }

        // Запомнить состояние для следующего вызова.
        self.prev_lock_state = Some(result.lock_state);
        result
    }

    pub fn reset(&mut self) {
        self.observed_samples = 0;
        self.pcm_window.clear();
        self.pcm_pending.clear();
        self.onset_history.clear();
        self.prev_frame_rms = None;
        self.prev_lock_state = None;
        self.bpm_history.clear();
        self.last_stable_bpm = None;
        self.tempo_shift_counter = 0;
        self.force_next_searching = false;
        self.has_ever_been_stable = false;
    }

    fn observed_seconds(&self) -> f32 {
        if self.config.sample_rate == 0 {
            0.0
        } else {
            self.observed_samples as f32 / self.config.sample_rate as f32
        }
    }
}

fn frame_geometry(sample_rate: u32) -> (usize, usize) {
    if sample_rate == 0 {
        return (1, 1);
    }
    let hop_size = ((sample_rate as f32 * 0.0025) as usize).max(1);
    let frame_size = hop_size.max((sample_rate as f32 * 0.010) as usize);
    (hop_size, frame_size)
}

fn frame_rms(frame: &[f32]) -> f32 {
    if frame.is_empty() {
        return 0.0;
    }
    (frame
        .iter()
        .map(|sample| {
            let value = *sample as f64;
            value * value
        })
        .sum::<f64>()
        / frame.len() as f64)
        .sqrt() as f32
}

/// Применить ту же постобработку, что и `onset_envelope` (медианный пол +
/// пиковая нормализация), к предварительно вычисленному ряду flux.
fn finalize_envelope(mut flux: Vec<f32>) -> Vec<f32> {
    if flux.len() < 4 {
        return Vec::new();
    }
    let floor = median(&flux);
    for value in &mut flux {
        *value = (*value - floor).max(0.0);
    }
    let peak = flux.iter().copied().fold(0.0_f32, f32::max);
    if peak > 0.0 {
        for value in &mut flux {
            *value /= peak;
        }
    }
    flux
}

impl Default for DspEngine {
    fn default() -> Self {
        Self::new(DspConfig::default())
    }
}

#[derive(Debug, Clone, Copy)]
struct RawPeak {
    bpm: f32,
    score: f32,
}

pub fn analyze_pcm(samples: &[f32], sample_rate: u32, config: DspConfig) -> DspResult {
    let signal_quality = measure_signal(samples, sample_rate);
    let duration_sec = if sample_rate == 0 {
        0.0
    } else {
        samples.len() as f32 / sample_rate as f32
    };

    if samples.is_empty() || sample_rate == 0 || signal_quality.silence {
        return empty_result(LockState::Searching, signal_quality, duration_sec, config);
    }

    let (envelope, hop_sec) = onset_envelope(samples, sample_rate);
    // Батч-путь: нет скользящей истории → передаём None, сглаживание не применяется.
    analyze_from_envelope(samples, sample_rate, &envelope, hop_sec, config, None)
}

/// Общий пост-онсетный пайплайн, используемый и офлайн-точкой входа `analyze_pcm`,
/// и потоковой точкой входа `DspEngine::analyze`. Принимает PCM-окно,
/// финализированную огибающую онсетов и соответствующий `hop_sec`,
/// возвращает `DspResult` с полным скорингом, нормализацией кандидатов
/// и классификацией состояния захвата.
///
/// `prev_lock_state` — состояние предыдущего вызова анализа (только в режиме
/// стриминга; `None` в батч-режиме). Используется для условного сглаживания
/// огибающей онсетов при шумном клубном входе: см. `smooth_onset_envelope`.
fn analyze_from_envelope(
    samples: &[f32],
    sample_rate: u32,
    envelope: &[f32],
    hop_sec: f32,
    config: DspConfig,
    prev_lock_state: Option<LockState>,
) -> DspResult {
    let mut signal_quality = measure_signal(samples, sample_rate);
    let duration_sec = if sample_rate == 0 {
        0.0
    } else {
        samples.len() as f32 / sample_rate as f32
    };
    let mut timing = DspTiming {
        analysis_time_sec: round_3(duration_sec),
        window_time_sec: round_3(duration_sec),
        hop_time_sec: if hop_sec > 0.0 { hop_sec } else { 0.0025 },
        first_lock_time_sec: None,
    };

    if samples.is_empty() || sample_rate == 0 || signal_quality.silence {
        return empty_result(LockState::Searching, signal_quality, duration_sec, config);
    }
    if envelope.is_empty() || envelope.iter().copied().fold(0.0, f32::max) <= 0.0 {
        return empty_result(LockState::NoiseOnly, signal_quality, duration_sec, config);
    }

    if tail_onset_breakdown(envelope, hop_sec) {
        signal_quality.breakdown_likely = true;
    }

    // Адаптивное сглаживание огибающей онсетов для шумного клубного микрофона.
    //
    // Применяется только при одновременном выполнении двух условий:
    //
    // 1. Предыдущий вызов `analyze()` дал LOCKING или STABLE — в скользящем
    //    окне есть доказательство консистентного темпа. Без этой истории
    //    сглаживание может создать ложную периодичность в чистом шуме или
    //    хаотичном сигнале (регрессия `unstable_club_simulation`).
    //
    // 2. Текущий шумовой уровень — High (не NoiseOnly). High означает
    //    «музыкальный сигнал с высоким шумом»; NoiseOnly означает «шум
    //    без структуры» — там сглаживать нечего.
    //
    // 3-точечная MA убирает широкополосные шумовые пики между kick-ударами,
    //    не смещая позиции транзиентов (автокорреляция смотрит на лаги ≥130 мс).
    //    Результат: более чистый пик автокорреляции → выше уверенность →
    //    движок быстрее достигает и удерживает STABLE при реальном клубном входе.
    //
    // Батч-путь (`analyze_pcm`) всегда передаёт `prev_lock_state = None`,
    //    поэтому сглаживание на нём никогда не применяется → все batch-тесты
    //    в `offline_contract.rs` остаются без изменений.
    let smoothed_envelope_storage: Vec<f32>;
    let effective_envelope: &[f32] = {
        let has_tempo_history = matches!(
            prev_lock_state,
            Some(LockState::Locking | LockState::Stable)
        );
        let is_noisy_not_noise_only = signal_quality.noise_level == NoiseLevel::High;
        if has_tempo_history && is_noisy_not_noise_only {
            smoothed_envelope_storage = smooth_onset_envelope(envelope);
            &smoothed_envelope_storage
        } else {
            envelope
        }
    };

    let raw_peaks = tempo_autocorrelation(
        effective_envelope,
        hop_sec,
        config.broad_bpm_min,
        config.broad_bpm_max,
    );
    let mut candidates = build_candidates(&raw_peaks, config);
    candidates = dedupe_candidates(candidates);
    candidates = mark_primary_candidate(candidates, config);
    let signal_factor = signal_factor(&signal_quality);
    candidates = apply_signal_quality_factor(candidates, signal_factor);

    let onset_strength = envelope.iter().sum::<f32>() / envelope.len() as f32;
    let prominence = peak_prominence(&raw_peaks);
    let harmonic_ambiguity = harmonic_ambiguity(&candidates);
    let periodicity = raw_peaks.first().map(|peak| peak.score).unwrap_or(0.0);

    if candidates.is_empty() {
        return empty_result(LockState::NoiseOnly, signal_quality, duration_sec, config);
    }

    let primary = candidates[0].clone();
    let duration_factor = (duration_sec / 6.0).clamp(0.0, 1.0);
    let clarity_factor = ((periodicity - 0.08) / 0.42).clamp(0.0, 1.0);
    let prominence_factor = (prominence / 0.45).clamp(0.0, 1.0);
    let ambiguity_factor = 1.0 - (0.16 * harmonic_ambiguity);
    let mut confidence = primary.score
        * (0.38
            + 0.22 * signal_factor
            + 0.18 * duration_factor
            + 0.12 * clarity_factor
            + 0.10 * prominence_factor)
        * ambiguity_factor;
    confidence = confidence.clamp(0.0, 1.0);

    let mut lock_state = LockState::Locking;
    let mut primary_bpm = Some(round_1(primary.bpm));
    let severe_clipping = severe_clipping(&signal_quality);

    if severe_clipping {
        lock_state = LockState::ClippedMic;
        confidence = confidence.min(0.34);
        primary_bpm = None;
    } else if signal_quality.clipping {
        confidence = confidence.min(0.69);
        if matches!(lock_state, LockState::Stable) {
            lock_state = LockState::Locking;
        }
    } else if signal_quality.breakdown_likely {
        lock_state = LockState::Breakdown;
        confidence = confidence.min(0.42);
        primary_bpm = None;
    } else if periodicity < 0.24 || prominence < 0.10 || onset_strength < 0.002 {
        lock_state = LockState::NoiseOnly;
        confidence = confidence.min(0.28);
        primary_bpm = None;
    } else if confidence >= 0.70 && duration_sec >= config.lock_min_seconds {
        lock_state = LockState::Stable;
        timing.first_lock_time_sec = Some(config.lock_min_seconds.min(round_3(duration_sec)));
    } else if confidence < 0.45 {
        lock_state = LockState::Unstable;
    }

    candidates.truncate(10);

    // ── Сборка DspDebug ───────────────────────────────────────────────────────
    let onset_rate_hz = if duration_sec > 0.0 {
        round_3(raw_peaks.len() as f32 / duration_sec)
    } else {
        0.0
    };
    let mut warnings: Vec<String> = Vec::new();
    if signal_quality.clipping {
        warnings.push("clipping".to_string());
    }
    if signal_quality.breakdown_likely {
        warnings.push("breakdown_likely".to_string());
    }
    if harmonic_ambiguity > 0.5 {
        warnings.push(format!("harmonic_ambiguity={:.2}", harmonic_ambiguity));
    }
    let primary_stability = candidates.first().map(|c| c.stability_score).unwrap_or(0.0);
    let debug = DspDebug {
        onset_rate_hz,
        onset_strength: round_6(onset_strength),
        tempo_peak_prominence: round_6(prominence),
        harmonic_ambiguity: round_6(harmonic_ambiguity),
        stability_score: round_6(primary_stability),
        warnings,
    };

    DspResult {
        primary_bpm,
        confidence: round_3(confidence),
        lock_state,
        signal_quality,
        candidates,
        timing,
        genre_preset: GenrePreset::default(),
        key_result: None,
        energy_result: None,
        debug,
    }
}

pub fn analyze_candidates(
    raw_candidates: &[(f32, f32)],
    analysis_time_sec: f32,
    config: DspConfig,
) -> DspResult {
    let raw_peaks: Vec<RawPeak> = raw_candidates
        .iter()
        .filter_map(|&(bpm, score)| {
            if bpm.is_finite() && score.is_finite() && bpm > 0.0 {
                Some(RawPeak {
                    bpm,
                    score: score.clamp(0.0, 1.0),
                })
            } else {
                None
            }
        })
        .collect();
    let mut candidates = build_candidates(&raw_peaks, config);
    candidates = dedupe_candidates(candidates);
    candidates = mark_primary_candidate(candidates, config);
    let signal_quality = default_signal_quality(raw_candidates.is_empty());

    if raw_candidates.is_empty() {
        return empty_result(LockState::Searching, signal_quality, analysis_time_sec, config);
    }

    let primary = candidates.first().cloned();
    let confidence = primary.as_ref().map(|item| item.score).unwrap_or(0.0).clamp(0.0, 1.0);
    let lock_state = if confidence >= 0.70 && analysis_time_sec >= config.stable_min_seconds {
        LockState::Stable
    } else if confidence >= 0.45 && analysis_time_sec >= config.lock_min_seconds {
        LockState::Locking
    } else {
        LockState::Unstable
    };
    let primary_bpm = if matches!(lock_state, LockState::Stable | LockState::Locking) {
        primary.as_ref().map(|item| round_3(item.bpm))
    } else {
        None
    };

    DspResult {
        primary_bpm,
        confidence: round_3(confidence),
        lock_state,
        signal_quality,
        candidates,
        timing: DspTiming {
            analysis_time_sec: round_3(analysis_time_sec),
            window_time_sec: config.analysis_window_seconds,
            hop_time_sec: 0.0,
            first_lock_time_sec: primary_bpm.map(|_| analysis_time_sec.min(config.lock_min_seconds)),
        },
        genre_preset: GenrePreset::default(),
        key_result: None,
        energy_result: None,
        debug: DspDebug {
            onset_rate_hz: 0.0,
            onset_strength: 0.0,
            tempo_peak_prominence: 0.0,
            harmonic_ambiguity: 0.0,
            stability_score: 0.0,
            warnings: Vec::new(),
        },
    }
}

pub fn normalize_candidates(raw_candidates: &[(f32, f32)], config: DspConfig) -> Vec<TempoCandidate> {
    let raw_peaks: Vec<RawPeak> = raw_candidates
        .iter()
        .filter_map(|&(bpm, score)| {
            if bpm.is_finite() && score.is_finite() && bpm > 0.0 {
                Some(RawPeak {
                    bpm,
                    score: score.clamp(0.0, 1.0),
                })
            } else {
                None
            }
        })
        .collect();
    mark_primary_candidate(dedupe_candidates(build_candidates(&raw_peaks, config)), config)
}

fn build_candidates(raw_peaks: &[RawPeak], config: DspConfig) -> Vec<TempoCandidate> {
    let mut candidates = Vec::new();
    for peak in raw_peaks {
        let raw_score = peak.score.clamp(0.0, 1.0);
        candidates.push(candidate(
            peak.bpm,
            TempoRelation::Raw,
            raw_score,
            raw_score,
            None,
            config,
        ));

        if peak.bpm < 130.0 {
            candidates.push(candidate(
                peak.bpm * 2.0,
                TempoRelation::NormalizedFromHalf,
                (raw_score * 0.98).clamp(0.0, 1.0),
                raw_score,
                Some(peak.bpm),
                config,
            ));
        }

        if peak.bpm > 260.0 {
            candidates.push(candidate(
                peak.bpm / 2.0,
                TempoRelation::NormalizedFromDouble,
                (raw_score * 0.98).clamp(0.0, 1.0),
                raw_score,
                Some(peak.bpm),
                config,
            ));
        }
    }

    candidates.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    if let Some(primary) = candidates.first().cloned() {
        candidates.push(candidate(
            primary.bpm / 2.0,
            TempoRelation::HalfTime,
            primary.raw_score * 0.62,
            primary.raw_score,
            Some(primary.bpm),
            config,
        ));
        candidates.push(candidate(
            primary.bpm * 2.0,
            TempoRelation::DoubleTime,
            primary.raw_score * 0.48,
            primary.raw_score,
            Some(primary.bpm),
            config,
        ));
    }

    candidates
}

fn dedupe_candidates(mut candidates: Vec<TempoCandidate>) -> Vec<TempoCandidate> {
    candidates.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let mut deduped = Vec::new();
    let mut seen: Vec<(i32, TempoRelation)> = Vec::new();
    for candidate in candidates {
        let key = (candidate.bpm.round() as i32, candidate.relation);
        if seen.contains(&key) {
            continue;
        }
        seen.push(key);
        deduped.push(candidate);
    }
    deduped
}

fn mark_primary_candidate(candidates: Vec<TempoCandidate>, config: DspConfig) -> Vec<TempoCandidate> {
    let Some(primary) = candidates.first() else {
        return Vec::new();
    };
    let mut main = candidate(
        primary.bpm,
        TempoRelation::Main,
        primary.score,
        primary.raw_score,
        primary.source_bpm,
        config,
    );
    main.score = primary.score;
    main.raw_score = primary.raw_score;
    main.stability_score = primary.stability_score;
    main.range_score = primary.range_score;
    main.confidence_factors = primary.confidence_factors.clone();

    let mut marked = Vec::with_capacity(candidates.len() + 1);
    marked.push(main);
    marked.extend(candidates);
    marked
}

fn apply_signal_quality_factor(
    mut candidates: Vec<TempoCandidate>,
    signal_factor_value: f32,
) -> Vec<TempoCandidate> {
    for candidate in &mut candidates {
        candidate.confidence_factors.signal_quality = round_6(signal_factor_value);
    }
    candidates
}

fn candidate(
    bpm: f32,
    relation: TempoRelation,
    evidence_score: f32,
    raw_score: f32,
    source_bpm: Option<f32>,
    config: DspConfig,
) -> TempoCandidate {
    let range_score = range_score(bpm, config);
    let score = (evidence_score * (0.58 + 0.42 * range_score)).clamp(0.0, 1.0);
    TempoCandidate {
        bpm: round_3(bpm),
        relation,
        score: round_6(score),
        raw_score: round_6(raw_score),
        stability_score: round_6(raw_score.clamp(0.0, 1.0)),
        range_score: round_6(range_score),
        source_bpm: source_bpm.map(round_3),
        confidence_factors: ConfidenceFactors {
            onset_clarity: round_6(raw_score),
            peak_prominence: round_6(evidence_score),
            harmonic_support: if source_bpm.is_some() { 0.82 } else { 0.68 },
            recent_stability: round_6(raw_score),
            signal_quality: 1.0,
        },
    }
}

fn range_score(bpm: f32, config: DspConfig) -> f32 {
    if (config.target_bpm_min..=config.target_bpm_max).contains(&bpm) {
        return 1.0;
    }
    if (130.0..config.target_bpm_min).contains(&bpm) {
        return 0.45 + 0.55 * ((bpm - 130.0) / (config.target_bpm_min - 130.0));
    }
    if bpm > config.target_bpm_max && bpm <= 260.0 {
        return 1.0 - 0.45 * ((bpm - config.target_bpm_max) / (260.0 - config.target_bpm_max));
    }
    if (config.broad_bpm_min..130.0).contains(&bpm)
        || (260.0..=config.broad_bpm_max).contains(&bpm)
    {
        return 0.26;
    }
    0.1
}

fn measure_signal(samples: &[f32], sample_rate: u32) -> SignalQuality {
    let count = samples.len();
    let peak = samples
        .iter()
        .map(|sample| sample.abs())
        .fold(0.0_f32, f32::max);
    let rms = if count == 0 {
        0.0
    } else {
        (samples
            .iter()
            .map(|sample| {
                let value = *sample as f64;
                value * value
            })
            .sum::<f64>()
            / count as f64)
            .sqrt() as f32
    };
    let full_scale_ratio = if count == 0 {
        0.0
    } else {
        samples
            .iter()
            .filter(|sample| (**sample).abs() >= 0.985)
            .count() as f32
            / count as f32
    };
    let flat_top_sample_ratio = if count == 0 {
        0.0
    } else {
        samples
            .iter()
            .filter(|sample| peak > 0.7 && (**sample).abs() >= peak * 0.995)
            .count() as f32
            / count as f32
    };
    let flat_top_frame_ratio = flat_top_frame_ratio(samples, sample_rate, peak);
    let clipping = full_scale_ratio > 0.01 || flat_top_sample_ratio > 0.015;
    let clipped_frame_ratio = if full_scale_ratio > 0.01 {
        full_scale_ratio.max(flat_top_frame_ratio)
    } else if flat_top_sample_ratio > 0.015 {
        flat_top_sample_ratio.max(flat_top_frame_ratio)
    } else {
        full_scale_ratio.max(flat_top_sample_ratio)
    };
    let silence = rms < 0.0002 || peak < 0.001;
    let tail_samples = (sample_rate as usize).saturating_mul(3);
    let tail_start = count.saturating_sub(tail_samples);
    let tail = &samples[tail_start..];
    let tail_rms = if tail.is_empty() {
        0.0
    } else {
        (tail
            .iter()
            .map(|sample| {
                let value = *sample as f64;
                value * value
            })
            .sum::<f64>()
            / tail.len() as f64)
            .sqrt() as f32
    };
    let breakdown_likely =
        !silence && sample_rate > 0 && count >= sample_rate as usize * 6 && tail_rms < 0.004_f32.max(rms * 0.18);
    let crest_db = if rms > 0.0 && peak > 0.0 {
        Some(20.0 * (peak.max(1e-12) / rms).log10())
    } else {
        None
    };
    let noise_level = if silence {
        NoiseLevel::Low
    } else if (crest_db.is_some_and(|value| value < 8.0) && rms > 0.03) || (rms > 0.14 && peak < 0.6) {
        NoiseLevel::NoiseOnly
    } else if crest_db.is_some_and(|value| value < 10.0) {
        NoiseLevel::High
    } else if rms < 0.035 {
        NoiseLevel::Low
    } else if rms < 0.18 {
        NoiseLevel::Medium
    } else {
        NoiseLevel::High
    };

    SignalQuality {
        input_level_dbfs: dbfs(rms),
        peak_dbfs: dbfs(peak),
        clipping,
        clipped_frame_ratio: round_6(clipped_frame_ratio),
        noise_level,
        snr_estimate_db: if silence { None } else { estimate_snr_db(samples, sample_rate) },
        silence,
        breakdown_likely,
    }
}

fn flat_top_frame_ratio(samples: &[f32], sample_rate: u32, peak: f32) -> f32 {
    if samples.is_empty() || sample_rate == 0 || peak < 0.7 {
        return 0.0;
    }
    let frame_size = ((sample_rate as f32 * 0.010) as usize).max(1);
    let mut frames = 0;
    let mut clipped_frames = 0;
    for frame in samples.chunks(frame_size) {
        if frame.is_empty() {
            continue;
        }
        frames += 1;
        if frame.iter().any(|sample| sample.abs() >= peak * 0.995) {
            clipped_frames += 1;
        }
    }
    if frames == 0 {
        0.0
    } else {
        clipped_frames as f32 / frames as f32
    }
}

fn onset_envelope(samples: &[f32], sample_rate: u32) -> (Vec<f32>, f32) {
    if sample_rate == 0 {
        return (Vec::new(), 0.0);
    }
    let hop_size = ((sample_rate as f32 * 0.0025) as usize).max(1);
    let frame_size = hop_size.max((sample_rate as f32 * 0.010) as usize);
    let mut frame_rms = Vec::new();
    let mut start = 0;
    let end = samples.len().saturating_sub(frame_size);
    while start < end {
        let frame = &samples[start..start + frame_size];
        let rms = (frame
            .iter()
            .map(|sample| {
                let value = *sample as f64;
                value * value
            })
            .sum::<f64>()
            / frame.len() as f64)
            .sqrt() as f32;
        frame_rms.push(rms);
        start += hop_size;
    }

    if frame_rms.len() < 4 {
        return (Vec::new(), hop_size as f32 / sample_rate as f32);
    }

    let mut flux = Vec::with_capacity(frame_rms.len());
    flux.push(0.0);
    for idx in 1..frame_rms.len() {
        flux.push((frame_rms[idx] - frame_rms[idx - 1]).max(0.0));
    }

    let floor = median(&flux);
    let mut envelope: Vec<f32> = flux.into_iter().map(|value| (value - floor).max(0.0)).collect();
    let peak = envelope.iter().copied().fold(0.0_f32, f32::max);
    if peak > 0.0 {
        for value in &mut envelope {
            *value /= peak;
        }
    }
    (envelope, hop_size as f32 / sample_rate as f32)
}

fn tail_onset_breakdown(envelope: &[f32], hop_sec: f32) -> bool {
    if hop_sec <= 0.0 {
        return false;
    }
    let tail_frames = ((3.0 / hop_sec) as usize).max(1);
    if envelope.len() < tail_frames * 2 {
        return false;
    }
    let split = envelope.len() - tail_frames;
    let history = &envelope[..split];
    let tail = &envelope[split..];
    if history.is_empty() {
        return false;
    }
    let history_mean = history.iter().sum::<f32>() / history.len() as f32;
    let tail_mean = tail.iter().sum::<f32>() / tail.len() as f32;
    let history_peak = history.iter().copied().fold(0.0_f32, f32::max);
    let tail_peak = tail.iter().copied().fold(0.0_f32, f32::max);
    history_peak > 0.45 && tail_peak < 0.20 && tail_mean < 0.003_f32.max(history_mean * 0.95)
}

/// Минимальный знаменатель параболической коррекции. При значениях ниже
/// этого порога вершина считается «плоской» и используется целочисленный лаг.
const PARABOLIC_DENOM_MIN: f64 = 1e-6;

fn tempo_autocorrelation(envelope: &[f32], hop_sec: f32, min_bpm: f32, max_bpm: f32) -> Vec<RawPeak> {
    if envelope.len() < 4 || hop_sec <= 0.0 || min_bpm <= 0.0 || max_bpm <= 0.0 {
        return Vec::new();
    }
    let min_lag = ((60.0 / max_bpm / hop_sec).floor() as usize).max(1);
    let max_lag = (envelope.len() - 2).min((60.0 / min_bpm / hop_sec).ceil() as usize);
    if max_lag <= min_lag {
        return Vec::new();
    }

    let mut scores = Vec::with_capacity(max_lag - min_lag + 1);
    for lag in min_lag..=max_lag {
        let mut current_energy = 0.0_f64;
        let mut shifted_energy = 0.0_f64;
        let mut numerator = 0.0_f64;
        for idx in lag..envelope.len() {
            let current = envelope[idx] as f64;
            let shifted = envelope[idx - lag] as f64;
            numerator += current * shifted;
            current_energy += current * current;
            shifted_energy += shifted * shifted;
        }
        let denom = (current_energy * shifted_energy).sqrt();
        let score = if denom > 0.0 { numerator / denom } else { 0.0 };
        scores.push((lag, score as f32));
    }

    let mut peaks = Vec::new();
    for idx in 1..scores.len().saturating_sub(1) {
        let (lag, score) = scores[idx];
        if score >= scores[idx - 1].1 && score >= scores[idx + 1].1 {
            // Параболическая интерполяция пика: снижает ошибку дискретизации
            // с ±1.6 BPM (целый лаг) до < 0.2 BPM (дробный лаг).
            //
            // k_frac = k - (A[k+1] - A[k-1]) / (2 * (2*A[k] - A[k+1] - A[k-1]))
            //
            // idx гарантированно interior (1..len-1), поэтому scores[idx-1]
            // и scores[idx+1] всегда существуют.
            let a = scores[idx - 1].1 as f64;
            let b = scores[idx].1 as f64;
            let c = scores[idx + 1].1 as f64;
            let parabolic_denom = 2.0 * (2.0 * b - a - c);
            let frac_lag: f64 = if parabolic_denom.abs() > PARABOLIC_DENOM_MIN {
                // x* = k + (C - A) / (2*(2*B - A - C))
                // Знак «+»: пик сдвигается в сторону более высокого соседа.
                let candidate = lag as f64 + (c - a) / parabolic_denom;
                // Fallback если дробный лаг выходит за допустимый диапазон BPM.
                let interp_bpm = 60.0 / (candidate as f32 * hop_sec);
                if candidate > 0.0 && interp_bpm >= min_bpm && interp_bpm <= max_bpm {
                    candidate
                } else {
                    lag as f64
                }
            } else {
                // Плоская вершина — интерполяция бессмысленна.
                lag as f64
            };
            peaks.push(RawPeak {
                bpm: 60.0 / (frac_lag as f32 * hop_sec),
                score,
            });
        }
    }
    peaks.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    peaks.truncate(16);
    peaks
}

fn peak_prominence(raw_peaks: &[RawPeak]) -> f32 {
    if raw_peaks.is_empty() {
        return 0.0;
    }
    let scores: Vec<f32> = raw_peaks.iter().map(|peak| peak.score).collect();
    (scores[0] - median(&scores)).clamp(0.0, 1.0)
}

fn harmonic_ambiguity(candidates: &[TempoCandidate]) -> f32 {
    if candidates.len() < 2 {
        return 0.0;
    }
    let primary = &candidates[0];
    if primary.bpm <= 0.0 {
        return 0.0;
    }
    for candidate in &candidates[1..] {
        let relative_distance = (candidate.bpm - primary.bpm).abs() / primary.bpm;
        if relative_distance > 0.015 {
            return (candidate.score / primary.score.max(0.0001)).clamp(0.0, 1.0);
        }
    }
    0.0
}

fn signal_factor(signal_quality: &SignalQuality) -> f32 {
    if signal_quality.silence || signal_quality.breakdown_likely {
        return 0.0;
    }
    if signal_quality.clipping && severe_clipping(signal_quality) {
        return 0.0;
    }
    if signal_quality.clipping {
        return 0.62;
    }

    // Если SNR-оценка доступна — используем её для более точного фактора.
    // Это позволяет правильно обработать «громкий, но чистый» сигнал
    // в отличие от «тихого, но шумного».
    if let Some(snr) = signal_quality.snr_estimate_db {
        return if snr >= 20.0 {
            1.0
        } else if snr >= 10.0 {
            0.72 + 0.28 * ((snr - 10.0) / 10.0)
        } else if snr >= 3.0 {
            0.45 + 0.27 * ((snr - 3.0) / 7.0)
        } else {
            0.28 // очень низкий SNR — близко к NOISE_ONLY
        };
    }

    // Фолбэк на noise_level, когда SNR-оценка недоступна.
    match signal_quality.noise_level {
        NoiseLevel::NoiseOnly => 0.28,
        NoiseLevel::High => 0.68,
        NoiseLevel::Medium => 0.92,
        _ => 1.0,
    }
}

fn severe_clipping(signal_quality: &SignalQuality) -> bool {
    signal_quality.clipped_frame_ratio >= 0.05
}

/// Оценивает SNR по перцентильному методу: шумовой уровень = 20-й перцентиль
/// RMS-кадров, уровень сигнала = 80-й перцентиль. Возвращает `None` при
/// тишине или когда кадров недостаточно для надёжной оценки.
///
/// 20-мс кадры выбраны как компромисс: достаточно длинные, чтобы усреднить
/// широкополосный шум, но короче типичного kick-транзиента (≈55 мс).
fn estimate_snr_db(samples: &[f32], sample_rate: u32) -> Option<f32> {
    if samples.is_empty() || sample_rate == 0 {
        return None;
    }
    let frame_len = ((sample_rate as f32 * 0.020) as usize)
        .max(64)
        .min(samples.len());
    let rms_frames: Vec<f32> = samples
        .chunks(frame_len)
        .filter(|frame| frame.len() >= frame_len / 2)
        .map(frame_rms)
        .collect();
    if rms_frames.len() < 6 {
        return None;
    }
    let mut sorted = rms_frames.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let noise_rms = sorted[sorted.len() / 5]; // 20-й перцентиль ≈ шумовой пол
    let signal_rms = sorted[sorted.len() * 4 / 5]; // 80-й перцентиль ≈ уровень сигнала
    if noise_rms < 1e-8 || signal_rms <= noise_rms {
        return None;
    }
    Some(round_3(20.0 * (signal_rms / noise_rms).log10()))
}

/// Лёгкое 3-точечное скользящее среднее для огибающей онсетов.
///
/// Применяется только потоковым движком (`DspEngine::analyze`) и только когда
/// `prev_lock_state == LOCKING|STABLE` и `noise_level == High` — чтобы убрать
/// широкополосные шумовые пики без создания ложной периодичности.
/// Граничные точки: среднее из двух ближайших соседей (без zero-padding).
fn smooth_onset_envelope(envelope: &[f32]) -> Vec<f32> {
    let n = envelope.len();
    if n < 3 {
        return envelope.to_vec();
    }
    let mut smoothed = Vec::with_capacity(n);
    smoothed.push((envelope[0] + envelope[1]) / 2.0);
    for i in 1..n - 1 {
        smoothed.push((envelope[i - 1] + envelope[i] + envelope[i + 1]) / 3.0);
    }
    smoothed.push((envelope[n - 2] + envelope[n - 1]) / 2.0);
    smoothed
}

fn resample_linear(samples: &[f32], source_rate: u32, target_rate: u32) -> Vec<f32> {
    if samples.is_empty() || source_rate == 0 || target_rate == 0 || source_rate == target_rate {
        return samples.to_vec();
    }
    let output_len = ((samples.len() as f64 * target_rate as f64) / source_rate as f64)
        .round()
        .max(1.0) as usize;
    let ratio = source_rate as f64 / target_rate as f64;
    let mut output = Vec::with_capacity(output_len);
    for idx in 0..output_len {
        let source_index = idx as f64 * ratio;
        let left = source_index.floor() as usize;
        let right = (left + 1).min(samples.len() - 1);
        let frac = (source_index - left as f64) as f32;
        output.push(samples[left] * (1.0 - frac) + samples[right] * frac);
    }
    output
}

fn default_signal_quality(empty: bool) -> SignalQuality {
    SignalQuality {
        input_level_dbfs: None,
        peak_dbfs: None,
        clipping: false,
        clipped_frame_ratio: 0.0,
        noise_level: if empty { NoiseLevel::Unknown } else { NoiseLevel::Medium },
        snr_estimate_db: None,
        silence: empty,
        breakdown_likely: false,
    }
}

fn empty_result(
    lock_state: LockState,
    signal_quality: SignalQuality,
    analysis_time_sec: f32,
    config: DspConfig,
) -> DspResult {
    DspResult {
        primary_bpm: None,
        confidence: 0.0,
        lock_state,
        signal_quality,
        candidates: Vec::new(),
        timing: DspTiming {
            analysis_time_sec,
            window_time_sec: config.analysis_window_seconds,
            hop_time_sec: 0.0,
            first_lock_time_sec: None,
        },
        genre_preset: GenrePreset::default(),
        key_result: None,
        energy_result: None,
        debug: DspDebug {
            onset_rate_hz: 0.0,
            onset_strength: 0.0,
            tempo_peak_prominence: 0.0,
            harmonic_ambiguity: 0.0,
            stability_score: 0.0,
            warnings: Vec::new(),
        },
    }
}

fn round_3(value: f32) -> f32 {
    (value * 1000.0).round() / 1000.0
}

fn round_1(value: f32) -> f32 {
    (value * 10.0).round() / 10.0
}

fn round_6(value: f32) -> f32 {
    (value * 1_000_000.0).round() / 1_000_000.0
}

fn dbfs(value: f32) -> Option<f32> {
    if value <= 0.0 {
        None
    } else {
        Some(round_3(20.0 * value.min(1.0).log10()))
    }
}

fn median(values: &[f32]) -> f32 {
    if values.is_empty() {
        return 0.0;
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(|left, right| {
        left.partial_cmp(right)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let middle = sorted.len() / 2;
    if sorted.len() % 2 == 0 {
        (sorted[middle - 1] + sorted[middle]) / 2.0
    } else {
        sorted[middle]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn half_time_candidate_is_preserved_and_normalized() {
        let result = analyze_candidates(&[(100.0, 0.9)], 12.0, DspConfig::default());

        assert_eq!(result.lock_state, LockState::Stable);
        assert_eq!(result.primary_bpm, Some(200.0));
        assert!(result
            .candidates
            .iter()
            .any(|candidate| candidate.bpm == 100.0 && candidate.relation == TempoRelation::Raw));
        assert!(result.candidates.iter().any(|candidate| {
            candidate.bpm == 200.0 && candidate.relation == TempoRelation::NormalizedFromHalf
        }));
    }

    #[test]
    fn double_time_candidate_is_preserved_and_normalized() {
        let result = analyze_candidates(&[(400.0, 0.9)], 12.0, DspConfig::default());

        assert_eq!(result.lock_state, LockState::Stable);
        assert_eq!(result.primary_bpm, Some(200.0));
        assert!(result
            .candidates
            .iter()
            .any(|candidate| candidate.bpm == 400.0 && candidate.relation == TempoRelation::Raw));
        assert!(result.candidates.iter().any(|candidate| {
            candidate.bpm == 200.0 && candidate.relation == TempoRelation::NormalizedFromDouble
        }));
    }

    #[test]
    fn empty_input_does_not_invent_a_bpm() {
        let result = analyze_candidates(&[], 0.0, DspConfig::default());

        assert_eq!(result.primary_bpm, None);
        assert_eq!(result.lock_state, LockState::Searching);
        assert!(result.signal_quality.silence);
    }
}
