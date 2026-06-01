// hitech-bpm-ffi public C ABI.
//
// This header is the single source of truth for `ffigen` (Dart) and any
// native consumer. Symbols are implemented in `core/ffi/src/lib.rs` and
// exported from the cdylib `libhitech_bpm_ffi.{dylib,so,dll}`.
//
// Lifetime contract:
//   - `hitech_bpm_engine_new` returns an opaque handle or NULL on alloc
//     failure.
//   - The handle must eventually be released with
//     `hitech_bpm_engine_free`. Passing NULL is a no-op.
//   - `hitech_bpm_engine_push_samples` is the audio-thread ingress; it
//     is allocation-light and returns `false` on invalid input
//     (null handle, null pointer, zero length, zero sample rate).
//   - `hitech_bpm_engine_analyze_json` allocates a NUL-terminated UTF-8
//     buffer the caller owns. Release it with `hitech_bpm_string_free`.
//     Recommended poll rate ~10-30 Hz; do NOT call from the audio thread.
//
// BPM math stays inside the Rust DSP crate. This boundary only moves
// PCM in and JSON snapshots out.

#ifndef HITECH_BPM_FFI_H
#define HITECH_BPM_FFI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HitechBpmEngine HitechBpmEngine;

HitechBpmEngine *hitech_bpm_engine_new(void);
HitechBpmEngine *hitech_bpm_engine_new_with_min_bpm(float min_bpm);
void hitech_bpm_engine_free(HitechBpmEngine *engine);
void hitech_bpm_engine_reset(HitechBpmEngine *engine);

bool hitech_bpm_engine_push_samples(HitechBpmEngine *engine,
                                    const float *samples,
                                    size_t len,
                                    uint32_t sample_rate);

char *hitech_bpm_engine_analyze_json(HitechBpmEngine *engine);
void hitech_bpm_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif  // HITECH_BPM_FFI_H
