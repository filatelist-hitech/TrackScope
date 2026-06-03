//! Потоковый Rust-анализатор WAV через DspEngine.
//!
//! В отличие от `analyze_wav` (batch `analyze_pcm`), этот бинарник кормит
//! аудио через DspEngine 100-мс чанками и снимает финальный `DspResult`.
//! Нужен для инспекции `energy_result` и `key_result`, которые доступны
//! только в потоковом движке, а не в batch-пути.
//!
//! Использование:
//!   stream_analyze_wav --input <path.wav> [--chunk-ms N] [--skip-secs S]
//!
//! Выводит `DspResult` как JSON на stdout.

use std::env;
use std::fs;
use std::process::ExitCode;

use hitech_bpm_dsp::{DspConfig, DspEngine};

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    let mut input_path: Option<String> = None;
    let mut chunk_ms: f32 = 100.0;
    let mut skip_secs: f32 = 0.0;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--input" => input_path = args.next(),
            "--chunk-ms" => {
                if let Some(v) = args.next() {
                    chunk_ms = v.parse().unwrap_or(100.0);
                }
            }
            "--skip-secs" => {
                if let Some(v) = args.next() {
                    skip_secs = v.parse().unwrap_or(0.0);
                }
            }
            "--help" | "-h" => {
                eprintln!(
                    "usage: stream_analyze_wav --input <path.wav> [--chunk-ms N] [--skip-secs S]"
                );
                return ExitCode::from(0);
            }
            other => {
                eprintln!("unexpected argument: {other}");
                return ExitCode::from(2);
            }
        }
    }

    let Some(path) = input_path else {
        eprintln!("--input <path> is required");
        return ExitCode::from(2);
    };

    let bytes = match fs::read(&path) {
        Ok(bytes) => bytes,
        Err(err) => {
            eprintln!("failed to read {path}: {err}");
            return ExitCode::from(1);
        }
    };

    let (samples, sample_rate) = match read_pcm16_wav(&bytes) {
        Ok(pair) => pair,
        Err(err) => {
            eprintln!("failed to parse WAV: {err}");
            return ExitCode::from(1);
        }
    };

    let skip_samples = (skip_secs * sample_rate as f32) as usize;
    let samples = &samples[skip_samples.min(samples.len())..];

    let chunk_samples = ((chunk_ms / 1000.0) * sample_rate as f32) as usize;
    let chunk_samples = chunk_samples.max(1);

    let mut engine = DspEngine::new(DspConfig::default());

    for chunk in samples.chunks(chunk_samples) {
        engine.push_samples(chunk, sample_rate);
    }

    let result = engine.analyze();
    match serde_json::to_string_pretty(&result) {
        Ok(json) => {
            println!("{json}");
            ExitCode::from(0)
        }
        Err(err) => {
            eprintln!("failed to serialize result: {err}");
            ExitCode::from(1)
        }
    }
}

/// Минимальный ридер 16-битных моно PCM WAV-файлов.
fn read_pcm16_wav(bytes: &[u8]) -> Result<(Vec<f32>, u32), String> {
    if bytes.len() < 44 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return Err("not a RIFF/WAVE file".to_string());
    }

    let mut cursor = 12usize;
    let mut sample_rate: u32 = 0;
    let mut channels: u16 = 0;
    let mut bits_per_sample: u16 = 0;
    let mut data: Option<&[u8]> = None;

    while cursor + 8 <= bytes.len() {
        let chunk_id = &bytes[cursor..cursor + 4];
        let chunk_size = u32::from_le_bytes([
            bytes[cursor + 4],
            bytes[cursor + 5],
            bytes[cursor + 6],
            bytes[cursor + 7],
        ]) as usize;
        let chunk_start = cursor + 8;
        let chunk_end = chunk_start + chunk_size;
        if chunk_end > bytes.len() {
            return Err("truncated WAV chunk".to_string());
        }

        match chunk_id {
            b"fmt " => {
                if chunk_size < 16 {
                    return Err("fmt chunk too small".to_string());
                }
                let audio_format =
                    u16::from_le_bytes([bytes[chunk_start], bytes[chunk_start + 1]]);
                if audio_format != 1 {
                    return Err(format!(
                        "unsupported audio format: {audio_format} (PCM=1 required)"
                    ));
                }
                channels = u16::from_le_bytes([bytes[chunk_start + 2], bytes[chunk_start + 3]]);
                sample_rate = u32::from_le_bytes([
                    bytes[chunk_start + 4],
                    bytes[chunk_start + 5],
                    bytes[chunk_start + 6],
                    bytes[chunk_start + 7],
                ]);
                bits_per_sample =
                    u16::from_le_bytes([bytes[chunk_start + 14], bytes[chunk_start + 15]]);
            }
            b"data" => {
                data = Some(&bytes[chunk_start..chunk_end]);
            }
            _ => {}
        }
        cursor = chunk_end + (chunk_size & 1);
    }

    let data = data.ok_or_else(|| "missing data chunk".to_string())?;
    if channels == 0 || sample_rate == 0 {
        return Err("missing fmt chunk".to_string());
    }
    if bits_per_sample != 16 {
        return Err(format!(
            "only 16-bit PCM is supported (got {bits_per_sample})"
        ));
    }

    let stride = channels as usize * 2;
    if data.len() % stride != 0 {
        return Err("data chunk size not aligned to frame stride".to_string());
    }

    let mut samples = Vec::with_capacity(data.len() / stride);
    let mut idx = 0;
    while idx + stride <= data.len() {
        let mut frame_sum = 0.0_f32;
        for ch in 0..channels as usize {
            let lo = data[idx + ch * 2];
            let hi = data[idx + ch * 2 + 1];
            let int_sample = i16::from_le_bytes([lo, hi]);
            frame_sum += int_sample as f32 / 32_768.0;
        }
        samples.push(frame_sum / channels as f32);
        idx += stride;
    }

    Ok((samples, sample_rate))
}
