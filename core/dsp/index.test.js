"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { analyzePcm, DspEngine } = require("./index");

const SAMPLE_RATE = 44100;

test("detects clean hitech synthetic tempos with candidates and confidence", () => {
  for (const bpm of [170, 180, 190, 200, 220]) {
    const result = analyzePcm(pulseTrain({ bpm }), SAMPLE_RATE);
    assert.equal(result.lock_state, "STABLE", `${bpm} BPM should be stable`);
    assert.ok(result.primary_bpm !== null, `${bpm} BPM primary should not be null`);
    assert.ok(Math.abs(result.primary_bpm - bpm) <= 1, `${bpm} got ${result.primary_bpm}`);
    assert.ok(result.confidence >= 0.7, `${bpm} confidence ${result.confidence}`);
    assert.ok(result.candidates.length > 1, `${bpm} should expose candidate list`);
  }
});

test("normalizes a 100 BPM half-time trap to 200 BPM without hiding the raw candidate", () => {
  const result = analyzePcm(pulseTrain({ bpm: 100 }), SAMPLE_RATE);
  assert.equal(result.lock_state, "STABLE");
  assert.ok(result.primary_bpm !== null);
  assert.ok(Math.abs(result.primary_bpm - 200) <= 1, `got ${result.primary_bpm}`);
  assert.ok(result.candidates.some((candidate) => candidate.relation === "raw" && near(candidate.bpm, 100, 1)));
  assert.ok(
    result.candidates.some(
      (candidate) => candidate.relation === "normalized_from_half" && near(candidate.bpm, 200, 1),
    ),
  );
});

test("normalizes a 400 BPM double-time trap to 200 BPM without hiding the raw candidate", () => {
  const result = analyzePcm(pulseTrain({ bpm: 400 }), SAMPLE_RATE);
  assert.equal(result.lock_state, "STABLE");
  assert.ok(result.primary_bpm !== null);
  assert.ok(Math.abs(result.primary_bpm - 200) <= 1, `got ${result.primary_bpm}`);
  assert.ok(result.candidates.some((candidate) => candidate.relation === "raw" && near(candidate.bpm, 400, 2)));
  assert.ok(
    result.candidates.some(
      (candidate) => candidate.relation === "normalized_from_double" && near(candidate.bpm, 200, 1),
    ),
  );
});

test("keeps usable noisy hitech input deterministic without overclaiming perfect confidence", () => {
  const result = analyzePcm(pulseTrain({ bpm: 200, noise: 0.08 }), SAMPLE_RATE);
  assert.ok(result.primary_bpm !== null);
  assert.ok(Math.abs(result.primary_bpm - 200) <= 4, `got ${result.primary_bpm}`);
  assert.ok(["LOCKING", "STABLE"].includes(result.lock_state), result.lock_state);
  assert.ok(result.confidence < 0.98);
});

test("does not invent a tempo for silence", () => {
  const result = analyzePcm(new Float32Array(SAMPLE_RATE * 12), SAMPLE_RATE);
  assert.equal(result.primary_bpm, null);
  assert.equal(result.lock_state, "SEARCHING");
  assert.equal(result.signal_quality.silence, true);
});

test("does not return stable confidence for noise-only input", () => {
  const result = analyzePcm(noiseOnly(12, 0.15), SAMPLE_RATE);
  assert.equal(result.primary_bpm, null);
  assert.notEqual(result.lock_state, "STABLE");
  assert.ok(["NOISE_ONLY", "SEARCHING", "UNSTABLE"].includes(result.lock_state), result.lock_state);
});

test("flags clipped input and suppresses final BPM", () => {
  const result = analyzePcm(pulseTrain({ bpm: 200, clipped: true }), SAMPLE_RATE);
  assert.equal(result.signal_quality.clipping, true);
  assert.equal(result.lock_state, "CLIPPED_MIC");
  assert.equal(result.primary_bpm, null);
  assert.ok(result.candidates.length > 0);
});

test("streaming engine feeds chunks through the same analyzer", () => {
  const engine = new DspEngine();
  const samples = pulseTrain({ bpm: 190 });
  const chunk = SAMPLE_RATE;
  for (let offset = 0; offset < samples.length; offset += chunk) {
    engine.pushSamples(samples.slice(offset, offset + chunk), SAMPLE_RATE);
  }
  const result = engine.analyze();
  assert.equal(result.lock_state, "STABLE");
  assert.ok(result.primary_bpm !== null);
  assert.ok(Math.abs(result.primary_bpm - 190) <= 1, `got ${result.primary_bpm}`);
});

function pulseTrain({ bpm, duration = 12, noise = 0, clipped = false }) {
  const samples = new Float32Array(Math.floor(duration * SAMPLE_RATE));
  const period = 60 / bpm;
  const pulseLength = Math.floor(0.045 * SAMPLE_RATE);
  let seed = 0x12345678;
  for (let beatTime = 0; beatTime < duration; beatTime += period) {
    const start = Math.round(beatTime * SAMPLE_RATE);
    for (let i = 0; i < pulseLength && start + i < samples.length; i += 1) {
      const t = i / SAMPLE_RATE;
      const decay = Math.exp(-t * 85);
      const kick = Math.sin(2 * Math.PI * 58 * t) * decay;
      const click = i < 14 ? 0.7 * (1 - i / 14) : 0;
      samples[start + i] += 0.82 * kick + click;
    }
  }

  for (let i = 0; i < samples.length; i += 1) {
    if (noise > 0) {
      seed = (1664525 * seed + 1013904223) >>> 0;
      samples[i] += ((seed / 0xffffffff) * 2 - 1) * noise;
    }
    samples[i] = clipped
      ? Math.max(-1, Math.min(1, samples[i] * 2.8))
      : Math.max(-1, Math.min(1, samples[i]));
  }
  return samples;
}

function noiseOnly(duration, amplitude) {
  const samples = new Float32Array(Math.floor(duration * SAMPLE_RATE));
  let seed = 0xf00d;
  for (let i = 0; i < samples.length; i += 1) {
    seed = (1664525 * seed + 1013904223) >>> 0;
    samples[i] = ((seed / 0xffffffff) * 2 - 1) * amplitude;
  }
  return samples;
}

function near(value, expected, tolerance) {
  return Math.abs(value - expected) <= tolerance;
}
