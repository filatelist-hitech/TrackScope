//! Детерминированные синтетические фикстуры для регрессионных тестов Rust DSP.
//!
//! Зеркалируют `core/tests/helpers/synthetic_fixtures.py`. Генераторы
//! сидированы так, что вывод тестов воспроизводим на разных прогонах и
//! платформах; никакой зависимости от `std::time` или thread-local RNG.

#![allow(dead_code)]

pub const SAMPLE_RATE: u32 = 48_000;
pub const DEFAULT_DURATION_SEC: f32 = 14.0;

pub fn sample_count(duration_sec: f32) -> usize {
    (duration_sec * SAMPLE_RATE as f32).round() as usize
}

pub fn silence(duration_sec: f32) -> Vec<f32> {
    vec![0.0; sample_count(duration_sec)]
}

pub fn pulse_track(bpm: f32, duration_sec: f32, amplitude: f32) -> Vec<f32> {
    let mut samples = vec![0.0; sample_count(duration_sec)];
    let beat_period = 60.0 / bpm;
    let mut beat = 0.0;
    while beat < duration_sec {
        add_kick(
            &mut samples,
            (beat * SAMPLE_RATE as f32).round() as usize,
            amplitude,
        );
        beat += beat_period;
    }
    normalize(samples, 0.88)
}

pub fn severely_clipped_pulse(bpm: f32, duration_sec: f32) -> Vec<f32> {
    pulse_track(bpm, duration_sec, 1.8)
        .into_iter()
        .map(|sample| (sample * 2.8).clamp(-0.78, 0.78))
        .collect()
}

pub fn recoverable_clipped_pulse(bpm: f32, duration_sec: f32) -> Vec<f32> {
    pulse_track(bpm, duration_sec, 1.12)
        .into_iter()
        .map(|sample| (sample * 1.55).clamp(-0.93, 0.93))
        .collect()
}

pub fn breakdown_without_kick(bpm: f32, head_sec: f32, tail_sec: f32, seed: u64) -> Vec<f32> {
    let mut samples = pulse_track(bpm, head_sec, 0.9);
    samples.extend(low_rumble(tail_sec, seed, 0.08));
    samples
}

pub fn dense_hitech_bassline(bpm: f32, duration_sec: f32) -> Vec<f32> {
    let mut samples = pulse_track(bpm, duration_sec, 0.82);
    add_rolling_bassline(&mut samples, bpm, duration_sec);
    normalize(samples, 0.92)
}

pub fn white_noise(seed: u64, amplitude: f32, duration_sec: f32) -> Vec<f32> {
    let mut rng = Lcg::new(seed);
    (0..sample_count(duration_sec))
        .map(|_| rng.uniform(-amplitude, amplitude))
        .collect()
}

pub fn pink_noise(seed: u64, amplitude: f32, duration_sec: f32) -> Vec<f32> {
    let mut rng = Lcg::new(seed);
    let mut value = 0.0;
    let mut samples = Vec::with_capacity(sample_count(duration_sec));
    for _ in 0..sample_count(duration_sec) {
        value = (0.985 * value) + (0.015 * rng.uniform(-1.0, 1.0));
        samples.push(value);
    }
    normalize(samples, amplitude)
}

pub fn low_rumble(duration_sec: f32, seed: u64, amplitude: f32) -> Vec<f32> {
    let mut rng = Lcg::new(seed);
    let mut samples = Vec::with_capacity(sample_count(duration_sec));
    for idx in 0..sample_count(duration_sec) {
        let t = idx as f32 / SAMPLE_RATE as f32;
        let rumble = (2.0 * std::f32::consts::PI * 37.0 * t).sin() * 0.7;
        let drift = (2.0 * std::f32::consts::PI * 0.21 * t).sin() * 0.2;
        samples.push(amplitude * (rumble + drift + rng.uniform(-0.08, 0.08)));
    }
    samples
}

