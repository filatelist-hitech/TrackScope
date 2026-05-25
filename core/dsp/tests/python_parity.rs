use hitech_bpm_dsp::{analyze_pcm, DspConfig, LockState, TempoCandidate, TempoRelation};
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const SAMPLE_RATE: u32 = 48_000;
const DURATION_SEC: f32 = 14.0;

#[test]
fn python_rust_parity_on_reference_fixtures() {
    for (name, samples) in fixture_matrix() {
        let rust = analyze_pcm(&samples, SAMPLE_RATE, DspConfig::default());
        let python = analyze_python(&samples, SAMPLE_RATE);

        assert_lock_state_parity(rust.lock_state, &python, name);
        assert_signal_quality_parity(&rust, &python, name);
        assert_primary_bpm_parity(rust.primary_bpm, &python, name);
        assert_confidence_parity(rust.confidence, &python, name);
        assert_candidate_parity(&rust.candidates, &python, name);
    }
}

fn fixture_matrix() -> Vec<(&'static str, Vec<f32>)> {
    vec![
        ("clean_200", pulse_samples(200.0, DURATION_SEC, 0.9)),
        ("half_time_trap_100", pulse_samples(100.0, DURATION_SEC, 0.9)),
        ("double_time_trap_400", pulse_samples(400.0, DURATION_SEC, 0.9)),
        (
            "severely_clipped_mic",
            pulse_samples(200.0, DURATION_SEC, 1.8)
                .into_iter()
                .map(|sample| (sample * 2.8).clamp(-0.78, 0.78))
                .collect(),
        ),
        (
            "recoverable_clipped_mic",
            pulse_samples(200.0, DURATION_SEC, 1.12)
                .into_iter()
                .map(|sample| (sample * 1.55).clamp(-0.93, 0.93))
                .collect(),
        ),
        ("white_noise", white_noise(170_170, 0.28)),
    ]
}

fn analyze_python(samples: &[f32], sample_rate: u32) -> Value {
    let root = repo_root();
    let fixture_path = root.join("core/dsp/tests/.tmp_parity_fixture.wav");
    write_wav(&fixture_path, samples, sample_rate);
    let output = Command::new("python3")
        .arg(root.join("tools/offline-lab/analyze.py"))
        .arg("--input")
        .arg(&fixture_path)
        .arg("--mode")
        .arg("hitech")
        .arg("--json")
        .output()
        .expect("python analyzer execution should succeed");
    fs::remove_file(&fixture_path).ok();
    assert!(
        output.status.success(),
        "python analyzer failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).expect("python analyzer JSON should parse")
}

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("repo root should resolve")
}

fn write_wav(path: &Path, samples: &[f32], sample_rate: u32) {
    let mut data = Vec::with_capacity(44 + samples.len() * 2);
    let pcm_len = (samples.len() * 2) as u32;
    data.extend_from_slice(b"RIFF");
    data.extend_from_slice(&(36 + pcm_len).to_le_bytes());
    data.extend_from_slice(b"WAVEfmt ");
    data.extend_from_slice(&16u32.to_le_bytes());
    data.extend_from_slice(&1u16.to_le_bytes());
    data.extend_from_slice(&1u16.to_le_bytes());
    data.extend_from_slice(&sample_rate.to_le_bytes());
    let byte_rate = sample_rate * 2;
    data.extend_from_slice(&byte_rate.to_le_bytes());
    data.extend_from_slice(&2u16.to_le_bytes());
    data.extend_from_slice(&16u16.to_le_bytes());
    data.extend_from_slice(b"data");
    data.extend_from_slice(&pcm_len.to_le_bytes());
    for sample in samples {
        let clamped = sample.clamp(-1.0, 1.0);
        let int_sample = (clamped * 32767.0).round() as i16;
        data.extend_from_slice(&int_sample.to_le_bytes());
    }
    fs::write(path, data).expect("temporary parity fixture should write");
}

fn assert_lock_state_parity(rust: LockState, python: &Value, name: &str) {
    let expected = python["lock_state"]
        .as_str()
        .expect("python lock state should be string");
    let actual = match rust {
        LockState::Searching => "SEARCHING",
        LockState::Locking => "LOCKING",
        LockState::Stable => "STABLE",
        LockState::Unstable => "UNSTABLE",
        LockState::Breakdown => "BREAKDOWN",
        LockState::ClippedMic => "CLIPPED_MIC",
        LockState::NoiseOnly => "NOISE_ONLY",
    };
    assert_eq!(actual, expected, "lock_state parity for {name}");
}

fn assert_signal_quality_parity(
    rust: &hitech_bpm_dsp::DspResult,
    python: &Value,
    name: &str,
) {
    let py = &python["signal_quality"];
    assert_eq!(
        rust.signal_quality.clipping,
        py["clipping"].as_bool().unwrap_or(false),
        "clipping parity for {name}"
    );
    let py_ratio = py["clipped_frame_ratio"].as_f64().unwrap_or(0.0) as f32;
    assert!(
        (rust.signal_quality.clipped_frame_ratio - py_ratio).abs() <= 0.015,
        "clipped ratio parity for {name}: rust={} python={}",
        rust.signal_quality.clipped_frame_ratio,
        py_ratio
    );
}

