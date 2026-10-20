// A program of WebGL 2 — a vertex and a fragment shader in GLSL ES 3.00 — made over for Metal,
// with glslang (GLSL to SPIR-V) and SPIRV-Cross (SPIR-V to Metal Shading Language).
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

/// A JSON text, to be freed with free(): {"error": text} or the two stages in Metal Shading
/// Language with where each uniform, texture and vertex input ends up:
/// {"vertex", "fragment", "inputs": [{name, location}], "vertexUniforms" / "fragmentUniforms":
/// [{name, offset, size, arrayStride, matrixStride, columns, vecsize, count, basetype}],
/// "vertexBuffer", "fragmentBuffer", "textures" / "vertexTextures": [{name, texture, sampler}]}.
char *shader_translate(const char *vertex, const char *fragment);

/// Whether one shader compiles by itself: NULL if it does, else what the compiler says of it, in
/// the form browsers give it ("ERROR: 0:line: …"), to be freed with free().
char *shader_check(int fragment, const char *source);

#ifdef __cplusplus
}
#endif
