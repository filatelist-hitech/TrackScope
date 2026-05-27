"use strict";

const DEFAULT_CONFIG = Object.freeze({
  mode: "hitech",
  sampleRate: 44100,
  targetBpmMin: 170,
  targetBpmMax: 230,
  broadBpmMin: 80,
  broadBpmMax: 460,
  analysisWindowSeconds: 12,
  hopSeconds: 128 / 44100,
  frameSeconds: 1024 / 44100,
  lockMinSeconds: 4,
  stableMinSeconds: 8,
  lockConfidence: 0.45,
  stableConfidence: 0.7,
});

class DspEngine {
  constructor(config = {}) {
    this.config = normalizeConfig(config);
    this.reset();
  }

  reset() {
    this.samples = new Float32Array(0);
    this.observedSeconds = 0;
    this.firstLockTimeSec = null;
  }

  pushSamples(input, sampleRate = this.config.sampleRate) {
    const mono = toFloatMono(input);
    const samples =
      sampleRate === this.config.sampleRate
        ? mono
        : resampleLinear(mono, sampleRate, this.config.sampleRate);

    const merged = new Float32Array(this.samples.length + samples.length);
    merged.set(this.samples, 0);
    merged.set(samples, this.samples.length);

    const maxSamples = Math.floor(
      this.config.analysisWindowSeconds * this.config.sampleRate,
    );
    this.samples =
      merged.length > maxSamples ? merged.slice(merged.length - maxSamples) : merged;
    this.observedSeconds += samples.length / this.config.sampleRate;
  }

  analyze() {
    const result = analyzePcm(this.samples, this.config.sampleRate, {
      ...this.config,
      observedSeconds: this.observedSeconds,
      firstLockTimeSec: this.firstLockTimeSec,
    });

    if (this.firstLockTimeSec === null && result.primary_bpm !== null) {
      this.firstLockTimeSec = Math.min(
        this.observedSeconds,
        result.timing.analysis_time_sec,
      );
      result.timing.first_lock_time_sec = this.firstLockTimeSec;
    }

    return result;
  }
}

function analyzePcm(input, sampleRate = DEFAULT_CONFIG.sampleRate, config = {}) {
  const cfg = normalizeConfig(config);
  const samples =
    sampleRate === cfg.sampleRate
      ? toFloatMono(input)
      : resampleLinear(toFloatMono(input), sampleRate, cfg.sampleRate);

  const analysisTimeSec = samples.length / cfg.sampleRate;
  const quality = analyzeSignalQuality(samples);
  const envelope = computeOnsetEnvelope(samples, cfg.sampleRate, cfg);
  const tempo = estimateTempoCandidates(envelope.values, envelope.rateHz, cfg, quality);

  let candidates = tempo.candidates;
  let primary = candidates[0] || null;
  let confidence = primary ? clamp01(primary.score) : 0;
  let lockState = classifyLockState({
    quality,
    envelope,
    tempo,
    primary,
    confidence,
    analysisTimeSec,
    cfg,
  });

  let primaryBpm = null;
  if (
    primary &&
    confidence >= cfg.lockConfidence &&
    lockState !== "CLIPPED_MIC" &&
    lockState !== "NOISE_ONLY" &&
    lockState !== "SEARCHING" &&
    lockState !== "BREAKDOWN"
  ) {
    primaryBpm = round(primary.bpm, 3);
  }

  if (primaryBpm === null && lockState === "LOCKING" && confidence < cfg.lockConfidence) {
    lockState = quality.silence ? "SEARCHING" : "NOISE_ONLY";
  }

  return {
    primary_bpm: primaryBpm,
    confidence: round(confidence, 4),
    lock_state: lockState,
    signal_quality: quality,
    candidates,
    timing: {
      analysis_time_sec: round(analysisTimeSec, 4),
      window_time_sec: round(cfg.analysisWindowSeconds, 4),
      hop_time_sec: round(cfg.hopSeconds, 6),
      first_lock_time_sec: config.firstLockTimeSec ?? null,
    },
    debug: {
      onset_rate_hz: round(envelope.rateHz, 4),
      onset_strength: round(envelope.stats.onsetStrength, 4),
      tempo_peak_prominence: round(tempo.peakProminence, 4),
      harmonic_ambiguity: round(tempo.harmonicAmbiguity, 4),
      stability_score: primary ? primary.stability_score : 0,
      warnings: buildWarnings(quality, envelope, tempo),
    },
  };
}

