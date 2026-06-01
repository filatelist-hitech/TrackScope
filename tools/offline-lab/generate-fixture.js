#!/usr/bin/env node
"use strict";

const fs = require("node:fs");

function main(argv) {
  const args = parseArgs(argv);
  if (args.help || !args.output) {
    printUsage();
    process.exit(args.help ? 0 : 1);
  }

  const sampleRate = Number(args.sampleRate || 44100);
  const duration = Number(args.duration || 12);
  const bpm = Number(args.bpm || 200);
  const samples = generatePulseTrain({
    bpm,
    duration,
    sampleRate,
    noise: Number(args.noise || 0),
    clipped: Boolean(args.clipped),
    silence: Boolean(args.silence),
  });

  fs.writeFileSync(args.output, encodeWavMono16(samples, sampleRate));
}

function parseArgs(argv) {
  const parsed = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help" || arg === "-h") parsed.help = true;
    else if (arg === "--bpm") parsed.bpm = Number(argv[++i]);
    else if (arg === "--duration") parsed.duration = Number(argv[++i]);
    else if (arg === "--sample-rate") parsed.sampleRate = Number(argv[++i]);
    else if (arg === "--noise") parsed.noise = Number(argv[++i]);
    else if (arg === "--clipped") parsed.clipped = true;
    else if (arg === "--silence") parsed.silence = true;
    else if (!parsed.output) parsed.output = arg;
    else throw new Error(`unexpected argument: ${arg}`);
  }
  return parsed;
}

function printUsage() {
  process.stdout.write(`Usage:
  node tools/offline-lab/generate-fixture.js <out.wav> --bpm 200 [--duration 12] [--noise 0.05] [--clipped]
`);
}

function generatePulseTrain({
  bpm,
  duration = 12,
  sampleRate = 44100,
  noise = 0,
  clipped = false,
  silence = false,
}) {
  const samples = new Float32Array(Math.floor(duration * sampleRate));
  if (silence) return samples;

  const period = 60 / bpm;
  const pulseLength = Math.floor(0.045 * sampleRate);
  let seed = 0xdecafbad;

  for (let beatTime = 0; beatTime < duration; beatTime += period) {
    const start = Math.round(beatTime * sampleRate);
    for (let i = 0; i < pulseLength && start + i < samples.length; i += 1) {
      const t = i / sampleRate;
      const decay = Math.exp(-t * 85);
      const body = Math.sin(2 * Math.PI * 58 * t) * decay;
      const click = i < 14 ? 0.7 * (1 - i / 14) : 0;
      samples[start + i] += 0.82 * body + click;
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

function encodeWavMono16(samples, sampleRate) {
  const dataSize = samples.length * 2;
  const buffer = Buffer.alloc(44 + dataSize);
  buffer.write("RIFF", 0, "ascii");
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write("WAVE", 8, "ascii");
  buffer.write("fmt ", 12, "ascii");
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write("data", 36, "ascii");
  buffer.writeUInt32LE(dataSize, 40);
  for (let i = 0; i < samples.length; i += 1) {
    const value = Math.max(-1, Math.min(1, samples[i]));
    buffer.writeInt16LE(Math.round(value * 32767), 44 + i * 2);
  }
  return buffer;
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
  encodeWavMono16,
  generatePulseTrain,
};
