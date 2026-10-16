// The VP9 and Opus encoders of libWallAeroCodecs.dylib (scripts/codecs.sh), loaded when first
// needed so the app builds and runs without the library.
#ifndef CCODECS_H
#define CCODECS_H

#include <stddef.h>
#include <stdint.h>

/// Loads the library from `path`; returns 1 when its encoders are there. May be called again.
int wa_codecs_load(const char *path);

typedef struct WAVideoEncoder WAVideoEncoder;

/// A VP9 encoder for pictures of `width`×`height`, with times in milliseconds. `quality` runs
/// from 0 (smallest) to 63; about 30 looks like the source. Returns NULL when it cannot be made.
/// `bt709` marks the colors as HD video's (else standard definition's), `fullRange` as using
/// every value rather than video's 16–235.
WAVideoEncoder *wa_vp9_create(int width, int height, double framesPerSecond, int quality, int threads, int bt709,
                              int fullRange);
/// Encodes one picture in I420 (planes of Y, U and V); `keyframe` forces a picture that needs
/// no other. The packets made are read with `wa_vp9_packet`. Returns 0 when all is well.
int wa_vp9_encode(WAVideoEncoder *encoder,
                  const uint8_t *y, int yStride, const uint8_t *u, int uStride, const uint8_t *v, int vStride,
                  int64_t time, int64_t duration, int keyframe);
/// Encodes what is left; the packets are read with `wa_vp9_packet`.
int wa_vp9_finish(WAVideoEncoder *encoder);
/// The next packet made, if any: returns 1 and points `data` at it until the next call.
int wa_vp9_packet(WAVideoEncoder *encoder, const uint8_t **data, size_t *size, int64_t *time, int *keyframe);
void wa_vp9_destroy(WAVideoEncoder *encoder);

typedef struct WAAudioEncoder WAAudioEncoder;

/// An Opus encoder for 48 kHz sound in `channels` (1 or 2) at `bitrate` bits a second.
/// `preSkip` is set to the samples a player leaves out at the start.
WAAudioEncoder *wa_opus_create(int channels, int bitrate, int *preSkip);
/// Encodes 960 samples (20 ms) for each channel, interleaved; returns the bytes written to
/// `output`, or a negative number on failure.
int wa_opus_encode(WAAudioEncoder *encoder, const float *samples, uint8_t *output, int capacity);
void wa_opus_destroy(WAAudioEncoder *encoder);

#endif
