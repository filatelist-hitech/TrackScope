---
name: qa-audio-dataset
description: Use when creating synthetic audio fixtures, test datasets, BPM accuracy tests, regression cases, and QA reports.
---

# QA Audio Dataset Skill

Use this workflow for audio QA.

Required fixtures:

- clean click tracks
- kick-like synthetic pulses
- noisy club-like input
- clipped microphone input
- silence
- breakdown sections
- half-time trap
- double-time trap

Required report:

- expected BPM
- detected BPM
- error in BPM
- confidence
- lock state
- pass/fail
- notes

Acceptance targets:

- clean synthetic: ±1 BPM
- noisy mic: ±2–4 BPM
- no false STABLE on silence/noise