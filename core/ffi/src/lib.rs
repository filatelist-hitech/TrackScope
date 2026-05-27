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

#[no_mangle]
pub unsafe extern "C" fn hitech_bpm_engine_free(engine: *mut HitechBpmEngine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

#[no_mangle]
pub unsafe extern "C" fn hitech_bpm_engine_reset(engine: *mut HitechBpmEngine) {
    if let Some(engine) = engine.as_mut() {
        engine.inner.reset();
    }
}

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
#[no_mangle]
pub unsafe extern "C" fn hitech_bpm_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}
