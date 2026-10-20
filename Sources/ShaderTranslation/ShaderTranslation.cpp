// glslang turns the two GLSL ES 3.00 shaders, linked together so that what one hands the other
// is found in the same place, into SPIR-V; SPIRV-Cross turns that into Metal Shading Language
// and says where each uniform, texture and input ends up.
#include "ShaderTranslation.h"
#include <glslang/Public/ShaderLang.h>
#include <glslang/Public/ResourceLimits.h>
#include <SPIRV/GlslangToSpv.h>
#include "spirv_msl.hpp"
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

namespace {

std::string escaped(const std::string &text) {
  std::string out;
  for (char c : text) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': break;
      case '\t': out += "\\t"; break;
      default:
        if ((unsigned char)c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); out += b; } else out += c;
    }
  }
  return out;
}

char *result(const std::string &json) {
  char *copy = (char *)malloc(json.size() + 1);
  memcpy(copy, json.c_str(), json.size() + 1);
  return copy;
}

char *failure(const std::string &message) { return result("{\"error\":\"" + escaped(message) + "\"}"); }

bool initialized = false;

// The uniforms of a stage's default block: name, offset, size, and the stride of an array.
std::string uniformsOf(spirv_cross::CompilerMSL &msl, std::string &bufferIndex) {
  std::ostringstream out;
  out << "[";
  auto resources = msl.get_shader_resources();
  bool first = true;
  bufferIndex = "-1";
  for (auto &block : resources.uniform_buffers) {
    uint32_t index = msl.get_automatic_msl_resource_binding(block.id);
    bufferIndex = std::to_string(index);
    const auto &type = msl.get_type(block.base_type_id);
    for (uint32_t member = 0; member < type.member_types.size(); member++) {
      const auto &memberType = msl.get_type(type.member_types[member]);
      std::string name = msl.get_member_name(block.base_type_id, member);
      uint32_t offset = msl.type_struct_member_offset(type, member);
      size_t size = msl.get_declared_struct_member_size(type, member);
      uint32_t stride = memberType.array.empty() ? 0 : msl.type_struct_member_array_stride(type, member);
      uint32_t matrixStride = memberType.columns > 1 ? msl.type_struct_member_matrix_stride(type, member) : 0;
      if (!first) out << ",";
      first = false;
      out << "{\"name\":\"" << escaped(name) << "\",\"offset\":" << offset << ",\"size\":" << size
          << ",\"arrayStride\":" << stride << ",\"matrixStride\":" << matrixStride
          << ",\"columns\":" << memberType.columns << ",\"vecsize\":" << memberType.vecsize
          << ",\"count\":" << (memberType.array.empty() ? 1 : memberType.array[0])
          << ",\"basetype\":" << (int)memberType.basetype << "}";
    }
  }
  out << "]";
  return out.str();
}

std::string texturesOf(spirv_cross::CompilerMSL &msl) {
  std::ostringstream out;
  out << "[";
  auto resources = msl.get_shader_resources();
  bool first = true;
  for (auto &image : resources.sampled_images) {
    if (!first) out << ",";
    first = false;
    out << "{\"name\":\"" << escaped(image.name) << "\",\"texture\":" << msl.get_automatic_msl_resource_binding(image.id)
        << ",\"sampler\":" << msl.get_automatic_msl_resource_binding_secondary(image.id) << "}";
  }
  out << "]";
  return out.str();
}

}  // namespace