function normalizeConfig(config) {
  const cfg = { ...DEFAULT_CONFIG, ...config };
  cfg.sampleRate = Number(cfg.sampleRate);
  cfg.targetBpmMin = Number(cfg.targetBpmMin);
  cfg.targetBpmMax = Number(cfg.targetBpmMax);
  cfg.broadBpmMin = Number(cfg.broadBpmMin);
  cfg.broadBpmMax = Number(cfg.broadBpmMax);
  cfg.analysisWindowSeconds = Number(cfg.analysisWindowSeconds);
  cfg.hopSeconds = Number(cfg.hopSeconds);
  cfg.frameSeconds = Number(cfg.frameSeconds);
  return cfg;
}

function toFloatMono(input) {
  if (input instanceof Float32Array) {
    return input;
  }
  if (Array.isArray(input)) {
    return Float32Array.from(input);
  }
  if (ArrayBuffer.isView(input)) {
    return Float32Array.from(input);
  }
  throw new TypeError("PCM input must be an array or typed array of mono float samples");
}

function resampleLinear(samples, sourceRate, targetRate) {
  if (sourceRate <= 0 || targetRate <= 0) {
    throw new Error("sample rates must be positive");
  }
  if (samples.length === 0 || sourceRate === targetRate) {
    return samples;
  }

  const outputLength = Math.max(1, Math.round((samples.length * targetRate) / sourceRate));
  const output = new Float32Array(outputLength);
  const ratio = sourceRate / targetRate;
  for (let i = 0; i < outputLength; i += 1) {
    const sourceIndex = i * ratio;
    const left = Math.floor(sourceIndex);
    const right = Math.min(samples.length - 1, left + 1);
    const frac = sourceIndex - left;
    output[i] = samples[left] * (1 - frac) + samples[right] * frac;
  }
  return output;
}

function analyzeSignalQuality(samples) {
  if (samples.length === 0) {
    return {
      input_level_dbfs: null,
      peak_dbfs: null,
      clipping: false,
      clipped_frame_ratio: 0,
      noise_level: "unknown",
      snr_estimate_db: null,
      silence: true,
      breakdown_likely: false,
    };
  }

  let sumSquares = 0;
  let peak = 0;
  let clipped = 0;
  for (let i = 0; i < samples.length; i += 1) {
    const value = Math.abs(samples[i]);
    sumSquares += value * value;
    if (value > peak) peak = value;
    if (value >= 0.995) clipped += 1;
  }

  const rms = Math.sqrt(sumSquares / samples.length);
  const clippedRatio = clipped / samples.length;
  const silence = rms < 0.0008 || peak < 0.004;
  const crestDb = rms > 0 ? 20 * Math.log10(Math.max(peak, 1e-12) / rms) : null;
  const snrEstimate = crestDb === null ? null : clamp(crestDb * 1.8, 0, 48);

  let noiseLevel = "low";
  if (silence) noiseLevel = "unknown";
  else if (clippedRatio > 0.015) noiseLevel = "high";
  else if (snrEstimate !== null && snrEstimate < 10) noiseLevel = "noise_only";
  else if (snrEstimate !== null && snrEstimate < 18) noiseLevel = "high";
  else if (snrEstimate !== null && snrEstimate < 28) noiseLevel = "medium";

  return {
    input_level_dbfs: round(dbfs(rms), 3),
    peak_dbfs: round(dbfs(peak), 3),
    clipping: clippedRatio > 0.001,
    clipped_frame_ratio: round(clippedRatio, 5),
    noise_level: noiseLevel,
    snr_estimate_db: snrEstimate === null ? null : round(snrEstimate, 3),
    silence,
    breakdown_likely: !silence && peak > 0.02 && rms < 0.006,
  };
}

