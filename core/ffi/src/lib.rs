//! C ABI boundary for mobile integration.
//!
//! The bridge owns handles and sample ingress only. BPM calculation stays in
//! `hitech_bpm_dsp`; Flutter must not implement a parallel tempo detector.

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
