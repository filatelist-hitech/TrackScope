# tools/offline-lab

Offline analyzer and fixture generator boundary.

The offline lab must feed audio into the same `core/dsp` engine used by mobile. It may decode files, generate fixtures, and write reports, but it must not implement a separate BPM detector.