function computeOnsetEnvelope(samples, sampleRate, config) {
  const frameSize = Math.max(128, Math.round(config.frameSeconds * sampleRate));
  const hopSize = Math.max(32, Math.round(config.hopSeconds * sampleRate));
  const frameCount = Math.max(0, Math.floor((samples.length - frameSize) / hopSize) + 1);
  const values = new Float32Array(frameCount);
  const energy = new Float32Array(frameCount);

  let previousLogEnergy = null;
  for (let frame = 0; frame < frameCount; frame += 1) {
    const start = frame * hopSize;
    let sumSquares = 0;
    let sumAbsDiff = 0;
    let previous = samples[start] || 0;

    for (let i = 0; i < frameSize; i += 1) {
      const sample = samples[start + i] || 0;
      sumSquares += sample * sample;
      sumAbsDiff += Math.abs(sample - previous);
      previous = sample;
    }

    const rms = Math.sqrt(sumSquares / frameSize);
    const transient = sumAbsDiff / frameSize;
    const logEnergy = Math.log10(1e-9 + rms * rms + transient * 0.35);
    const flux =
      previousLogEnergy === null ? 0 : Math.max(0, logEnergy - previousLogEnergy);

    energy[frame] = rms;
    values[frame] = flux;
    previousLogEnergy = logEnergy;
  }

  removeLocalMean(values, Math.max(3, Math.round((0.12 * sampleRate) / hopSize)));
  halfWave(values);
  const stats = onsetStats(values, energy, hopSize, sampleRate);
  return {
    values,
    rateHz: sampleRate / hopSize,
    hopSize,
    stats,
  };
}

function removeLocalMean(values, radius) {
  if (values.length === 0) return;
  const prefix = new Float64Array(values.length + 1);
  for (let i = 0; i < values.length; i += 1) {
    prefix[i + 1] = prefix[i] + values[i];
  }
  for (let i = 0; i < values.length; i += 1) {
    const start = Math.max(0, i - radius);
    const end = Math.min(values.length, i + radius + 1);
    const mean = (prefix[end] - prefix[start]) / (end - start);
    values[i] -= mean;
  }
}

function halfWave(values) {
  for (let i = 0; i < values.length; i += 1) {
    values[i] = Math.max(0, values[i]);
  }
}

function onsetStats(values, energy, hopSize, sampleRate) {
  if (values.length === 0) {
    return {
      onsetStrength: 0,
      onsetClarity: 0,
      onsetDensityHz: 0,
      energyDropRatio: 0,
    };
  }

  const sorted = Array.from(values).sort((a, b) => a - b);
  const mean = average(sorted);
  const topStart = Math.max(0, Math.floor(sorted.length * 0.9));
  const topMean = average(sorted.slice(topStart));
  const max = sorted[sorted.length - 1] || 0;
  const threshold = Math.max(mean * 2.5, max * 0.18, 1e-5);
  let active = 0;
  for (let i = 0; i < values.length; i += 1) {
    if (values[i] >= threshold) active += 1;
  }

  const durationSec = (values.length * hopSize) / sampleRate;
  const firstEnergy = average(Array.from(energy.slice(0, Math.max(1, energy.length / 3))));
  const lastEnergy = average(Array.from(energy.slice(Math.floor((energy.length * 2) / 3))));
  const clarityRatio = mean > 0 ? topMean / mean : 0;

  return {
    onsetStrength: clamp01(max / 0.08),
    onsetClarity: clamp01((clarityRatio - 1.6) / 7),
    onsetDensityHz: durationSec > 0 ? active / durationSec : 0,
    energyDropRatio: firstEnergy > 0 ? clamp01(1 - lastEnergy / firstEnergy) : 0,
  };
}

