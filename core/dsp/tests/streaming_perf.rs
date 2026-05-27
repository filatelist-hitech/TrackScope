mod common;

use std::time::Instant;

use common::{pulse_track, DEFAULT_DURATION_SEC, SAMPLE_RATE};
use hitech_bpm_dsp::{DspConfig, DspEngine};

/// Измерение wall-time на один push. Заявленный предел намеренно мягкий —
/// цель — выявить грубые регрессии в CI, а не зафиксировать точное число.
/// Запустить с `--ignored --nocapture`, чтобы увидеть median/p95/max.
#[test]
#[ignore]
fn push_samples_per_call_cost() {
    let samples = pulse_track(200.0, 60.0, 0.9);
    let chunk_size = (SAMPLE_RATE as f32 * 0.1) as usize; // чанки по 100 мс
    let mut engine = DspEngine::default();
    let mut push_times = Vec::with_capacity(samples.len() / chunk_size + 1);
    let mut analyze_times = Vec::with_capacity(samples.len() / chunk_size + 1);

    for chunk in samples.chunks(chunk_size) {
        let push_start = Instant::now();
        engine.push_samples(chunk, SAMPLE_RATE);
        push_times.push(push_start.elapsed());
        let analyze_start = Instant::now();
        let _ = engine.analyze();
        analyze_times.push(analyze_start.elapsed());
    }

    let _ = DEFAULT_DURATION_SEC; // подавить предупреждение о мёртвом коде
    let _ = DspConfig::default();

    let push_us: Vec<u128> = push_times.iter().map(|d| d.as_micros()).collect();
    let analyze_us: Vec<u128> = analyze_times.iter().map(|d| d.as_micros()).collect();
    let summary = |label: &str, values: &[u128]| {
        let mut sorted = values.to_vec();
        sorted.sort_unstable();
        let median = sorted[sorted.len() / 2];
        let p95 = sorted[(sorted.len() as f32 * 0.95) as usize];
        let max = *sorted.last().unwrap();
        eprintln!(
            "{label} count={} median={median}us p95={p95}us max={max}us",
            sorted.len()
        );
    };
    summary("push_samples ", &push_us);
    summary("analyze      ", &analyze_us);

    // Граница здравомыслия: один push 100 мс аудио не должен занимать более
    // 200 мс на любом разумном хосте, иначе realtime невозможен.
    let push_max = *push_us.iter().max().unwrap();
    assert!(push_max < 200_000, "push_samples max {push_max}us exceeded 200ms");
}