fn assert_primary_bpm_parity(rust: Option<f32>, python: &Value, name: &str) {
    let py = python["primary_bpm"].as_f64().map(|value| value as f32);
    match (rust, py) {
        (None, None) => {}
        (Some(rv), Some(pv)) => {
            assert!(
                (rv - pv).abs() <= 1.5,
                "primary bpm parity for {name}: rust={rv} python={pv}"
            );
        }
        _ => panic!("primary bpm parity mismatch for {name}: rust={rust:?} python={py:?}"),
    }
}

fn assert_confidence_parity(rust: f32, python: &Value, name: &str) {
    let py = python["confidence"].as_f64().unwrap_or(0.0) as f32;
    assert!(
        (rust - py).abs() <= 0.08,
        "confidence parity for {name}: rust={rust} python={py}"
    );
}

fn assert_candidate_parity(rust: &[TempoCandidate], python: &Value, name: &str) {
    let py_candidates = python["candidates"]
        .as_array()
        .expect("python candidates should be array");
    if name == "half_time_trap_100" {
        assert!(has_candidate(rust, 100.0, Some(TempoRelation::Raw), 1.0));
        assert!(has_candidate(
            rust,
            200.0,
            Some(TempoRelation::NormalizedFromHalf),
            1.0
        ));
    }
    if name == "double_time_trap_400" {
        assert!(has_candidate(rust, 400.0, Some(TempoRelation::Raw), 1.5));
        assert!(has_candidate(
            rust,
            200.0,
            Some(TempoRelation::NormalizedFromDouble),
            1.0
        ));
    }
    for (bpm, relation) in [(200.0, "main"), (100.0, "raw")] {
        let python_has = py_candidates.iter().any(|candidate| {
            candidate["bpm"]
                .as_f64()
                .is_some_and(|value| (value as f32 - bpm).abs() <= 2.0)
                && candidate["relation"].as_str().is_some_and(|value| value == relation)
        });
        let rust_relation = match relation {
            "main" => TempoRelation::Main,
            "raw" => TempoRelation::Raw,
            _ => TempoRelation::Raw,
        };
        let rust_has = has_candidate(rust, bpm, Some(rust_relation), 2.0);
        assert_eq!(
            rust_has, python_has,
            "candidate parity for {name} ({relation} {bpm})"
        );
    }
}

fn has_candidate(
    candidates: &[TempoCandidate],
    bpm: f32,
    relation: Option<TempoRelation>,
    tolerance: f32,
) -> bool {
    candidates.iter().any(|candidate| {
        (candidate.bpm - bpm).abs() <= tolerance
            && relation.map_or(true, |expected| candidate.relation == expected)
    })
}

fn pulse_samples(bpm: f32, duration_sec: f32, amplitude: f32) -> Vec<f32> {
    let mut samples = vec![0.0; sample_count(duration_sec)];
    let beat_period = 60.0 / bpm;
    let mut beat = 0.0;
    while beat < duration_sec {
        add_kick(&mut samples, (beat * SAMPLE_RATE as f32).round() as usize, amplitude);
        beat += beat_period;
    }
    normalize(samples, 0.88)
}

fn add_kick(samples: &mut [f32], start: usize, amplitude: f32) {
    let length = (0.055 * SAMPLE_RATE as f32) as usize;
    let transient_len = ((0.003 * SAMPLE_RATE as f32) as usize).max(1);
    for offset in 0..length {
        let idx = start + offset;
        if idx >= samples.len() {
            return;
        }
        let t = offset as f32 / SAMPLE_RATE as f32;
        let envelope = (-72.0 * t).exp();
        let tone = (2.0 * std::f32::consts::PI * 72.0 * t).sin();
        let click = if offset < transient_len {
            1.0 - (offset as f32 / transient_len as f32)
        } else {
            0.0
        };
        samples[idx] += amplitude * ((0.72 * tone * envelope) + (0.55 * click * envelope));
    }
}

fn white_noise(seed: u64, amplitude: f32) -> Vec<f32> {
    let mut rng = Lcg::new(seed);
    (0..sample_count(DURATION_SEC))
        .map(|_| rng.uniform(-amplitude, amplitude))
        .collect()
}

fn normalize(samples: Vec<f32>, peak: f32) -> Vec<f32> {
    let current_peak = samples.iter().map(|sample| sample.abs()).fold(0.0, f32::max);
    if current_peak == 0.0 {
        return samples;
    }
    let scale = peak / current_peak;
    samples.into_iter().map(|sample| sample * scale).collect()
}

fn sample_count(duration_sec: f32) -> usize {
    (duration_sec * SAMPLE_RATE as f32).round() as usize
}

struct Lcg {
    state: u64,
}

impl Lcg {
    fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn next_f32(&mut self) -> f32 {
        self.state = self.state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        ((self.state & 0xffff_ffff) as f32) / u32::MAX as f32
    }

    fn uniform(&mut self, min: f32, max: f32) -> f32 {
        min + (max - min) * self.next_f32()
    }
}