function estimateTempoCandidates(envelope, onsetRateHz, config, quality) {
  if (envelope.length < onsetRateHz * 2) {
    return {
      candidates: [],
      peakProminence: 0,
      harmonicAmbiguity: 0,
      rawPeaks: [],
    };
  }

  const minLag = Math.max(1, Math.floor((60 * onsetRateHz) / config.broadBpmMax));
  const maxLag = Math.min(
    envelope.length - 2,
    Math.ceil((60 * onsetRateHz) / config.broadBpmMin),
  );
  if (maxLag <= minLag) {
    return {
      candidates: [],
      peakProminence: 0,
      harmonicAmbiguity: 0,
      rawPeaks: [],
    };
  }

  const acf = new Float32Array(maxLag + 1);
  for (let lag = minLag; lag <= maxLag; lag += 1) {
    acf[lag] = normalizedAutocorrelation(envelope, lag);
  }

  const rawPeaks = [];
  for (let lag = minLag + 1; lag < maxLag; lag += 1) {
    if (acf[lag] >= acf[lag - 1] && acf[lag] >= acf[lag + 1] && acf[lag] > 0.04) {
      const lagEstimate = parabolicLag(acf, lag);
      rawPeaks.push({
        bpm: (60 * onsetRateHz) / lagEstimate,
        lag,
        rawScore: acf[lag],
      });
    }
  }

  rawPeaks.sort((a, b) => b.rawScore - a.rawScore);
  const keptRawPeaks = dedupePeaks(rawPeaks, 1.2).slice(0, 10);
  const maxRaw = keptRawPeaks[0]?.rawScore || 0;
  const acfValues = [];
  for (let lag = minLag; lag <= maxLag; lag += 1) acfValues.push(acf[lag]);
  const medianAcf = percentile(acfValues, 0.5);
  const peakProminence = maxRaw > 0 ? clamp01((maxRaw - medianAcf) / maxRaw) : 0;

  const candidates = expandAndScoreCandidates({
    rawPeaks: keptRawPeaks,
    maxRaw,
    acf,
    onsetRateHz,
    config,
    quality,
    peakProminence,
  });

  const harmonicAmbiguity = candidates.length > 1
    ? clamp01(candidates[1].score / Math.max(candidates[0].score, 1e-9))
    : 0;

  return {
    candidates,
    peakProminence,
    harmonicAmbiguity,
    rawPeaks: keptRawPeaks,
  };
}

function normalizedAutocorrelation(values, lag) {
  let sum = 0;
  let leftEnergy = 0;
  let rightEnergy = 0;
  for (let i = lag; i < values.length; i += 1) {
    const left = values[i];
    const right = values[i - lag];
    sum += left * right;
    leftEnergy += left * left;
    rightEnergy += right * right;
  }
  const denom = Math.sqrt(leftEnergy * rightEnergy);
  return denom > 0 ? sum / denom : 0;
}

function parabolicLag(acf, lag) {
  const y0 = acf[lag - 1] || 0;
  const y1 = acf[lag] || 0;
  const y2 = acf[lag + 1] || 0;
  const denom = y0 - 2 * y1 + y2;
  if (Math.abs(denom) < 1e-9) return lag;
  return lag + clamp(0.5 * (y0 - y2) / denom, -0.5, 0.5);
}

function dedupePeaks(peaks, bpmTolerance) {
  const kept = [];
  for (const peak of peaks) {
    if (!kept.some((existing) => Math.abs(existing.bpm - peak.bpm) <= bpmTolerance)) {
      kept.push(peak);
    }
  }
  return kept;
}