extern "C" char *shader_translate(const char *vertexSource, const char *fragmentSource) {
  if (!initialized) {
    glslang::InitializeProcess();
    initialized = true;
  }
  glslang::TShader vertex(EShLangVertex), fragment(EShLangFragment);
  glslang::TShader *shaders[2] = {&vertex, &fragment};
  // ES 3.10 holds all of 3.00, and is the least glslang takes for SPIR-V.
  std::string texts[2] = {vertexSource, fragmentSource};
  for (auto &text : texts) {
    size_t at = text.find("#version 300 es");
    if (at != std::string::npos) text.replace(at, 15, "#version 310 es");
  }
  const char *sources[2] = {texts[0].c_str(), texts[1].c_str()};
  for (int i = 0; i < 2; i++) {
    auto *shader = shaders[i];
    shader->setStrings(&sources[i], 1);
    shader->setEnvInput(glslang::EShSourceGlsl, i == 0 ? EShLangVertex : EShLangFragment, glslang::EShClientVulkan, 100);
    shader->setEnvClient(glslang::EShClientVulkan, glslang::EShTargetVulkan_1_0);
    shader->setEnvTarget(glslang::EShTargetSpv, glslang::EShTargetSpv_1_0);
    // Loose uniforms and samplers, as WebGL has them, gathered into a block.
    shader->setEnvInputVulkanRulesRelaxed();
    shader->setGlobalUniformBlockName("Uniforms");
    shader->setAutoMapLocations(true);
    shader->setAutoMapBindings(true);
    if (!shader->parse(GetDefaultResources(), 300, ENoProfile, false, false,
                       (EShMessages)(EShMsgSpvRules | EShMsgVulkanRules | EShMsgDefault))) {
      return failure(std::string(i == 0 ? "vertex: " : "fragment: ") + shader->getInfoLog());
    }
  }
  glslang::TProgram program;
  program.addShader(&vertex);
  program.addShader(&fragment);
  if (!program.link(EShMsgDefault) || !program.mapIO()) return failure(std::string("link: ") + program.getInfoLog());

  std::string msls[2], uniforms[2], buffers[2], inputs = "[]", textures = "[]", vertexTextures = "[]";
  for (int i = 0; i < 2; i++) {
    std::vector<uint32_t> spirv;
    glslang::SpvOptions options;
    options.disableOptimizer = true;
    glslang::GlslangToSpv(*program.getIntermediate(i == 0 ? EShLangVertex : EShLangFragment), spirv, &options);
    try {
      spirv_cross::CompilerMSL msl(std::move(spirv));
      auto mslOptions = msl.get_msl_options();
      mslOptions.platform = spirv_cross::CompilerMSL::Options::macOS;
      mslOptions.set_msl_version(2, 3);
      // Each stage's uniform block in buffer 0; vertex buffers from 8 on.
      msl.set_msl_options(mslOptions);
      auto common = msl.get_common_options();
      common.vertex.flip_vert_y = true;
      msl.set_common_options(common);
      msls[i] = msl.compile();
      uniforms[i] = uniformsOf(msl, buffers[i]);
      if (i == 0) {
        std::ostringstream out;
        out << "[";
        bool first = true;
        for (auto &input : msl.get_shader_resources().stage_inputs) {
          if (!first) out << ",";
          first = false;
          out << "{\"name\":\"" << escaped(input.name) << "\",\"location\":" << msl.get_decoration(input.id, spv::DecorationLocation) << "}";
        }
        out << "]";
        inputs = out.str();
        vertexTextures = texturesOf(msl);
      } else {
        textures = texturesOf(msl);
      }
    } catch (const std::exception &error) {
      return failure(std::string(i == 0 ? "vertex msl: " : "fragment msl: ") + error.what());
    }
  }
  std::ostringstream out;
  out << "{\"vertex\":\"" << escaped(msls[0]) << "\",\"fragment\":\"" << escaped(msls[1]) << "\",\"inputs\":" << inputs
      << ",\"vertexUniforms\":" << uniforms[0] << ",\"vertexBuffer\":" << buffers[0]
      << ",\"fragmentUniforms\":" << uniforms[1] << ",\"fragmentBuffer\":" << buffers[1] << ",\"textures\":" << textures << ",\"vertexTextures\":" << vertexTextures << "}";
  return result(out.str());
}

extern "C" char *shader_check(int fragment, const char *source) {
  if (!initialized) {
    glslang::InitializeProcess();
    initialized = true;
  }
  std::string text = source;
  size_t at = text.find("#version 300 es");
  if (at != std::string::npos) text.replace(at, 15, "#version 310 es");
  const char *strings[1] = {text.c_str()};
  EShLanguage stage = fragment ? EShLangFragment : EShLangVertex;
  glslang::TShader shader(stage);
  shader.setStrings(strings, 1);
  shader.setEnvInput(glslang::EShSourceGlsl, stage, glslang::EShClientVulkan, 100);
  shader.setEnvClient(glslang::EShClientVulkan, glslang::EShTargetVulkan_1_0);
  shader.setEnvTarget(glslang::EShTargetSpv, glslang::EShTargetSpv_1_0);
  shader.setEnvInputVulkanRulesRelaxed();
  shader.setGlobalUniformBlockName("Uniforms");
  shader.setAutoMapLocations(true);
  shader.setAutoMapBindings(true);
  if (shader.parse(GetDefaultResources(), 300, ENoProfile, false, false, (EShMessages)(EShMsgSpvRules | EShMsgVulkanRules | EShMsgDefault))) {
    return nullptr;
  }
  return result(shader.getInfoLog());
}
