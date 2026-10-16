#include "CCodecs.h"

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

#include "opus/opus.h"
#include "vpx/vp8cx.h"
#include "vpx/vpx_encoder.h"

// MARK: - Loading

static struct {
  int loaded;
  vpx_codec_iface_t *(*vp9_cx)(void);
  vpx_codec_err_t (*enc_config_default)(vpx_codec_iface_t *, vpx_codec_enc_cfg_t *, unsigned int);
  vpx_codec_err_t (*enc_init_ver)(vpx_codec_ctx_t *, vpx_codec_iface_t *, const vpx_codec_enc_cfg_t *, vpx_codec_flags_t, int);
  vpx_codec_err_t (*encode)(vpx_codec_ctx_t *, const vpx_image_t *, vpx_codec_pts_t, unsigned long, vpx_enc_frame_flags_t,
                            vpx_enc_deadline_t);
  const vpx_codec_cx_pkt_t *(*get_cx_data)(vpx_codec_ctx_t *, vpx_codec_iter_t *);
  vpx_codec_err_t (*control_)(vpx_codec_ctx_t *, int, ...);
  vpx_codec_err_t (*destroy)(vpx_codec_ctx_t *);
  vpx_image_t *(*img_wrap)(vpx_image_t *, vpx_img_fmt_t, unsigned int, unsigned int, unsigned int, unsigned char *);
  OpusEncoder *(*opus_create)(opus_int32, int, int, int *);
  opus_int32 (*opus_encode_float)(OpusEncoder *, const float *, int, unsigned char *, opus_int32);
  int (*opus_ctl)(OpusEncoder *, int, ...);
  void (*opus_destroy)(OpusEncoder *);
} codecs;

int wa_codecs_load(const char *path) {
  if (codecs.loaded) {
    return 1;
  }
  void *library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    return 0;
  }
#define FIND(field, name)                         \
  *(void **)(&codecs.field) = dlsym(library, name); \
  if (!codecs.field) return 0;
  FIND(vp9_cx, "vpx_codec_vp9_cx")
  FIND(enc_config_default, "vpx_codec_enc_config_default")
  FIND(enc_init_ver, "vpx_codec_enc_init_ver")
  FIND(encode, "vpx_codec_encode")
  FIND(get_cx_data, "vpx_codec_get_cx_data")
  FIND(control_, "vpx_codec_control_")
  FIND(destroy, "vpx_codec_destroy")
  FIND(img_wrap, "vpx_img_wrap")
  FIND(opus_create, "opus_encoder_create")
  FIND(opus_encode_float, "opus_encode_float")
  FIND(opus_ctl, "opus_encoder_ctl")
  FIND(opus_destroy, "opus_encoder_destroy")
#undef FIND
  codecs.loaded = 1;
  return 1;
}

// MARK: - VP9

typedef struct {
  uint8_t *data;
  size_t size;
  int64_t time;
  int keyframe;
} Packet;

struct WAVideoEncoder {
  vpx_codec_ctx_t codec;
  int width, height;
  Packet *packets;
  size_t count, capacity, next;
  uint8_t *held;  // the packet last handed out
};

WAVideoEncoder *wa_vp9_create(int width, int height, double framesPerSecond, int quality, int threads, int bt709,
                              int fullRange) {
  if (!codecs.loaded || width < 2 || height < 2) {
    return NULL;
  }
  vpx_codec_iface_t *iface = codecs.vp9_cx();
  vpx_codec_enc_cfg_t config;
  if (codecs.enc_config_default(iface, &config, 0) != VPX_CODEC_OK) {
    return NULL;
  }
  config.g_w = (unsigned int)width;
  config.g_h = (unsigned int)height;
  config.g_timebase.num = 1;
  config.g_timebase.den = 1000;
  config.g_threads = (unsigned int)(threads > 0 ? threads : 4);
  config.g_lag_in_frames = 16;
  // Constant quality, with a ceiling on the rate that leaves fast scenes some room.
  config.rc_end_usage = VPX_CQ;
  double pixels = (double)width * height;
  double fps = framesPerSecond > 1 ? framesPerSecond : 30;
  config.rc_target_bitrate = (unsigned int)(pixels * fps * 0.12 / 1000);
  config.rc_min_quantizer = 0;
  config.rc_max_quantizer = 63;
  // A picture that needs no other at least every two seconds, so a video can start anywhere.
  config.kf_mode = VPX_KF_AUTO;
  config.kf_max_dist = (unsigned int)(fps * 2);
  WAVideoEncoder *encoder = calloc(1, sizeof(WAVideoEncoder));
  if (!encoder) {
    return NULL;
  }
  if (codecs.enc_init_ver(&encoder->codec, iface, &config, 0, VPX_ENCODER_ABI_VERSION) != VPX_CODEC_OK) {
    free(encoder);
    return NULL;
  }
  encoder->width = width;
  encoder->height = height;
  int tiles = width >= 3200 ? 3 : width >= 1600 ? 2 : width >= 800 ? 1 : 0;
  codecs.control_(&encoder->codec, VP8E_SET_CPUUSED, 4);
  codecs.control_(&encoder->codec, VP8E_SET_CQ_LEVEL, quality);
  codecs.control_(&encoder->codec, VP9E_SET_ROW_MT, 1);
  codecs.control_(&encoder->codec, VP9E_SET_TILE_COLUMNS, tiles);
  codecs.control_(&encoder->codec, VP9E_SET_FRAME_PARALLEL_DECODING, 1);
  codecs.control_(&encoder->codec, VP8E_SET_ENABLEAUTOALTREF, 1);
  codecs.control_(&encoder->codec, VP9E_SET_COLOR_SPACE, bt709 ? VPX_CS_BT_709 : VPX_CS_BT_601);
  codecs.control_(&encoder->codec, VP9E_SET_COLOR_RANGE, fullRange ? VPX_CR_FULL_RANGE : VPX_CR_STUDIO_RANGE);
  return encoder;
}