function expandAndScoreCandidates({
  rawPeaks,
  maxRaw,
  acf,
  onsetRateHz,
  config,
  quality,
  peakProminence,
}) {
  const expanded = [];
  const signalQuality = signalQualityScore(quality);
  const rawLookup = new Map();
  for (const peak of rawPeaks) {
    rawLookup.set(Math.round(peak.bpm), peak.rawScore / Math.max(maxRaw, 1e-9));
  }

  for (const peak of rawPeaks) {
    const normalizedRawScore = peak.rawScore / Math.max(maxRaw, 1e-9);
    const rawRelation = inTargetRange(peak.bpm, config) ? "main" : "raw";
    expanded.push(
      makeCandidate({
        bpm: peak.bpm,
        relation: rawRelation,
        sourceBpm: undefined,
        rawScore: normalizedRawScore,
        acf,
        onsetRateHz,
        config,
        quality,
        peakProminence,
        signalQuality,
      }),
    );

    if (peak.bpm < 130) {
      expanded.push(
        makeCandidate({
          bpm: peak.bpm * 2,
          relation: "normalized_from_half",
          sourceBpm: peak.bpm,
          rawScore: normalizedRawScore * 0.98,
          acf,
          onsetRateHz,
          config,
          quality,
          peakProminence,
          signalQuality,
        }),
      );
    }

    if (peak.bpm > 260) {
      expanded.push(
        makeCandidate({
          bpm: peak.bpm / 2,
          relation: "normalized_from_double",
          sourceBpm: peak.bpm,
          rawScore: normalizedRawScore * 0.98,
          acf,
          onsetRateHz,
          config,
          quality,
          peakProminence,
          signalQuality,
        }),
      );
    }

    if (inTargetRange(peak.bpm, config)) {
      const half = peak.bpm / 2;
      const double = peak.bpm * 2;
      if (half >= config.broadBpmMin) {
        expanded.push(
          makeCandidate({
            bpm: half,
            relation: "half_time",
            sourceBpm: peak.bpm,
            rawScore: normalizedRawScore * 0.68,
            acf,
            onsetRateHz,
            config,
            quality,
            peakProminence,
            signalQuality,
          }),
        );
      }
      if (double <= config.broadBpmMax) {
        expanded.push(
          makeCandidate({
            bpm: double,
            relation: "double_time",
            sourceBpm: peak.bpm,
            rawScore: normalizedRawScore * 0.62,
            acf,
            onsetRateHz,
            config,
            quality,
            peakProminence,
            signalQuality,
          }),
        );
      }
    }
  }

  return dedupeCandidates(expanded)
    .sort((a, b) => b.score - a.score)
    .slice(0, 12);
}

function makeCandidate({
  bpm,
  relation,
  sourceBpm,
  rawScore,
  acf,
  onsetRateHz,
  config,
  quality,
  peakProminence,
  signalQuality,
}) {
  const range = rangeScore(bpm, config);
  const harmonicSupportScore = harmonicSupport(bpm, acf, onsetRateHz);
  const recentStability = 1;
  const onsetClarity = quality.silence ? 0 : 0.88;
  let score =
    0.4 * rawScore +
    0.14 * peakProminence +
    0.1 * harmonicSupportScore +
    0.23 * range +
    0.08 * signalQuality;

  if (relation === "normalized_from_half" || relation === "normalized_from_double") {
    score += 0.015 * range;
  }
  if (relation === "half_time" || relation === "double_time") {
    score *= 0.82;
  }
  score *= signalQuality;

  return {
    bpm: round(bpm, 3),
    relation,
    score: round(clamp01(score), 4),
    raw_score: round(clamp01(rawScore), 4),
    stability_score: recentStability,
    range_score: round(range, 4),
    ...(sourceBpm === undefined ? {} : { source_bpm: round(sourceBpm, 3) }),
    confidence_factors: {
      onset_clarity: round(onsetClarity, 4),
      peak_prominence: round(peakProminence, 4),
      harmonic_support: round(harmonicSupportScore, 4),
      recent_stability: recentStability,
      signal_quality: round(signalQuality, 4),
    },
  };
}

function dedupeCandidates(candidates) {
  const best = new Map();
  for (const candidate of candidates) {
    const key = `${candidate.relation}:${Math.round(candidate.bpm * 10) / 10}`;
    const current = best.get(key);
    if (!current || candidate.score > current.score) best.set(key, candidate);
  }
  return Array.from(best.values());
}

