  // Models in three dimensions: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeModels(ctx) {
    var puppets = ctx.puppets, gl = ctx.gl, json = ctx.json, link = ctx.link, newTexture = ctx.newTexture, flat = ctx.flat, texture = ctx.texture, depthOf = ctx.depthOf, description = ctx.description, general = ctx.general, inDepth = ctx.inDepth, unplaced = ctx.unplaced, objects = ctx.objects, live = ctx.live, CHANNELS = ctx.CHANNELS, numbersOf = ctx.numbersOf, freeLook = ctx.freeLook, eyePlace = ctx.eyePlace, activeCamera = ctx.activeCamera, scenePathLook = ctx.scenePathLook, pathLook = ctx.pathLook, cameraMatrix = ctx.cameraMatrix, also = ctx.also, standing = ctx.standing, isSet = ctx.isSet;
    // --- Models in three dimensions --------------------------------------
    //
    // A scene may hold models: meshes with a picture laid over them, lit by the scene's lights,
    // by the light that comes from everywhere (ambient) and from the sky above. Wallpaper
    // Engine's own shaders for them are not in the wallpapers; they are drawn here by one of the
    // player's own, much as Wallpaper Engine lights them: what faces a light is lit by it, as
    // much as is left of it at that distance, with a shine as sharp as the material is smooth
    // and of the picture's own color as far as it is metal.

    ctx.MAX_LIGHTS = 32;

    // What the third texture of a model's material says of its surface, as Wallpaper Engine's
    // generic4 reads it: how metal it is, how rough, and where and how much it glows, each in
    // a channel of its own when the material turns that map on. The material may say so, or
    // the texture itself: bits 20 to 23 of its flags, in that order (3509243656's suns, the
    // eyes of Sonic). `maps` is null when there is nothing to read.
    function surfaceOf(pass, constants) {
      var name = (pass.textures || [])[2];
      var masks = typeof name === 'string' && name ? texture('materials/' + name) : null;
      var combos = pass.combos || {}, given = masks ? masks.maps || 0 : 0;
      var maps = ['METALLIC_MAP', 'ROUGHNESS_MAP', 'REFLECTION_MAP', 'EMISSIVE_MAP'].map(function (combo, index) {
        return masks && (isSet(combos[combo]) ? number(combos[combo], 0) === 1 : (given >> index & 1) === 1) ? 1 : 0;
      });
      var glow = number(plain(constants.emissivebrightness), 1);
      var emissive = numbers(plain(constants.emissivecolor), 3, 1).map(function (part) { return part * glow; });
      return { masks: masks, maps: maps[0] || maps[1] || maps[3] ? maps : null, emissive: emissive };
    }
    // Tells the model shader of a part's surface; its masks go in the third texture unit.
    function useSurface(at, surface) {
      var layer = surface.maps && surface.masks && surface.masks.ready !== false ? surface.masks.layers[0] : null;
      gl.uniform4f(at('u_Maps'), layer ? surface.maps[0] : 0, layer ? surface.maps[1] : 0, 0, layer ? surface.maps[3] : 0);
      gl.uniform3f(at('u_Emissive'), surface.emissive[0], surface.emissive[1], surface.emissive[2]);
      gl.activeTexture(gl.TEXTURE2);
      gl.bindTexture(gl.TEXTURE_2D, layer ? layer.texture : null);
      gl.uniform1i(at('u_Masks'), 2);
      gl.activeTexture(gl.TEXTURE0);
    }
    // How a model in three dimensions is shaded, whether its corners stand still or hang on bones.
    var modelFragment = [
      '#version 300 es',
      'precision highp float;',
      'in vec3 v_World;',
      'in vec3 v_Normal;',
      'in vec2 v_Uv;',
      'uniform sampler2D u_Texture;',
      'uniform int u_Channels;',
      'uniform vec4 u_Tint;',
      'uniform vec3 u_Ambient;',
      'uniform vec3 u_Sky;',
      'uniform vec3 u_Eye;',
      'uniform float u_Metallic;',
      'uniform float u_Roughness;',
      'uniform int u_Lit;',             // 0: the material takes no light, and shows its own colors
      'uniform int u_Classic;',         // 1: lit as Wallpaper Engine's generic2 lights, not by GGX
      'uniform float u_HalfLambert;',   // generic2's Light: how far its light wraps round, 0 to 1
      'uniform sampler2D u_Masks;',     // metal, roughness, -, glow; each read where u_Maps says
      'uniform vec4 u_Maps;',
      'uniform vec3 u_Emissive;',       // the color it glows in, times how bright
      'uniform float u_Cutoff;',        // over 0: what is clearer than this is not drawn, the rest is whole
      // Fog, as Wallpaper Engine's common_fog.h has it: by how far from the eye and by how
      // high, each from where it starts over how far it grows, at a base density plus a
      // share that grows as the square of the way in. `u_Fogged`: the material takes fog.
      'uniform int u_Fogged;',
      'uniform vec4 u_FogDist;',
      'uniform vec3 u_FogDistColor;',
      'uniform vec4 u_FogHeight;',
      'uniform vec3 u_FogHeightColor;',
      'vec3 fogged(vec3 c) {',
      '  if (u_Fogged == 0) return c;',
      '  if (u_FogHeight.y != 0.0) { float h = clamp((v_World.y - u_FogHeight.x) / u_FogHeight.y, 0.0, 1.0);',
      '    c = mix(c, u_FogHeightColor, clamp(u_FogHeight.z + u_FogHeight.w * h * h, 0.0, 1.0)); }',
      '  if (u_FogDist.y != 0.0) { float d = clamp((length(u_Eye - v_World) - u_FogDist.x) / u_FogDist.y, 0.0, 1.0);',
      '    c = mix(c, u_FogDistColor, clamp(u_FogDist.z + u_FogDist.w * d * d, 0.0, 1.0)); }',
      '  return c;',
      '}',
      'uniform int u_LightCount;',
      'uniform vec4 u_LightPlace[' + ctx.MAX_LIGHTS + '];', // where (w 1), or which way it shines (w 0)
      'uniform vec4 u_LightColor[' + ctx.MAX_LIGHTS + '];', // color times strength, and how far it reaches
      'uniform vec4 u_LightAim[' + ctx.MAX_LIGHTS + '];',   // which way a spot points, and how fast it fades
      'uniform vec4 u_LightEnd[' + ctx.MAX_LIGHTS + '];',   // a tube's other end (w 1): it shines from the nearest point between
      // The sun's shadows: where each point is as the light sees it, and how near to the
      // light the nearest thing there is, kept in four bytes.
      // The sun's shadows, as Wallpaper Engine casts them: up to three cascades, each a map of
      // a piece of the scene round the eye as the sun sees it — the nearest the finest — with
      // how near to the sun the nearest thing there is, kept in four bytes.
      'uniform int u_Shadows;',
      'uniform int u_ShadowCount;',
      'uniform mat4 u_ShadowMatrix[3];',
      'uniform sampler2D u_ShadowMap0;',
      'uniform sampler2D u_ShadowMap1;',
      'uniform sampler2D u_ShadowMap2;',
      'uniform vec2 u_ShadowTexel;',
      'float unpackDepth(vec4 c) { return dot(c, vec4(1.0, 1.0 / 255.0, 1.0 / 65025.0, 1.0 / 16581375.0)); }',
      // Whether a point is lit, between texels: the four around compared and weighed by
      // nearness, as the comparing sampler Wallpaper Engine reads its shadows with does.
      'float litAt(sampler2D map, vec2 uv, float z) {',
      '  vec2 t = uv / u_ShadowTexel - 0.5;',
      '  vec2 f = fract(t);',
      '  vec2 b = (floor(t) + 0.5) * u_ShadowTexel;',
      '  float a = z <= unpackDepth(texture(map, b)) ? 1.0 : 0.0;',
      '  float c = z <= unpackDepth(texture(map, b + vec2(u_ShadowTexel.x, 0.0))) ? 1.0 : 0.0;',
      '  float d = z <= unpackDepth(texture(map, b + vec2(0.0, u_ShadowTexel.y))) ? 1.0 : 0.0;',
      '  float e = z <= unpackDepth(texture(map, b + u_ShadowTexel)) ? 1.0 : 0.0;',
      '  return mix(mix(a, c, f.x), mix(d, e, f.x), f.y);',
      '}',
      // Nine of those round the point, at Wallpaper Engine's own offsets.
      'float soft(sampler2D map, vec3 at) {',
      '  vec2 o = u_ShadowTexel * 1.02323;',
      '  vec2 r = u_ShadowTexel * 0.81616;',
      '  float z = at.z - 0.0015;',
      '  return (litAt(map, at.xy - r, z) + litAt(map, at.xy + vec2(0.0, -o.y), z) + litAt(map, at.xy + vec2(r.x, -r.y), z) +',
      '          litAt(map, at.xy + vec2(-o.x, 0.0), z) + litAt(map, at.xy, z) + litAt(map, at.xy + vec2(o.x, 0.0), z) +',
      '          litAt(map, at.xy + vec2(-r.x, r.y), z) + litAt(map, at.xy + vec2(0.0, o.y), z) + litAt(map, at.xy + r, z)) / 9.0;',
      '}',
      // The finest cascade the point lies in; outside all of them it is lit.
      'float sunlit(vec3 world) {',
      '  for (int i = 0; i < 3; i++) {',
      '    if (i >= u_ShadowCount) break;',
      '    vec4 seen = u_ShadowMatrix[i] * vec4(world, 1.0);',
      '    vec3 at = seen.xyz / seen.w;',
      '    if (abs(at.x) >= 0.99 || abs(at.y) >= 0.99 || abs(at.z) >= 0.99) continue;',
      '    at = at * 0.5 + 0.5;',
      '    if (i == 0) return soft(u_ShadowMap0, at);',
      '    if (i == 1) return soft(u_ShadowMap1, at);',
      '    return soft(u_ShadowMap2, at);',
      '  }',
      '  return 1.0;',
      '}',
      'out vec4 color;',
      'const float PI = 3.14159265;',
      // Light from one direction, as Wallpaper Engine lights a model: a diffuse part and a
      // specular one by the GGX distribution, Smith geometry and Schlick's Fresnel.
      'vec3 shade(vec3 n, vec3 v, vec3 l, vec3 albedo, vec3 radiance, vec3 f0, float rough, float metal) {',
      '  vec3 h = normalize(v + l);',
      '  float a = rough * rough;',
      '  float a2 = a * a;',
      '  float nh = max(dot(n, h), 0.0);',
      '  float spread = nh * nh * (a2 - 1.0) + 1.0;',
      '  float d = a2 / (PI * spread * spread);',
      '  float k = (rough + 1.0) * (rough + 1.0) / 8.0;',
      '  float nv = max(dot(n, v), 0.001);',
      '  float nl = max(dot(n, l), 0.0);',
      '  float g = nv / (nv * (1.0 - k) + k) * max(nl, 0.001) / (max(nl, 0.001) * (1.0 - k) + k);',
      '  vec3 f = f0 + (1.0 - f0) * pow(max(1.0 - max(dot(h, v), 0.0), 0.001), 5.0);',
      '  vec3 specular = d * g * f / max(4.0 * nv * nl, 0.001);',
      '  return ((1.0 - metal) * (1.0 - f) * albedo / PI + specular) * radiance * nl;',
      '}',
      'void main() {',
      '  vec4 base = texture(u_Texture, v_Uv);',
      '  if (u_Channels == 1) base = vec4(1.0, 1.0, 1.0, base.r);',
      '  if (u_Channels == 2) base = vec4(base.rrr, base.g);',
      '  base *= u_Tint;',
      // Alpha to coverage, as Wallpaper Engine draws it with no samples to spare: a cut.
      '  if (u_Cutoff > 0.0) { if (base.a < u_Cutoff) discard; base.a = 1.0; }',
      '  vec4 masks = u_Maps == vec4(0.0) ? vec4(0.0) : texture(u_Masks, v_Uv);',
      // What glows does so whatever light falls on it, at least as bright as its glow.
      '  vec3 glow = u_Emissive * base.rgb * masks.a * u_Maps.w;',
      '  if (u_Lit == 0) { color = vec4(fogged(base.rgb + glow), base.a); return; }',
      '  vec3 n = normalize(v_Normal);',
      '  if (!gl_FrontFacing) n = -n;',
      '  vec3 toEye = normalize(u_Eye - v_World);',
      '  float metal = mix(u_Metallic, masks.r, u_Maps.x);',
      '  vec3 f0 = mix(vec3(0.04), base.rgb, metal);',
      '  float rough = clamp(mix(u_Roughness, masks.g, u_Maps.y), 0.03, 1.0);',
      // As Wallpaper Engine's generic4: the sky's light from below blending into the ambient
      // light from above, by which way the surface faces.
      '  vec3 around = mix(u_Sky, u_Ambient, dot(n, vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5) * base.rgb;',
      // As Wallpaper Engine's generic2 and generic light a model (common_fragment.h,
      // ComputeLightSpecular): lambert, wrapped round as far as the material's Light says, a
      // rim that grows with its metal, a highlight as sharp and strong as its roughness and
      // metal make it, each falling off as the square of the way to the light's reach.
      '  if (u_Classic == 1) {',
      '    vec3 light = mix(u_Sky, u_Ambient, dot(n, vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5);',
      '    vec3 highlight = vec3(0.0);',
      '    float power = (1.01 - u_Roughness) * mix(400.0, 250.0, u_Metallic);',
      '    float strength = (0.5 + u_Metallic * 0.5) * (1.0 - u_Roughness * 0.9);',
      '    for (int i = 0; i < ' + ctx.MAX_LIGHTS + '; i++) {',
      '      if (i >= u_LightCount) break;',
      '      vec3 dir; float attn = 1.0;',
      '      if (u_LightPlace[i].w > 0.5) {',
      '        vec3 way = u_LightPlace[i].xyz - v_World; float far = max(length(way), 0.0001);',
      '        dir = way / far;',
      '        float reach = u_LightColor[i].w;',
      '        if (reach > 0.0) attn = clamp((reach - far) / reach, 0.0, 1.0);',
      '      } else { dir = normalize(-u_LightPlace[i].xyz); }',
      '      vec3 c = u_LightColor[i].rgb;',
      '      highlight += pow(max(0.0, dot(normalize(toEye + dir), n)), power) * strength * attn * c;',
      '      float d = dot(dir, n), wrap = d * 0.5 + 0.5;',
      '      d = mix(d, wrap, u_HalfLambert);',
      '      float rim = u_Metallic * 2.0;',
      '      rim = pow((1.0 - clamp(dot(n, toEye), 0.0, 1.0)) * pow(wrap, 0.25), 6.0 - rim) * rim;',
      '      light += c * (clamp(d, 0.0, 1.0) + rim) * attn * attn;',
      '    }',
      '    color = vec4(fogged(max(base.rgb * light + highlight, glow)), base.a);',
      '    return;',
      '  }',
      '  vec3 lit = vec3(0.0);',
      '  for (int i = 0; i < ' + ctx.MAX_LIGHTS + '; i++) {',
      '    if (i >= u_LightCount) break;',
      '    vec3 toLight;',
      '    float left = 1.0;',
      '    if (u_LightPlace[i].w > 0.5) {',
      '      vec3 from = u_LightPlace[i].xyz;',
      '      if (u_LightEnd[i].w > 0.5) {',
      '        vec3 along = u_LightEnd[i].xyz - from;',
      '        from += along * clamp(dot(v_World - from, along) / max(dot(along, along), 0.000001), 0.0, 1.0);',
      '      }',
      '      vec3 way = from - v_World;',
      '      float far = length(way);',
      '      toLight = way / max(far, 0.0001);',
      '      float reach = u_LightColor[i].w;',
      '      if (reach > 0.0) left = pow(clamp(1.0 - far / reach, 0.0, 1.0), max(u_LightAim[i].w, 0.01));',
      '      if (dot(u_LightAim[i].xyz, u_LightAim[i].xyz) > 0.0) left *= smoothstep(0.5, 0.9, dot(-toLight, normalize(u_LightAim[i].xyz)));',
      '    } else {',
      '      toLight = normalize(-u_LightPlace[i].xyz);',
      '      if (i == 0 && u_Shadows == 1) left *= sunlit(v_World);',
      '    }',
      // A light's color times its strength is what reaches the surface, as in Wallpaper
      // Engine's lighting; the diffuse part is the albedo over pi of it.
      '    lit += shade(n, toEye, toLight, base.rgb, u_LightColor[i].rgb * left, f0, rough, metal);',
      '  }',
      '  color = vec4(fogged(max(lit, glow) + around), base.a);',
      '}'
    ].join('\n');
    var modelProgram = link([
      '#version 300 es',
      'in vec3 a_Position;',
      'in vec3 a_Normal;',
      'in vec2 a_TexCoord;',
      'uniform mat4 u_Model;',
      'uniform mat4 u_ViewProjection;',
      'uniform mat3 u_NormalMatrix;',
      'out vec3 v_World;',
      'out vec3 v_Normal;',
      'out vec2 v_Uv;',
      'void main() {',
      '  vec4 world = u_Model * vec4(a_Position, 1.0);',
      '  v_World = world.xyz;',
      '  v_Normal = u_NormalMatrix * a_Normal;',
      '  v_Uv = a_TexCoord;',
      '  gl_Position = u_ViewProjection * world;',
      '}'
    ].join('\n'), modelFragment, 'the player\'s own shader');
    // A model whose corners hang on bones: each corner is moved by up to four of them, as
    // much as its weights say, before it is placed in the scene.
    var MAX_SKIN_BONES = 128;
    var skinnedProgram = link([
      '#version 300 es',
      'in vec3 a_Position;',
      'in vec3 a_Normal;',
      'in vec2 a_TexCoord;',
      'in vec4 a_Bones;',
      'in vec4 a_Weights;',
      'uniform mat4 u_Model;',
      'uniform mat4 u_ViewProjection;',
      'uniform mat3 u_NormalMatrix;',
      'uniform mat4 u_Skin[' + MAX_SKIN_BONES + '];',
      'out vec3 v_World;',
      'out vec3 v_Normal;',
      'out vec2 v_Uv;',
      'void main() {',
      '  float total = a_Weights.x + a_Weights.y + a_Weights.z + a_Weights.w;',
      '  vec4 w = total > 0.0001 ? a_Weights / total : vec4(1.0, 0.0, 0.0, 0.0);',
      '  mat4 skin = u_Skin[int(a_Bones.x)] * w.x + u_Skin[int(a_Bones.y)] * w.y + u_Skin[int(a_Bones.z)] * w.z + u_Skin[int(a_Bones.w)] * w.w;',
      '  vec4 world = u_Model * (skin * vec4(a_Position, 1.0));',
      '  v_World = world.xyz;',
      '  v_Normal = u_NormalMatrix * (mat3(skin) * a_Normal);',
      '  v_Uv = a_TexCoord;',
      '  gl_Position = u_ViewProjection * world;',
      '}'
    ].join('\n'), modelFragment, 'the player\'s own shader');
    // --- The sun's shadows ------------------------------------------------------------------
    //
    // As Wallpaper Engine draws them for a light that casts shadows: what casts them is drawn
    // as the light sees it, nearest only, and every lit point asks whether something nearer
    // to the light stands in the way. One map around the camera, as far as the light's nearer
    // cascades reach.
    var SHADOW_SIZE = 2048;
    var shadowVertex = [
      '#version 300 es',
      'in vec3 a_Position;',
      'in vec4 a_Bones;',
      'in vec4 a_Weights;',
      'uniform mat4 u_Model;',
      'uniform mat4 u_LightViewProjection;',
      'uniform int u_Skinned;',
      'uniform mat4 u_Skin[' + MAX_SKIN_BONES + '];',
      'void main() {',
      '  vec4 place = vec4(a_Position, 1.0);',
      '  if (u_Skinned == 1) {',
      '    float total = a_Weights.x + a_Weights.y + a_Weights.z + a_Weights.w;',
      '    vec4 w = total > 0.0001 ? a_Weights / total : vec4(1.0, 0.0, 0.0, 0.0);',
      '    place = (u_Skin[int(a_Bones.x)] * w.x + u_Skin[int(a_Bones.y)] * w.y + u_Skin[int(a_Bones.z)] * w.z + u_Skin[int(a_Bones.w)] * w.w) * place;',
      '  }',
      '  gl_Position = u_LightViewProjection * (u_Model * place);',
      '}'
    ].join('\n');
    var shadowProgram = link(shadowVertex, [
      '#version 300 es',
      'precision highp float;',
      'out vec4 color;',
      'void main() {',
      '  vec4 e = fract(gl_FragCoord.z * vec4(1.0, 255.0, 65025.0, 16581375.0));',
      '  color = e - e.yzww * vec4(1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0, 0.0);',
      '}'
    ].join('\n'), 'the player\'s own shader');
    var shadowMaps = [], shadowFrame = -1, shadowState = null;

    // The light that casts shadows, if the scene has one that shows: the first sun.
    function shadowLight() {
      for (var index = 0; index < objects.length; index++) {
        var thing = objects[index];
        if (thing.lightKind === 'directional' && flag(plain(thing.said.castshadow), false) && standing(thing, true).visible) return thing;
      }
      return null;
    }
    // Draws what casts shadows as the light sees it, once a frame; what is drawn after it
    // binds its own target again.
    function ensureShadows() {
      if (shadowFrame === ctx.frames) return shadowState;
      shadowFrame = ctx.frames;
      shadowState = null;
      var sun = inDepth && shadowProgram ? shadowLight() : null;
      if (!sun) return null;
      // The cascades the sun says, nearest first: each takes in the eye's view out to so far.
      var distances = [0, 1, 2].map(function (index) { return number(plain(sun.said['cascadedistance' + index]), [25, 150, 650][index]); })
        .filter(function (distance) { return distance > 0; });
      var m = standing(sun, true).matrix;
      var way = [m[0], m[1], m[2]], length = Math.hypot(way[0], way[1], way[2]) || 1;
      way = way.map(function (part) { return part / length; });
      var up = Math.abs(way[1]) > 0.95 ? [0, 0, 1] : [0, 1, 0];
      var eye = eyePlace();
      var shot = activeCamera(), ahead;
      if (shot) { var c = cameraMatrix(shot); ahead = [-c[8], -c[9], -c[10]]; }
      else {
        var said = description.camera || {};
        var centre0 = numbers(said.center, 3, 0);
        ahead = said.eye ? [centre0[0] - eye[0], centre0[1] - eye[1], centre0[2] - eye[2]] : [0, 0, -1];
      }
      var aheadLength = Math.hypot(ahead[0], ahead[1], ahead[2]) || 1;
      ahead = ahead.map(function (part) { return part / aheadLength; });
      var tall = Math.tan(number(general.perspectiveoverridefov, number(general.fov, defaults.general.fov)) * Math.PI / 360);
      var wide = tall * (ctx.surface.width / Math.max(1, ctx.surface.height));
      var lookAtSun = Mat4.lookAt(new Vec3(0, 0, 0), new Vec3(way[0], way[1], way[2]), new Vec3(up[0], up[1], up[2])).m;
      gl.disable(gl.BLEND);
      gl.enable(gl.DEPTH_TEST);
      gl.depthFunc(gl.LEQUAL);
      gl.depthMask(true);
      gl.clearColor(1, 1, 1, 1);
      gl.useProgram(shadowProgram.program);
      function at(name) { var uniform = shadowProgram.uniforms[name]; return uniform ? uniform.location : null; }
      var matrices = [], textures = [];
      distances.forEach(function (distance, index) {
        var map = shadowMaps[index];
        if (!map) {
          map = shadowMaps[index] = { texture: newTexture(true, false), framebuffer: gl.createFramebuffer(), depth: gl.createRenderbuffer() };
          gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, SHADOW_SIZE, SHADOW_SIZE, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
          gl.bindRenderbuffer(gl.RENDERBUFFER, map.depth);
          gl.renderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, SHADOW_SIZE, SHADOW_SIZE);
          gl.bindFramebuffer(gl.FRAMEBUFFER, map.framebuffer);
          gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, map.texture, 0);
          gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, map.depth);
        }
        // The ball round the piece of the view out to this far, its middle held still on the
        // map's texels so that the shadows do not shimmer as the eye moves.
        var reach = distance * Math.sqrt(0.25 + wide * wide + tall * tall);
        var middle = [eye[0] + ahead[0] * distance / 2, eye[1] + ahead[1] * distance / 2, eye[2] + ahead[2] * distance / 2];
        var texel = reach * 2 / SHADOW_SIZE;
        var seen = [0, 1, 2].map(function (row) { return lookAtSun[row] * middle[0] + lookAtSun[4 + row] * middle[1] + lookAtSun[8 + row] * middle[2]; });
        var snapped = [Math.round(seen[0] / texel) * texel, Math.round(seen[1] / texel) * texel, seen[2]];
        var centre = [0, 1, 2].map(function (row) { return lookAtSun[row * 4] * snapped[0] + lookAtSun[row * 4 + 1] * snapped[1] + lookAtSun[row * 4 + 2] * snapped[2]; });
        var from = [centre[0] - way[0] * reach * 2, centre[1] - way[1] * reach * 2, centre[2] - way[2] * reach * 2];
        var look = Mat4.lookAt(new Vec3(from[0], from[1], from[2]), new Vec3(centre[0], centre[1], centre[2]), new Vec3(up[0], up[1], up[2])).m;
        var far = reach * 4;
        var box = [1 / reach, 0, 0, 0, 0, 1 / reach, 0, 0, 0, 0, -2 / far, 0, 0, 0, -1, 1];
        var matrix = times4(box, look);
        gl.bindFramebuffer(gl.FRAMEBUFFER, map.framebuffer);
        gl.viewport(0, 0, SHADOW_SIZE, SHADOW_SIZE);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.uniformMatrix4fv(at('u_LightViewProjection'), false, new Float32Array(matrix));
        objects.forEach(function (thing) {
          if (!thing.drawShadow || flag(plain(thing.said.castshadow), true) === false) return;
          var stands = standing(thing);
          if (!stands.visible) return;
          thing.drawShadow(stands.matrix, at);
        });
        matrices.push.apply(matrices, matrix);
        textures.push(map.texture);
      });
      gl.bindVertexArray(null);
      gl.disable(gl.DEPTH_TEST);
      shadowState = { matrices: matrices, textures: textures };
      return shadowState;
    }
    // Hands the scene's fog to a program that draws models: by distance (`fogdistance`) and
    // by height (`fogheight`), each from `…start` to `…end`, at `…startdensity` growing to
    // `…enddensity`, in `…color`. How the settings become the shader's four numbers (start,
    // reach, base, growth) is worked out from common_fog.h, not measured on a scene.
    function useFog(at) {
      ['distance', 'height'].forEach(function (kind) {
        var on = flag(plain(general['fog' + kind]), false);
        var start = number(plain(general['fog' + kind + 'start']), 0), end = number(plain(general['fog' + kind + 'end']), 0);
        var from = number(plain(general['fog' + kind + 'startdensity']), 0), to = number(plain(general['fog' + kind + 'enddensity']), 1);
        var color = numbers(plain(general['fog' + kind + 'color']), 3, 1);
        var name = kind === 'distance' ? 'u_FogDist' : 'u_FogHeight';
        gl.uniform4f(at(name), start, on && end !== start ? end - start : 0, from, to - from);
        gl.uniform3f(at(name + 'Color'), color[0], color[1], color[2]);
      });
    }
    // Hands the shadows to a program that lights.
    function useShadows(at, unit) {
      var shadows = shadowState;
      gl.uniform1i(at('u_Shadows'), shadows ? 1 : 0);
      if (!shadows) return;
      gl.uniform1i(at('u_ShadowCount'), shadows.textures.length);
      gl.uniformMatrix4fv(at('u_ShadowMatrix[0]') || at('u_ShadowMatrix'), false, new Float32Array(shadows.matrices));
      gl.uniform2f(at('u_ShadowTexel'), 1 / SHADOW_SIZE, 1 / SHADOW_SIZE);
      // Every map's sampler has a texture, the cascades the sun lacks the nearest one's.
      [0, 1, 2].forEach(function (index) {
        gl.activeTexture(gl.TEXTURE0 + unit + index);
        gl.bindTexture(gl.TEXTURE_2D, shadows.textures[Math.min(index, shadows.textures.length - 1)]);
        gl.uniform1i(at('u_ShadowMap' + index), unit + index);
      });
      gl.activeTexture(gl.TEXTURE0);
    }


    // The lights of the scene as they are now, for the models: at most so many, the strongest.
    function sceneLights() {
      var list = [];
      objects.forEach(function (thing) {
        if (!thing.lightKind) return;
        var stands = standing(thing, true);
        if (!stands.visible) return;
        var m = stands.matrix;
        var shade = thing.state.color || [1, 1, 1];
        var strength = number((thing.state.intensity || [])[0], defaults.light.intensity);
        // Which way it shines: a sun along its own x axis — the way the light of the Sonic
        // scenes falls in Wallpaper Engine's videos of them, from above where their scripts
        // turn it — a spot down its own z axis.
        var aim = thing.lightKind === 'directional' ? [m[0], m[1], m[2]] : [-m[8], -m[9], -m[10]];
        var length = Math.sqrt(aim[0] * aim[0] + aim[1] * aim[1] + aim[2] * aim[2]) || 1;
        aim = aim.map(function (part) { return part / length; });
        var reach = thing.lightKind === 'tube' ? thing.tubeReach : [0, 0, 0];
        var half = [m[0] * reach[0] + m[4] * reach[1] + m[8] * reach[2], m[1] * reach[0] + m[5] * reach[1] + m[9] * reach[2],
                    m[2] * reach[0] + m[6] * reach[1] + m[10] * reach[2]];
        list.push({
          place: thing.lightKind === 'directional' ? [aim[0], aim[1], aim[2], 0]
               : [m[12] - half[0], m[13] - half[1], m[14] - half[2], 1],
          end: thing.lightKind === 'tube' ? [m[12] + half[0], m[13] + half[1], m[14] + half[2], 1] : [0, 0, 0, 0],
          color: [shade[0] * strength, shade[1] * strength, shade[2] * strength, number((thing.state.radius || [])[0], defaults.light.radius)],
          aim: thing.lightKind === 'spot' ? [aim[0], aim[1], aim[2], number((thing.state.exponent || [])[0], defaults.light.exponent)] : [0, 0, 0, number((thing.state.exponent || [])[0], defaults.light.exponent)],
          strength: strength
        });
      });
      list.sort(function (a, b) { return b.strength - a.strength; });
      return list.slice(0, ctx.MAX_LIGHTS);
    }

    // From the scene to where it lands on what is drawn on: the scene's own flat view, with
    // nearer for larger z; or, for a scene seen through a lens, from in front of its middle.
    function viewProjection() {
      var w = ctx.surface.width, h = ctx.surface.height;
      var far = Math.max(1, number(general.farz, defaults.general.farz));
      // What is drawn is kept with its top row first, as the pictures are: y is turned over.
      if (general.orthogonalprojection) {
        return [2 / w, 0, 0, 0, 0, -2 / h, 0, 0, 0, 0, -1 / far, 0,
                -1 - 2 * ctx.surface.left / w, 1 + 2 * ctx.surface.bottom / h, 0, 1];
      }
      // A scene in three dimensions, seen through its camera: the last camera object that
      // shows, where it stands — it may hang on what moves it — looking down its own −z; else
      // the scene's own eye, looking at its centre. As wide as the camera sees, up and down.
      var shot = activeCamera();
      var onPath = pathLook(shot);
      var fov = ((onPath && onPath.fov > 0 && onPath.fov) || (shot && number(plain(shot.state.fov ? shot.state.fov[0] : shot.said.fov), 0)) ||
                 number(general.perspectiveoverridefov, number(general.fov, defaults.general.fov))) * Math.PI / 180;
      var near = Math.max(0.0001, number(general.nearz, defaults.general.nearz)), f = 1 / Math.tan(fov / 2), aspect = w / h;
      var lens = [f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) / (near - far), -1, 0, 0, 2 * far * near / (near - far), 0];
      if (freeLook() && editorView.flat > 0) {
        // Flat: as far as the eye is, in front and behind, all seen at one size.
        var half = editorView.flat, deep = far;
        lens = [1 / (half * aspect), 0, 0, 0, 0, 1 / half, 0, 0, 0, 0, -1 / deep, 0, 0, 0, 0, 1];
      }
      var look;
      if (freeLook()) {
        var own = freeLook();
        look = Mat4.lookAt(new Vec3(own.eye[0], own.eye[1], own.eye[2]), new Vec3(own.center[0], own.center[1], own.center[2]), new Vec3(own.up[0], own.up[1], own.up[2])).m;
      } else if (ctx.scriptedLook) {
        var put = ctx.scriptedLook;
        look = Mat4.lookAt(new Vec3(put.eye[0], put.eye[1], put.eye[2]), new Vec3(put.center[0], put.center[1], put.center[2]), new Vec3(put.up[0], put.up[1], put.up[2])).m;
      } else if (shot) {
        look = m4invert(cameraMatrix(shot));
      } else {
        var eyeSaid = (description.camera || {}), onScenePath = scenePathLook();
        var eye = numbers(eyeSaid.eye, 3, 0), centre = numbers(eyeSaid.center, 3, 0), up = numbers(eyeSaid.up, 3, 0);
        if (!eyeSaid.eye) { eye = [0, 0, 1]; centre = [0, 0, 0]; }
        if (onScenePath) { eye = onScenePath.eye; centre = onScenePath.center; up = onScenePath.up; }
        if (!(up[0] || up[1] || up[2])) up = [0, 1, 0];
        look = Mat4.lookAt(new Vec3(eye[0], eye[1], eye[2]), new Vec3(centre[0], centre[1], centre[2]), new Vec3(up[0], up[1], up[2])).m;
      }
      var seen = times4(lens, look);
      // The camera's shake, in a scene in three dimensions: the picture sways on the screen by
      // as much of it as in a flat scene — measured on Wallpaper Engine (2098326060): a few
      // pixels from frame to frame, smoothly, not the metres a shift of the world would make.
      if (inDepth && ctx.shake && ctx.shake.on && !editorView.free && (ctx.shake.x || ctx.shake.y)) {
        var dx = 2 * ctx.shake.x / Math.max(1, ctx.sceneWidth), dy = 2 * ctx.shake.y / Math.max(1, ctx.sceneHeight);
        for (var column = 0; column < 4; column++) {
          seen[column * 4] += dx * seen[column * 4 + 3];
          seen[column * 4 + 1] += dy * seen[column * 4 + 3];
        }
      }
      [1, 5, 9, 13].forEach(function (index) { seen[index] = -seen[index]; });
      return seen;
    }

    // --- Models whose corners hang on bones ----------------------------------------------
    //
    // A character that walks, a stage that moves: corners in three dimensions, each moved by
    // up to four bones; the bones posed, frame by frame, by the model's animations, in the
    // layers the scene sets — one that sets the pose, others that add to it.

    // Matrices of four by four, column by column, as plain lists: fast enough for every bone
    // of every frame.
    function m4mul(a, b) {
      var out = new Array(16);
      for (var c = 0; c < 4; c++) {
        for (var r = 0; r < 4; r++) {
          out[c * 4 + r] = a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1] + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3];
        }
      }
      return out;
    }
    function m4invert(m) {
      var inv = new Array(16);
      inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
      inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
      inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
      inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
      inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
      inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
      inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
      inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
      inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
      inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
      inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
      inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
      inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
      inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
      inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
      inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
      var det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
      if (Math.abs(det) < 1e-12) return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
      return inv.map(function (v) { return v / det; });
    }
    // Place, turn (about x, then y, then z) and scale, as a matrix.
    function m4pose(p) {
      var cx = Math.cos(p[3]), sx = Math.sin(p[3]), cy = Math.cos(p[4]), sy = Math.sin(p[4]), cz = Math.cos(p[5]), sz = Math.sin(p[5]);
      // R = Rz · Ry · Rx
      var r00 = cz * cy, r01 = cz * sy * sx - sz * cx, r02 = cz * sy * cx + sz * sx;
      var r10 = sz * cy, r11 = sz * sy * sx + cz * cx, r12 = sz * sy * cx - cz * sx;
      var r20 = -sy, r21 = cy * sx, r22 = cy * cx;
      return [r00 * p[6], r10 * p[6], r20 * p[6], 0, r01 * p[7], r11 * p[7], r21 * p[7], 0, r02 * p[8], r12 * p[8], r22 * p[8], 0, p[0], p[1], p[2], 1];
    }
    // A matrix as place, turn and scale, the way `m4pose` makes one.
    function m4unpose(m) {
      var sx = Math.hypot(m[0], m[1], m[2]) || 1, sy = Math.hypot(m[4], m[5], m[6]) || 1, sz = Math.hypot(m[8], m[9], m[10]) || 1;
      var r20 = m[2] / sx, r21 = m[6] / sy, r22 = m[10] / sz, r10 = m[1] / sx, r00 = m[0] / sx;
      var y = Math.asin(Math.max(-1, Math.min(1, -r20)));
      return [m[12], m[13], m[14], Math.atan2(r21, r22), y, Math.atan2(r10, r00), sx, sy, sz];
    }

    function buildSkinned(mesh, object, thing) {
      var bones = (mesh.bones || []).map(function (bone) {
        var rest = (bone.matrix || []).slice(0, 16);
        if (rest.length < 16) rest = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
        return { name: bone.name || '', parent: number(bone.parent, -1), rest: rest, still: m4unpose(rest) };
      });
      if (!bones.length) bones = [{ name: '', parent: -1, rest: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], still: [0, 0, 0, 0, 0, 0, 1, 1, 1] }];
      var count = Math.min(bones.length, MAX_SKIN_BONES);
      // Where each bone is at rest in the model, and the way back from there.
      var restWorld = [];
      function worldAtRest(index, depth) {
        if (restWorld[index]) return restWorld[index];
        var bone = bones[index];
        restWorld[index] = bone.parent >= 0 && bone.parent < bones.length && depth < 256 ? m4mul(worldAtRest(bone.parent, depth + 1), bone.rest) : bone.rest;
        return restWorld[index];
      }
      var back = bones.map(function (bone, index) { return m4invert(worldAtRest(index, 0)); });

      // The layers of animation, each with its clock.
      var animations = mesh.animations || [];
      // How fast it plays, how much of it shows and whether it plays at all may each be a
      // script's — a run that gives way to a ball while the model is in the air — so they are
      // kept with the model's own values and read every frame.
      var layers = (object.animationlayers || []).map(function (config, number_) {
        var wanted = number(plain(config.animation), -1);
        var animation = animations.filter(function (each) { return each.id === wanted; })[0];
        if (!animation) return null;
        function kept(name, raw, fallback, kind) {
          var value = live(raw === undefined ? fallback : raw, kind === 'flag' ? 0 : 1, fallback, thing, kind);
          also(thing, 'layer' + number_ + ':' + name, value);
          return value;
        }
        return { frames: numbersOf(animation.frames, Float32Array), frameCount: animation.frameCount, length: animation.length,
                 fps: animation.fps || 30, mode: animation.mode, adds: flag(config.additive, false), frame: 0,
                 rate: kept('rate', config.rate, 1), weight: kept('blend', config.blend, 1),
                 shows: kept('visible', config.visible, true, 'flag') };
      }).filter(Boolean);
      function speedOf(layer) { return number((layer.rate.now || [1])[0], 1); }
      function weightOf(layer) { return Math.max(0, Math.min(1, number((layer.weight.now || [1])[0], 1))); }
      function showing(layer) { return layer.shows.now !== false; }
      function sample(layer, index) {
        var at = layer.frame, length = Math.max(1, layer.length);
        if (layer.mode === 'mirror') { at = at % (length * 2); if (at > length) at = length * 2 - at; }
        else if (layer.mode === 'single') at = Math.min(at, length);
        else at = at % length;
        var before = Math.min(Math.floor(at), layer.frameCount - 1), after = Math.min(before + 1, layer.frameCount - 1), share = at - before;
        var one = (index * layer.frameCount + before) * 9, two = (index * layer.frameCount + after) * 9, out = [];
        for (var k = 0; k < 9; k++) {
          var a = layer.frames[one + k], b = layer.frames[two + k];
          // A turn takes the short way round.
          if (k >= 3 && k < 6) { while (b - a > Math.PI) b -= Math.PI * 2; while (a - b > Math.PI) b += Math.PI * 2; }
          out.push(a + (b - a) * share);
        }
        return out;
      }
      var skin = new Float32Array(MAX_SKIN_BONES * 16);
      for (var i = 0; i < MAX_SKIN_BONES; i++) skin[i * 16] = skin[i * 16 + 5] = skin[i * 16 + 10] = skin[i * 16 + 15] = 1;
      var posed = -1;
      // Every bone where the layers have it now, and how far each corner on it moves.
      function pose() {
        if (posed === ctx.frames) return;
        posed = ctx.frames;
        // The layers in their order, each over what those before it made, as much as it
        // shows: one that shows whole takes the bone over; one that adds moves it on from
        // where it is by how far its animation is from the bone at rest.
        var playing = layers.filter(function (layer) { return showing(layer) && layer.frameCount > 0 && weightOf(layer) > 0; });
        var world = [];
        for (var index = 0; index < count; index++) {
          var bone = bones[index];
          var p = bone.still.slice();
          playing.forEach(function (layer) {
            var q = sample(layer, index), share = weightOf(layer);
            if (layer.adds) {
              for (var k = 0; k < 6; k++) p[k] += (q[k] - bone.still[k]) * share;
              for (var s = 6; s < 9; s++) p[s] *= 1 + (q[s] / (bone.still[s] || 1) - 1) * share;
              return;
            }
            for (var j = 0; j < 9; j++) {
              var to = q[j];
              // A turn takes the short way round.
              if (j >= 3 && j < 6) { while (to - p[j] > Math.PI) to -= Math.PI * 2; while (p[j] - to > Math.PI) to += Math.PI * 2; }
              p[j] += (to - p[j]) * share;
            }
          });
          var local = m4pose(p);
          world[index] = bone.parent >= 0 && bone.parent < index ? m4mul(world[bone.parent], local)
                       : (bone.parent >= 0 && world[bone.parent] ? m4mul(world[bone.parent], local) : local);
          var moved = m4mul(world[index], back[index]);
          for (var e = 0; e < 16; e++) skin[index * 16 + e] = moved[e];
        }
        thing.boneWorld = world;
      }
      // Where a point of the model is now, in the model's own space: the bone it hangs on as
      // the animation has it, then the point's own place on that bone.
      thing.attachmentMatrix = function (name) {
        var point = (mesh.attachments || []).filter(function (each) { return each.name === name; })[0];
        if (!point) return null;
        pose();
        var bone = thing.boneWorld && thing.boneWorld[number(point.bone, -1)];
        if (!bone) return null;
        return (point.matrix || []).length >= 16 ? m4mul(bone, point.matrix) : bone;
      };
      thing.step = function (passed) {
        layers.forEach(function (layer) { if (showing(layer)) layer.frame += passed * layer.fps * speedOf(layer); });
      };
      thing.moving = layers.length > 0;

      var low = [Infinity, Infinity, Infinity], high = [-Infinity, -Infinity, -Infinity];
      var parts = (mesh.skinned || []).map(function (piece, number_) {
        var corners = numbersOf(piece.corners, Float32Array);
        var triangles = numbersOf(piece.triangles, Uint32Array);
        var cornerCount = Math.floor(corners.length / 16);
        if (!cornerCount || !triangles.length) return null;
        for (var corner = 0; corner < cornerCount; corner += 7) {
          for (var axis = 0; axis < 3; axis++) {
            low[axis] = Math.min(low[axis], corners[corner * 16 + axis]);
            high[axis] = Math.max(high[axis], corners[corner * 16 + axis]);
          }
        }
        var materialName = number_ === 0 && object.material ? object.material : piece.material;
        var material = json(String(materialName || '')) || {};
        var pass = (material.passes || [])[0] || {};
        var constants = {};
        Object.keys(pass.constantshadervalues || {}).forEach(function (each) { constants[key(each)] = pass.constantshadervalues[each]; });
        var shape = gl.createVertexArray();
        gl.bindVertexArray(shape);
        gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
        gl.bufferData(gl.ARRAY_BUFFER, corners, gl.STATIC_DRAW);
        [[0, 3, 0], [8, 3, 12], [1, 2, 24], [9, 4, 32], [10, 4, 48]].forEach(function (a) {
          gl.enableVertexAttribArray(a[0]);
          gl.vertexAttribPointer(a[0], a[1], gl.FLOAT, false, 64, a[2]);
        });
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.createBuffer());
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, triangles, gl.STATIC_DRAW);
        gl.bindVertexArray(null);
        return {
          shape: shape, length: triangles.length,
          picture: (pass.textures || [])[0] ? texture('materials/' + pass.textures[0]) : null,
          culls: key(String(pass.cullmode || 'normal')) !== 'nocull',
          tests: key(String(pass.depthtest || 'enabled')) !== 'disabled',
          writes: key(String(pass.depthwrite || 'enabled')) !== 'disabled',
          blending: key(String(pass.blending || 'normal')),
          metallic: number(plain(constants.metallic !== undefined ? constants.metallic : constants.metal), defaults.material.metallic),
          roughness: number(plain(constants.roughness !== undefined ? constants.roughness : constants.rough), defaults.material.roughness),
          lit: alwaysLit(pass) || number((pass.combos || {}).LIGHTING, 1) !== 0,
          classic: alwaysLit(pass), halfLambert: number(plain(constants.light), 0),
          fogged: number((pass.combos || {}).FOG, 1) !== 0,
          surface: surfaceOf(pass, constants),
          // How much it shows, as its material says: a number, or what a script makes of it —
          // a flame that shows only while the button is held.
          alpha: constants.alpha === undefined ? null : materialLive(thing, number_, 'alpha', constants.alpha, 1),
          // The color the material lays over its picture, which a script may change — a sky
          // that darkens at night.
          color: constants.color === undefined ? null : materialLive(thing, number_, 'color', constants.color, 3)
        };
      }).filter(Boolean);
      if (!parts.length) return null;
      var middle = [(low[0] + high[0]) / 2, (low[1] + high[1]) / 2, (low[2] + high[2]) / 2];
      thing.bounds = { middle: middle, radius: Math.hypot(high[0] - low[0], high[1] - low[1], high[2] - low[2]) / 2 };
      // Where a bone of the model is in the scene, by name: what scripts and cameras ask.
      thing.boneMatrix = function (name) {
        pose();
        for (var b = 0; b < count; b++) if (bones[b].name === name) return m4mul(standing(thing).matrix, thing.boneWorld[b]);
        return null;
      };
      thing.drawShadow = function (matrix, at) {
        pose();
        gl.uniformMatrix4fv(at('u_Model'), false, new Float32Array(matrix));
        gl.uniform1i(at('u_Skinned'), 1);
        gl.uniformMatrix4fv(at('u_Skin[0]') || at('u_Skin'), false, skin);
        gl.disable(gl.CULL_FACE);
        parts.forEach(function (part) {
          if (part.blending === 'additive' || !part.writes) return;
          gl.bindVertexArray(part.shape);
          gl.drawElements(gl.TRIANGLES, part.length, gl.UNSIGNED_INT, 0);
        });
      };
      var white = null;
      thing.isModel = true;
      // Which of the two passes of a scene in three dimensions it has parts for.
      var showsThrough = parts.some(function (part) { return part.blending === 'additive' || part.blending === 'translucent'; });
      var hides = parts.some(function (part) { return part.blending !== 'additive' && part.blending !== 'translucent'; });
      thing.draw = function (pass) {
        if (inDepth && !(pass === 'through' ? showsThrough : hides)) return;
        var stands = standing(thing);
        if (!stands.visible || !skinnedProgram) return;
        pose();
        ensureShadows();
        var target = ctx.surface.target;
        depthOf(target);
        gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
        gl.viewport(0, 0, target.width, target.height);
        var program = skinnedProgram;
        function at(name) { var uniform = program.uniforms[name]; return uniform ? uniform.location : null; }
        gl.useProgram(program.program);
        var model = stands.matrix;
        gl.uniformMatrix4fv(at('u_Model'), false, new Float32Array(model));
        gl.uniformMatrix4fv(at('u_ViewProjection'), false, new Float32Array(viewProjection()));
        gl.uniformMatrix3fv(at('u_NormalMatrix'), false, new Float32Array(new Mat4(model).normalMatrix().m));
        gl.uniformMatrix4fv(at('u_Skin[0]') || at('u_Skin'), false, skin);
        useShadows(at, 3);
        useFog(at);
        var tint = thing.state.color || [1, 1, 1];
        gl.uniform4f(at('u_Tint'), tint[0], tint[1], tint[2], stands.alpha);
        var ambient = numbers(plain(general.ambientcolor), 3, defaults.general.ambientcolor), sky = numbers(plain(general.skylightcolor), 3, defaults.general.skylightcolor);
        gl.uniform3f(at('u_Ambient'), ambient[0], ambient[1], ambient[2]);
        gl.uniform3f(at('u_Sky'), sky[0], sky[1], sky[2]);
        var eyeAt = eyePlace();
        gl.uniform3f(at('u_Eye'), eyeAt[0], eyeAt[1], eyeAt[2]);
        var lights = sceneLights();
        gl.uniform1i(at('u_LightCount'), lights.length);
        if (lights.length) {
          var places = [], shades = [], aims = [], ends = [];
          lights.forEach(function (light) { places.push.apply(places, light.place); shades.push.apply(shades, light.color); aims.push.apply(aims, light.aim); ends.push.apply(ends, light.end); });
          gl.uniform4fv(at('u_LightEnd'), new Float32Array(ends));
          gl.uniform4fv(at('u_LightPlace'), new Float32Array(places));
          gl.uniform4fv(at('u_LightColor'), new Float32Array(shades));
          gl.uniform4fv(at('u_LightAim'), new Float32Array(aims));
        }
        gl.depthFunc(gl.LEQUAL);
        gl.frontFace(gl.CW);
        gl.enable(gl.BLEND);
        gl.activeTexture(gl.TEXTURE0);
        gl.uniform1i(at('u_Texture'), 0);
        parts.forEach(function (part) {
          // In a scene in three dimensions, the parts that show through are drawn on the second pass.
          var through = part.blending === 'additive' || part.blending === 'translucent';
          if (inDepth && through !== (pass === 'through')) return;
          gl.uniform1f(at('u_Metallic'), part.metallic);
          gl.uniform1i(at('u_Lit'), part.lit ? 1 : 0); gl.uniform1i(at('u_Classic'), part.classic ? 1 : 0); gl.uniform1f(at('u_HalfLambert'), part.halfLambert || 0);
          gl.uniform1i(at('u_Fogged'), part.fogged ? 1 : 0);
          gl.uniform1f(at('u_Roughness'), part.roughness);
          useSurface(at, part.surface);
          gl.uniform1f(at('u_Cutoff'), part.blending === 'alphatocoverage' ? 0.5 : 0);
          var shown = part.alpha ? Math.max(0, Math.min(1, number((part.alpha.now || [1])[0], 1))) : 1;
          if (!(shown > 0.001)) return;
          var shade = part.color ? part.color.now || [1, 1, 1] : [1, 1, 1];
          gl.uniform4f(at('u_Tint'), tint[0] * number(shade[0], 1), tint[1] * number(shade[1], 1), tint[2] * number(shade[2], 1), stands.alpha * shown);
          var layer = part.picture && part.picture.ready !== false ? part.picture.layers[0] : null;
          if (!layer) white = white || flat(255, 255, 255, 255);
          gl.bindTexture(gl.TEXTURE_2D, (layer || white.layers[0]).texture);
          gl.uniform1i(at('u_Channels'), layer ? (CHANNELS[part.picture.channels] || 0) : 0);
          if (part.tests) gl.enable(gl.DEPTH_TEST); else gl.disable(gl.DEPTH_TEST);
          gl.depthMask(part.writes);
          if (part.culls) gl.enable(gl.CULL_FACE); else gl.disable(gl.CULL_FACE);
          if (part.blending === 'additive') gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
          else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
          gl.bindVertexArray(part.shape);
          gl.drawElements(gl.TRIANGLES, part.length, gl.UNSIGNED_INT, 0);
        });
        gl.bindVertexArray(null);
        gl.disable(gl.DEPTH_TEST);
        gl.disable(gl.CULL_FACE);
        gl.frontFace(gl.CCW);
        gl.depthMask(true);
      };
      return thing;
    }

    // Wallpaper Engine's older model shaders, generic and generic2, light what they draw
    // whatever the material's LIGHTING says: they have no such switch (2854680269's statue,
    // purple in its light); generic2 names its metal and roughness Metal and Rough.
    function alwaysLit(pass) {
      var shader = key(String(pass.shader || ''));
      return shader === 'generic' || shader === 'generic2';
    }

    function buildModel(object, thing) {
      var name = String(plain(object.model) || '');
      var mesh = puppets[key(name)];
      if (mesh && mesh.skinned && mesh.skinned.length) return buildSkinned(mesh, object, thing);
      if (!mesh || !mesh.solid || !modelProgram) {
        note('“' + thing.name + '”: its model, ' + name + ', ' + (mesh ? 'has no faces to light' : 'is not in the scene') + '; it is left out');
        return null;
      }
      // A model may be made of several parts, each drawn with a material of its own: a body,
      // a face, hair. The first is the file's own; the scene may name another material for it.
      var given = [{ solid: mesh.solid, triangles: mesh.triangles, wideTriangles: mesh.wideTriangles, material: object.material || mesh.material }]
        .concat((mesh.pieces || []).map(function (piece) {
          return { solid: piece.solid, triangles: piece.triangles, wideTriangles: piece.wideTriangles, material: piece.material };
        }));
      var low = [Infinity, Infinity, Infinity], high = [-Infinity, -Infinity, -Infinity];
      var parts = given.map(function (piece, number_) {
        var corners = numbersOf(piece.solid, Float32Array);
        // A part of more than 65 536 corners counts them in four bytes.
        var triangles = piece.wideTriangles ? numbersOf(piece.wideTriangles, Uint32Array) : numbersOf(piece.triangles, Uint16Array);
        var count = Math.floor(corners.length / 8);
        if (!count || !triangles.length) return null;
        for (var corner = 0; corner < count; corner++) {
          for (var axis = 0; axis < 3; axis++) {
            low[axis] = Math.min(low[axis], corners[corner * 8 + axis]);
            high[axis] = Math.max(high[axis], corners[corner * 8 + axis]);
          }
        }
        var material = json(String(piece.material || '')) || {};
        var pass = (material.passes || [])[0] || {};
        var constants = {};
        Object.keys(pass.constantshadervalues || {}).forEach(function (each) { constants[key(each)] = pass.constantshadervalues[each]; });
        var shape = gl.createVertexArray();
        gl.bindVertexArray(shape);
        gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
        gl.bufferData(gl.ARRAY_BUFFER, corners, gl.STATIC_DRAW);
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 32, 0);
        gl.enableVertexAttribArray(8);
        gl.vertexAttribPointer(8, 3, gl.FLOAT, false, 32, 12);
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 32, 24);
        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl.createBuffer());
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, triangles, gl.STATIC_DRAW);
        gl.bindVertexArray(null);
        return {
          corners: corners, count: count, shape: shape, length: triangles.length,
          counted: piece.wideTriangles ? gl.UNSIGNED_INT : gl.UNSIGNED_SHORT,
          picture: (pass.textures || [])[0] ? texture('materials/' + pass.textures[0]) : null,
          culls: key(String(pass.cullmode || 'normal')) !== 'nocull',
          tests: key(String(pass.depthtest || 'enabled')) !== 'disabled',
          writes: key(String(pass.depthwrite || 'enabled')) !== 'disabled',
          blending: key(String(pass.blending || 'normal')),
          metallic: number(plain(constants.metallic !== undefined ? constants.metallic : constants.metal), defaults.material.metallic),
          roughness: number(plain(constants.roughness !== undefined ? constants.roughness : constants.rough), defaults.material.roughness),
          // Lit unless the material says not: a model's material is, in Wallpaper Engine.
          lit: alwaysLit(pass) || number((pass.combos || {}).LIGHTING, 1) !== 0,
          classic: alwaysLit(pass), halfLambert: number(plain(constants.light), 0),
          fogged: number((pass.combos || {}).FOG, 1) !== 0,
          surface: surfaceOf(pass, constants),
          // How much it shows and the color laid over its picture, as its material says —
          // numbers, or what scripts make of them: a sky that darkens at night.
          alpha: constants.alpha === undefined ? null : materialLive(thing, number_, 'alpha', constants.alpha, 1),
          color: constants.color === undefined ? null : materialLive(thing, number_, 'color', constants.color, 3)
        };
      }).filter(Boolean);
      if (!parts.length) return null;
      // How large it is, for what is said to bounce off it.
      var middle = [(low[0] + high[0]) / 2, (low[1] + high[1]) / 2, (low[2] + high[2]) / 2];
      var radius = 0;
      parts.forEach(function (part) {
        for (var corner = 0; corner < part.count; corner++) {
          radius = Math.max(radius, Math.hypot(part.corners[corner * 8] - middle[0], part.corners[corner * 8 + 1] - middle[1], part.corners[corner * 8 + 2] - middle[2]));
        }
      });
      thing.bounds = { middle: middle, radius: radius };
      thing.drawShadow = function (matrix, at) {
        gl.uniformMatrix4fv(at('u_Model'), false, new Float32Array(matrix));
        gl.uniform1i(at('u_Skinned'), 0);
        gl.disable(gl.CULL_FACE);
        parts.forEach(function (part) {
          if (part.blending === 'additive' || !part.writes) return;
          gl.bindVertexArray(part.shape);
          gl.drawElements(gl.TRIANGLES, part.length, part.counted, 0);
        });
      };
      var white = null;
      thing.isModel = true;
      // Which of the two passes of a scene in three dimensions it has parts for.
      var showsThrough = parts.some(function (part) { return part.blending === 'additive' || part.blending === 'translucent'; });
      var hides = parts.some(function (part) { return part.blending !== 'additive' && part.blending !== 'translucent'; });
      thing.draw = function (pass) {
        if (inDepth && !(pass === 'through' ? showsThrough : hides)) return;
        var stands = standing(thing);
        if (!stands.visible) return;
        ensureShadows();
        var target = ctx.surface.target;
        depthOf(target);
        gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
        gl.viewport(0, 0, target.width, target.height);
        var program = modelProgram;
        // A uniform the compiler left out has no place; setting it at none does nothing.
        function at(name) { var uniform = program.uniforms[name]; return uniform ? uniform.location : null; }
        gl.useProgram(program.program);
        var model = stands.matrix;
        gl.uniformMatrix4fv(at('u_Model'), false, new Float32Array(model));
        gl.uniformMatrix4fv(at('u_ViewProjection'), false, new Float32Array(viewProjection()));
        gl.uniformMatrix3fv(at('u_NormalMatrix'), false, new Float32Array(new Mat4(model).normalMatrix().m));
        useShadows(at, 3);
        useFog(at);
        var tint = thing.state.color || [1, 1, 1];
        gl.uniform4f(at('u_Tint'), tint[0], tint[1], tint[2], stands.alpha);
        var ambient = numbers(plain(general.ambientcolor), 3, defaults.general.ambientcolor), sky = numbers(plain(general.skylightcolor), 3, defaults.general.skylightcolor);
        gl.uniform3f(at('u_Ambient'), ambient[0], ambient[1], ambient[2]);
        gl.uniform3f(at('u_Sky'), sky[0], sky[1], sky[2]);
        var eyeAt = eyePlace();
        gl.uniform3f(at('u_Eye'), eyeAt[0], eyeAt[1], eyeAt[2]);
        var lights = sceneLights();
        gl.uniform1i(at('u_LightCount'), lights.length);
        if (lights.length) {
          var places = [], shades = [], aims = [], ends = [];
          lights.forEach(function (light) { places.push.apply(places, light.place); shades.push.apply(shades, light.color); aims.push.apply(aims, light.aim); ends.push.apply(ends, light.end); });
          gl.uniform4fv(at('u_LightEnd'), new Float32Array(ends));
          gl.uniform4fv(at('u_LightPlace'), new Float32Array(places));
          gl.uniform4fv(at('u_LightColor'), new Float32Array(shades));
          gl.uniform4fv(at('u_LightAim'), new Float32Array(aims));
        }
        gl.depthFunc(gl.LEQUAL);
        // Turned over, the faces that look this way go round the other way.
        gl.frontFace(gl.CW);
        gl.enable(gl.BLEND);
        gl.activeTexture(gl.TEXTURE0);
        gl.uniform1i(at('u_Texture'), 0);
        parts.forEach(function (part) {
          // In a scene in three dimensions, the parts that show through are drawn on the second pass.
          var through = part.blending === 'additive' || part.blending === 'translucent';
          if (inDepth && through !== (pass === 'through')) return;
          gl.uniform1f(at('u_Metallic'), part.metallic);
          gl.uniform1i(at('u_Lit'), part.lit ? 1 : 0); gl.uniform1i(at('u_Classic'), part.classic ? 1 : 0); gl.uniform1f(at('u_HalfLambert'), part.halfLambert || 0);
          gl.uniform1i(at('u_Fogged'), part.fogged ? 1 : 0);
          gl.uniform1f(at('u_Roughness'), part.roughness);
          useSurface(at, part.surface);
          gl.uniform1f(at('u_Cutoff'), part.blending === 'alphatocoverage' ? 0.5 : 0);
          var shown = part.alpha ? Math.max(0, Math.min(1, number((part.alpha.now || [1])[0], 1))) : 1;
          if (!(shown > 0.001)) return;
          var shade = part.color ? part.color.now || [1, 1, 1] : [1, 1, 1];
          gl.uniform4f(at('u_Tint'), tint[0] * number(shade[0], 1), tint[1] * number(shade[1], 1), tint[2] * number(shade[2], 1), stands.alpha * shown);
          var layer = part.picture && part.picture.ready !== false ? part.picture.layers[0] : null;
          if (!layer) white = white || flat(255, 255, 255, 255);
          gl.bindTexture(gl.TEXTURE_2D, (layer || white.layers[0]).texture);
          gl.uniform1i(at('u_Channels'), layer ? (CHANNELS[part.picture.channels] || 0) : 0);
          if (part.tests) gl.enable(gl.DEPTH_TEST); else gl.disable(gl.DEPTH_TEST);
          gl.depthMask(part.writes);
          if (part.culls) gl.enable(gl.CULL_FACE); else gl.disable(gl.CULL_FACE);
          if (part.blending === 'additive') gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
          else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
          gl.bindVertexArray(part.shape);
          gl.drawElements(gl.TRIANGLES, part.length, part.counted, 0);
        });
        gl.bindVertexArray(null);
        gl.disable(gl.DEPTH_TEST);
        gl.disable(gl.CULL_FACE);
        gl.frontFace(gl.CCW);
        gl.depthMask(true);
      };
      return thing;
    }

    // A value of a model's material: kept with the model's own, so that what a script or an
    // animation makes of it is read every frame.
    function materialLive(thing, part, name, raw, count) {
      var value = live(raw, count, 1, thing);
      also(thing, 'material' + part + ':' + name, value);
      return value;
    }

    // A light: where it is, its color and strength, how far it reaches and how fast it fades
    // there. A light that shines from far away in one direction has no place, only a way.
    function buildLight(object, thing) {
      var kind = key(String(plain(object.light) || defaults.light.light));
      thing.lightKind = /dir|sun/.test(kind) ? 'directional' : (/spot/.test(kind) ? 'spot' : (/tube/.test(kind) ? 'tube' : 'point'));
      // A tube reaches as far each way from its middle as its control point says, along the
      // light's own axes.
      thing.tubeReach = numbers(plain(object.controlpoint), 3, 0);
      // A light's place animated with nothing said of `relative` moves about where it stands,
      // as Wallpaper Engine moves it: 2854680269's lamp at 9 goes down by 3 and back, and its
      // angel is lit from above, changing as it goes (taken as said, the lamp would sink to
      // the statue's feet and light it from below). A picture's place so animated is set by
      // the numbers as they are (measured in Wallpaper Engine's window).
      var where = object.origin;
      if (where && typeof where === 'object' && !Array.isArray(where) && where.animation && typeof where.animation === 'object' &&
          where.animation.relative === undefined) {
        var moved = JSON.parse(JSON.stringify(where));
        moved.animation.relative = true;
        thing.lives.origin = live(moved, 3, unplaced(object), thing);
      }
      also(thing, 'intensity', live(object.intensity === undefined ? defaults.light.intensity : object.intensity, 1, defaults.light.intensity, thing));
      also(thing, 'radius', live(object.radius === undefined ? defaults.light.radius : object.radius, 1, defaults.light.radius, thing));
      also(thing, 'exponent', live(object.exponent === undefined ? defaults.light.exponent : object.exponent, 1, defaults.light.exponent, thing));
      return thing;
    }

    return { sceneLights: sceneLights, viewProjection: viewProjection, m4mul: m4mul, m4invert: m4invert, buildModel: buildModel, buildLight: buildLight };
  }

