//! Граница C ABI для мобильной интеграции.
//!
//! Мост владеет только хэндлами и приёмом сэмплов. Вычисление BPM остаётся в
//! `hitech_bpm_dsp`; Flutter не должен реализовывать параллельный детектор темпа.
//!
//! Состояние пересекает границу как JSON-кодированный `DspResult`, возвращаемый
//! `hitech_bpm_engine_analyze_json`. Вызывающая сторона обязана освободить
//! буфер через `hitech_bpm_string_free`. JSON предназначен для поллинга на
//! частоте UI (~10–30 Гц), не из аудио-потока — `push_samples` остаётся
//! лёгким по аллокациям; сериализация происходит только по запросу.

use std::ffi::CString;
use std::os::raw::c_char;

use hitech_bpm_dsp::{DspConfig, DspEngine};

#[repr(C)]
pub struct HitechBpmEngine {
    inner: DspEngine,
}

#[no_mangle]
pub extern "C" fn hitech_bpm_engine_new() -> *mut HitechBpmEngine {
    Box::into_raw(Box::new(HitechBpmEngine {
        inner: DspEngine::new(DspConfig::default()),
    }))
}

/// Создать движок с кастомным минимальным BPM для hitech-диапазона.
/// `min_bpm` зажимается в [80.0, 230.0]; не-finite значения заменяются на 155.0.
/// Используется для Free-tier (170) vs Pro-tier (155) гейтирования.
#[no_mangle]
pub extern "C" fn hitech_bpm_engine_new_with_min_bpm(min_bpm: f32) -> *mut HitechBpmEngine {
    let clamped = if min_bpm.is_finite() {
        min_bpm.clamp(80.0, 230.0)
    } else {
        155.0
    };
    let cfg = DspConfig {
        target_bpm_min: clamped,
        ..DspConfig::default()
    };
    Box::into_raw(Box::new(HitechBpmEngine {
        inner: DspEngine::new(cfg),
    }))
}

/// Создать движок с явным диапазоном `(min_bpm, max_bpm)`.
/// `min_bpm` зажимается в [80.0, 260.0]; `max_bpm` зажимается в [min+10.0, 300.0].
/// Не-finite значения заменяются дефолтами (155.0, 230.0).
/// Используется для Custom-пресета (Pro), где пользователь задаёт свой диапазон.
#[no_mangle]
pub extern "C" fn hitech_bpm_engine_new_with_range(
    min_bpm: f32,
    max_bpm: f32,
) -> *mut HitechBpmEngine {
    let min = if min_bpm.is_finite() {
        min_bpm.clamp(80.0, 260.0)
    } else {
        155.0
    };
    let max = if max_bpm.is_finite() {
        max_bpm.clamp(min + 10.0, 300.0)
    } else {
        230.0
    };
    let cfg = DspConfig {
        target_bpm_min: min,
        target_bpm_max: max,
        ..DspConfig::default()
    };
    Box::into_raw(Box::new(HitechBpmEngine {
        inner: DspEngine::new(cfg),
    }))
}

/// # Safety
/// `engine` must be a valid pointer returned by `hitech_bpm_engine_new`, or null.
/// After calling this function, `engine` is invalid and must not be used.
#[no_mangle]
pub unsafe extern "C" fn hitech_bpm_engine_free(engine: *mut HitechBpmEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

/// # Safety
/// `engine` must be a valid pointer returned by `hitech_bpm_engine_new`, or null.
#[no_mangle]
pub unsafe extern "C" fn hitech_bpm_engine_reset(engine: *mut HitechBpmEngine) {
    if let Some(engine) = engine.as_mut() {
        engine.inner.reset();
    }
}

/// # Safety
/// - `engine` must be a valid pointer returned by `hitech_bpm_engine_new`, or null.
/// - `samples` must point to a valid array of at least `len` f32 elements.
/// - The memory pointed to by `samples` must remain valid for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn hitech_bpm_engine_push_samples(
    engine: *mut HitechBpmEngine,
    samples: *const f32,
    len: usize,
    sample_rate: u32,
) -> bool {
    if engine.is_null() || samples.is_null() || len == 0 || sample_rate == 0 {
        return false;
    }
    let engine = &mut *engine;
    let samples = std::slice::from_raw_parts(samples, len);
    engine.inner.push_samples(samples, sample_rate);
    true
}

/// Сериализовать текущий скользящий `DspResult` как null-terminated JSON UTF-8
/// строку. Право собственности переходит к вызывающей стороне; освободить через
/// `hitech_bpm_string_free`. Возвращает null при невалидном хэндле или ошибке
/// сериализации (последнее должно быть недостижимо при типизированном контракте).
///
/// # Safety
/// `engine` must be a valid pointer returned by `hitech_bpm_engine_new`, or null.
#[no_mangle]
pub unsafe extern "C" fn hitech_bpm_engine_analyze_json(
    engine: *mut HitechBpmEngine,
) -> *mut c_char {
    // `as_mut` вместо `as_ref`: `DspEngine::analyze` теперь принимает `&mut self`,
    // чтобы сохранять `prev_lock_state` для адаптивного сглаживания огибающей.
    let Some(engine) = engine.as_mut() else {
        return std::ptr::null_mut();
    };
    let result = engine.inner.analyze();
    let Ok(json) = serde_json::to_string(&result) else {
        return std::ptr::null_mut();
    };
    let Ok(c_string) = CString::new(json) else {
        return std::ptr::null_mut();
    };
    c_string.into_raw()
}

/// Освободить буфер, ранее возвращённый `hitech_bpm_engine_analyze_json`.
/// Передача null-указателя — no-op. Передача любого другого указателя —
/// неопределённое поведение.
///
/// # Safety
/// `ptr` must be either null or a pointer returned by `hitech_bpm_engine_analyze_json`.
/// After calling this function, `ptr` is invalid and must not be used.
#[no_mangle]
pub unsafe extern "C" fn hitech_bpm_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}