function harmonicSupport(bpm, acf, onsetRateHz) {
  const direct = acfAtBpm(bpm, acf, onsetRateHz);
  const half = acfAtBpm(bpm / 2, acf, onsetRateHz);
  const double = acfAtBpm(bpm * 2, acf, onsetRateHz);
  return clamp01(0.55 * direct + 0.25 * half + 0.2 * double);
}

function acfAtBpm(bpm, acf, onsetRateHz) {
  if (bpm <= 0) return 0;
  const lag = Math.round((60 * onsetRateHz) / bpm);
  if (lag < 0 || lag >= acf.length) return 0;
  return acf[lag] || 0;
}

function rangeScore(bpm, config) {
  if (bpm >= config.targetBpmMin && bpm <= config.targetBpmMax) return 1;
  const nearest =
    bpm < config.targetBpmMin ? config.targetBpmMin : config.targetBpmMax;
  const distance = Math.abs(bpm - nearest);
  return clamp01(1 - distance / 120);
}

function inTargetRange(bpm, config) {
  return bpm >= config.targetBpmMin && bpm <= config.targetBpmMax;
}

function signalQualityScore(quality) {
  if (quality.silence) return 0;
  if (quality.clipped_frame_ratio > 0.015) return 0.28;
  if (quality.noise_level === "noise_only") return 0.2;
  if (quality.noise_level === "high") return 0.62;
  if (quality.noise_level === "medium") return 0.82;
  return 1;
}

function classifyLockState({
  quality,
  envelope,
  tempo,
  primary,
  confidence,
  analysisTimeSec,
  cfg,
}) {
  if (quality.silence) return "SEARCHING";
  if (quality.clipped_frame_ratio > 0.015) return "CLIPPED_MIC";
  if (quality.breakdown_likely || envelope.stats.energyDropRatio > 0.86) {
    return "BREAKDOWN";
  }
  if (!primary || tempo.peakProminence < 0.12 || envelope.stats.onsetClarity < 0.08) {
    return "NOISE_ONLY";
  }
  if (confidence >= cfg.stableConfidence && analysisTimeSec >= cfg.stableMinSeconds) {
    return "STABLE";
  }
  if (confidence >= cfg.lockConfidence && analysisTimeSec >= cfg.lockMinSeconds) {
    return "LOCKING";
  }
  return analysisTimeSec >= cfg.lockMinSeconds ? "UNSTABLE" : "SEARCHING";
}

function buildWarnings(quality, envelope, tempo) {
  const warnings = [];
  if (quality.silence) warnings.push("silence");
  if (quality.clipping) warnings.push("clipping_detected");
  if (quality.noise_level === "noise_only") warnings.push("noise_only_level");
  if (quality.noise_level === "high") warnings.push("high_noise");
  if (quality.breakdown_likely || envelope.stats.energyDropRatio > 0.86) {
    warnings.push("breakdown_likely");
  }
  if (tempo.harmonicAmbiguity > 0.88) warnings.push("harmonic_ambiguity");
  if (tempo.peakProminence < 0.18) warnings.push("weak_tempo_peak");
  return warnings;
}

function dbfs(value) {
  if (value <= 0) return -Infinity;
  return 20 * Math.log10(Math.min(1, value));
}

function average(values) {
  if (values.length === 0) return 0;
  let sum = 0;
  for (const value of values) sum += value;
  return sum / values.length;
}

function percentile(values, position) {
  if (values.length === 0) return 0;
  const sorted = Array.from(values).sort((a, b) => a - b);
  const index = clamp(Math.floor(position * (sorted.length - 1)), 0, sorted.length - 1);
  return sorted[index];
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function clamp01(value) {
  return clamp(value, 0, 1);
}

function round(value, decimals) {
  if (!Number.isFinite(value)) return value;
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

module.exports = {
  DEFAULT_CONFIG,
  DspEngine,
  analyzePcm,
  computeOnsetEnvelope,
  estimateTempoCandidates,
  analyzeSignalQuality,
  resampleLinear,
};
