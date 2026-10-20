/// The scripts the scene player runs with in JavaScriptCore: WebGL 2 on top of the app's Metal
/// (`metalGL`), and the little of a web page the player uses (`environment`). The page's side
/// of each is `__native`, made by `MetalScenePlayer`.
enum MetalSceneScripts {
    // MARK: - WebGL 2

    static let metalGL = #"""
    (function (global) {
      'use strict';
      // WebGL's numbers, as many as the player names.
      var CONSTANTS = {
        DEPTH_BUFFER_BIT: 0x100, COLOR_BUFFER_BIT: 0x4000, POINTS: 0, LINES: 1, LINE_STRIP: 3, TRIANGLES: 4, TRIANGLE_STRIP: 5, TRIANGLE_FAN: 6,
        ZERO: 0, ONE: 1, SRC_COLOR: 0x300, ONE_MINUS_SRC_COLOR: 0x301, SRC_ALPHA: 0x302, ONE_MINUS_SRC_ALPHA: 0x303, DST_ALPHA: 0x304,
        ONE_MINUS_DST_ALPHA: 0x305, DST_COLOR: 0x306, ONE_MINUS_DST_COLOR: 0x307, FUNC_ADD: 0x8006, MIN: 0x8007, MAX: 0x8008,
        FUNC_SUBTRACT: 0x800A, FUNC_REVERSE_SUBTRACT: 0x800B, ARRAY_BUFFER: 0x8892, ELEMENT_ARRAY_BUFFER: 0x8893, STATIC_DRAW: 0x88E4,
        DYNAMIC_DRAW: 0x88E8, STREAM_DRAW: 0x88E0, CULL_FACE: 0x0B44, BLEND: 0x0BE2, DEPTH_TEST: 0x0B71, SCISSOR_TEST: 0x0C11,
        CW: 0x0900, CCW: 0x0901, FRONT: 0x0404, BACK: 0x0405, BYTE: 0x1400, UNSIGNED_BYTE: 0x1401, SHORT: 0x1402, UNSIGNED_SHORT: 0x1403,
        INT: 0x1404, UNSIGNED_INT: 0x1405, FLOAT: 0x1406, HALF_FLOAT: 0x140B, DEPTH_COMPONENT: 0x1902, RED: 0x1903, ALPHA: 0x1906,
        RGB: 0x1907, RGBA: 0x1908, RG: 0x8227, R8: 0x8229, RG8: 0x822B, RGBA8: 0x8058, RGBA16F: 0x881A, RGBA32F: 0x8814,
        DEPTH_COMPONENT16: 0x81A5, DEPTH_COMPONENT24: 0x81A6, FRAGMENT_SHADER: 0x8B30, VERTEX_SHADER: 0x8B31, COMPILE_STATUS: 0x8B81,
        LINK_STATUS: 0x8B82, ACTIVE_UNIFORMS: 0x8B86, ACTIVE_ATTRIBUTES: 0x8B89, NEVER: 0x200, LESS: 0x201, EQUAL: 0x202, LEQUAL: 0x203,
        GREATER: 0x204, NOTEQUAL: 0x205, GEQUAL: 0x206, ALWAYS: 0x207, NEAREST: 0x2600, LINEAR: 0x2601, NEAREST_MIPMAP_NEAREST: 0x2700,
        LINEAR_MIPMAP_NEAREST: 0x2701, NEAREST_MIPMAP_LINEAR: 0x2702, LINEAR_MIPMAP_LINEAR: 0x2703, TEXTURE_MAG_FILTER: 0x2800,
        TEXTURE_MIN_FILTER: 0x2801, TEXTURE_WRAP_S: 0x2802, TEXTURE_WRAP_T: 0x2803, TEXTURE_2D: 0x0DE1, TEXTURE0: 0x84C0,
        REPEAT: 0x2901, CLAMP_TO_EDGE: 0x812F, MIRRORED_REPEAT: 0x8370, FLOAT_VEC2: 0x8B50, FLOAT_VEC3: 0x8B51, FLOAT_VEC4: 0x8B52,
        INT_VEC2: 0x8B53, INT_VEC3: 0x8B54, INT_VEC4: 0x8B55, BOOL: 0x8B56, FLOAT_MAT2: 0x8B5A, FLOAT_MAT3: 0x8B5B, FLOAT_MAT4: 0x8B5C,
        SAMPLER_2D: 0x8B5E, FRAMEBUFFER: 0x8D40, RENDERBUFFER: 0x8D41, READ_FRAMEBUFFER: 0x8CA8, DRAW_FRAMEBUFFER: 0x8CA9,
        COLOR_ATTACHMENT0: 0x8CE0, DEPTH_ATTACHMENT: 0x8D00, FRAMEBUFFER_COMPLETE: 0x8CD5, NONE: 0, NO_ERROR: 0,
        UNPACK_FLIP_Y_WEBGL: 0x9240, UNPACK_PREMULTIPLY_ALPHA_WEBGL: 0x9241, UNPACK_COLORSPACE_CONVERSION_WEBGL: 0x9243,
        MAX_TEXTURE_SIZE: 0x0D33, VIEWPORT: 0x0BA2, FRAMEBUFFER_BINDING: 0x8CA6, READ_FRAMEBUFFER_BINDING: 0x8CAA,
        DRAW_FRAMEBUFFER_BINDING: 0x8CA6, RGBA_INTEGER: 0x8D99
      };
      for (var unit = 1; unit < 32; unit++) CONSTANTS['TEXTURE' + unit] = 0x84C0 + unit;

      function MetalGL(native, canvas) {
        var gl = this;
        Object.keys(CONSTANTS).forEach(function (name) { gl[name] = CONSTANTS[name]; });
        gl.canvas = canvas;
        var stream = new Float64Array(1 << 15), length = 0, payloads = [];
        var nextId = 1;
        function room(count) {
          if (length + count <= stream.length) return;
          var bigger = new Float64Array(Math.max(stream.length * 2, length + count));
          bigger.set(stream.subarray(0, length));
          stream = bigger;
        }
        function put() {
          room(arguments.length);
          for (var i = 0; i < arguments.length; i++) stream[length++] = +arguments[i] || 0;
        }
        // A copy, so that the page may change its array before the stream is carried out.
        function payload(value) {
          var copy;
          if (value instanceof Float32Array || value instanceof Uint8Array || value instanceof Uint16Array || value instanceof Int32Array ||
              value instanceof Uint32Array || value instanceof Int16Array || value instanceof Int8Array || value instanceof Uint8ClampedArray ||
              value instanceof Float64Array) {
            copy = new Uint8Array(value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength));
          } else if (value instanceof ArrayBuffer) {
            copy = new Uint8Array(value.slice(0));
          } else if (Array.isArray(value)) {
            copy = new Uint8Array(new Float32Array(value).buffer);
          } else {
            copy = new Uint8Array(0);
          }
          payloads.push(copy);
          return payloads.length - 1;
        }
        gl.__flush = function () {
          if (!length) return;
          native.run(stream, length, payloads);
          length = 0;
          payloads = [];
        };
        function id(object) { return object ? object.id : 0; }
        function made(kind) { return { id: nextId++, kind: kind }; }

        gl.getExtension = function () { return null; };
        gl.getSupportedExtensions = function () { return []; };
        gl.getParameter = function (name) { return name === CONSTANTS.MAX_TEXTURE_SIZE ? 16384 : null; };
        gl.getError = function () { return 0; };
        gl.isContextLost = function () { return false; };
        gl.getContextAttributes = function () { return { alpha: false, antialias: false, depth: false, stencil: false }; };
        gl.checkFramebufferStatus = function () { return CONSTANTS.FRAMEBUFFER_COMPLETE; };
        gl.flush = gl.finish = function () {};

        gl.createTexture = function () { return made('texture'); };
        gl.createBuffer = function () { return made('buffer'); };
        gl.createFramebuffer = function () { return made('framebuffer'); };
        gl.createRenderbuffer = function () { return made('renderbuffer'); };
        gl.createVertexArray = function () { return made('vertexArray'); };
        gl.createSampler = function () { return made('sampler'); };
        var deleted = { texture: 1, buffer: 2, framebuffer: 3, renderbuffer: 4, program: 5, vertexArray: 6, sampler: 7 };
        function remove(object) { if (object) put(43, deleted[object.kind] || 0, object.id); }
        gl.deleteTexture = gl.deleteBuffer = gl.deleteFramebuffer = gl.deleteRenderbuffer = gl.deleteVertexArray = gl.deleteSampler = remove;
        gl.deleteProgram = remove;

        // Shaders are made over when their program is linked: both are needed for it.
        gl.createShader = function (type) { return { kind: 'shader', type: type, source: '' }; };
        gl.shaderSource = function (shader, source) { shader.source = String(source); };
        gl.compileShader = function (shader) { shader.log = native.checkShader(shader.type === CONSTANTS.FRAGMENT_SHADER, shader.source) || ''; };
        gl.getShaderParameter = function (shader, name) { return name === CONSTANTS.COMPILE_STATUS ? !shader.log : 0; };
        gl.getShaderInfoLog = function (shader) { return shader.log || ''; };
        gl.deleteShader = function () {};
        gl.createProgram = function () { var program = made('program'); program.shaders = []; program.attributes = {}; return program; };
        gl.attachShader = function (program, shader) { program.shaders.push(shader); };
        gl.bindAttribLocation = function (program, index, name) { program.attributes[name] = index; };
        gl.linkProgram = function (program) {
          gl.__flush();
          var vertex = '', fragment = '';
          program.shaders.forEach(function (shader) {
            if (shader.type === CONSTANTS.VERTEX_SHADER) vertex = shader.source; else fragment = shader.source;
          });
          var linked = native.link(program.id, vertex, fragment, program.attributes);
          program.linked = !!(linked && linked.ok);
          program.log = linked && linked.error ? String(linked.error) : '';
          program.uniforms = (linked && linked.uniforms) || [];
          program.names = (linked && linked.names) || [];
        };
        gl.getProgramParameter = function (program, name) {
          if (name === CONSTANTS.LINK_STATUS) return !!program.linked;
          if (name === CONSTANTS.ACTIVE_UNIFORMS) return program.uniforms.length;
          return 0;
        };
        gl.getProgramInfoLog = function (program) { return program.log || ''; };
        gl.getActiveUniform = function (program, index) { return program.uniforms[index] || null; };
        gl.getUniformLocation = function (program, name) {
          var plain = String(name).replace(/\[0\]$/, '');
          var index = program.names.indexOf(plain);
          return index < 0 ? null : { kind: 'location', program: program.id, index: index };
        };
        gl.useProgram = function (program) { put(13, id(program)); };

        function uniform(location, values, integer) {
          if (!location) return;
          put(integer ? 16 : 14, location.index, values.length);
          for (var i = 0; i < values.length; i++) put(values[i]);
        }
        gl.uniform1f = function (l, x) { uniform(l, [x], false); };
        gl.uniform2f = function (l, x, y) { uniform(l, [x, y], false); };
        gl.uniform3f = function (l, x, y, z) { uniform(l, [x, y, z], false); };
        gl.uniform4f = function (l, x, y, z, w) { uniform(l, [x, y, z, w], false); };
        gl.uniform1i = function (l, x) { uniform(l, [x], true); };
        gl.uniform2i = function (l, x, y) { uniform(l, [x, y], true); };
        function vector(l, values, integer) {
          if (!l || !values) return;
          if (values.length <= 4) { uniform(l, Array.prototype.slice.call(values), integer); return; }
          if (integer) { uniform(l, Array.prototype.slice.call(values), true); return; }
          put(15, l.index, payload(values instanceof Float32Array ? values : new Float32Array(values)));
        }
        gl.uniform1fv = gl.uniform2fv = gl.uniform3fv = gl.uniform4fv = function (l, values) { vector(l, values, false); };
        gl.uniform1iv = function (l, values) { vector(l, values, true); };
        function matrix(l, transpose, values) {
          if (!l || !values) return;
          put(15, l.index, payload(values instanceof Float32Array ? values : new Float32Array(values)));
        }
        gl.uniformMatrix2fv = gl.uniformMatrix3fv = gl.uniformMatrix4fv = matrix;

        gl.bindFramebuffer = function (target, fb) { put(1, target, id(fb)); };
        gl.bindVertexArray = function (va) { put(2, id(va)); };
        gl.bindTexture = function (target, texture) { put(3, target, id(texture)); };
        gl.activeTexture = function (unit) { put(4, unit); };
        gl.viewport = function (x, y, w, h) { put(5, x, y, w, h); };
        gl.scissor = function () {};
        gl.colorMask = function () {};
        gl.enable = function (cap) { put(6, cap); };
        gl.disable = function (cap) { put(7, cap); };
        gl.bindBuffer = function (target, buffer) { put(8, target, id(buffer)); };
        gl.vertexAttribPointer = function (index, size, type, normalized, stride, offset) { put(9, index, size, type, normalized ? 1 : 0, stride, offset); };
        gl.enableVertexAttribArray = function (index) { put(10, index); };
        gl.disableVertexAttribArray = function (index) { put(11, index); };
        gl.vertexAttribDivisor = function (index, divisor) { put(12, index, divisor); };
        gl.blendFuncSeparate = function (a, b, c, d) { put(17, a, b, c, d); };
        gl.blendFunc = function (a, b) { put(18, a, b); };
        gl.blendEquation = gl.blendEquationSeparate = function (mode) { put(19, mode); };
        gl.bufferData = function (target, data) {
          if (typeof data === 'number') put(20, target, -1, data); else put(20, target, payload(data), 0);
        };
        gl.bufferSubData = function (target, offset, data) { put(21, target, offset, payload(data), 0); };
        gl.drawArrays = function (mode, first, count) { put(22, mode, first, count); };
        gl.drawElements = function (mode, count, type, offset) { put(23, mode, count, type, offset); };
        gl.drawArraysInstanced = function (mode, first, count, instances) { put(24, mode, first, count, instances); };
        gl.texParameteri = function (target, name, value) { put(25, target, name, value); };
        gl.samplerParameteri = function (sampler, name, value) { put(26, id(sampler), name, value); };
        gl.bindSampler = function (unit, sampler) { put(27, unit, id(sampler)); };
        gl.texImage2D = function () {
          var a = arguments;
          if (a.length >= 9) {
            put(28, a[0], a[1], a[2], a[3], a[4], a[6], a[7], a[8] ? payload(a[8]) : -1);
          } else {
            // A picture, a canvas or a video, as it is now.
            var handle = native.capture(a[5]);
            if (handle > 0) put(29, a[0], a[1], a[2], a[3], a[4], handle);
          }
        };
        gl.pixelStorei = function (name, value) { put(30, name, typeof value === 'boolean' ? (value ? 1 : 0) : value); };
        gl.blitFramebuffer = function (a, b, c, d, e, f, g, h, mask, filter) { put(31, a, b, c, d, e, f, g, h, mask, filter); };
        gl.clear = function (mask) { put(32, mask); };
        gl.clearColor = function (r, g, b, a) { put(33, r, g, b, a); };
        gl.depthMask = function (on) { put(34, on ? 1 : 0); };
        gl.depthFunc = function (f) { put(35, f); };
        gl.frontFace = function (f) { put(36, f); };
        gl.cullFace = function (f) { put(37, f); };
        gl.framebufferTexture2D = function (target, attachment, textarget, texture, level) { put(38, target, attachment, textarget, id(texture), level); };
        gl.framebufferRenderbuffer = function (target, attachment, rbtarget, rb) { put(39, target, attachment, rbtarget, id(rb)); };
        gl.bindRenderbuffer = function (target, rb) { put(40, target, id(rb)); };
        gl.renderbufferStorage = function (target, format, w, h) { put(41, target, format, w, h); };
        gl.generateMipmap = function (target) { put(42, target); };
        gl.readPixels = function (x, y, w, h, format, type, pixels) {
          gl.__flush();
          var read = native.readPixels(x, y, w, h);
          if (read && pixels) pixels.set(read.subarray(0, Math.min(read.length, pixels.length)));
        };
      }
      global.MetalGL = MetalGL;
    })(this);
    """#

    // MARK: - A page, as much of one as the player uses

    static let environment = #"""
    (function (global) {
      'use strict';
      var native = global.__native;
      global.window = global;
      global.self = global;
      global.console = {
        log: function () { native.log('log', Array.prototype.join.call(arguments, ' ')); },
        info: function () { native.log('info', Array.prototype.join.call(arguments, ' ')); },
        warn: function () { native.log('warn', Array.prototype.join.call(arguments, ' ')); },
        error: function () { native.log('error', Array.prototype.join.call(arguments, ' ')); }
      };
      global.performance = { now: function () { return native.now(); } };

      // Timers, kept by number; the app calls them back.
      var timers = {}, nextTimer = 1;
      global.setTimeout = function (callback, delay) {
        var id = nextTimer++;
        timers[id] = { callback: callback, args: Array.prototype.slice.call(arguments, 2) };
        native.timer(id, Math.max(0, +delay || 0), false);
        return id;
      };
      global.setInterval = function (callback, delay) {
        var id = nextTimer++;
        timers[id] = { callback: callback, args: Array.prototype.slice.call(arguments, 2), repeats: true };
        native.timer(id, Math.max(4, +delay || 0), true);
        return id;
      };
      global.clearTimeout = global.clearInterval = function (id) {
        if (timers[id]) { delete timers[id]; native.cancelTimer(id); }
      };
      global.__timer = function (id) {
        var timer = timers[id];
        if (!timer) return;
        if (!timer.repeats) delete timers[id];
        try { timer.callback.apply(global, timer.args); } catch (error) { console.error(error && error.stack || error); }
        global.__flushAll();
      };

      // Frames: callbacks for the next one, called when the app says it is time.
      var frameCallbacks = [], nextFrame = 1;
      global.requestAnimationFrame = function (callback) {
        var id = nextFrame++;
        frameCallbacks.push({ id: id, callback: callback });
        native.wantFrame();
        return id;
      };
      global.cancelAnimationFrame = function (id) {
        frameCallbacks = frameCallbacks.filter(function (entry) { return entry.id !== id; });
      };
      global.__frame = function (time) {
        var due = frameCallbacks;
        frameCallbacks = [];
        due.forEach(function (entry) {
          try { entry.callback(time); } catch (error) { console.error(error && error.stack || error); }
        });
        global.__flushAll();
        return frameCallbacks.length > 0;
      };
      var contexts = [];
      global.__flushAll = function () { contexts.forEach(function (gl) { gl.__flush(); }); };

      // Events of the window: the pointer, a change of size.
      var listeners = {};
      function listen(target) {
        target.addEventListener = function (name, callback) { (target.__listeners = target.__listeners || {})[name] = (target.__listeners[name] || []).concat([callback]); };
        target.removeEventListener = function (name, callback) {
          if (target.__listeners && target.__listeners[name]) target.__listeners[name] = target.__listeners[name].filter(function (each) { return each !== callback; });
        };
        target.dispatchEvent = function (event) {
          ((target.__listeners || {})[event.type] || []).slice().forEach(function (callback) {
            try { callback.call(target, event); } catch (error) { console.error(error && error.stack || error); }
          });
          return true;
        };
      }
      listen(global);
      global.CustomEvent = function (type, options) { this.type = type; this.detail = options && options.detail; };
      global.Event = function (type) { this.type = type; };
      global.__dispatchWindow = function (type, properties) {
        var event = { type: type, preventDefault: function () {}, stopPropagation: function () {} };
        for (var key in properties) event[key] = properties[key];
        global.dispatchEvent(event);
        global.__flushAll();
      };
      global.__size = { width: 1, height: 1, ratio: 1 };
      Object.defineProperty(global, 'innerWidth', { get: function () { return global.__size.width; } });
      Object.defineProperty(global, 'innerHeight', { get: function () { return global.__size.height; } });
      Object.defineProperty(global, 'devicePixelRatio', { get: function () { return global.__size.ratio; } });

      // Canvases: the one the scene is drawn on, with WebGL; others, with CoreGraphics.
      function Canvas(main) {
        var canvas = this, width = 300, height = 150, handle = 0, context = null;
        listen(canvas);
        canvas.style = { objectFit: 'cover', objectPosition: '50% 50%' };
        canvas.isConnected = true;
        Object.defineProperty(canvas, 'width', {
          get: function () { return width; },
          set: function (value) { width = Math.max(0, Math.floor(value)); if (main) native.setCanvasSize(width, height); else if (handle) native.canvasResize(handle, width, height); }
        });
        Object.defineProperty(canvas, 'height', {
          get: function () { return height; },
          set: function (value) { height = Math.max(0, Math.floor(value)); if (main) native.setCanvasSize(width, height); else if (handle) native.canvasResize(handle, width, height); }
        });
        canvas.getBoundingClientRect = function () {
          var w = global.__size.width, h = global.__size.height;
          return { left: 0, top: 0, right: w, bottom: h, width: w, height: h, x: 0, y: 0 };
        };
        canvas.getContext = function (kind) {
          if (context) return context;
          if (main && kind === 'webgl2') {
            context = new global.MetalGL(native, canvas);
            contexts.push(context);
          } else if (!main && kind === '2d') {
            handle = native.canvasMake(width, height);
            canvas.__handle = handle;
            context = new Context2D(handle, canvas);
          }
          return context;
        };
        canvas.remove = function () {};
      }
      global.__mainCanvas = new Canvas(true);

      function Context2D(handle, canvas) {
        var context = this;
        context.canvas = canvas;
        var state = { fillStyle: '#000', strokeStyle: '#000', lineWidth: 1, lineJoin: 'miter', globalAlpha: 1, font: '10px sans-serif',
                      textBaseline: 'alphabetic', textAlign: 'start', shadowColor: 'rgba(0,0,0,0)', shadowBlur: 0, shadowOffsetX: 0,
                      shadowOffsetY: 0, filter: 'none', letterSpacing: '0px', globalCompositeOperation: 'source-over' };
        Object.keys(state).forEach(function (name) {
          Object.defineProperty(context, name, {
            get: function () { return state[name]; },
            set: function (value) {
              state[name] = value;
              native.canvasSet(handle, name, value && value.__gradient ? { gradient: value.__gradient } : value);
            }
          });
        });
        ['save', 'restore', 'beginPath', 'closePath', 'moveTo', 'lineTo', 'quadraticCurveTo', 'bezierCurveTo', 'arc', 'ellipse', 'rect',
         'fill', 'stroke', 'fillRect', 'strokeRect', 'clearRect', 'translate', 'rotate', 'scale', 'setTransform', 'transform',
         'fillText', 'strokeText', 'drawImage', 'clip'].forEach(function (name) {
          context[name] = function () {
            var args = Array.prototype.slice.call(arguments).map(function (each) { return each && each.__handle ? { handle: each.__handle } : each; });
            native.canvasCall(handle, name, args);
          };
        });
        var saved = [];
        var save = context.save, restore = context.restore;
        context.save = function () { saved.push(JSON.parse(JSON.stringify(state, function (k, v) { return v && v.__gradient ? undefined : v; }))); save(); };
        context.restore = function () { var back = saved.pop(); if (back) for (var key in back) state[key] = back[key]; restore(); };
        context.measureText = function (text) { return native.canvasMeasure(handle, String(text)); };
        context.getImageData = function (x, y, w, h) { return { width: w, height: h, data: native.canvasRead(handle, x, y, w, h) }; };
        function gradient(id) { return { __gradient: id, addColorStop: function (offset, color) { native.gradientStop(id, offset, String(color)); } }; }
        context.createLinearGradient = function (x0, y0, x1, y1) { return gradient(native.gradientMake([x0, y0, x1, y1])); };
        context.createRadialGradient = function (x0, y0, r0, x1, y1, r1) { return gradient(native.gradientMake([x0, y0, r0, x1, y1, r1])); };
      }

      // Media: pictures, videos and sounds the app plays.
      function Media(kind) {
        var media = this;
        listen(media);
        media.__handle = native.mediaMake(kind);
        media.__kind = kind;
        media.style = {};
        media.isConnected = true;
        media.wallaeroShare = 1;
        var values = { src: '', loop: false, muted: false, volume: 1, playbackRate: 1, defaultMuted: false, preload: 'auto', playsInline: true };
        Object.keys(values).forEach(function (name) {
          Object.defineProperty(media, name, {
            get: function () { return values[name]; },
            set: function (value) { values[name] = value; native.mediaSet(media.__handle, name, value); }
          });
        });
        ['currentTime', 'duration', 'paused', 'ended', 'readyState', 'videoWidth', 'videoHeight', 'naturalWidth', 'naturalHeight', 'width', 'height', 'complete'].forEach(function (name) {
          Object.defineProperty(media, name, {
            get: function () { return native.mediaGet(media.__handle, name); },
            set: function (value) { native.mediaSet(media.__handle, name, value); }
          });
        });
        Object.defineProperty(media, 'currentSrc', { get: function () { return values.src; } });
        media.play = function () { native.mediaCall(media.__handle, 'play'); return Promise.resolve(); };
        media.pause = function () { native.mediaCall(media.__handle, 'pause'); };
        media.load = function () {};
        media.remove = function () { native.mediaCall(media.__handle, 'remove'); };
        media.setAttribute = function () {};
        global.__media[media.__handle] = media;
      }
      global.__media = {};
      global.__mediaEvent = function (handle, type) {
        var media = global.__media[handle];
        if (!media) return;
        var event = { type: type, target: media };
        if (typeof media['on' + type] === 'function') { try { media['on' + type](event); } catch (error) { console.error(error && error.stack || error); } }
        media.dispatchEvent(event);
        global.__flushAll();
      };
      global.Image = function () { Media.call(this, 'image'); };

      global.document = {
        createElement: function (tag) {
          tag = String(tag).toLowerCase();
          if (tag === 'canvas') return new Canvas(false);
          if (tag === 'video') return new Media('video');
          if (tag === 'audio') return new Media('audio');
          if (tag === 'img') return new global.Image();
          var element = { style: {}, appendChild: function () {}, setAttribute: function () {}, remove: function () {} };
          listen(element);
          return element;
        },
        body: { appendChild: function () {}, removeChild: function () {} },
        head: { appendChild: function () {} },
        documentElement: {},
        querySelector: function () { return null; },
        querySelectorAll: function () { return []; },
        fonts: { add: function () {}, ready: Promise.resolve() },
        visibilityState: 'visible',
        hidden: false
      };
      listen(global.document);
      global.FontFace = function (family, source) {
        var file = /url\(["']?([^"')]*)["']?\)/.exec(String(source));
        var path = file ? decodeURI(file[1]) : '';
        this.family = family;
        this.load = function () {
          return native.fontLoad(String(family), path) ? Promise.resolve(this) : Promise.reject(new Error('the font cannot be loaded'));
        };
      };

      var stored = {};
      global.localStorage = {
        getItem: function (key) { return Object.prototype.hasOwnProperty.call(stored, key) ? stored[key] : null; },
        setItem: function (key, value) { stored[key] = String(value); },
        removeItem: function (key) { delete stored[key]; },
        clear: function () { stored = {}; }
      };
      var letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      global.atob = function (text) {
        text = String(text).replace(/[^A-Za-z0-9+/]/g, '');
        if (text.length % 4 === 1) text = text.slice(0, -1);
        while (text.length % 4) text += '=';
        return native.atob(text);
      };
      global.btoa = function (text) {
        var out = '', i = 0;
        for (; i + 2 < text.length; i += 3) {
          var n = (text.charCodeAt(i) << 16) | (text.charCodeAt(i + 1) << 8) | text.charCodeAt(i + 2);
          out += letters[n >> 18 & 63] + letters[n >> 12 & 63] + letters[n >> 6 & 63] + letters[n & 63];
        }
        if (i < text.length) {
          var m = text.charCodeAt(i) << 16 | (i + 1 < text.length ? text.charCodeAt(i + 1) << 8 : 0);
          out += letters[m >> 18 & 63] + letters[m >> 12 & 63] + (i + 1 < text.length ? letters[m >> 6 & 63] : '=') + '=';
        }
        return out;
      };
      global.XMLHttpRequest = function () { throw new Error('not here'); };
      global.fetch = function () { return Promise.reject(new Error('not here')); };

      // The app's side of a wallpaper, as pages have it (see WebWallpaperView's bridge): every
      // video and sound at the app's speed and volume, each sound with its share of the volume.
      var host = { rate: 1, muted: true, volume: 1, playing: true };
      function applyTo(media) {
        if (media.__kind === 'image') return;
        var rate = host.playing === false ? 0 : host.rate;
        if (rate > 0 && media.playbackRate !== rate) media.playbackRate = rate;
        if (media.muted !== host.muted) media.muted = host.muted;
        var volume = host.volume * (typeof media.wallaeroShare === 'number' ? media.wallaeroShare : 1);
        if (media.volume !== volume) media.volume = volume;
      }
      var paused = false;
      function tellPaused() {
        if ((host.playing === false) === paused) return;
        paused = !paused;
        var listener = global.wallpaperPropertyListener;
        try { if (listener && typeof listener.setPaused === 'function') listener.setPaused(paused); } catch (error) {}
      }
      global.__wallaeroHost = {
        apply: function (settings) {
          for (var key in settings) host[key] = settings[key];
          for (var handle in global.__media) applyTo(global.__media[handle]);
          tellPaused();
        },
        autoplay: function (media) { applyTo(media); media.play(); },
        get rate() { return host.playing === false ? 0 : host.rate; }
      };
      // Wallpaper Engine's way for a scene to follow the sound: 128 numbers, 64 bands of the
      // left channel and 64 of the right, low notes first, each from 0 to 1.
      var soundListeners = [];
      global.wallpaperRegisterAudioListener = function (listener) {
        if (typeof listener !== 'function') return;
        soundListeners.push(listener);
        if (soundListeners.length === 1) native.listensToSound(true);
      };
      global.__wallaeroHost.sound = function (levels) {
        soundListeners.forEach(function (listener) { try { listener(levels); } catch (error) { console.error(error && error.stack || error); } });
        global.__flushAll();
      };
      // What music plays, as Wallpaper Engine tells its scenes, kind by kind; the app is asked
      // for it once a scene listens. As on the page.
      global.wallpaperMediaIntegration = { PLAYBACK_STOPPED: 0, PLAYBACK_PLAYING: 1, PLAYBACK_PAUSED: 2 };
      var mediaListeners = [];
      var music = null;
      function css(color) {
        var parts = Array.isArray(color) ? color : [0, 0, 0];
        return 'rgb(' + parts.slice(0, 3).map(function (part) { return Math.round(Math.max(0, Math.min(1, part)) * 255); }).join(', ') + ')';
      }
      function mediaEvent(kind, from) {
        if (kind === 'status') return { enabled: !!from.enabled };
        if (kind === 'properties') {
          return { title: from.title || '', artist: from.artist || '', subTitle: from.subTitle || '', albumTitle: from.albumTitle || '',
                   albumArtist: from.albumArtist || '', genres: from.genres || '', contentType: from.contentType || '' };
        }
        if (kind === 'thumbnail') {
          var colors = from.colors || {};
          return { thumbnail: from.thumbnail || '', primaryColor: css(colors.primary), secondaryColor: css(colors.secondary),
                   tertiaryColor: css(colors.tertiary), textColor: css(colors.text || [1, 1, 1]),
                   highContrastColor: css(colors.highContrast || [1, 1, 1]) };
        }
        if (kind === 'playback') return { state: from.state || 0 };
        return { position: from.position || 0, duration: from.duration || 0 };
      }
      function tellMedia(kind, event) {
        mediaListeners.forEach(function (entry) {
          if (entry.kind !== kind) return;
          try { entry.call(event); } catch (error) { console.error(error && error.stack || error); }
        });
      }
      ['Status', 'Properties', 'Thumbnail', 'Playback', 'Timeline'].forEach(function (name) {
        var kind = name.toLowerCase();
        global['wallpaperRegisterMedia' + name + 'Listener'] = function (listener) {
          if (typeof listener !== 'function') return;
          mediaListeners.push({ kind: kind, call: listener });
          if (mediaListeners.length === 1) native.listensToMedia(true);
          // One that comes late hears at once how things stand.
          if (music) setTimeout(function () {
            try { listener(mediaEvent(kind, music)); } catch (error) { console.error(error && error.stack || error); }
          }, 0);
        };
      });
      global.__wallaeroHost.media = function (message) {
        if (message.timeline) {
          if (music) {
            music.position = message.timeline.position;
            music.duration = message.timeline.duration;
          }
          tellMedia('timeline', mediaEvent('timeline', message.timeline));
        } else {
          var before = music;
          music = message;
          ['status', 'properties', 'thumbnail', 'playback'].forEach(function (kind) {
            var event = mediaEvent(kind, message);
            if (!before || JSON.stringify(event) !== JSON.stringify(mediaEvent(kind, before))) tellMedia(kind, event);
          });
          tellMedia('timeline', mediaEvent('timeline', message));
        }
        global.__flushAll();
      };

      // The player, started with the scene, its settings and the editor's changes.
      global.__start = function (settings, changes, fit, position) {
        var canvas = global.__mainCanvas;
        canvas.style.objectFit = fit || 'cover';
        canvas.style.objectPosition = position + '% ' + position + '%';
        global.__player = global.WallaeroEngine.play(canvas, global.wallaeroEngineScene, settings || {}, changes || {});
        global.__flushAll();
      };
    })(this);
    """#
}
