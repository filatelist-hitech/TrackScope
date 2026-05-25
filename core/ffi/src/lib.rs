//! C ABI boundary for mobile integration.
//!
//! The bridge owns handles and sample ingress only. BPM calculation stays in
//! `hitech_bpm_dsp`; Flutter must not implement a parallel tempo detector.
//!
//! State crosses the boundary as a JSON-encoded `DspResult` returned by
//! `hitech_bpm_engine_analyze_json`. Callers must release the returned buffer
//! with `hitech_bpm_string_free`. JSON is intended for UI-rate polling
//! (~10-30 Hz), not for the audio thread — `push_samples` stays allocation-
//! light; serialization only happens when the consumer asks for state.

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

/// Serialize the current rolling `DspResult` as a null-terminated JSON UTF-8
/// string. Ownership transfers to the caller; release with
/// `hitech_bpm_string_free`. Returns null on invalid handle or serialization
/// failure (the latter should be unreachable given the typed contract).
#[no_mangle]
pub unsafe extern "C" fn hitech_bpm_engine_analyze_json(
    engine: *mut HitechBpmEngine,
) -> *mut c_char {
    let Some(engine) = engine.as_ref() else {
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

/// Free a buffer previously returned by `hitech_bpm_engine_analyze_json`.
/// Passing a null pointer is a no-op. Passing any other pointer is undefined
/// behavior.
#[no_mangle]
pub unsafe extern "C" fn hitech_bpm_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}
