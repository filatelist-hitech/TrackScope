//! End-to-end FFI smoke-тест: прогнать `push_samples` + `analyze_json` через
//! C ABI, затем распарсить JSON обратно и подтвердить, что контракт скользящего
//! `DspResult` выполняется. Гарантирует, что FFI-граница сохраняет ту же форму,
//! которую будут читать Flutter / нативные потребители.

use std::ffi::CStr;

use hitech_bpm_ffi::{
    hitech_bpm_engine_analyze_json, hitech_bpm_engine_free, hitech_bpm_engine_new,
    hitech_bpm_engine_push_samples, hitech_bpm_string_free,
};

const SAMPLE_RATE: u32 = 48_000;

fn pulse_200_bpm(duration_sec: f32) -> Vec<f32> {
    let total = (duration_sec * SAMPLE_RATE as f32).round() as usize;
    let mut samples = vec![0.0_f32; total];
    let beat_period = 60.0_f32 / 200.0;
    let mut beat = 0.0;
    while beat < duration_sec {
        let start = (beat * SAMPLE_RATE as f32).round() as usize;
        let kick_len = (SAMPLE_RATE as f32 * 0.012) as usize;
        for i in 0..kick_len {
            if start + i >= samples.len() {
                break;
            }
            let phase = i as f32 / SAMPLE_RATE as f32;
            let env = (-phase * 90.0).exp();
            let osc = (2.0 * std::f32::consts::PI * 60.0 * phase).sin();
            samples[start + i] += 0.9 * env * osc;
        }
        beat += beat_period;
    }
    samples
}

#[test]
fn ffi_analyze_json_round_trips_dsp_result_contract() {
    unsafe {
        let engine = hitech_bpm_engine_new();
        assert!(!engine.is_null(), "engine ctor returned null");

        // Стримить 13 с чистого 200 BPM чанками по 100 мс. По контракту
        // потоковый движок должен достигнуть STABLE в течение 12 с,
        // так что 13 с дают небольшой запас.
        let chunk_sec = 0.1;
        let chunk_len = (SAMPLE_RATE as f32 * chunk_sec) as usize;
        let pcm = pulse_200_bpm(13.0);
        for chunk in pcm.chunks(chunk_len) {
            let ok = hitech_bpm_engine_push_samples(
                engine,
                chunk.as_ptr(),
                chunk.len(),
                SAMPLE_RATE,
            );
            assert!(ok, "push_samples returned false on valid input");
        }

        let ptr = hitech_bpm_engine_analyze_json(engine);
        assert!(!ptr.is_null(), "analyze_json returned null");
        let json = CStr::from_ptr(ptr).to_str().expect("utf-8 json").to_owned();
        hitech_bpm_string_free(ptr);
        hitech_bpm_engine_free(engine);

        let parsed: serde_json::Value =
            serde_json::from_str(&json).expect("FFI JSON must parse");

        // Форма контракта.
        for key in [
            "primary_bpm",
            "confidence",
            "lock_state",
            "signal_quality",
            "candidates",
            "timing",
        ] {
            assert!(parsed.get(key).is_some(), "missing key in DspResult: {key}");
        }

        let lock_state = parsed["lock_state"].as_str().expect("lock_state is string");
        assert!(
            matches!(
                lock_state,
                "SEARCHING"
                    | "LOCKING"
                    | "STABLE"
                    | "UNSTABLE"
                    | "BREAKDOWN"
                    | "CLIPPED_MIC"
                    | "NOISE_ONLY"
            ),
            "unexpected lock_state: {lock_state}"
        );
        assert_eq!(lock_state, "STABLE", "13 s of 200 BPM must reach STABLE");

        let bpm = parsed["primary_bpm"]
            .as_f64()
            .expect("primary_bpm must be set when STABLE");
        assert!((bpm - 200.0).abs() <= 2.0, "primary_bpm = {bpm}, want 200 ± 2");

        let confidence = parsed["confidence"].as_f64().expect("confidence");
        assert!((0.0..=1.0).contains(&confidence), "confidence out of [0,1]: {confidence}");

        let candidates = parsed["candidates"].as_array().expect("candidates array");
        assert!(!candidates.is_empty(), "candidates must remain visible");

        // Half-time-кандидат (raw или нормализованный) обязан присутствовать
        // для чистого сигнала 200 BPM — это правило видимости.
        let has_half_evidence = candidates.iter().any(|c| {
            let b = c.get("bpm").and_then(|v| v.as_f64()).unwrap_or(0.0);
            (b - 100.0).abs() < 5.0
        });
        assert!(
            has_half_evidence,
            "half-time evidence near 100 BPM must remain visible"
        );
    }
}

#[test]
fn ffi_analyze_json_silence_never_stable() {
    unsafe {
        let engine = hitech_bpm_engine_new();
        let pcm = vec![0.0_f32; SAMPLE_RATE as usize * 14];
        let ok =
            hitech_bpm_engine_push_samples(engine, pcm.as_ptr(), pcm.len(), SAMPLE_RATE);
        assert!(ok);

        let ptr = hitech_bpm_engine_analyze_json(engine);
        let json = CStr::from_ptr(ptr).to_str().unwrap().to_owned();
        hitech_bpm_string_free(ptr);
        hitech_bpm_engine_free(engine);

        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        let lock = parsed["lock_state"].as_str().unwrap();
        assert_ne!(lock, "STABLE", "silence must never reach STABLE");
        assert!(parsed["primary_bpm"].is_null(), "silence must yield null BPM");
    }
}

#[test]
fn ffi_null_handle_returns_null() {
    unsafe {
        let ptr = hitech_bpm_engine_analyze_json(std::ptr::null_mut());
        assert!(ptr.is_null());
        // string_free на null — no-op.
        hitech_bpm_string_free(std::ptr::null_mut());
    }
}
