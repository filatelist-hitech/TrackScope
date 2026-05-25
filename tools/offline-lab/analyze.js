#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { analyzePcm } = require("../../core/dsp");

function main(argv) {
  const args = parseArgs(argv);
  if (args.help || !args.input) {
    printUsage();
    process.exit(args.help ? 0 : 1);
  }

  const audio = args.raw
    ? decodeRawPcm(fs.readFileSync(args.input), args)
    : decodeWav(fs.readFileSync(args.input));
  const result = analyzePcm(audio.samples, audio.sampleRate, {
    sampleRate: Number(args.dspRate || 44100),
  });

  if (args.json) {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return;
  }

  printHumanReport(args.input, result);
}

function parseArgs(argv) {
  const parsed = {
    channels: 1,
    format: "f32le",
    sampleRate: 44100,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") parsed.help = true;
    else if (arg === "--json") parsed.json = true;
    else if (arg === "--raw") parsed.raw = true;
    else if (arg === "--sample-rate") parsed.sampleRate = Number(argv[++i]);
    else if (arg === "--channels") parsed.channels = Number(argv[++i]);
    else if (arg === "--format") parsed.format = argv[++i];
    else if (arg === "--dsp-rate") parsed.dspRate = Number(argv[++i]);
    else if (!parsed.input) parsed.input = arg;
    else throw new Error(`unexpected argument: ${arg}`);
  }
  return parsed;
}

function printUsage() {
  process.stdout.write(`Usage:
  node tools/offline-lab/analyze.js <file.wav> [--json]
  node tools/offline-lab/analyze.js <file.pcm> --raw --sample-rate 44100 --channels 1 --format f32le [--json]

Formats:
  WAV: PCM 16/24/32-bit integer or 32-bit float
  RAW: f32le or s16le interleaved PCM
`);
}

function printHumanReport(input, result) {
  process.stdout.write(`Offline tempo report: ${path.basename(input)}
primary_bpm: ${result.primary_bpm === null ? "null" : result.primary_bpm}
confidence: ${result.confidence}
lock_state: ${result.lock_state}
input_level_dbfs: ${result.signal_quality.input_level_dbfs}
clipping: ${result.signal_quality.clipping}
noise_level: ${result.signal_quality.noise_level}
candidates:
`);
  for (const candidate of result.candidates) {
    process.stdout.write(
      `  - ${candidate.bpm} BPM ${candidate.relation} score=${candidate.score} raw=${candidate.raw_score} range=${candidate.range_score}\n`,
    );
  }
}

function decodeRawPcm(buffer, options) {
  const channels = Number(options.channels || 1);
  const sampleRate = Number(options.sampleRate || 44100);
  const format = options.format || "f32le";
  if (!Number.isFinite(channels) || channels < 1) {
    throw new Error("raw PCM channels must be positive");
  }

  let frameCount;
  let readSample;
  if (format === "f32le") {
    frameCount = Math.floor(buffer.length / 4 / channels);
    readSample = (offset) => buffer.readFloatLE(offset);
  } else if (format === "s16le") {
    frameCount = Math.floor(buffer.length / 2 / channels);
    readSample = (offset) => buffer.readInt16LE(offset) / 32768;
  } else {
    throw new Error(`unsupported raw format: ${format}`);
  }

  const bytesPerSample = format === "f32le" ? 4 : 2;
  const samples = new Float32Array(frameCount);
  for (let frame = 0; frame < frameCount; frame += 1) {
    let sum = 0;
    for (let channel = 0; channel < channels; channel += 1) {
      sum += readSample((frame * channels + channel) * bytesPerSample);
    }
    samples[frame] = sum / channels;
  }
  return { samples, sampleRate };
}

function decodeWav(buffer) {
  if (buffer.toString("ascii", 0, 4) !== "RIFF" || buffer.toString("ascii", 8, 12) !== "WAVE") {
    throw new Error("input is not a RIFF/WAVE file; use --raw for raw PCM");
  }

  let offset = 12;
  let fmt = null;
  let data = null;
  while (offset + 8 <= buffer.length) {
    const id = buffer.toString("ascii", offset, offset + 4);
    const size = buffer.readUInt32LE(offset + 4);
    const start = offset + 8;
    const end = start + size;
    if (id === "fmt ") {
      fmt = {
        audioFormat: buffer.readUInt16LE(start),
        channels: buffer.readUInt16LE(start + 2),
        sampleRate: buffer.readUInt32LE(start + 4),
        bitsPerSample: buffer.readUInt16LE(start + 14),
      };
    } else if (id === "data") {
      data = buffer.slice(start, end);
    }
    offset = end + (size % 2);
  }

  if (!fmt || !data) {
    throw new Error("WAV file must contain fmt and data chunks");
  }
  if (fmt.channels < 1) {
    throw new Error("WAV file has no channels");
  }

  const bytesPerSample = fmt.bitsPerSample / 8;
  const frameCount = Math.floor(data.length / bytesPerSample / fmt.channels);
  const samples = new Float32Array(frameCount);
  for (let frame = 0; frame < frameCount; frame += 1) {
    let sum = 0;
    for (let channel = 0; channel < fmt.channels; channel += 1) {
      const sampleOffset = (frame * fmt.channels + channel) * bytesPerSample;
      sum += readWavSample(data, sampleOffset, fmt.audioFormat, fmt.bitsPerSample);
    }
    samples[frame] = sum / fmt.channels;
  }
  return { samples, sampleRate: fmt.sampleRate };
}

function readWavSample(buffer, offset, audioFormat, bitsPerSample) {
  if (audioFormat === 3 && bitsPerSample === 32) {
    return buffer.readFloatLE(offset);
  }
  if (audioFormat !== 1) {
    throw new Error(`unsupported WAV audio format: ${audioFormat}`);
  }
  if (bitsPerSample === 16) {
    return buffer.readInt16LE(offset) / 32768;
  }
  if (bitsPerSample === 24) {
    const value = buffer.readIntLE(offset, 3);
    return value / 8388608;
  }
  if (bitsPerSample === 32) {
    return buffer.readInt32LE(offset) / 2147483648;
  }
  throw new Error(`unsupported WAV bit depth: ${bitsPerSample}`);
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
  }
}

module.exports = {
  decodeRawPcm,
  decodeWav,
};