static int collect(WAVideoEncoder *encoder) {
  vpx_codec_iter_t iterator = NULL;
  const vpx_codec_cx_pkt_t *packet;
  while ((packet = codecs.get_cx_data(&encoder->codec, &iterator))) {
    if (packet->kind != VPX_CODEC_CX_FRAME_PKT) {
      continue;
    }
    if (encoder->count == encoder->capacity) {
      size_t capacity = encoder->capacity ? encoder->capacity * 2 : 16;
      Packet *grown = realloc(encoder->packets, capacity * sizeof(Packet));
      if (!grown) return -1;
      encoder->packets = grown;
      encoder->capacity = capacity;
    }
    Packet *kept = &encoder->packets[encoder->count++];
    kept->size = packet->data.frame.sz;
    kept->data = malloc(kept->size);
    if (!kept->data) return -1;
    memcpy(kept->data, packet->data.frame.buf, kept->size);
    kept->time = packet->data.frame.pts;
    kept->keyframe = (packet->data.frame.flags & VPX_FRAME_IS_KEY) != 0;
  }
  return 0;
}

int wa_vp9_encode(WAVideoEncoder *encoder,
                  const uint8_t *y, int yStride, const uint8_t *u, int uStride, const uint8_t *v, int vStride,
                  int64_t time, int64_t duration, int keyframe) {
  vpx_image_t image;
  if (!codecs.img_wrap(&image, VPX_IMG_FMT_I420, (unsigned int)encoder->width, (unsigned int)encoder->height, 1,
                       (unsigned char *)y)) {
    return -1;
  }
  image.planes[VPX_PLANE_Y] = (unsigned char *)y;
  image.planes[VPX_PLANE_U] = (unsigned char *)u;
  image.planes[VPX_PLANE_V] = (unsigned char *)v;
  image.stride[VPX_PLANE_Y] = yStride;
  image.stride[VPX_PLANE_U] = uStride;
  image.stride[VPX_PLANE_V] = vStride;
  vpx_enc_frame_flags_t flags = keyframe ? VPX_EFLAG_FORCE_KF : 0;
  if (codecs.encode(&encoder->codec, &image, time, (unsigned long)(duration > 0 ? duration : 1), flags, VPX_DL_GOOD_QUALITY) !=
      VPX_CODEC_OK) {
    return -1;
  }
  return collect(encoder);
}

int wa_vp9_finish(WAVideoEncoder *encoder) {
  for (int round = 0; round < 64; round++) {
    size_t before = encoder->count;
    if (codecs.encode(&encoder->codec, NULL, 0, 1, 0, VPX_DL_GOOD_QUALITY) != VPX_CODEC_OK) return -1;
    if (collect(encoder) != 0) return -1;
    if (encoder->count == before) break;
  }
  return 0;
}

int wa_vp9_packet(WAVideoEncoder *encoder, const uint8_t **data, size_t *size, int64_t *time, int *keyframe) {
  free(encoder->held);
  encoder->held = NULL;
  if (encoder->next >= encoder->count) {
    encoder->next = encoder->count = 0;
    return 0;
  }
  Packet *packet = &encoder->packets[encoder->next++];
  encoder->held = packet->data;
  *data = packet->data;
  *size = packet->size;
  *time = packet->time;
  *keyframe = packet->keyframe;
  return 1;
}

void wa_vp9_destroy(WAVideoEncoder *encoder) {
  if (!encoder) return;
  codecs.destroy(&encoder->codec);
  free(encoder->held);
  for (size_t i = encoder->next; i < encoder->count; i++) free(encoder->packets[i].data);
  free(encoder->packets);
  free(encoder);
}

// MARK: - Opus

struct WAAudioEncoder {
  OpusEncoder *opus;
  int channels;
};

WAAudioEncoder *wa_opus_create(int channels, int bitrate, int *preSkip) {
  if (!codecs.loaded || channels < 1 || channels > 2) {
    return NULL;
  }
  int error = 0;
  OpusEncoder *opus = codecs.opus_create(48000, channels, OPUS_APPLICATION_AUDIO, &error);
  if (!opus || error != OPUS_OK) {
    return NULL;
  }
  codecs.opus_ctl(opus, OPUS_SET_BITRATE(bitrate));
  opus_int32 lookahead = 0;
  codecs.opus_ctl(opus, OPUS_GET_LOOKAHEAD(&lookahead));
  if (preSkip) *preSkip = lookahead;
  WAAudioEncoder *encoder = calloc(1, sizeof(WAAudioEncoder));
  if (!encoder) {
    codecs.opus_destroy(opus);
    return NULL;
  }
  encoder->opus = opus;
  encoder->channels = channels;
  return encoder;
}

int wa_opus_encode(WAAudioEncoder *encoder, const float *samples, uint8_t *output, int capacity) {
  return codecs.opus_encode_float(encoder->opus, samples, 960, output, capacity);
}

void wa_opus_destroy(WAAudioEncoder *encoder) {
  if (!encoder) return;
  codecs.opus_destroy(encoder->opus);
  free(encoder);
}