pub fn unstable_club_simulation(duration_sec: f32) -> Vec<f32> {
    let mut rng = Lcg::new(0x5150);
    let mut samples = vec![0.0; sample_count(duration_sec)];
    let mut beat_time = 0.0;
    while beat_time < duration_sec {
        let bpm = rng.uniform(175.0, 245.0);
        beat_time += 60.0 / bpm;
        if rng.next_f32() < 0.22 {
            continue;
        }
        add_kick(
            &mut samples,
            (beat_time * SAMPLE_RATE as f32).round() as usize,
            rng.uniform(0.25, 0.75),
        );
    }

    for (idx, sample) in samples.iter_mut().enumerate() {
        let t = idx as f32 / SAMPLE_RATE as f32;
        let rumble = 0.09 * (2.0 * std::f32::consts::PI * 43.0 * t).sin();
        *sample += rumble + rng.uniform(-0.32, 0.32);
    }
    normalize(samples, 0.9)
}

pub fn normalize(samples: Vec<f32>, peak: f32) -> Vec<f32> {
    let current_peak = samples.iter().map(|sample| sample.abs()).fold(0.0, f32::max);
    if current_peak == 0.0 {
        return samples;
    }
    let scale = peak / current_peak;
    samples.into_iter().map(|sample| sample * scale).collect()
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

fn add_rolling_bassline(samples: &mut [f32], bpm: f32, duration_sec: f32) {
    let step = 60.0 / (bpm * 4.0);
    let pulse_len = (0.045 * SAMPLE_RATE as f32) as usize;
    let mut position = step / 2.0;
    while position < duration_sec {
        let start = (position * SAMPLE_RATE as f32).round() as usize;
        for offset in 0..pulse_len {
            let idx = start + offset;
            if idx >= samples.len() {
                break;
            }
            let t = offset as f32 / SAMPLE_RATE as f32;
            let envelope = (-38.0 * t).exp();
            let tone = (2.0 * std::f32::consts::PI * 98.0 * t).sin();
            samples[idx] += 0.18 * tone * envelope;
        }
        position += step;
    }
}

pub struct Lcg {
    state: u64,
}

impl Lcg {
    pub fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    pub fn next_f32(&mut self) -> f32 {
        self.state = self.state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        ((self.state & 0xffff_ffff) as f32) / u32::MAX as f32
    }

    pub fn uniform(&mut self, min: f32, max: f32) -> f32 {
        min + (max - min) * self.next_f32()
    }
}

/// Канонический инвентарь фикстур, зеркалирующий core/tests/helpers/synthetic_fixtures.py.
pub fn fixture_samples(name: &str) -> Vec<f32> {
    match name {
        "clean_170" => pulse_track(170.0, DEFAULT_DURATION_SEC, 0.9),
        "clean_180" => pulse_track(180.0, DEFAULT_DURATION_SEC, 0.9),
        "clean_190" => pulse_track(190.0, DEFAULT_DURATION_SEC, 0.9),
        "clean_200" => pulse_track(200.0, DEFAULT_DURATION_SEC, 0.9),
        "clean_220" => pulse_track(220.0, DEFAULT_DURATION_SEC, 0.9),
        "half_time_trap_100" => pulse_track(100.0, DEFAULT_DURATION_SEC, 0.9),
        "double_time_trap_400" => pulse_track(400.0, DEFAULT_DURATION_SEC, 0.9),
        "silence" => silence(DEFAULT_DURATION_SEC),
        "white_noise" => white_noise(170_170, 0.28, DEFAULT_DURATION_SEC),
        "pink_noise" => pink_noise(220_220, 0.32, DEFAULT_DURATION_SEC),
        "severely_clipped_mic" => severely_clipped_pulse(200.0, DEFAULT_DURATION_SEC),
        "recoverable_clipped_mic" => recoverable_clipped_pulse(200.0, DEFAULT_DURATION_SEC),
        "breakdown_without_kick" => breakdown_without_kick(200.0, 6.0, 8.0, 0xBEEFDA),
        "dense_hitech_bassline" => dense_hitech_bassline(200.0, DEFAULT_DURATION_SEC),
        "unstable_club_simulation" => unstable_club_simulation(DEFAULT_DURATION_SEC),
        _ => panic!("unknown fixture: {name}"),
    }
}

pub const CANONICAL_FIXTURES: &[&str] = &[
    "clean_170",
    "clean_180",
    "clean_190",
    "clean_200",
    "clean_220",
    "half_time_trap_100",
    "double_time_trap_400",
    "silence",
    "white_noise",
    "pink_noise",
    "recoverable_clipped_mic",
    "severely_clipped_mic",
    "breakdown_without_kick",
    "dense_hitech_bassline",
    "unstable_club_simulation",
];
