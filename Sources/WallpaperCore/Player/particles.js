  // Particles: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeParticles(ctx) {
    var gl = ctx.gl, bound = ctx.bound, json = ctx.json, link = ctx.link, passBuffer = ctx.passBuffer, sheetFrames = ctx.sheetFrames, texture = ctx.texture, acquire = ctx.acquire, depthOf = ctx.depthOf, general = ctx.general, sceneVersion = ctx.sceneVersion, inDepth = ctx.inDepth, live = ctx.live, times = ctx.times, matrixOf = ctx.matrixOf, CHANNELS = ctx.CHANNELS, viewProjection = ctx.viewProjection, m4invert = ctx.m4invert, byId = ctx.byId, freeLook = ctx.freeLook, cameraLook = ctx.cameraLook, eyePlace = ctx.eyePlace, activeCamera = ctx.activeCamera, cameraMatrix = ctx.cameraMatrix, also = ctx.also, standing = ctx.standing, hearing = ctx.hearing, isSet = ctx.isSet;
    // --- Particles --------------------------------------------------------
    //
    // A system of particles is said in three lists: emitters, which make particles; initializers,
    // which give each new one its size, color, speed and time to live; and operators, which
    // change it as it lives. They are played here on the processor, and all the particles of a
    // system are drawn at once.

    var particleProgram = link([
      '#version 300 es',
      'in vec2 a_TexCoord;',
      'in vec4 a_Place;',  // where its middle is on the scene, its size and how far it is turned
      'in vec4 a_Color;',
      'in vec4 a_Frame;',  // where in the texture its picture is
      'in vec4 a_More;',   // how many times longer than wide it is drawn
      'uniform mat2 u_Linear;',
      'uniform vec2 u_Scene;',
      'out vec2 v_Uv;',
      'out vec4 v_Color;',
      'void main() {',
      '  vec2 corner = vec2(a_TexCoord.x - 0.5, (0.5 - a_TexCoord.y) * a_More.x);',
      '  float c = cos(a_Place.w);',
      '  float s = sin(a_Place.w);',
      '  vec2 at = a_Place.xy + u_Linear * (vec2(corner.x * c - corner.y * s, corner.x * s + corner.y * c) * a_Place.z);',
      '  gl_Position = vec4(2.0 * at.x / u_Scene.x - 1.0, 1.0 - 2.0 * at.y / u_Scene.y, 0.0, 1.0);',
      '  v_Uv = a_Frame.xy + a_TexCoord * a_Frame.zw;',
      '  v_Color = a_Color;',
      '}'
    ].join('\n'), [
      '#version 300 es',
      'precision highp float;',
      'in vec2 v_Uv;',
      'in vec4 v_Color;',
      'uniform sampler2D u_Texture;',
      'uniform int u_Channels;',
      'uniform float u_Bright;',
      'out vec4 color;',
      'void main() {',
      '  vec4 c = texture(u_Texture, v_Uv);',
      '  if (u_Channels == 1) c = vec4(1.0, 1.0, 1.0, c.r);',
      '  if (u_Channels == 2) c = vec4(c.rrr, c.g);',
      '  color = vec4(c.rgb * v_Color.rgb * u_Bright, clamp(c.a * v_Color.a, 0.0, 1.0));',
      '}'
    ].join('\n'), 'the player\'s own shader');
    // Particles that bend what is behind them — drops on glass, bubbles — rather than show a
    // picture: each is a clear lens over a copy of what is under it, which it takes from
    // nearer its middle the nearer its edge, as a drop does. Its picture only says its shape.
    var refractProgram = link([
      '#version 300 es',
      'in vec2 a_TexCoord;',
      'in vec4 a_Place;',
      'in vec4 a_Color;',
      'in vec4 a_Frame;',
      'in vec4 a_More;',
      'uniform mat2 u_Linear;',
      'uniform vec2 u_Scene;',
      'out vec2 v_Uv;',
      'out vec2 v_Local;',
      'out vec4 v_Color;',
      'out float v_Size;',
      'out float v_Turn;',
      'void main() {',
      '  vec2 corner = vec2(a_TexCoord.x - 0.5, (0.5 - a_TexCoord.y) * a_More.x);',
      '  float c = cos(a_Place.w);',
      '  float s = sin(a_Place.w);',
      '  vec2 at = a_Place.xy + u_Linear * (vec2(corner.x * c - corner.y * s, corner.x * s + corner.y * c) * a_Place.z);',
      '  gl_Position = vec4(2.0 * at.x / u_Scene.x - 1.0, 1.0 - 2.0 * at.y / u_Scene.y, 0.0, 1.0);',
      '  v_Uv = a_Frame.xy + a_TexCoord * a_Frame.zw;',
      '  v_Local = vec2(a_TexCoord.x * 2.0 - 1.0, 1.0 - a_TexCoord.y * 2.0);',
      '  v_Color = a_Color;',
      '  v_Size = a_Place.z;',
      '  v_Turn = a_Place.w;',
      '}'
    ].join('\n'), [
      '#version 300 es',
      'precision highp float;',
      'in vec2 v_Uv;',
      'in vec2 v_Local;',
      'in vec4 v_Color;',
      'in float v_Size;',
      'in float v_Turn;',
      'uniform sampler2D u_Texture;',
      'uniform sampler2D u_Normal;',
      'uniform int u_NormalChannels;',
      'uniform float u_NormalLevel;',
      'uniform sampler2D u_Behind;',
      'uniform vec2 u_BehindSize;',
      'uniform int u_Channels;',
      'uniform float u_Bright;',
      'uniform float u_Amount;',
      'uniform float u_Fill;',
      'out vec4 color;',
      'void main() {',
      '  vec4 c = texture(u_Texture, v_Uv);',
      '  if (u_Channels == 1) c = vec4(1.0, 1.0, 1.0, c.r);',
      '  if (u_Channels == 2) c = vec4(c.rrr, c.g);',
      '  vec4 base = c * v_Color;',
      // The way a clear drop faces where it bends what is behind it: as a dome does, its
      // slope growing toward its rim, where it ends.
      '  vec2 local = v_Local / u_Fill;',
      '  float r = length(local);',
      '  vec2 slope = r < 1.0 ? local * (1.0 - smoothstep(0.85, 1.0, r)) : vec2(0.0);',
      // As Wallpaper Engine bends it: by so much of the screen as the material says, for a
      // particle as far as it shows.
      // With a map of how the drop faces, as Wallpaper Engine bends it: by the map's two
      // directions along the particle's own, as much as the map's mask and the particle show.
      // A scene's own map holds its directions in alpha and green and its mask in red, with
      // its second direction downward; a sheet of drops has its shapes only there. Compressed,
      // its level sits at u_NormalLevel. Those of the player's own making say x, y and mask.
      '  if (u_NormalChannels > 0) {',
      '    vec4 n = texture(u_Normal, v_Uv);',
      '    vec2 facing = n.xy * 2.0 - 1.0;',
      '    float mask = n.a;',
      '    if (u_NormalChannels == 2) { facing = vec2(n.g, 1.0 - n.r) * 2.0 - 1.0; mask = 1.0; }',
      '    if (u_NormalChannels == 3) { facing = vec2(n.a * 2.0 - u_NormalLevel, 1.0 - n.g * 2.0); mask = n.r; }',
      '    float c = cos(v_Turn), s = sin(v_Turn);',
      '    slope = vec2(facing.x * c - facing.y * s, facing.x * s + facing.y * c) * vec2(1.0, -1.0) * mask;',
      '  }',
      '  vec2 at = gl_FragCoord.xy / u_BehindSize + slope * u_Amount * v_Color.a;',
      '  vec3 behind = texture(u_Behind, at).rgb;',
      '  color = vec4(base.rgb * behind * u_Bright, clamp(base.a, 0.0, 1.0));',
      '}'
    ].join('\n'), 'the player\'s own shader');
    // How see-through a particle is goes to the shader as it is, past 1 if the scene's
    // `alpha` says so, and is cut only after the picture's own is taken in: in Wallpaper
    // Engine's window a soft halo given alpha 3 shows three times as far out, and one of 1/3
    // given 3 as one of 1 (3598808038's vapor, alpha 2 and 3, is that much thicker).
    var FLOATS = 16; // to a particle, for the shader
    // How far in front of a flat scene's middle Wallpaper Engine's rope shader puts the eye it
    // turns its bands to, in the scene's units, whatever the scene's size (measured: 1975 to
    // 2110 on scenes of 3840 by 2160 and 1920 by 1080).
    var ROPE_EYE = 2048;
    // A particle's square is half its size on a side: Wallpaper Engine hands its shaders half
    // the size and its sprite spans that much (measured in its own window: white squares of
    // 30 are 5 pixels at a third). Turned by its random angle a square reaches 0.71 of its
    // size across, which is what its videos of runes, petals and drops showed.
    var PARTICLE_SIDE = 0.5;
    // Particles drawn as a rope: one band through them all, in the order they were made, as
    // wide as each is large. The picture is laid across the band, and along it where the band
    // is the tail of one particle.
    var ropeProgram = link([
      '#version 300 es',
      'in vec4 a_Place;',  // where a point of the band's edge is, and where across the picture
      'in vec4 a_Color;',
      'uniform vec2 u_Scene;',
      'out vec2 v_Uv;',
      'out vec4 v_Color;',
      'void main() {',
      '  gl_Position = vec4(2.0 * a_Place.x / u_Scene.x - 1.0, 1.0 - 2.0 * a_Place.y / u_Scene.y, 0.0, 1.0);',
      '  v_Uv = a_Place.zw;',
      '  v_Color = a_Color;',
      '}'
    ].join('\n'), [
      '#version 300 es',
      'precision highp float;',
      'in vec2 v_Uv;',
      'in vec4 v_Color;',
      'uniform sampler2D u_Texture;',
      'uniform int u_Channels;',
      'uniform float u_Bright;',
      'uniform int u_Refracts;',
      'uniform sampler2D u_Behind;',
      'uniform vec2 u_BehindSize;',
      'uniform sampler2D u_Normal;',
      'uniform int u_NormalChannels;',
      'uniform float u_NormalLevel;',
      'uniform float u_Amount;',
      'out vec4 color;',
      'void main() {',
      '  vec4 c = texture(u_Texture, v_Uv);',
      '  if (u_Channels == 1) c = vec4(1.0, 1.0, 1.0, c.r);',
      '  if (u_Channels == 2) c = vec4(c.rrr, c.g);',
      '  color = vec4(c.rgb * v_Color.rgb * u_Bright, clamp(c.a * v_Color.a, 0.0, 1.0));',
      // A band of water bends what is behind it, as Wallpaper Engine's rope shader does: its
      // colour is taken times what lies under it, looked at as far off as its normal map
      // says — across the band and along it, as the band lies on the screen — times the
      // material's amount, the map's mask and how much the band shows.
      '  if (u_Refracts == 1) {',
      '    vec2 slope = vec2(0.0);',
      '    if (u_NormalChannels > 0) {',
      '      vec4 n = texture(u_Normal, v_Uv);',
      '      vec2 facing = n.xy * 2.0 - 1.0;',
      '      float mask = n.a;',
      '      if (u_NormalChannels == 2) { facing = vec2(n.g, 1.0 - n.r) * 2.0 - 1.0; mask = 1.0; }',
      '      if (u_NormalChannels == 3) { facing = vec2(n.a * 2.0 - u_NormalLevel, 1.0 - n.g * 2.0); mask = n.r; }',
      '      vec2 across = vec2(dFdx(v_Uv.x), dFdy(v_Uv.x));',
      '      vec2 along = vec2(dFdx(v_Uv.y), dFdy(v_Uv.y));',
      '      across = dot(across, across) > 0.0 ? normalize(across) : vec2(0.0);',
      '      along = dot(along, along) > 0.0 ? normalize(along) : vec2(0.0);',
      '      slope = (across * facing.x + along * facing.y) * mask;',
      '    }',
      '    color.rgb *= texture(u_Behind, gl_FragCoord.xy / u_BehindSize + slope * u_Amount * v_Color.a).rgb;',
      '  }',
      '}'
    ].join('\n'), 'the player\'s own shader');

    // What a band of particles that bends what is behind it is drawn over: a copy of the scene
    // under it as it is so far, for the rope shader to take its colour from.
    function ropeBehind(system, surface) {
      var uniforms = ropeProgram.uniforms;
      if (uniforms.u_Refracts) gl.uniform1i(uniforms.u_Refracts.location, system.refracts ? 1 : 0);
      if (!system.refracts) return;
      var onto = surface.target;
      if (!surface.copy) surface.copy = acquire(onto.width, onto.height);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, onto.framebuffer);
      gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, surface.copy.framebuffer);
      gl.blitFramebuffer(0, 0, onto.width, onto.height, 0, 0, onto.width, onto.height, gl.COLOR_BUFFER_BIT, gl.NEAREST);
      gl.bindFramebuffer(gl.FRAMEBUFFER, onto.framebuffer);
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, surface.copy.texture);
      if (uniforms.u_Behind) gl.uniform1i(uniforms.u_Behind.location, 1);
      if (uniforms.u_BehindSize) gl.uniform2f(uniforms.u_BehindSize.location, onto.width, onto.height);
      if (uniforms.u_Amount) gl.uniform1f(uniforms.u_Amount.location, system.refractAmount);
      // The map of how the band faces, if the material has one ready.
      var facing = system.normals && system.normals.ready !== false ? system.normals : null;
      if (uniforms.u_NormalChannels) gl.uniform1i(uniforms.u_NormalChannels.location, !facing ? 0 : facing.builtin ? 1 : CHANNELS[facing.channels] === 2 ? 2 : 3);
      if (uniforms.u_NormalLevel) gl.uniform1f(uniforms.u_NormalLevel.location, facing && facing.compressed ? 0.965 : 1);
      if (facing) {
        gl.activeTexture(gl.TEXTURE2);
        gl.bindTexture(gl.TEXTURE_2D, facing.layers[0].texture);
        if (uniforms.u_Normal) gl.uniform1i(uniforms.u_Normal.location, 2);
      }
      gl.activeTexture(gl.TEXTURE0);
    }

    // Particles in a scene in three dimensions: each corner already where Wallpaper Engine's
    // own particle shader puts it in the system's space, then through the model, the view
    // and the lens at once, as there.
    var deepParticleProgram = link([
      '#version 300 es',
      'in vec3 a_Position;',
      'in vec2 a_TexCoord;',
      'in vec4 a_Color;',
      'uniform mat4 u_Matrix;',
      'out vec2 v_Uv;',
      'out vec4 v_Color;',
      'void main() {',
      '  gl_Position = u_Matrix * vec4(a_Position, 1.0);',
      '  v_Uv = a_TexCoord;',
      '  v_Color = a_Color;',
      '}'
    ].join('\n'), [
      '#version 300 es',
      'precision highp float;',
      'in vec2 v_Uv;',
      'in vec4 v_Color;',
      'uniform sampler2D u_Texture;',
      'uniform int u_Channels;',
      'uniform float u_Bright;',
      'out vec4 color;',
      'void main() {',
      '  vec4 c = texture(u_Texture, v_Uv);',
      '  if (u_Channels == 1) c = vec4(1.0, 1.0, 1.0, c.r);',
      '  if (u_Channels == 2) c = vec4(c.rrr, c.g);',
      '  color = vec4(c.rgb * v_Color.rgb * u_Bright, clamp(c.a * v_Color.a, 0.0, 1.0));',
      '}'
    ].join('\n'), 'the player\'s own shader');
    var deepParticleBuffer = null, deepParticleShape = null, deepParticleData = new Float32Array(0);

    // Which way the eye's right and up are, and where it is, in the scene.
    function eyeBasis() {
      var eye = eyePlace(), shot = activeCamera();
      if (shot && !ctx.scriptedLook && !freeLook()) {
        var m = cameraMatrix(shot);
        return { right: [m[0], m[1], m[2]], up: [m[4], m[5], m[6]], eye: eye };
      }
      var said = freeLook() || cameraLook();
      var centre = said.center, up = said.up;
      var view = Mat4.lookAt(new Vec3(eye[0], eye[1], eye[2]), new Vec3(centre[0], centre[1], centre[2]), new Vec3(up[0], up[1], up[2])).m;
      return { right: [view[0], view[4], view[8]], up: [view[1], view[5], view[9]], eye: eye };
    }

    function mix(from, to, share) {
      return from + (to - from) * share;
    }

    // A color written "r g b", by Wallpaper Engine from 0 to 255 in some places and from 0 to
    // 1 in others; here from 0 to 1.
    function color(value, fallback) {
      var parts = numbers(value, 3, fallback);
      var large = parts[0] > 1.5 || parts[1] > 1.5 || parts[2] > 1.5;
      return large ? parts.map(function (part) { return part / 255; }) : parts;
    }

    // What gives a new particle one of its properties; null for one not known here.
    function initializer(said, system) {
      var exponent = number(said.exponent, 1);
      function pick(least, most) {
        return mix(least, most, exponent === 1 ? Math.random() : Math.pow(Math.random(), exponent));
      }
      var least, most;
      switch (key(said.name)) {
        case 'lifetimerandom':
          least = number(said.min, 1);
          most = number(said.max, 1);
          return function (particle) { particle.life = Math.max(0.01, pick(least, most)); };
        case 'sizerandom':
          least = number(said.min, 20);
          most = number(said.max, 20);
          return function (particle) { particle.size = pick(least, most); };
        case 'alpharandom':
          least = number(said.min, 1);
          most = number(said.max, 1);
          return function (particle) { particle.alpha = pick(least, most); };
        case 'velocityrandom':
          least = numbers(said.min, 3, 0);
          most = numbers(said.max, 3, 0);
          return function (particle) {
            particle.vx += pick(least[0], most[0]);
            particle.vy += pick(least[1], most[1]);
            particle.vz += pick(least[2], most[2]);
          };
        case 'colorrandom':
          // One end said alone stands for both: a system that says only `max: "0 0 0"` makes
          // black particles in Wallpaper Engine (3598808038's dark vapor), one that says only
          // `min` white ones; neither said, white.
          least = color(isSet(said.min) ? said.min : said.max, 255);
          most = color(isSet(said.max) ? said.max : said.min, 255);
          return function (particle) {
            // One of the colors between the two, not each part of it on its own.
            var share = pick(0, 1);
            particle.red = mix(least[0], most[0], share);
            particle.green = mix(least[1], most[1], share);
            particle.blue = mix(least[2], most[2], share);
          };
        case 'rotationrandom':
          // Without bounds a particle is turned anyhow, up to a whole turn (Wallpaper Engine
          // draws the squares of such a fog every which way).
          least = numbers(said.min, 3, 0)[2];
          most = numbers(said.max, 3, [0, 0, Math.PI * 2])[2];
          return function (particle) { particle.angle = pick(least, most); };
        case 'angularvelocityrandom':
          least = numbers(said.min, 3, 0)[2];
          most = numbers(said.max, 3, 0)[2];
          return function (particle) { particle.spin = pick(least, most); };
        case 'turbulentvelocityrandom':
          // A speed in a direction that wanders around `forward`, the more the larger the scale.
          var forward = numbers(said.forward, 3, [0, 1, 0]);
          // `offset` turns the way it goes, in radians: leaves at 3 fall where embers at −0.5 rise
          // (measured on Wallpaper Engine's own video of "Anime lake at night").
          var heading = Math.atan2(forward[1], forward[0]) + number(said.offset, 0);
          var spread = number(said.scale, 1) * Math.PI / 2;
          least = number(said.speedmin, 100);
          most = number(said.speedmax, 250);
          return function (particle) {
            // In a rope, one particle after another makes one line: each wanders as the one made
            // just before it did, a little further on, so the line bends rather than frays.
            var where = system.rope ? 0 : particle.seed * 50;
            var wander = (smoothNoise(system.age * number(said.timescale, 1) * 2, where, 256, 11) - 0.5) * 2 * spread;
            var speed = mix(least, most, Math.random());
            particle.vx += Math.cos(heading + wander) * speed;
            particle.vy += Math.sin(heading + wander) * speed;
          };
        case 'mapsequencearoundcontrolpoint':
          // One particle after another is sent off a step further round: so many to a turn.
          var toTurn = Math.max(1, Math.round(number(said.count, 1)));
          var offLeast = numbers(said.speedmin, 3, 0), offMost = numbers(said.speedmax, 3, 0);
          return function (particle) {
            var turn = ((particle.id - 1) % toTurn) / toTurn * Math.PI * 2;
            var share = Math.random();
            var x = mix(offLeast[0], offMost[0], share), y = mix(offLeast[1], offMost[1], share);
            particle.vx += x * Math.cos(turn) - y * Math.sin(turn);
            particle.vy += x * Math.sin(turn) + y * Math.cos(turn);
            particle.vz += mix(offLeast[2], offMost[2], share);
          };
        case 'hsvcolorrandom':
          // A color said as where on the wheel it is, how full and how light: each drawn by itself.
          var hues = [number(said.huemin, 0), number(said.huemax, 1)];
          if (hues[0] > 1.5 || hues[1] > 1.5) hues = [hues[0] / 360, hues[1] / 360];
          var fullness = [number(said.saturationmin, 0), number(said.saturationmax, 1)];
          var lightness = [number(said.valuemin, 0), number(said.valuemax, 1)];
          return function (particle) {
            var hue = ((pick(hues[0], hues[1]) % 1) + 1) % 1 * 6;
            var full = Math.max(0, Math.min(1, pick(fullness[0], fullness[1]))), light = Math.max(0, Math.min(1, pick(lightness[0], lightness[1])));
            function part(shift) {
              var k = (shift + hue) % 6;
              return light - light * full * Math.max(0, Math.min(k, 4 - k, 1));
            }
            particle.red = part(5);
            particle.green = part(3);
            particle.blue = part(1);
          };
        case 'mapsequencebetweencontrolpoints':
          // One particle after another is put a step further along the way from one of the
          // system's points to another: so many to the way, and then back or from the start.
          var toWay = Math.max(2, Math.round(number(said.count, 2)));
          var wayFrom = number(said.controlpointstart, 0), wayTo = number(said.controlpointend, 1);
          var back = key(said.limitbehavior || 'repeat') === 'mirror';
          return function (particle) {
            var step = (particle.id - 1) % (back ? (toWay - 1) * 2 : toWay);
            if (back && step >= toWay) step = (toWay - 1) * 2 - step;
            var share = step / (toWay - 1);
            var here = system.pointAt(wayFrom), there = system.pointAt(wayTo);
            particle.x = mix(here[0], there[0], share);
            particle.y = mix(here[1], there[1], share);
            particle.z = mix(here[2], there[2], share);
          };
        case 'colorlist':
          // One of the colors of a list, each as likely as another.
          var listed = (Array.isArray(said.colors) ? said.colors : []).map(function (each) { return color(each, 1); });
          if (!listed.length) return null;
          return function (particle) {
            var chosen = listed[Math.floor(Math.random() * listed.length)];
            particle.red = chosen[0];
            particle.green = chosen[1];
            particle.blue = chosen[2];
          };
        case 'positionoffsetrandom':
          // Put somewhere within a distance of where it was made.
          var within = number(said.distance, 0);
          return function (particle) {
            var turn = Math.random() * Math.PI * 2, far = Math.sqrt(Math.random()) * within;
            particle.x += Math.cos(turn) * far;
            particle.y += Math.sin(turn) * far;
          };
        case 'inheritcontrolpointvelocity':
          // Sent off with a share of the speed one of the system's points moves at: particles made
          // where the pointer is fly off the way it was going.
          var moving = number(said.controlpoint, 0);
          least = number(said.min, 1);
          most = number(said.max, 1);
          return function (particle) {
            var speed = system.pointVelocity(moving), share = pick(least, most);
            particle.vx += speed[0] * share;
            particle.vy += speed[1] * share;
            particle.vz += speed[2] * share;
          };
        case 'remapinitialvalue':
          return remapping(said, system);
        case 'inheritinitialvaluefromevent':
          // A child's particle made by one of its parent's starts as that one is.
          var taking = inheriting(said);
          return function (particle) {
            var parent = particle.from && (particle.from.source || particle.from.host);
            if (parent) taking(particle, parent);
          };
        default:
          note('“' + system.name + '”: what sets up a particle by “' + said.name + '” is not played');
          return null;
      }
    }

    // A property of a new particle set by something measured: how far it is from one of the
    // system's points, how far two points are apart, how long the system has run — or chance.
    function remapping(said, system) {
      var input = key(said.input || 'random');
      var from = number(said.inputrangemin, 0), to = number(said.inputrangemax, 1);
      var low = numbers(said.outputrangemin, 3, 0), high = numbers(said.outputrangemax, 3, 1);
      var how = key(said.operation || 'remap');
      // What is changed when the scene does not say: the size — Wallpaper Engine's own
      // lightning preset leaves it unsaid on a beam that narrows towards where it strikes
      // (inferred; its documentation does not name the default).
      var output = key(said.output || 'size');
      var first = number(said.inputcontrolpoint0, 0), second = number(said.inputcontrolpoint1, 1);
      function measured(particle) {
        var a, b;
        if (input === 'distancetocontrolpoint') {
          a = system.pointAt(first);
          return Math.sqrt(Math.pow(particle.x - a[0], 2) + Math.pow(particle.y - a[1], 2) + Math.pow(particle.z - a[2], 2));
        }
        if (input === 'distancebetweencontrolpoints') {
          a = system.pointAt(first);
          b = system.pointAt(second);
          return Math.sqrt(Math.pow(a[0] - b[0], 2) + Math.pow(a[1] - b[1], 2) + Math.pow(a[2] - b[2], 2));
        }
        if (input === 'particlesystemtime' || input === 'time') return system.age;
        if (input === 'lifetime') return particle.life;
        return mix(from, to, Math.random());
      }
      function put(old, value) {
        return how === 'add' ? old + value : (how === 'multiply' ? old * value : value);
      }
      var setters = {
        color: function (particle, value) {
          particle.red = put(particle.red, value[0]);
          particle.green = put(particle.green, value[1]);
          particle.blue = put(particle.blue, value[2]);
        },
        size: function (particle, value) { particle.size = put(particle.size, value[0]); },
        alpha: function (particle, value) { particle.alpha = put(particle.alpha, value[0]); },
        lifetime: function (particle, value) { particle.life = Math.max(0.01, put(particle.life, value[0])); },
        velocity: function (particle, value) {
          particle.vx = put(particle.vx, value[0]);
          particle.vy = put(particle.vy, value[1]);
          particle.vz = put(particle.vz, value[2]);
        },
        rotation: function (particle, value) { particle.angle = put(particle.angle, value[2]); },
        angularvelocity: function (particle, value) { particle.spin = put(particle.spin, value[2]); }
      };
      setters.opacity = setters.alpha;
      setters.angle = setters.rotation;
      var set = setters[output];
      if (!set) {
        note('“' + system.name + '”: a particle\'s “' + String(said.output) + '” set by “' + said.name + '” is not played');
        return null;
      }
      return function (particle) {
        var share = to === from ? 0 : Math.max(0, Math.min(1, (measured(particle) - from) / (to - from)));
        set(particle, [mix(low[0], high[0], share), mix(low[1], high[1], share), mix(low[2], high[2], share)]);
      };
    }

    // Takes what a particle of a child has from the particle of its parent it goes with: its
    // color unless another property is said.
    function inheriting(said) {
      var what = key(said.input || said.output || 'color');
      return function (particle, parent) {
        if (what === 'size') {
          particle.size = parent.size * (parent.sizeNow || 1);
        } else if (what === 'alpha' || what === 'opacity') {
          particle.alpha = parent.alpha * (parent.alphaNow || 1);
        } else if (what === 'velocity') {
          particle.vx = parent.vx;
          particle.vy = parent.vy;
          particle.vz = parent.vz;
        } else if (what === 'rotation' || what === 'angle') {
          particle.angle = parent.angle;
        } else {
          particle.red = parent.red * (parent.redNow || 1);
          particle.green = parent.green * (parent.greenNow || 1);
          particle.blue = parent.blue * (parent.blueNow || 1);
        }
      };
    }

    // How far a change that runs from `start` to `end` of a particle's life has got.
    function ramp(share, start, end) {
      return end <= start ? (share >= end ? 1 : 0) : Math.max(0, Math.min(1, (share - start) / (end - start)));
    }

    // What changes a particle as it lives; null for one not known here.
    function operator(said, system) {
      var start = number(said.starttime, 0), end = number(said.endtime, 1);
      // The wave of an oscillation at a moment of a particle's life, from −1 to 1. Each
      // particle has its own pace and start, drawn once from its own number.
      function wave(particle, share, salt) {
        var pace = mix(number(said.frequencymin, 0), number(said.frequencymax, 10), hash(particle.id, salt, 1));
        var shift = mix(number(said.phasemin, 0), number(said.phasemax, Math.PI * 2), hash(particle.id, salt, 2));
        return Math.sin(Math.PI * 2 * pace * share + shift);
      }
      switch (key(said.name)) {
        case 'movement':
          var gravity = numbers(said.gravity, 3, 0);
          var drag = number(said.drag, 0);
          return function (particle, seconds) {
            var keep = Math.max(0, 1 - drag * seconds);
            var pull = system.speedBy * seconds;
            particle.vx = (particle.vx + gravity[0] * pull) * keep;
            particle.vy = (particle.vy + gravity[1] * pull) * keep;
            particle.vz = (particle.vz + gravity[2] * pull) * keep;
            particle.x += particle.vx * seconds;
            particle.y += particle.vy * seconds;
            particle.z += particle.vz * seconds;
          };
        case 'angularmovement':
          var force = numbers(said.force, 3, 0)[2];
          var slowing = number(said.drag, 0);
          return function (particle, seconds) {
            particle.spin = (particle.spin + force * seconds) * Math.max(0, 1 - slowing * seconds);
            particle.angle += particle.spin * seconds;
          };
        case 'alphafade':
          var fadeIn = number(said.fadeintime, 0.5), fadeOut = number(said.fadeouttime, 0.5);
          return function (particle, seconds, share) {
            if (fadeIn > 0 && share < fadeIn) particle.alphaNow *= share / fadeIn;
            if (fadeOut < 1 && share > fadeOut) particle.alphaNow *= (1 - share) / (1 - fadeOut);
          };
        case 'sizechange':
          var sizeFrom = number(said.startvalue, 1), sizeTo = number(said.endvalue, 0);
          // The scene's own size factor counts once more here: Wallpaper Engine scales this
          // change by it as well as the particle (measured on ropes in its own window: 0.2 of
          // 40 at size 2 is 32 wide, not 16 — oscillatesize and alphachange take it only once).
          return function (particle, seconds, share) { particle.sizeNow *= mix(sizeFrom, sizeTo, ramp(share, start, end)) * system.sizeBy; };
        case 'alphachange':
          var alphaFrom = number(said.startvalue, 1), alphaTo = number(said.endvalue, 0);
          return function (particle, seconds, share) { particle.alphaNow *= mix(alphaFrom, alphaTo, ramp(share, start, end)); };
        case 'colorchange':
          var colorFrom = color(said.startvalue, 1), colorTo = color(said.endvalue, 1);
          return function (particle, seconds, share) {
            var done = ramp(share, start, end);
            particle.redNow *= mix(colorFrom[0], colorTo[0], done);
            particle.greenNow *= mix(colorFrom[1], colorTo[1], done);
            particle.blueNow *= mix(colorFrom[2], colorTo[2], done);
          };
        case 'oscillatealpha':
          var alphaLow = number(said.scalemin, 0), alphaHigh = number(said.scalemax, 1);
          return function (particle, seconds, share) { particle.alphaNow *= mix(alphaLow, alphaHigh, 0.5 + 0.5 * wave(particle, share, 31)); };
        case 'oscillatesize':
          var sizeLow = number(said.scalemin, 0.8), sizeHigh = number(said.scalemax, 1.2);
          return function (particle, seconds, share) { particle.sizeNow *= mix(sizeLow, sizeHigh, 0.5 + 0.5 * wave(particle, share, 37)); };
        case 'oscillateposition':
          var mask = numbers(said.mask, 3, [1, 1, 0]);
          var swingLow = number(said.scalemin, 1), swingHigh = number(said.scalemax, 1);
          return function (particle, seconds, share) {
            var swing = mix(swingLow, swingHigh, hash(particle.id, 43, 3)) * wave(particle, share, 41);
            particle.shiftX += mask[0] * swing;
            particle.shiftY += mask[1] * swing;
          };
        case 'turbulence':
          // A push that changes smoothly from place to place and with time.
          var grain = number(said.scale, 0.01), pace = number(said.timescale, 1);
          var pushLow = number(said.speedmin, 100), pushHigh = number(said.speedmax, 200);
          var along = numbers(said.mask, 3, [1, 1, 0]);
          return function (particle, seconds) {
            var push = mix(pushLow, pushHigh, hash(particle.id, 47, 4)) * seconds;
            var at = system.age * pace;
            particle.vx += along[0] * push * (smoothNoise(particle.x * grain + at, particle.y * grain, 4096, 5) - 0.5) * 2;
            particle.vy += along[1] * push * (smoothNoise(particle.x * grain, particle.y * grain + at, 4096, 6) - 0.5) * 2;
          };
        case 'controlpointattract':
          // Pulled toward one of the system's points, or pushed from it, while nearer to it
          // than the threshold.
          var toward = number(said.controlpoint, 0), pull = number(said.scale, 0), reach = number(said.threshold, 0);
          var beside = numbers(said.origin, 3, 0);
          return function (particle, seconds) {
            var point = system.pointAt(toward);
            var dx = point[0] + beside[0] - particle.x, dy = point[1] + beside[1] - particle.y, dz = point[2] + beside[2] - particle.z;
            var far = Math.sqrt(dx * dx + dy * dy + dz * dz);
            if (far < 0.0001 || (reach > 0 && far > reach)) return;
            var by = pull * seconds / far;
            particle.vx += dx * by;
            particle.vy += dy * by;
            particle.vz += dz * by;
          };
        case 'vortex_v2':
        case 'vortex':
          // Swept round one of the system's points: fastest within the inner distance, less
          // and less up to the outer one.
          var about = number(said.controlpoint, 0), swirlAt = numbers(said.offset, 3, 0);
          var inner = number(said.distanceinner, 0), outer = number(said.distanceouter, 0);
          var swiftest = number(said.speedinner, 0), slowest = number(said.speedouter, 0);
          var handed = numbers(said.axis, 3, [0, 0, 1])[2] < 0 ? -1 : 1;
          return function (particle, seconds) {
            var point = system.pointAt(about);
            var dx = particle.x - point[0] - swirlAt[0], dy = particle.y - point[1] - swirlAt[1];
            var far = Math.sqrt(dx * dx + dy * dy);
            if (far < 0.0001) return;
            var out = outer > inner ? Math.max(0, Math.min(1, (far - inner) / (outer - inner))) : (far > outer ? 1 : 0);
            var by = mix(swiftest, slowest, out) * seconds * handed / far;
            particle.vx -= dy * by;
            particle.vy += dx * by;
          };
        case 'remapvalue':
          // One of a particle's properties follows a wave or a smooth wandering along its life,
          // between two values. Each particle wanders its own way.
          var remapped = key(said.output || '');
          var way = key(said.transformfunction || 'linear');
          var grain = number(said.transforminputscale, 1);
          var lowest = numbers(said.outputrangemin, 3, 0), highest = numbers(said.outputrangemax, 3, 1);
          var inFrom = number(said.inputrangemin, 0), inTo = number(said.inputrangemax, 1);
          var how = key(said.operation || 'remap');
          function wandered(particle, share, axis) {
            var input = ramp(share, inFrom, inTo) * grain;
            if (/noise/.test(way)) return smoothNoise(input + particle.seed * 97 + axis * 31.7, particle.seed * 53 + axis * 17.3, 4096, 61 + axis);
            if (way === 'sine') return 0.5 + 0.5 * Math.sin(input * Math.PI * 2);
            if (way === 'cosine') return 0.5 + 0.5 * Math.cos(input * Math.PI * 2);
            if (way === 'square') return input % 1 < 0.5 ? 0 : 1;
            if (way === 'saw') return ((input % 1) + 1) % 1;
            if (way === 'triangle') return 1 - Math.abs(((input % 1) + 1) % 1 * 2 - 1);
            return Math.max(0, Math.min(1, input));
          }
          function taken(old, value, seconds) {
            return how === 'add' ? old + value * seconds : (how === 'multiply' ? old * value : value);
          }
          if (remapped === 'velocity') {
            return function (particle, seconds, share) {
              particle.vx = taken(particle.vx, mix(lowest[0], highest[0], wandered(particle, share, 0)), seconds);
              particle.vy = taken(particle.vy, mix(lowest[1], highest[1], wandered(particle, share, 1)), seconds);
              particle.vz = taken(particle.vz, mix(lowest[2], highest[2], wandered(particle, share, 2)), seconds);
            };
          }
          if (remapped === 'speed') {
            // How fast it goes the way it goes, as so many times its speed: drops on a window
            // run down, now quicker, now slower, and stop a while where it comes to nought or
            // less.
            return function (particle, seconds, share) {
              var by = Math.max(0, mix(lowest[0], highest[0], wandered(particle, share, 0)));
              particle.vx *= by;
              particle.vy *= by;
              particle.vz *= by;
            };
          }
          if (remapped === 'size') {
            return function (particle, seconds, share) { particle.sizeNow *= mix(lowest[0], highest[0], wandered(particle, share, 0)); };
          }
          if (remapped === 'alpha' || remapped === 'opacity') {
            return function (particle, seconds, share) { particle.alphaNow *= mix(lowest[0], highest[0], wandered(particle, share, 0)); };
          }
          if (remapped === 'color') {
            return function (particle, seconds, share) {
              particle.redNow *= mix(lowest[0], highest[0], wandered(particle, share, 0));
              particle.greenNow *= mix(lowest[1], highest[1], wandered(particle, share, 1));
              particle.blueNow *= mix(lowest[2], highest[2], wandered(particle, share, 2));
            };
          }
          if (remapped === 'rotation' || remapped === 'angle') {
            return function (particle, seconds, share) { particle.angle = taken(particle.angle, mix(lowest[2], highest[2], wandered(particle, share, 2)), seconds); };
          }
          if (remapped === 'angularvelocity') {
            return function (particle, seconds, share) { particle.spin = taken(particle.spin, mix(lowest[2], highest[2], wandered(particle, share, 2)), seconds); };
          }
          note('“' + system.name + '”: a particle\'s “' + String(said.output) + '” changed by “remapvalue” is not played');
          return null;
        case 'capvelocity':
          // No faster than a speed, from a point of its life on.
          var fastest = number(said.maxspeed, 100), capFrom = number(said.blendinstart, 0), capTo = number(said.blendinend, 0);
          return function (particle, seconds, share) {
            var speed = Math.sqrt(particle.vx * particle.vx + particle.vy * particle.vy + particle.vz * particle.vz);
            if (speed <= fastest || speed < 0.000001) return;
            var by = mix(1, fastest / speed, ramp(share, capFrom, capTo));
            particle.vx *= by;
            particle.vy *= by;
            particle.vz *= by;
          };
        case 'reducemovementnearcontrolpoint':
          // Slowed near one of the system's points: the most within the inner distance, less and
          // less up to the outer one.
          var slowAt = number(said.controlpoint, 0), slowInner = number(said.distanceinner, 0), slowOuter = number(said.distanceouter, 100);
          var cutInner = number(said.reductioninner, 1), cutOuter = number(said.reductionouter, 0);
          return function (particle, seconds) {
            var point = system.pointAt(slowAt);
            var far = Math.sqrt(Math.pow(particle.x - point[0], 2) + Math.pow(particle.y - point[1], 2) + Math.pow(particle.z - point[2], 2));
            var out = slowOuter > slowInner ? Math.max(0, Math.min(1, (far - slowInner) / (slowOuter - slowInner))) : (far > slowOuter ? 1 : 0);
            var keep = Math.max(0, 1 - mix(cutInner, cutOuter, out) * seconds);
            particle.vx *= keep;
            particle.vy *= keep;
            particle.vz *= keep;
          };
        case 'maintaindistancetocontrolpoint':
          // Kept at a distance from one of the system's points: drawn back to it from either side.
          var keptFrom = number(said.controlpoint, 0), keptAt = number(said.distance, 100), firm = number(said.variablestrength, 5);
          return function (particle, seconds) {
            var point = system.pointAt(keptFrom);
            var dx = particle.x - point[0], dy = particle.y - point[1], dz = particle.z - point[2];
            var far = Math.sqrt(dx * dx + dy * dy + dz * dz);
            if (far < 0.0001) return;
            var by = (keptAt - far) / far * Math.min(1, firm * seconds);
            particle.x += dx * by;
            particle.y += dy * by;
            particle.z += dz * by;
          };
        case 'maintaindistancebetweencontrolpoints':
          // Kept on the way between two of the system's points, as on a string held between them.
          var endA = number(said.controlpointstart, 0), endB = number(said.controlpointend, 1), hold = number(said.variablestrength, 5);
          return function (particle, seconds) {
            var a = system.pointAt(endA), b = system.pointAt(endB);
            var wx = b[0] - a[0], wy = b[1] - a[1], wz = b[2] - a[2];
            var length = wx * wx + wy * wy + wz * wz;
            var along = length > 0 ? Math.max(0, Math.min(1, ((particle.x - a[0]) * wx + (particle.y - a[1]) * wy + (particle.z - a[2]) * wz) / length)) : 0;
            var by = Math.min(1, hold * seconds);
            particle.x += (a[0] + wx * along - particle.x) * by;
            particle.y += (a[1] + wy * along - particle.y) * by;
            particle.z += (a[2] + wz * along - particle.z) * by;
          };
        case 'boids':
          // A flock: drawn to the middle of those near it and kept apart from the nearest,
          // going the way they go.
          var sight = Math.max(1, number(said.neighborthreshold, 50));
          var cohesion = number(said.cohesionfactor, 1), separation = number(said.separationfactor, 1), alignment = number(said.alignmentfactor, 0);
          return function (particle, seconds) {
            var near = system.neighbors(particle, sight);
            if (!near.length) return;
            var cx = 0, cy = 0, cz = 0, sx = 0, sy = 0, sz = 0, ax = 0, ay = 0, az = 0;
            near.forEach(function (other) {
              cx += other.x;
              cy += other.y;
              cz += other.z;
              ax += other.vx;
              ay += other.vy;
              az += other.vz;
              var dx = particle.x - other.x, dy = particle.y - other.y, dz = particle.z - other.z;
              var far = Math.sqrt(dx * dx + dy * dy + dz * dz) || 0.0001;
              var push = (sight - far) / sight / far;
              sx += dx * push;
              sy += dy * push;
              sz += dz * push;
            });
            var count = near.length;
            particle.vx += ((cx / count - particle.x) * cohesion + sx * separation * sight + (ax / count - particle.vx) * alignment) * seconds;
            particle.vy += ((cy / count - particle.y) * cohesion + sy * separation * sight + (ay / count - particle.vy) * alignment) * seconds;
            particle.vz += ((cz / count - particle.z) * cohesion + sz * separation * sight + (az / count - particle.vz) * alignment) * seconds;
          };
        case 'collisionplane':
        case 'collisionquad':
        case 'collisionsphere':
        case 'collisionbounds':
        case 'collisionmodel':
          return collision(said, system);
        case 'inheritvaluefromevent':
          // A child's particle that goes with one of its parent's keeps taking after it.
          var takingNow = inheriting(said);
          return function (particle) {
            var parent = particle.from && (particle.from.host || particle.from.source);
            if (parent) takingNow(particle, parent);
          };
        default:
          note('“' + system.name + '”: what changes a particle by “' + said.name + '” is not played');
          return null;
      }
    }

    // What a particle meets and what then becomes of it: it bounces off, slides along, stops or
    // dies. A plane (the ground, say), a rectangle of one, a ball, or the edges of the scene.
    function collision(said, system) {
      var kind = key(said.name);
      var behavior = key(said.collisionbehavior || 'bounce');
      var bounce = number(said.bouncefactor, behavior === 'slide' ? 0 : 0.5);
      var origin = numbers(said.origin, 3, 0);
      var normal = numbers(said.plane || said.normal || said.forward, 3, [0, 1, 0]);
      var length = Math.sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]) || 1;
      normal = normal.map(function (part) { return part / length; });
      var distance = number(said.distance, 0);
      var size = numbers(said.size, 2, 100);
      var radius = number(said.radius, 100);
      // Meets a surface with `n` pointing to the side it must stay on, `under` deep beyond it.
      function meet(particle, n, under) {
        particle.x += n[0] * under;
        particle.y += n[1] * under;
        particle.z += n[2] * under;
        if (behavior === 'kill' || behavior === 'die') {
          particle.age = particle.life;
          return;
        }
        var toward = particle.vx * n[0] + particle.vy * n[1] + particle.vz * n[2];
        if (toward >= 0) return;
        var by = behavior === 'stop' ? 1 : (behavior === 'slide' ? 1 : 1 + bounce);
        particle.vx -= n[0] * toward * by;
        particle.vy -= n[1] * toward * by;
        particle.vz -= n[2] * toward * by;
        if (behavior === 'stop') {
          particle.vx = particle.vy = particle.vz = 0;
        }
      }
      if (kind === 'collisionsphere') {
        return function (particle) {
          var dx = particle.x - origin[0], dy = particle.y - origin[1], dz = particle.z - origin[2];
          var far = Math.sqrt(dx * dx + dy * dy + dz * dz);
          if (far >= radius || far < 0.0001) return;
          meet(particle, [dx / far, dy / far, dz / far], radius - far);
        };
      }
      if (kind === 'collisionmodel') {
        // The model the scene names for it, met as the ball around its shape: the n-th such
        // operator of the system meets the n-th model its object depends on.
        var which = system.collisionModels = (system.collisionModels || 0) + 1;
        var needs = ((system.owner && system.owner.said && system.owner.said.dependencies) || []).filter(function (each) {
          return each && key(String(each.type || '')) === 'collisionmodel';
        });
        var need = needs.filter(function (each) { return number(each.index, 0) === which - 1; })[0] || needs[which - 1] || needs[0];
        if (!need) return null;
        return function (particle) {
          var model = byId[String(need.id)];
          if (!model || !model.bounds) return;
          var stands = standing(model, true);
          if (!stands.visible) return;
          var m = stands.matrix, b = model.bounds.middle;
          var middle = system.fromScene(m[0] * b[0] + m[4] * b[1] + m[8] * b[2] + m[12],
                                        m[1] * b[0] + m[5] * b[1] + m[9] * b[2] + m[13],
                                        m[2] * b[0] + m[6] * b[1] + m[10] * b[2] + m[14]);
          if (!middle) return;
          var grown = Math.max(Math.hypot(m[0], m[1], m[2]), Math.hypot(m[4], m[5], m[6]), Math.hypot(m[8], m[9], m[10]));
          var reach = model.bounds.radius * grown * middle[3];
          var dx = particle.x - middle[0], dy = particle.y - middle[1], dz = particle.z - middle[2];
          var far = Math.sqrt(dx * dx + dy * dy + dz * dz);
          if (far >= reach || far < 0.0001) return;
          meet(particle, [dx / far, dy / far, dz / far], reach - far);
        };
      }
      if (kind === 'collisionbounds') {
        return function (particle) {
          var box = system.sceneBox();
          if (!box) return;
          if (particle.x < box[0]) meet(particle, [1, 0, 0], box[0] - particle.x);
          if (particle.x > box[2]) meet(particle, [-1, 0, 0], particle.x - box[2]);
          if (particle.y < box[1]) meet(particle, [0, 1, 0], box[1] - particle.y);
          if (particle.y > box[3]) meet(particle, [0, -1, 0], particle.y - box[3]);
        };
      }
      // A plane through `origin` (a quad) or at `distance` from the system's middle.
      var through = kind === 'collisionquad' ? origin[0] * normal[0] + origin[1] * normal[1] + origin[2] * normal[2] : distance;
      return function (particle) {
        var side = particle.x * normal[0] + particle.y * normal[1] + particle.z * normal[2] - through;
        if (side >= 0) return;
        if (kind === 'collisionquad') {
          // Only within the rectangle, which lies across the plane.
          var rx = particle.x - origin[0], rz = particle.z - origin[2], ry = particle.y - origin[1];
          var across = Math.abs(normal[1]) > 0.5 ? [rx, rz] : [rx, ry];
          if (Math.abs(across[0]) > size[0] / 2 || Math.abs(across[1]) > size[1] / 2) return;
          // A particle that is well past it came round, not through it.
          if (side < -Math.max(4, Math.abs(particle.vx) + Math.abs(particle.vy) + Math.abs(particle.vz)) * 0.1) return;
        }
        meet(particle, normal, -side);
      };
    }

    function buildParticles(object, thing) {
      var fileName = String(plain(object.particle) || '');
      if (!json(fileName)) {
        note('“' + thing.name + '”: its particles, ' + fileName + ', are not in the scene');
        return null;
      }
      var system = particleSystem(fileName, thing, thing, null, 0);
      // A system begins as if it had been running for a while already: as long as the one of
      // its family that asks for the longest.
      var warm = Math.min(60, Math.max(0, system.warm));
      for (var played = 0; played < warm; played += 1 / 20) system.step(1 / 20);
      return system;
    }

    // The object of the scene another one depends on for something — `kind` as the scene
    // names it — the n-th of them, or the first; null for none.
    function dependency(thing, kind, nth) {
      var needs = ((thing.said && thing.said.dependencies) || []).filter(function (each) {
        return each && key(String(each.type || '')) === kind;
      });
      var need = needs.filter(function (each) { return number(each.index, 0) === nth; })[0] || needs[nth] || needs[0];
      return need ? { id: String(need.id) } : null;
    }

    // A point of the scene where a picture shows, picked at random among the places it is not
    // see-through: the picture is read back once, made small, when it has come.
    var OPAQUE_SIDE = 128;
    function opaqueSpot(wanted) {
      var picture = byId[wanted.id];
      if (!picture || !picture.size) return null;
      var source = picture.picture;
      var layer = source && source.ready !== false && source.layers ? source.layers[0] : null;
      if (!layer || !layer.texture) return null;
      if (picture.opaque === undefined || picture.opaqueFrom !== layer.texture) {
        picture.opaqueFrom = layer.texture;
        picture.opaque = opaqueCells(layer.texture, layer.width || source.width, layer.height || source.height, source.channels);
      }
      var cells = picture.opaque;
      if (!cells || !cells.length) return null;
      var cell = cells[Math.floor(Math.random() * cells.length)];
      var u = (cell % OPAQUE_SIDE + Math.random()) / OPAQUE_SIDE, v = (Math.floor(cell / OPAQUE_SIDE) + Math.random()) / OPAQUE_SIDE;
      var x = (u - 0.5) * picture.size[0], y = (0.5 - v) * picture.size[1];
      var m = standing(picture, true).matrix;
      return [m[0] * x + m[4] * y + m[12], m[1] * x + m[5] * y + m[13], m[2] * x + m[6] * y + m[14]];
    }
    function opaqueCells(texture, width, height, channels) {
      if (!(width > 0 && height > 0)) return null;
      var wasRead = bound.read, wasDrawn = bound.draw;
      var read = gl.createFramebuffer(), small = gl.createFramebuffer(), store = gl.createRenderbuffer();
      gl.bindRenderbuffer(gl.RENDERBUFFER, store);
      gl.renderbufferStorage(gl.RENDERBUFFER, gl.RGBA8, OPAQUE_SIDE, OPAQUE_SIDE);
      gl.bindFramebuffer(gl.FRAMEBUFFER, small);
      gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, store);
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, read);
      gl.framebufferTexture2D(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
      var cells = null;
      if (gl.checkFramebufferStatus(gl.READ_FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE) {
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, small);
        gl.blitFramebuffer(0, 0, width, height, 0, 0, OPAQUE_SIDE, OPAQUE_SIDE, gl.COLOR_BUFFER_BIT, gl.LINEAR);
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, small);
        var pixels = new Uint8Array(OPAQUE_SIDE * OPAQUE_SIDE * 4);
        gl.readPixels(0, 0, OPAQUE_SIDE, OPAQUE_SIDE, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
        // How see-through a texel is: its alpha, or for a texture of one or two channels the
        // last of them.
        var part = channels === 'r8' ? 0 : (channels === 'rg88' ? 1 : 3);
        cells = [];
        for (var i = 0; i < OPAQUE_SIDE * OPAQUE_SIDE; i++) if (pixels[i * 4 + part] > 127) cells.push(i);
      }
      gl.bindFramebuffer(gl.READ_FRAMEBUFFER, wasRead);
      gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, wasDrawn);
      gl.deleteFramebuffer(read);
      gl.deleteFramebuffer(small);
      gl.deleteRenderbuffer(store);
      return cells;
    }

    // A system of particles, made of its file, drawn for `thing`, the object of the scene that
    // has it. That is the system itself, or — for a child of another system, as `entry` of
    // that one's children says — the object of the system it is a child of, which it goes
    // with: where that one is, with what the scene changes of it. A child either makes its
    // particles alongside its parent, or goes with each of the parent's particles: follows
    // it, or makes its particles where one is made or where one dies.
    function firstOf(value) { return Array.isArray(value) ? value[0] : value; }

    function particleSystem(fileName, system, thing, entry, depth) {
      var said = json(fileName);
      var name = system.name;
      var material = ((json(said.material) || {}).passes || [])[0] || {};
      var over = thing.said.instanceoverride || {};
      // Whether it picks its particles a color at random, which a color the scene gives takes
      // the place of (see `settle`).
      system.picksColor = (said.initializer || []).some(function (each) { return each && key(String(each.name || '')) === 'colorrandom'; });
      // What the scene changes of the particles may be a script's — more of them while the
      // button is held, none but on a birthday — kept with the object's values and read
      // every frame, once for the object however many systems it has.
      if (!depth) {
        ['count', 'rate', 'size', 'alpha', 'lifetime', 'speed', 'colorn'].forEach(function (name) {
          var raw = over[name];
          if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return;
          also(thing, 'instance:' + name, live(raw, name === 'colorn' ? 3 : 1, 1, thing));
        });
      }
      // A value of the scene's change: as a script or a setting has it now, else as said.
      function overNow(name) {
        var now = thing.state['instance:' + name];
        return now !== undefined ? now : over[name];
      }
      var kind = entry ? key(String(plain(entry.type) || 'static')) : 'static';
      if (['static', 'eventfollow', 'eventspawn', 'eventdeath'].indexOf(kind) < 0) kind = 'static';
      system.kind = kind;
      system.children = [];
      // A child may be given a count of its own; one that goes with its parent's particles has
      // that many for each of them.
      var ownMost = entry && isSet(entry.maxcount) ? number(entry.maxcount, 100) : number(said.maxcount, 100);
      // Where a child stands on its parent's place, and the way back from there.
      var offset = entry ? matrixOf(numbers(entry.origin, 3, 0), numbers(entry.angles, 3, 0).map(function (angle) { return angle * Math.PI / 180; }),
                                    numbers(entry.scale, 3, 1)) : null;
      function placement(whole) {
        var up = standing(thing, whole);
        return offset ? { matrix: times(up.matrix, offset), alpha: up.alpha, above: up.above, visible: up.visible } : up;
      }
      function ownPoint(x, y, z) {
        if (!offset) return [x, y, z];
        var area = offset[0] * offset[5] - offset[4] * offset[1];
        if (Math.abs(area) < 1e-9) return null; // a child made of no size is not seen
        var dx = x - offset[12], dy = y - offset[13];
        return [(dx * offset[5] - dy * offset[4]) / area, (dy * offset[0] - dx * offset[1]) / area, z - offset[14]];
      }
      // Whether particles stay where they were made when what made them moves on, as a trail
      // does; a glow that goes with a particle moves along with it.
      var stays = (number(said.flags, 0) & 1) !== 0;
      system.moving = true;
      system.age = 0;
      system.particles = [];
      system.made = 0;
      // A particle that bends what is behind it, a drop on glass, has for its pictures how it
      // bends it rather than what it looks like. The bending is not drawn here; such a drop
      // shows as a clear bead.
      system.refracts = number(plain((material.combos || {}).REFRACT), 0) === 1 && !!refractProgram;
      system.refractAmount = number(plain((material.constantshadervalues || {}).ui_editor_properties_refract_amount), 0.05);
      system.picture = texture('materials/' + ((material.textures || [])[0] || 'particle/dot'));
      // A sheet of frames: each particle shows one at random, or goes through them as it lives.
      system.randomFrame = key(said.animationmode || '') === 'randomframe';
      // How a clear particle faces, for how it bends what is behind it.
      system.normals = system.refracts && (material.textures || [])[1] ? texture('materials/' + material.textures[1]) : null;
      system.frameRuns = Math.max(0.0001, number(said.sequencemultiplier, 1));
      // A clear drop that the scene does not bring a picture of is drawn as a drop, whatever
      // picture it names: a halo or a dot would bend nothing as a drop does.
      if (system.refracts && system.picture.made && !system.picture.builtin && system.picture.fill === undefined) {
        system.picture = texture('materials/particle/water/rain_drops_sheet');
      }
      system.additive = key(material.blending || 'translucent') === 'additive';
      // Hidden behind models in a scene in three dimensions, unless its material says not.
      system.depthTest = key(String(material.depthtest || 'enabled')) !== 'disabled';
      system.bright = number((material.constantshadervalues || {}).ui_editor_properties_overbright, 1);
      // Further away is smaller: the particles have depth, and are drawn as seen by an eye.
      system.perspective = (number(said.flags, 0) & 4) !== 0;
      // What the scene changes of the particles where it uses them; a setting of the
      // wallpaper may stand behind each, and the editor may change each.
      system.settle = function () {
        over = thing.said.instanceoverride || {};
        // None at all when the scene says so.
        // Wallpaper Engine's reference: count is the "factor to control emission rate", rate the
        // "factor to control simulation rate", speed the factor of "initial velocity and forces".
        // With only the room cut, a system short of it spends it at once and waits for all of
        // it to die, and its particles come in waves.
        system.countBy = Math.max(0, number(firstOf(overNow('count')), 1));
        system.each = Math.min(20000, Math.round(ownMost * system.countBy));
        system.most = kind === 'static' ? system.each : Math.min(20000, system.each * Math.max(1, system.owner ? system.owner.most : 1));
        system.pace = Math.max(0, number(firstOf(overNow('rate')), 1));
        system.sizeBy = number(firstOf(overNow('size')), 1);
        system.alphaBy = number(firstOf(overNow('alpha')), 1);
        system.speedBy = number(firstOf(overNow('speed')), 1);
        system.lifeBy = number(firstOf(overNow('lifetime')), 1);
        system.tint = [1, 1, 1];
        // The color the scene gives is the particles' color, whatever the system would have
        // given them and however it would have changed it as they live: a fire that burns
        // from yellow to red, given violet by the scene, is violet throughout. Wallpaper Engine
        // tints the particles with it, and in scenes saved before version 5 of its format,
        // where the system picks them a color at random, gives them this one in its place as
        // well, so it is drawn squared (`colorn` and `color` alike; measured in its own window:
        // 0.5 grey comes out 64 with colorrandom in versions 1 to 4, and 128 without it or in
        // version 5; 2981249186's violet fog, version 1, 0.37 0.26 0.69, is 35 18 121, and
        // 3598808038's calm fog, version 5, is not darkened).
        var colorn = overNow('colorn');
        system.recolorGiven = colorn !== undefined ? (Array.isArray(colorn) ? colorn.slice(0, 3) : color(colorn, 1)) : (over.color !== undefined ? color(over.color, 255) : null);
        var squared = system.picksColor && sceneVersion < 5;
        system.recolor = system.recolorGiven ? system.recolorGiven.map(function (part) { return squared ? part * part : part; }) : null;
      };
      // The color of a particle as it is drawn.
      system.colorOf = function (particle, state) {
        var own = system.recolor || [particle.red * particle.redNow, particle.green * particle.greenNow, particle.blue * particle.blueNow];
        return [own[0] * system.tint[0] * state.color[0], own[1] * system.tint[1] * state.color[1], own[2] * system.tint[2] * state.color[2]];
      };
      system.settle();
      // The points a system's particles are counted from. One may follow the pointer: a
      // system that makes its particles there trails the mouse.
      var points = (Array.isArray(said.controlpoint) ? said.controlpoint : []).map(function (point) {
        var id = number(point.id, 0);
        // The scene may put a point of the system somewhere of its own choosing: a place on
        // the scene, not one counted from the system.
        var put = over['controlpoint' + id];
        return { id: id, follows: (number(point.flags, 0) & 1) !== 0, offset: numbers(point.offset, 3, 0),
                 onScene: put !== undefined && put !== null ? numbers(put, 3, 0) : null };
      });
      var pointerThere = [0, 0]; // the pointer, in the system's own coordinates
      function follows(index) {
        return points.some(function (point) { return point.id === index && point.follows; });
      }
      system.pointAt = function (index) {
        var point = points.filter(function (each) { return each.id === index; })[0];
        if (!point) return [0, 0, 0];
        // A script may have put the point somewhere since.
        var put = (thing.said.instanceoverride || {})['controlpoint' + index];
        if (put !== undefined && put !== null) point.onScene = numbers(put, 3, 0);
        if (point.onScene) {
          var matrix = placement(true).matrix;
          var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
          if (Math.abs(area) < 1e-9) return point.offset;
          var dx = point.onScene[0] - matrix[12], dy = point.onScene[1] - matrix[13];
          return [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area, point.onScene[2]];
        }
        return point.follows ? [pointerThere[0] + point.offset[0], pointerThere[1] + point.offset[1], point.offset[2]] : point.offset;
      };
      // How fast each of the system's points moves, measured from one step to the next.
      var pointsBefore = {}, pointSpeeds = {};
      system.pointVelocity = function (index) {
        return pointSpeeds[index] || [0, 0, 0];
      };
      function measurePoints(seconds) {
        if (!(seconds > 0)) return;
        points.forEach(function (point) {
          var now = system.pointAt(point.id), before = pointsBefore[point.id];
          pointSpeeds[point.id] = before ? [(now[0] - before[0]) / seconds, (now[1] - before[1]) / seconds, (now[2] - before[2]) / seconds] : [0, 0, 0];
          pointsBefore[point.id] = now;
        });
      }
      // The scene's edges in the system's own coordinates: left, bottom, right, top.
      // A point of the scene in the system's own coordinates, and how much larger a length of
      // the scene is there; null where the system has no size.
      system.owner = thing;
      system.fromScene = function (x, y, z) {
        var matrix = placement(true).matrix;
        var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
        if (Math.abs(area) < 1e-9) return null;
        var dx = x - matrix[12], dy = y - matrix[13];
        return [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area, (z - matrix[14]) / Math.sqrt(Math.abs(area)), 1 / Math.sqrt(Math.abs(area))];
      };
      system.sceneBox = function () {
        var matrix = placement(true).matrix;
        var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
        if (Math.abs(area) < 1e-9) return null;
        var xs = [], ys = [];
        [[0, 0], [ctx.sceneWidth, 0], [0, ctx.sceneHeight], [ctx.sceneWidth, ctx.sceneHeight]].forEach(function (corner) {
          var dx = corner[0] - matrix[12], dy = corner[1] - matrix[13];
          xs.push((dx * matrix[5] - dy * matrix[4]) / area);
          ys.push((dy * matrix[0] - dx * matrix[1]) / area);
        });
        return [Math.min.apply(null, xs), Math.min.apply(null, ys), Math.max.apply(null, xs), Math.max.apply(null, ys)];
      };
      // The particles near one, found through a grid of cells as large as the distance looked
      // across, made once a step.
      var grid = null, gridSize = 0, gridAge = -1;
      system.neighbors = function (particle, reach) {
        if (gridAge !== system.age || gridSize !== reach) {
          grid = {};
          gridSize = reach;
          gridAge = system.age;
          system.particles.forEach(function (each) {
            var cell = Math.floor(each.x / reach) + ',' + Math.floor(each.y / reach);
            (grid[cell] || (grid[cell] = [])).push(each);
          });
        }
        var near = [], cx = Math.floor(particle.x / reach), cy = Math.floor(particle.y / reach);
        for (var gx = cx - 1; gx <= cx + 1; gx++) {
          for (var gy = cy - 1; gy <= cy + 1; gy++) {
            (grid[gx + ',' + gy] || []).forEach(function (other) {
              if (other === particle || near.length >= 32) return;
              var dx = other.x - particle.x, dy = other.y - particle.y, dz = other.z - particle.z;
              if (dx * dx + dy * dy + dz * dz < reach * reach) near.push(other);
            });
          }
        }
        return near;
      };
      function findPointer() {
        var matrix = placement(true).matrix;
        var area = matrix[0] * matrix[5] - matrix[4] * matrix[1];
        if (Math.abs(area) < 1e-9) return;
        var dx = ctx.pointer[0] * ctx.sceneWidth - matrix[12], dy = (1 - ctx.pointer[1]) * ctx.sceneHeight - matrix[13];
        pointerThere = [(dx * matrix[5] - dy * matrix[4]) / area, (dy * matrix[0] - dx * matrix[1]) / area];
      }
      var layerEmitters = 0;
      system.emitters = (said.emitter || []).map(function (emitter) {
        var fromLayer = key(emitter.name) === 'layerimage';
        return {
          // The picture of the scene it is made over, as the object names it; the n-th such
          // emitter has the n-th one.
          picture: fromLayer ? dependency(thing, 'emitterimage', layerEmitters++) : null,
          point: number(emitter.controlpoint, 0), withPointer: follows(number(emitter.controlpoint, 0)),
          box: key(emitter.name) === 'boxrandom',
          // Made all over a layer's picture: here, over the scene where the system lies.
          layer: key(emitter.name) === 'layerimage',
          origin: numbers(emitter.origin, 3, 0), directions: numbers(emitter.directions, 3, 1),
          least: numbers(emitter.distancemin, 3, 0), most: numbers(emitter.distancemax, 3, 256),
          sign: numbers(emitter.sign, 3, 0),
          rate: number(emitter.rate, 5), burst: number(emitter.instantaneous, 0),
          speedLeast: number(emitter.speedmin, 0), speedMost: number(emitter.speedmax, 0),
          lasts: number(emitter.duration, 0), waits: number(emitter.delay, 0), owed: 0,
          // Not more than one particle a frame, however many the rate owes: the second of the
          // emitter's flags (Wallpaper Engine's editor: "Limit to one per frame").
          eachFrame: (number(emitter.flags, 0) & 2) !== 0,
          hears: hearing(emitter)
        };
      });
      system.initializers = (said.initializer || []).map(function (each) { return initializer(each, system); }).filter(Boolean);
      system.operators = (said.operator || []).map(function (each) { return operator(each, system); }).filter(Boolean);
      (said.renderer || []).forEach(function (renderer) {
        var kind = key(renderer.name);
        if (kind === 'rope') {
          system.rope = true;
          // So many points between two particles, on a curve through them. A rope that does not
          // say bends as smoothly as one of 3 in Wallpaper Engine's own window; one of 0 has
          // sharp corners there.
          system.subdivision = Math.max(0, Math.min(16, Math.round(number(plain(renderer.subdivision), 3))));
        } else if (kind === 'spritetrail') {
          // Stretched along its way: so many times its width to a unit of speed, within bounds.
          system.trail = { by: number(renderer.length, 0.05), least: Math.max(0, number(renderer.minlength, 0)),
                           most: Math.max(0, number(renderer.maxlength, 10)) };
        } else if (kind === 'ropetrail') {
          // A tail behind each particle, through where it has been in the last seconds.
          system.tails = Math.max(0.02, number(renderer.length, 1));
        } else if (kind === 'sprite') {
          // Which way a sprite lies in a scene in three dimensions: turned to the eye (screen),
          // standing up and turned to it about the up axis (upright), or lying flat (fixed).
          system.orientation = key(String(plain(renderer.orientation) || 'screen'));
        } else {
          note('“' + name + '”: particles drawn as “' + renderer.name + '” are drawn as plain sprites');
        }
      });
      system.data = new Float32Array(system.most * FLOATS);
      system.buffer = gl.createBuffer();
      system.shape = gl.createVertexArray();
      gl.bindVertexArray(system.shape);
      gl.bindBuffer(gl.ARRAY_BUFFER, passBuffer);
      gl.enableVertexAttribArray(1);
      gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 20, 12);
      gl.bindBuffer(gl.ARRAY_BUFFER, system.buffer);
      gl.bufferData(gl.ARRAY_BUFFER, system.data.byteLength, gl.DYNAMIC_DRAW);
      [2, 3, 4, 7].forEach(function (place, attribute) {
        gl.enableVertexAttribArray(place);
        gl.vertexAttribPointer(place, 4, gl.FLOAT, false, FLOATS * 4, attribute * 16);
        gl.vertexAttribDivisor(place, 1);
      });
      gl.bindVertexArray(null);

      // Where the system makes its particles: for most, the one place of the system itself; for
      // a child that goes with its parent's particles, the place of each of them — those it
      // follows, or where one was made or died. `alive`: how many of its particles live.
      system.instances = kind === 'static' ? [{ at: [0, 0, 0], age: 0, owed: [], burst: [], alive: 0 }] : [];

      // Something happened to a particle of the parent: it was made, or it died.
      system.event = function (particle) {
        var at = ownPoint(particle.x + (particle.shiftX || 0), particle.y + (particle.shiftY || 0), particle.z);
        if (at) system.instances.push({ at: at, age: 0, owed: [], burst: [], alive: 0, source: particle });
      };

      // A child that follows the parent's particles makes its particles where each of them is.
      function followParent() {
        var known = {};
        system.instances.forEach(function (instance) { known[instance.host.id] = instance; });
        system.instances = system.owner.particles.map(function (particle) {
          var instance = known[particle.id] || { host: particle, age: 0, owed: [], burst: [], alive: 0 };
          instance.at = ownPoint(particle.x + (particle.shiftX || 0), particle.y + (particle.shiftY || 0), particle.z);
          return instance;
        }).filter(function (instance) { return instance.at; });
      }

      function room(instance) {
        return system.particles.length < system.most && (kind === 'static' || instance.alive < system.each);
      }

      function tell(what, particle) {
        system.children.forEach(function (child) {
          if (child.kind === what) child.event(particle);
        });
      }

      function make(emitter, instance) {
        var particle = { id: ++system.made, seed: Math.random(), age: 0, life: 1, size: 20, alpha: 1, red: 1, green: 1, blue: 1,
                         angle: 0, spin: 0, x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, from: instance, base: instance.at.slice() };
        var away = [0, 0, 0];
        var axis;
        var spot = emitter.picture ? opaqueSpot(emitter.picture) : null;
        var spread = emitter.layer && !spot && !emitter.picture ? system.sceneBox() : null;
        if (emitter.picture && !spot) {
          // Its picture shows nothing yet, or nowhere: nothing is made.
          return null;
        }
        if (spot) {
          var there = system.fromScene(spot[0], spot[1], spot[2]);
          if (!there) return null;
          var from0 = system.pointAt(emitter.point);
          away = [there[0] - emitter.origin[0] - from0[0] - instance.at[0], there[1] - emitter.origin[1] - from0[1] - instance.at[1],
                  there[2] - emitter.origin[2] - from0[2] - instance.at[2]];
        } else if (spread) {
          away = [mix(spread[0], spread[2], Math.random()), mix(spread[1], spread[3], Math.random()), 0];
        } else if (emitter.box) {
          for (axis = 0; axis < 3; axis++) {
            var side = emitter.sign[axis] > 0 ? 1 : (emitter.sign[axis] < 0 ? -1 : (Math.random() < 0.5 ? -1 : 1));
            away[axis] = side * mix(emitter.least[axis], emitter.most[axis], Math.random()) * emitter.directions[axis];
          }
        } else {
          // Anywhere in the ball as far out as the most, evenly through its volume, squeezed
          // along each axis by the directions; not nearer the middle than the least once so
          // squeezed. Measured in Wallpaper Engine's window: squeezed to a line, particles
          // lie evenly along it with a gap at the middle as wide as the least; squeezed to a
          // flat oval they thin out toward its rim as a ball seen from the side does
          // (1823900922's rain had bunched in the middle of each system).
          var least = emitter.least[0], most = emitter.most[0], tries = 0, reach;
          var inner = Math.pow(Math.max(0, Math.min(least, most)), 3), outer = Math.pow(Math.max(0, most), 3);
          do {
            var turn = Math.random() * Math.PI * 2, rise = Math.random() * 2 - 1, flat = Math.sqrt(1 - rise * rise);
            var toward = [Math.cos(turn) * flat, Math.sin(turn) * flat, rise];
            var far = Math.cbrt(inner + (outer - inner) * Math.random());
            reach = 0;
            for (axis = 0; axis < 3; axis++) {
              if (emitter.sign[axis] !== 0) toward[axis] = Math.abs(toward[axis]) * (emitter.sign[axis] > 0 ? 1 : -1);
              away[axis] = toward[axis] * far * emitter.directions[axis];
              reach += away[axis] * away[axis];
            }
          } while (least > 0 && Math.sqrt(reach) < least && ++tries < 12);
        }
        var from = system.pointAt(emitter.point);
        particle.x = emitter.origin[0] + away[0] + from[0] + instance.at[0];
        particle.y = emitter.origin[1] + away[1] + from[1] + instance.at[1];
        particle.z = emitter.origin[2] + away[2] + from[2] + instance.at[2];
        var speed = mix(emitter.speedLeast, emitter.speedMost, Math.random());
        var length = Math.sqrt(away[0] * away[0] + away[1] * away[1] + away[2] * away[2]);
        if (speed !== 0 && length > 0) {
          particle.vx = away[0] / length * speed;
          particle.vy = away[1] / length * speed;
          particle.vz = away[2] / length * speed;
        }
        system.initializers.forEach(function (set) { set(particle); });
        particle.vx *= system.speedBy;
        particle.vy *= system.speedBy;
        particle.vz *= system.speedBy;
        // The scene's lifetime for its particles: as many times as long for the system it names;
        // the systems that come with it — a glow round each spark, a ring that grows out of a
        // circle — live as many times shorter. Measured on Wallpaper Engine's own video of
        // "Zoltraak": its growing ring comes back every 2 / 0.48 seconds, not 2 × 0.48.
        if (entry) particle.life /= Math.max(0.01, system.lifeBy);
        else particle.life *= system.lifeBy;
        system.particles.push(particle);
        instance.alive++;
        tell('eventspawn', particle);
      }

      system.emitNow = function (count) {
        var instance = system.instances[0];
        if (!instance) return;
        for (var made = 0; made < count && room(instance); made++) {
          system.emitters.forEach(function (emitter) { if (room(instance)) make(emitter, instance); });
        }
        ctx.dirty = true;
      };
      var steered = ['count', 'rate', 'size', 'alpha', 'lifetime', 'speed', 'colorn'].some(function (name) { return thing.lives['instance:' + name]; });
      system.step = function (seconds) {
        // What scripts make of the scene's change, taken up as it comes.
        if (steered) system.settle();
        seconds *= system.pace;
        system.age += seconds;
        if (points.length) measurePoints(seconds);
        if (points.some(function (point) { return point.follows; })) findPointer();
        if (kind === 'eventfollow' && system.owner) followParent();
        system.instances.forEach(function (instance) {
          instance.age += seconds;
          system.emitters.forEach(function (emitter, index) {
            if (instance.age < emitter.waits) return;
            // Particles made where the pointer is are not made while it is away.
            if (emitter.withPointer && !ctx.pointerSeen) return;
            // A script may have stopped the system making particles.
            if (system.emitting === false) return;
            if (emitter.burst > 0 && !instance.burst[index]) {
              instance.burst[index] = true;
              for (var first = 0; first < emitter.burst && room(instance); first++) make(emitter, instance);
            }
            if (emitter.lasts > 0 && instance.age > emitter.waits + emitter.lasts) return;
            var loud = emitter.hears ? emitter.hears() : 1;
            instance.owed[index] = (instance.owed[index] || 0) + emitter.rate * system.countBy * loud * seconds;
            if (emitter.eachFrame) instance.owed[index] = Math.min(instance.owed[index], 1);
            while (instance.owed[index] >= 1) {
              instance.owed[index] -= 1;
              if (room(instance)) make(emitter, instance);
            }
          });
        });
        // What a particle made or dying started is over once its child has made what it makes:
        // a burst, or particles for as long as the child says — for a second where it does not.
        if (kind === 'eventspawn' || kind === 'eventdeath') {
          system.instances = system.instances.filter(function (instance) {
            return system.emitters.some(function (emitter) {
              return instance.age < emitter.waits || (emitter.rate > 0 && instance.age < emitter.waits + (emitter.lasts > 0 ? emitter.lasts : 1));
            });
          });
        }
        var alive = [];
        system.instances.forEach(function (instance) { instance.alive = 0; });
        system.particles.forEach(function (particle) {
          particle.age += seconds;
          if (particle.age >= particle.life) {
            tell('eventdeath', particle);
            return;
          }
          // A particle of a child that follows another goes along with it, unless it stays
          // where it was made.
          if (!stays && kind === 'eventfollow' && particle.from.at) {
            var at = particle.from.at;
            particle.x += at[0] - particle.base[0];
            particle.y += at[1] - particle.base[1];
            particle.z += at[2] - particle.base[2];
            particle.base = at.slice();
          }
          particle.from.alive++;
          particle.alphaNow = particle.sizeNow = particle.redNow = particle.greenNow = particle.blueNow = 1;
          particle.shiftX = particle.shiftY = 0;
          var share = particle.age / particle.life;
          system.operators.forEach(function (change) { change(particle, seconds, share); });
          if (system.tails) {
            // Where it has been, many times a tail's length, the oldest first — with one
            // place at or before the tail's end kept, for the end to be put between the two.
            var path = particle.path || (particle.path = []);
            if (!path.length || system.age - path[path.length - 1][2] >= system.tails / 48) {
              path.push([particle.x + particle.shiftX, particle.y + particle.shiftY, system.age, particle.z]);
            }
            while (path.length > 1 && system.age - path[1][2] >= system.tails) path.shift();
          }
          alive.push(particle);
        });
        system.particles = alive;
      };

      // The places a rope trail runs through, the oldest first, the particle itself last, each
      // with how far along the tail it is in time (0 at its end, 1 at the particle). The end is
      // just as long ago as the tail is long, put between the two places it falls between, so
      // the tail moves on smoothly and does not lose a piece each time a place is let go.
      function tailOf(particle) {
        var path = particle.path || [];
        var spots = path.map(function (spot) { return [spot[0], spot[1], spot[3] || 0, spot[2]]; });
        spots.push([particle.x + particle.shiftX, particle.y + particle.shiftY, particle.z, system.age]);
        var cut = system.age - system.tails;
        if (spots.length > 1 && spots[0][3] < cut) {
          var a = spots[0], b = spots[1], share = (cut - a[3]) / Math.max(1e-6, b[3] - a[3]);
          spots[0] = [mix(a[0], b[0], share), mix(a[1], b[1], share), mix(a[2], b[2], share), cut];
        }
        var from = spots[0][3], span = Math.max(1e-6, system.age - from);
        return spots.map(function (spot) { return [spot[0], spot[1], spot[2], (spot[3] - from) / span]; });
      }

      // How far the eye is from the scene, for particles with depth.
      var away = (ctx.sceneHeight / 2) / Math.tan(number(general.perspectiveoverridefov, number(general.fov, 50)) * Math.PI / 360);

      // In a scene in three dimensions, as Wallpaper Engine's particle shaders do it: a sprite
      // is a square about the particle in the system's own space — along its axes, or turned
      // to the eye — or, for a trail, stretched along its way; a rope trail is a band through
      // where the particle has been, turned to the eye. All of it then goes through the
      // system's whole matrix, its scale on each axis with it, and is hidden behind models.
      function drawDeep() {
        var stands = placement();
        if (!stands.visible || !system.particles.length || !deepParticleProgram) return;
        var model = stands.matrix;
        var back = m4invert(model);
        function inward(v) { return [back[0] * v[0] + back[4] * v[1] + back[8] * v[2], back[1] * v[0] + back[5] * v[1] + back[9] * v[2], back[2] * v[0] + back[6] * v[1] + back[10] * v[2]]; }
        var basis = eyeBasis();
        // Which way the eye's right and up are in the system's own space, a unit long there,
        // as Wallpaper Engine's particle shader takes them: what is drawn is then as much
        // larger as the system is scaled (3737268876's fairy: a glow scaled 0.35 within one
        // scaled 0.59).
        var viewRight = unit(inward(basis.right)), viewUp = unit(inward(basis.up));
        var wholeScale = Math.cbrt(Math.abs(model[0] * (model[5] * model[10] - model[6] * model[9]) - model[4] * (model[1] * model[10] - model[2] * model[9]) + model[8] * (model[1] * model[6] - model[2] * model[5]))) || 1;
        var eye = basis.eye, eyeHere = [back[0] * eye[0] + back[4] * eye[1] + back[8] * eye[2] + back[12],
                                        back[1] * eye[0] + back[5] * eye[1] + back[9] * eye[2] + back[13],
                                        back[2] * eye[0] + back[6] * eye[1] + back[10] * eye[2] + back[14]];
        function unit(v) { var l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; }
        function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
        var see = system.alphaBy * stands.alpha, state = system.state;
        var frames = sheetFrames(system.picture);
        var layer = system.picture.layers[0];
        var ratio = frames && frames[0] ? (frames[0][3] * (layer.height || 1)) / Math.max(1e-6, frames[0][2] * (layer.width || 1))
                                        : (layer.height || 1) / Math.max(1, layer.width || 1);
        var out = [];
        function corner(p, u, v, cell, tint) {
          out.push(p[0], p[1], p[2], cell ? cell[0] + u * cell[2] : u, cell ? cell[1] + v * cell[3] : v, tint[0], tint[1], tint[2], tint[3]);
        }
        system.particles.slice(0, system.most).forEach(function (particle) {
          var tint = system.colorOf(particle, state).concat([Math.max(0, particle.alpha * particle.alphaNow * see)]);
          if (!(tint[3] > 0.001)) return;
          var here = [particle.x + particle.shiftX, particle.y + particle.shiftY, particle.z];
          var size = particle.size * particle.sizeNow * system.sizeBy * PARTICLE_SIDE;
          var cell = frames ? frames[system.randomFrame
            ? Math.floor(hash(particle.id, 3, 11) * frames.length) % frames.length
            : Math.min(frames.length - 1, Math.floor((((particle.age / particle.life) * system.frameRuns) % 1) * frames.length))] : null;
          if (system.tails) {
            // As the rope trails of flat scenes, measured on Wallpaper Engine's previews: as
            // wide as the particle times the system's scale taken whole (not stretched along
            // any one axis), across the way it goes and the way the eye looks — laid in the
            // scene's own space, so the band is drawn without the system's matrix.
            var spots = tailOf(particle);
            if (spots.length < 2) return;
            spots = spots.map(function (spot) { return [model[0] * spot[0] + model[4] * spot[1] + model[8] * spot[2] + model[12],
                                                         model[1] * spot[0] + model[5] * spot[1] + model[9] * spot[2] + model[13],
                                                         model[2] * spot[0] + model[6] * spot[1] + model[10] * spot[2] + model[14], spot[3]]; });
            var rows = [];
            var half = particle.size * particle.sizeNow * system.sizeBy * wholeScale / 2;
            spots.forEach(function (spot, index) {
              var before = spots[Math.max(0, index - 1)], after = spots[Math.min(spots.length - 1, index + 1)];
              var along = [after[0] - before[0], after[1] - before[1], after[2] - before[2]];
              var across = unit(cross([spot[0] - eye[0], spot[1] - eye[1], spot[2] - eye[2]], along));
              var v = 1 - spot[3];
              rows.push([[spot[0] - across[0] * half, spot[1] - across[1] * half, spot[2] - across[2] * half], 0, v],
                        [[spot[0] + across[0] * half, spot[1] + across[1] * half, spot[2] + across[2] * half], 1, v]);
            });
            for (var r = 0; r + 1 < rows.length / 2; r++) {
              var a = rows[r * 2], b = rows[r * 2 + 1], c = rows[r * 2 + 2], d = rows[r * 2 + 3];
              [a, b, c, b, d, c].forEach(function (point) { corner(point[0], point[1], point[2], cell, tint); });
            }
            return;
          }
          var right, up;
          if (system.trail) {
            var speed = [particle.vx, particle.vy, particle.vz || 0];
            var length = Math.hypot(speed[0], speed[1], speed[2]);
            if (length < 1e-6) return;
            right = unit(cross([here[0] - eyeHere[0], here[1] - eyeHere[1], here[2] - eyeHere[2]], speed));
            var long = Math.max(system.trail.least, Math.min(system.trail.most, length * system.trail.by));
            up = [speed[0] / length * long, speed[1] / length * long, speed[2] / length * long];
          } else {
            // Clockwise, as on a flat scene.
            var c0 = Math.cos(particle.angle || 0), s0 = -Math.sin(particle.angle || 0);
            // Flat is along the system's x and z — measured on Wallpaper Engine's video of
            // Sonic AKIBA, whose speed lines are flat sprites that point at the far end of the
            // street; upright keeps the system's y up.
            var axisX = viewRight, axisY = viewUp;
            if (system.orientation === 'fixed') { axisX = [1, 0, 0]; axisY = [0, 0, 1]; }
            else if (system.orientation === 'upright') { axisY = [0, 1, 0]; axisX = unit([viewRight[0], 0, viewRight[2]]); }
            right = [axisX[0] * c0 + axisY[0] * s0, axisX[1] * c0 + axisY[1] * s0, axisX[2] * c0 + axisY[2] * s0];
            up = [axisY[0] * c0 - axisX[0] * s0, axisY[1] * c0 - axisX[1] * s0, axisY[2] * c0 - axisX[2] * s0];
          }
          function at(u, v) {
            var a = size * (u - 0.5), b = size * (v - 0.5) * ratio;
            return [here[0] + right[0] * a - up[0] * b, here[1] + right[1] * a - up[1] * b, here[2] + right[2] * a - up[2] * b];
          }
          [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]].forEach(function (uv) { corner(at(uv[0], uv[1]), uv[0], uv[1], cell, tint); });
        });
        var count = out.length / 9;
        if (!count) return;
        if (!deepParticleBuffer) {
          deepParticleBuffer = gl.createBuffer();
          deepParticleShape = gl.createVertexArray();
          gl.bindVertexArray(deepParticleShape);
          gl.bindBuffer(gl.ARRAY_BUFFER, deepParticleBuffer);
          gl.enableVertexAttribArray(0);
          gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 36, 0);
          gl.enableVertexAttribArray(1);
          gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 36, 12);
          gl.enableVertexAttribArray(3);
          gl.vertexAttribPointer(3, 4, gl.FLOAT, false, 36, 20);
          gl.bindVertexArray(null);
        }
        if (deepParticleData.length < out.length) deepParticleData = new Float32Array(out.length * 2);
        deepParticleData.set(out);
        var program = deepParticleProgram;
        function slot(name) { var uniform = program.uniforms[name]; return uniform ? uniform.location : null; }
        var target = ctx.surface.target;
        depthOf(target);
        gl.bindFramebuffer(gl.FRAMEBUFFER, target.framebuffer);
        gl.viewport(0, 0, target.width, target.height);
        gl.useProgram(program.program);
        gl.uniformMatrix4fv(slot('u_Matrix'), false, new Float32Array(system.tails ? viewProjection() : times4(viewProjection(), model)));
        gl.enable(gl.BLEND);
        if (system.additive) gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
        else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        if (system.depthTest) gl.enable(gl.DEPTH_TEST); else gl.disable(gl.DEPTH_TEST);
        gl.depthFunc(gl.LEQUAL);
        gl.depthMask(false);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, layer.texture);
        gl.uniform1i(slot('u_Texture'), 0);
        gl.uniform1i(slot('u_Channels'), CHANNELS[system.picture.channels] || 0);
        gl.uniform1f(slot('u_Bright'), system.bright);
        gl.bindVertexArray(deepParticleShape);
        gl.bindBuffer(gl.ARRAY_BUFFER, deepParticleBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, deepParticleData.subarray(0, out.length), gl.DYNAMIC_DRAW);
        gl.drawArrays(gl.TRIANGLES, 0, count);
        gl.bindVertexArray(null);
        gl.disable(gl.DEPTH_TEST);
        gl.depthMask(true);
      }

      system.draw = function () {
        if (inDepth) return drawDeep();
        if (!particleProgram || !system.particles.length) return;
        var stands = placement();
        if (!stands.visible) return;
        // The editor may have let the system have more particles than there was room for.
        if (system.data.length < system.most * FLOATS) {
          system.data = new Float32Array(system.most * FLOATS);
          gl.bindBuffer(gl.ARRAY_BUFFER, system.buffer);
          gl.bufferData(gl.ARRAY_BUFFER, system.data.byteLength, gl.DYNAMIC_DRAW);
        }
        var state = system.state;
        // Counted from the lower left corner of what the particles are drawn on.
        var matrix = stands.matrix;
        var originX = matrix[12] - ctx.surface.left, originY = matrix[13] - ctx.surface.bottom;
        var middleX = ctx.surface.width / 2, middleY = ctx.surface.height / 2;
        // Its own directions there: stretched, then turned.
        var linear = [matrix[0], matrix[1], matrix[4], matrix[5]];
        var deep = Math.sqrt(matrix[8] * matrix[8] + matrix[9] * matrix[9] + matrix[10] * matrix[10]);
        var see = system.alphaBy * stands.alpha;
        var data = system.data;
        var count = Math.min(system.particles.length, system.most);
        var layer = system.picture.layers[0];
        var frames = sheetFrames(system.picture);
        // As Wallpaper Engine's particle shader: a sprite is as tall to its width as its
        // picture (or a frame of its sheet), so a tall shaft of light stays tall.
        var ratio = frames && frames[0] ? (frames[0][3] * (layer.height || 1)) / Math.max(1e-6, frames[0][2] * (layer.width || 1))
                                        : (layer.height || 1) / Math.max(1, layer.width || 1);
        for (var i = 0; i < count; i++) {
          var particle = system.particles[i];
          var localX = particle.x + particle.shiftX, localY = particle.y + particle.shiftY;
          var x = originX + linear[0] * localX + linear[2] * localY;
          var y = originY + linear[1] * localX + linear[3] * localY;
          var near = 1, unseen = false;
          if (system.perspective) {
            // What has passed the eye is not seen. Drawn at the eye instead, it was a broad
            // bright bar over the middle of the scene.
            var ahead = away - particle.z * deep;
            unseen = ahead < away * 0.05;
            near = away / Math.max(away * 0.05, ahead);
            x = middleX + (x - middleX) * near;
            y = middleY + (y - middleY) * near;
          }
          var at = i * FLOATS;
          // A particle's own angle turns it clockwise, as Wallpaper Engine does (measured in its
          // window: 0.5 leans a light shaft's top to the right, and a spin of −0.1 turns it
          // the other way; 3598808038's shafts had leant twice as far as its own).
          var turned = -particle.angle, long = 1;
          if (system.trail) {
            var speed = Math.sqrt(particle.vx * particle.vx + particle.vy * particle.vy);
            long = Math.max(system.trail.least, Math.min(system.trail.most, speed * system.trail.by));
            if (speed > 0.0001) turned = Math.atan2(particle.vy, particle.vx) - Math.PI / 2;
          }
          data[at] = x;
          data[at + 1] = y;
          data[at + 2] = unseen ? 0 : particle.size * particle.sizeNow * system.sizeBy * near * PARTICLE_SIDE;
          data[at + 3] = turned;
          var shade = system.colorOf(particle, state);
          data[at + 4] = shade[0];
          data[at + 5] = shade[1];
          data[at + 6] = shade[2];
          data[at + 7] = Math.max(0, particle.alpha * particle.alphaNow * see);
          // The frame of a sheet it shows: one chosen when it was made, or one after another
          // along its life, as many times over as the system says.
          var cell = frames ? frames[system.randomFrame
            ? Math.floor(hash(particle.id, 3, 11) * frames.length) % frames.length
            : Math.min(frames.length - 1, Math.floor((((particle.age / particle.life) * system.frameRuns) % 1) * frames.length))] : null;
          data[at + 8] = cell ? cell[0] : 0;
          data[at + 9] = cell ? cell[1] : 0;
          data[at + 10] = cell ? cell[2] : 1;
          data[at + 11] = cell ? cell[3] : 1;
          data[at + 12] = long * ratio;
        }
        var program = system.refracts ? refractProgram : particleProgram;
        // A uniform the compiler left out has no place; setting it at none does nothing.
        function slot(name) { var uniform = program.uniforms[name]; return uniform ? uniform.location : null; }
        if (system.refracts) {
          // What is under the drops, as it is before they are drawn.
          var onto = ctx.surface.target;
          if (!ctx.surface.copy) ctx.surface.copy = acquire(onto.width, onto.height);
          gl.bindFramebuffer(gl.READ_FRAMEBUFFER, onto.framebuffer);
          gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, ctx.surface.copy.framebuffer);
          gl.blitFramebuffer(0, 0, onto.width, onto.height, 0, 0, onto.width, onto.height, gl.COLOR_BUFFER_BIT, gl.NEAREST);
          gl.bindFramebuffer(gl.FRAMEBUFFER, onto.framebuffer);
        }
        gl.useProgram(program.program);
        gl.enable(gl.BLEND);
        if (system.additive) gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
        else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, layer.texture);
        gl.uniform1i(slot('u_Texture'), 0);
        gl.uniform1i(slot('u_Channels'), CHANNELS[system.picture.channels] || 0);
        gl.uniform1f(slot('u_Bright'), system.bright);
        gl.uniformMatrix2fv(slot('u_Linear'), false, new Float32Array(linear));
        gl.uniform2f(slot('u_Scene'), ctx.surface.width, ctx.surface.height);
        if (system.refracts) {
          gl.activeTexture(gl.TEXTURE1);
          gl.bindTexture(gl.TEXTURE_2D, ctx.surface.copy.texture);
          gl.uniform1i(slot('u_Behind'), 1);
          gl.uniform2f(slot('u_BehindSize'), ctx.surface.target.width, ctx.surface.target.height);
          gl.uniform1f(slot('u_Amount'), system.refractAmount);
          gl.uniform1f(slot('u_Fill'), system.picture.fill || 1);
          // The map of how the particles face, if the material has one ready.
          var facing = system.normals && system.normals.ready !== false ? system.normals : null;
          gl.uniform1i(slot('u_NormalChannels'), !facing ? 0 : facing.builtin ? 1 : CHANNELS[facing.channels] === 2 ? 2 : 3);
          gl.uniform1f(slot('u_NormalLevel'), facing && facing.compressed ? 0.965 : 1);
          if (facing) {
            gl.activeTexture(gl.TEXTURE2);
            gl.bindTexture(gl.TEXTURE_2D, facing.layers[0].texture);
            gl.uniform1i(slot('u_Normal'), 2);
          }
          gl.activeTexture(gl.TEXTURE0);
        }
        gl.bindVertexArray(system.shape);
        gl.bindBuffer(gl.ARRAY_BUFFER, system.buffer);
        gl.bufferSubData(gl.ARRAY_BUFFER, 0, data.subarray(0, count * FLOATS));
        gl.drawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, count);
        gl.bindVertexArray(null);
      };

      if (system.rope && ropeProgram) {
        // Two points to a particle, one at each edge of the band, with its color.
        var band = new Float32Array(system.most * 16);
        var bandBuffer = gl.createBuffer();
        var bandShape = gl.createVertexArray();
        gl.bindVertexArray(bandShape);
        gl.bindBuffer(gl.ARRAY_BUFFER, bandBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, band.byteLength, gl.DYNAMIC_DRAW);
        gl.enableVertexAttribArray(2);
        gl.vertexAttribPointer(2, 4, gl.FLOAT, false, 32, 0);
        gl.enableVertexAttribArray(3);
        gl.vertexAttribPointer(3, 4, gl.FLOAT, false, 32, 16);
        gl.bindVertexArray(null);
        system.draw = function () {
          var count = Math.min(system.particles.length, system.most);
          var stands = placement();
          if (count < 2 || !stands.visible) return;
          var between = system.subdivision || 0;
          var total = (count - 1) * (between + 1) + 1;
          if (band.length < total * 16) {
            band = new Float32Array(total * 16);
            gl.bindBuffer(gl.ARRAY_BUFFER, bandBuffer);
            gl.bufferData(gl.ARRAY_BUFFER, band.byteLength, gl.DYNAMIC_DRAW);
          }
          var state = system.state;
          var matrix = stands.matrix;
          var see = system.alphaBy * stands.alpha;
          // The rope's course is laid out in the system's own space and then placed, so a
          // system scaled more one way than the other stretches where it goes; its width is
          // the scene's (see below), so a rope rising through a wide system is a thin wavy
          // line, not a thick bar.
          var spots = [];
          var i;
          for (i = 0; i < count; i++) {
            var particle = system.particles[i];
            spots.push([particle.x + particle.shiftX, particle.y + particle.shiftY]);
          }
          // Each point of the band: where it is, how large, its color and how see-through.
          var points = [];
          function pointOf(spot, each) {
            var shade = system.colorOf(each, state);
            return { spot: spot, size: each.size * each.sizeNow, shade: [shade[0], shade[1], shade[2]],
                     alpha: Math.max(0, each.alpha * each.alphaNow * see) };
          }
          for (i = 0; i < count; i++) {
            var here = pointOf(spots[i], system.particles[i]);
            points.push(here);
            if (i === count - 1 || !between) continue;
            // Between two particles the band follows Wallpaper Engine's curve: a cubic one from
            // the first to the second, pulled the way the rope comes in and goes on, the points
            // spaced closer at its ends.
            var there = pointOf(spots[i + 1], system.particles[i + 1]);
            var start = spots[i], end = spots[i + 1];
            var before = spots[Math.max(0, i - 1)], after = spots[Math.min(count - 1, i + 2)];
            var pull0 = [start[0] + 0.15 * (end[0] - before[0]), start[1] + 0.15 * (end[1] - before[1])];
            var pull1 = [end[0] + 0.15 * (start[0] - after[0]), end[1] + 0.15 * (start[1] - after[1])];
            for (var step = 1; step <= between; step++) {
              var s = smooth01(0, 1, step / (between + 1)), o = 1 - s;
              var b0 = o * o * o, b1 = 3 * s * o * o, b2 = 3 * s * s * o, b3 = s * s * s;
              points.push({
                spot: [b0 * start[0] + b1 * pull0[0] + b2 * pull1[0] + b3 * end[0], b0 * start[1] + b1 * pull0[1] + b2 * pull1[1] + b3 * end[1]],
                size: mix(here.size, there.size, s),
                shade: [mix(here.shade[0], there.shade[0], s), mix(here.shade[1], there.shade[1], s), mix(here.shade[2], there.shade[2], s)],
                alpha: mix(here.alpha, there.alpha, s)
              });
            }
          }
          count = points.length;
          // Where the rope goes in the scene: its points through the system's matrix.
          var placed = points.map(function (point) {
            return [matrix[12] + matrix[0] * point.spot[0] + matrix[4] * point.spot[1],
                    matrix[13] + matrix[1] * point.spot[0] + matrix[5] * point.spot[1]];
          });
          for (i = 0; i < count; i++) {
            var point = points[i], here = placed[i];
            var previous = placed[Math.max(0, i - 1)], next = placed[Math.min(count - 1, i + 1)];
            var dx = next[0] - previous[0], dy = next[1] - previous[1];
            // As wide as the particle is large, in the scene's own units whatever the system's
            // scale, and turned across its way to an eye ROPE_EYE in front of the scene's middle:
            // away from the middle the band leans from the eye and shows narrower. Measured in
            // Wallpaper Engine's window: a rope of 120 is 120 wide at the middle at any scale
            // from 0.5 to 2, 0.79 of that 1580 to the side and 0.91 of it 920 above, on scenes
            // of 3840 and of 1920 alike (3598808038's vapor was a third as thick).
            // Where the band does not go on, it has no width: a rope lying in one spot is not
            // seen.
            var toEyeX = ctx.sceneWidth / 2 - here[0], toEyeY = ctx.sceneHeight / 2 - here[1];
            var rightX = dy * ROPE_EYE, rightY = -dx * ROPE_EYE, rightZ = dx * toEyeY - dy * toEyeX;
            var reach = Math.sqrt(rightX * rightX + rightY * rightY + rightZ * rightZ);
            var half = reach > 1e-6 ? point.size * system.sizeBy / 2 / reach : 0;
            for (var side = 0; side < 2; side++) {
              var at = (i * 2 + side) * 8, turn = side ? 1 : -1;
              band[at] = here[0] - ctx.surface.left - rightX * half * turn;
              band[at + 1] = here[1] - ctx.surface.bottom - rightY * half * turn;
              band[at + 2] = side;
              // Along the band the picture runs once from end to end, so it fades at both
              // ends where its picture does.
              band[at + 3] = count > 1 ? 1 - i / (count - 1) : 0.5;
              band[at + 4] = point.shade[0];
              band[at + 5] = point.shade[1];
              band[at + 6] = point.shade[2];
              band[at + 7] = point.alpha;
            }
          }
          gl.useProgram(ropeProgram.program);
          gl.enable(gl.BLEND);
          if (system.additive) gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
          else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
          gl.activeTexture(gl.TEXTURE0);
          gl.bindTexture(gl.TEXTURE_2D, system.picture.layers[0].texture);
          gl.uniform1i(ropeProgram.uniforms.u_Texture.location, 0);
          gl.uniform1i(ropeProgram.uniforms.u_Channels.location, CHANNELS[system.picture.channels] || 0);
          gl.uniform1f(ropeProgram.uniforms.u_Bright.location, system.bright);
          gl.uniform2f(ropeProgram.uniforms.u_Scene.location, ctx.surface.width, ctx.surface.height);
          ropeBehind(system, ctx.surface);
          gl.bindVertexArray(bandShape);
          gl.bindBuffer(gl.ARRAY_BUFFER, bandBuffer);
          gl.bufferSubData(gl.ARRAY_BUFFER, 0, band.subarray(0, count * 16));
          gl.drawArrays(gl.TRIANGLE_STRIP, 0, count * 2);
          gl.bindVertexArray(null);
        };
      }

      if (system.tails && ropeProgram) {
        // A band to each particle, from where it was to where it is; the picture runs along
        // it, its top at the particle. The bands are drawn as one, joined by corners that
        // have no area.
        var tailBand = new Float32Array(0);
        var tailBuffer = gl.createBuffer();
        var tailShape = gl.createVertexArray();
        gl.bindVertexArray(tailShape);
        gl.bindBuffer(gl.ARRAY_BUFFER, tailBuffer);
        gl.enableVertexAttribArray(2);
        gl.vertexAttribPointer(2, 4, gl.FLOAT, false, 32, 0);
        gl.enableVertexAttribArray(3);
        gl.vertexAttribPointer(3, 4, gl.FLOAT, false, 32, 16);
        gl.bindVertexArray(null);
        system.draw = function () {
          if (inDepth) return drawDeep();
          var stands = placement();
          if (!stands.visible || !system.particles.length) return;
          var state = system.state;
          var matrix = stands.matrix;
          var wide = Math.sqrt(Math.abs(matrix[0] * matrix[5] - matrix[4] * matrix[1])) * system.sizeBy;
          var see = system.alphaBy * stands.alpha;
          var corners = [];
          system.particles.forEach(function (particle) {
            var spots = tailOf(particle);
            if (spots.length < 2) return;
            spots = spots.map(function (spot) {
              return [matrix[12] - ctx.surface.left + matrix[0] * spot[0] + matrix[4] * spot[1],
                      matrix[13] - ctx.surface.bottom + matrix[1] * spot[0] + matrix[5] * spot[1], spot[3]];
            });
            var tint = system.colorOf(particle, state).concat([Math.max(0, particle.alpha * particle.alphaNow * see)]);
            var half = particle.size * particle.sizeNow * wide / 2;
            var first = corners.length;
            spots.forEach(function (spot, index) {
              var before = spots[Math.max(0, index - 1)], after = spots[Math.min(spots.length - 1, index + 1)];
              var dx = after[0] - before[0], dy = after[1] - before[1];
              var far = Math.sqrt(dx * dx + dy * dy);
              var across = far > 0.0001 ? half / far : 0;
              for (var side = 0; side < 2; side++) {
                var turn = side ? 1 : -1;
                corners.push([spot[0] - dy * across * turn, spot[1] + dx * across * turn, side, 1 - spot[2]].concat(tint));
              }
            });
            // Joined to the band before it by its own first corner and that band's last, twice each.
            if (first > 0) corners.splice(first, 0, corners[first - 1], corners[first]);
          });
          if (corners.length < 4) return;
          if (tailBand.length < corners.length * 8) tailBand = new Float32Array(corners.length * 8 * 2);
          corners.forEach(function (corner, index) { tailBand.set(corner, index * 8); });
          gl.useProgram(ropeProgram.program);
          gl.enable(gl.BLEND);
          if (system.additive) gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ZERO, gl.ONE);
          else gl.blendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
          gl.activeTexture(gl.TEXTURE0);
          gl.bindTexture(gl.TEXTURE_2D, system.picture.layers[0].texture);
          gl.uniform1i(ropeProgram.uniforms.u_Texture.location, 0);
          gl.uniform1i(ropeProgram.uniforms.u_Channels.location, CHANNELS[system.picture.channels] || 0);
          gl.uniform1f(ropeProgram.uniforms.u_Bright.location, system.bright);
          gl.uniform2f(ropeProgram.uniforms.u_Scene.location, ctx.surface.width, ctx.surface.height);
          ropeBehind(system, ctx.surface);
          gl.bindVertexArray(tailShape);
          gl.bindBuffer(gl.ARRAY_BUFFER, tailBuffer);
          gl.bufferData(gl.ARRAY_BUFFER, tailBand.subarray(0, corners.length * 8), gl.DYNAMIC_DRAW);
          gl.drawArrays(gl.TRIANGLE_STRIP, 0, corners.length);
          gl.bindVertexArray(null);
        };
      }

      // Its children, made after it, are drawn after it and move on as it does.
      (Array.isArray(said.children) ? said.children : []).forEach(function (child) {
        if (!child || typeof child !== 'object' || depth >= 4) return;
        var childFile = String(plain(child.name) || '');
        if (!json(childFile)) {
          note('“' + name + '”: its particles ' + childFile + ' are not in the scene');
          return;
        }
        var made = particleSystem(childFile, { name: name, owner: system, state: thing.state }, thing, child, depth + 1);
        if (made) system.children.push(made);
      });
      var ownStep = system.step, ownDraw = system.draw, ownSettle = system.settle;
      system.step = function (seconds) {
        ownStep(seconds);
        system.children.forEach(function (child) { child.step(seconds); });
      };
      system.draw = function () {
        ownDraw();
        system.children.forEach(function (child) { child.draw(); });
      };
      system.settle = function () {
        ownSettle();
        system.children.forEach(function (child) { child.settle(); });
      };
      system.warm = system.children.reduce(function (most, child) { return Math.max(most, child.warm); }, number(said.starttime, 0));
      return system;
    }

    return { mix: mix, color: color, buildParticles: buildParticles };
  }

