  // Pictures that bend: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makePuppets(ctx) {
    var gl = ctx.gl, texture = ctx.texture, general = ctx.general, changed = ctx.changed, live = ctx.live;
    // --- Pictures that bend ---------------------------------------------------
    //
    // A puppet is a picture cut into triangles whose corners hang on bones. An animation says
    // where every bone is in every frame; a corner goes where its bones take it, each by its
    // weight. Bones and corners live on the flat of the picture, so a bone's place is kept as
    // six numbers: x' = a·x + c·y + e, y' = b·x + d·y + f.

    function numbersOf(text, kind) {
      var raw = atob(text || '');
      var bytes = new Uint8Array(raw.length);
      for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
      return new kind(bytes.buffer, 0, Math.floor(bytes.length / kind.BYTES_PER_ELEMENT));
    }

    // First `second`, then `first`.
    function joined(first, second) {
      return [first[0] * second[0] + first[2] * second[1], first[1] * second[0] + first[3] * second[1],
              first[0] * second[2] + first[2] * second[3], first[1] * second[2] + first[3] * second[3],
              first[0] * second[4] + first[2] * second[5] + first[4], first[1] * second[4] + first[3] * second[5] + first[5]];
    }

    function undone(move) {
      var det = move[0] * move[3] - move[2] * move[1] || 1;
      var a = move[3] / det, b = -move[1] / det, c = -move[2] / det, d = move[0] / det;
      return [a, b, c, d, -(a * move[4] + c * move[5]), -(b * move[4] + d * move[5])];
    }

    // How a bone sways by itself, as Wallpaper Engine's editor writes it: on a spring that
    // brings it back (`se`), or hanging free (`re`) where only friction holds it; turning about
    // its root (`r`), or moving (`t`), or both; pulled by gravity (`ge`, `gd`) or not, and
    // turned no further than it may (`la`, `lamin`, `lamax`). How stiff the spring is (`rs`,
    // `ts`), how much friction (`rf`, `tf`), how heavy it moves (`ri`, `ti`), and where its
    // tip is from its root (`tp`). Null for a bone that does not sway; bones bent towards a
    // target (`ik`) do not either.
    function swayOf(text) {
      if (typeof text !== 'string' || text.charAt(0) !== '{') return null;
      var said;
      try { said = JSON.parse(text); } catch (error) { return null; }
      if (!said || (!said.se && !said.re)) return null;
      var turns = said.r !== false && said.r !== null, moves = !!said.t;
      if (!turns && !moves) return null;
      var tip = numbers(said.tp, 3, 0);
      var gravity = numbers(said.gd, 3, 0);
      if (!said.gd) gravity = [0, -1, 0];
      var limited = !!said.la;
      return {
        spring: !!said.se, turns: turns, moves: moves,
        stiff: said.se ? number(said.rs, 200) : 0, friction: number(said.rf, 20), weight: Math.max(0.01, number(said.ri, 30)),
        moveStiff: said.se ? number(said.ts, 200) : 0, moveFriction: number(said.tf, 20), moveWeight: Math.max(0.01, number(said.ti, 30)),
        gravity: said.ge ? gravity : null,
        low: limited ? numbers(said.lamin, 3, 0)[2] : -Infinity, high: limited ? numbers(said.lamax, 3, 0)[2] : Infinity,
        tip: Math.hypot(tip[0], tip[1]) > 1e-3 ? [tip[0], tip[1]] : null,
        angle: 0, spin: 0, shift: [0, 0], speed: [0, 0], last: null
      };
    }

    // How strongly gravity pulls on a swaying bone, in pixels of the scene a second squared.
    var SWAY_GRAVITY = 1000;
    // How strongly the scene's wind pushes, at a strength of one.
    var SWAY_WIND = 400;

    // `culls`: whether the picture's material leaves out the backs of its triangles.
    function buildPuppet(said, layers, name, culls, owner) {
      var corners = numbersOf(said.corners, Float32Array);
      var triangles = numbersOf(said.triangles, Uint16Array);
      var count = Math.floor(corners.length / 12);
      var bones = (said.bones || []).map(function (bone) {
        var matrix = bone.matrix || [];
        return { name: typeof bone.name === 'string' ? bone.name : '', parent: number(bone.parent, -1),
                 rest: [matrix[0], matrix[1], matrix[4], matrix[5], matrix[12], matrix[13]], sway: swayOf(bone.physics) };
      });
      if (!count || !triangles.length || !bones.length) return null;
      // Where every bone is at rest, from the picture and not from its parent; and the way back.
      function atRest(index, depth) {
        var bone = bones[index];
        if (!bone.whole) {
          var parent = bones[bone.parent];
          bone.whole = parent && depth < 64 ? joined(atRest(bone.parent, depth + 1), bone.rest) : bone.rest;
        }
        return bone.whole;
      }
      bones.forEach(function (bone, index) { bone.back = undone(atRest(index, 0)); });

      // Points other objects of the scene hang on, by name: the bone each is on, and where it
      // is from the bone.
      var points = {};
      (said.attachments || []).forEach(function (point) {
        var matrix = point.matrix || [];
        var bone = number(point.bone, -1);
        if (typeof point.name !== 'string' || !bones[bone]) return;
        points[point.name] = { bone: bone, rest: [matrix[0], matrix[1], matrix[4], matrix[5], matrix[12], matrix[13]] };
      });

      // The layers of animation the object has, in their order, each with its own clock: the
      // frame it is on, whether it plays, how fast. A script may pause one, put it on a frame,
      // add one that plays once, or take one away. Of those that set the bones, one a script
      // started to play once comes first while it plays; else the first that has not come to
      // its end — one that plays once gives way to the next when it is over. Those that add to
      // them move the bones further, each by how far it takes them from where they are at rest,
      // as much as its blend says.
      var animations = said.animations || [];
      function animationOf(wanted) {
        return animations.filter(function (each) {
          return typeof wanted === 'number' ? each.id === wanted : each.name === wanted || String(each.id) === String(wanted);
        })[0] || null;
      }
      function makeLayer(animation, config) {
        config = config || {};
        return { name: typeof config.name === 'string' ? config.name : (animation.name || ''), animation: animation,
                 frames: numbersOf(animation.frames, Float32Array), frameCount: animation.frameCount, length: animation.length,
                 controls: animation.controls ? numbersOf(animation.controls, Float32Array) : null,
                 shapes: (animation.shapes || []).map(function (track) {
                   return { shape: number(track.shape, -1), weights: numbersOf(track.weights, Float32Array) };
                 }),
                 fps: animation.fps || 30, speed: number(plain(config.rate), 1), mode: animation.mode,
                 adds: flag(config.additive, false), blend: Math.max(0, Math.min(1, number(plain(config.blend), 1))),
                 visible: true, frame: 0, playing: true, done: false, ended: [], once: false };
      }
      var playing = [];
      (layers || []).forEach(function (config) {
        var animation = animationOf(number(plain(config.animation), -1));
        if (!animation) return;
        var layer = makeLayer(animation, config);
        // Whether it shows may be a setting of the wallpaper's, or what a script says; such a
        // script has the layer of animation for `thisObject`.
        layer.shows = live(config.visible === undefined ? true : config.visible, 0, true, owner || null, 'flag');
        if (layer.shows.script) layer.shows.script.animationLayer = function () { return puppet.scriptLayer(layer); };
        layer.visible = layer.shows.now !== false;
        playing.push(layer);
      });
      // A layer's clock moves on; what is said to happen when it comes to its end happens.
      function advance(passed) {
        playing.slice().forEach(function (layer) {
          if (!layer.playing || !(passed > 0)) return;
          var before = layer.frame;
          layer.frame += passed * layer.fps * layer.speed;
          var cycle = layer.mode === 'mirror' ? layer.length * 2 : layer.length;
          if (!(cycle > 0)) return;
          if (layer.mode === 'single' || layer.once) {
            if (layer.frame >= layer.length) {
              layer.frame = layer.length;
              layer.playing = false;
              layer.done = true;
              ended(layer);
              if (layer.once) puppet.removeLayer(layer);
            }
          } else if (Math.floor(layer.frame / cycle) > Math.floor(before / cycle)) {
            ended(layer);
          }
        });
      }
      function ended(layer) {
        layer.ended.slice().forEach(function (callback) {
          try {
            callback();
          } catch (error) {
            note('a script fails in what it asked for at the end of an animation: ' + error.message);
          }
        });
      }
      // Each bone at rest from its parent, as the frames have it: place, turn, scale.
      bones.forEach(function (bone) {
        var rest = bone.rest;
        bone.still = [rest[4], rest[5], Math.atan2(rest[1], rest[0]), Math.sqrt(rest[0] * rest[0] + rest[1] * rest[1]),
                      Math.sqrt(rest[2] * rest[2] + rest[3] * rest[3]), 0, 0];
      });
      // Where an animation has a bone on the frame its layer is on: place, turn in the
      // picture's plane, scale, and turn about the picture's x and y axes.
      function momentOf(layer) {
        var at = layer.frame;
        if (layer.mode === 'mirror') {
          at = at % (layer.length * 2);
          if (at > layer.length) at = layer.length * 2 - at;
        } else if (layer.mode === 'single') {
          at = Math.min(at, layer.length);
        } else {
          at = at % layer.length;
        }
        var before = Math.min(Math.floor(at), layer.frameCount - 1);
        return { before: before, after: Math.min(before + 1, layer.frameCount - 1), share: at - before };
      }
      function sample(layer, index, frames) {
        frames = frames || layer.frames;
        var moment = momentOf(layer), share = moment.share;
        var one = (index * layer.frameCount + moment.before) * 9, two = (index * layer.frameCount + moment.after) * 9;
        function value(part) { return frames[one + part] + (frames[two + part] - frames[one + part]) * share; }
        return [value(0), value(1), value(5), value(6), value(7), value(3), value(4)];
      }

      // Limbs bent towards a point (inverse kinematics), as Wallpaper Engine's puppets have
      // them: the last bone of a limb says `ik`, and how many bones above it bend (`ikd`).
      // Where the limb reaches is its target controller, a point of the puppet's own space
      // that the animations move — not a bone, so a foot stays planted while the body
      // squats, and the limb is pulled straight when the point goes past its reach. The
      // joints bend towards the limb's orientation controller (`ikg`), else the way the
      // animation has them bent. Stretched past its reach, the last bone turns to point at
      // the target (`ikr`), all the way once the target is `ikrd` beyond — its axis `a`
      // being the limb's forward direction.
      var controllers = (said.controllers || []).map(function (each) {
        return { bone: number(each.bone, -1), orients: each.orients === true, rest: [number(each.x, 0), number(each.y, 0)] };
      });
      var limbs = [];
      (said.bones || []).forEach(function (bone, end) {
        var settings = null;
        try { settings = typeof bone.physics === 'string' && bone.physics.charAt(0) === '{' ? JSON.parse(bone.physics) : null; } catch (error) {}
        if (!settings || settings.ik !== true) return;
        var chain = [end];
        var depth = Math.max(1, Math.min(16, Math.round(number(settings.ikd, 2))));
        while (chain.length <= depth && bones[bones[chain[0]].parent]) chain.unshift(bones[chain[0]].parent);
        var target = -1, orient = -1;
        controllers.forEach(function (each, index) {
          if (each.bone !== end) return;
          if (each.orients) { if (orient < 0) orient = index; } else if (target < 0) target = index;
        });
        if (chain.length < 2 || target < 0) return;
        var axis = numbers(settings.a, 3, 0);
        limbs.push({ chain: chain, target: target, orient: settings.ikg !== false ? orient : -1,
                     rope: settings.ikm === 'rope', turns: settings.ikr !== false, reach: Math.max(1e-3, number(settings.ikrd, 25)),
                     axis: Math.hypot(axis[0], axis[1]) > 1e-6 ? Math.atan2(axis[1], axis[0]) : 0 });
      });
      // Where each controller is on this frame: as the animation that sets the bones has
      // it, then moved further by those that add, as much as each one's blend says.
      function controllerSpots(base, adding) {
        return controllers.map(function (each, index) {
          var spot = each.rest.slice();
          if (base && base.controls) {
            var said = sample(base, index, base.controls);
            spot[0] += (said[0] - each.rest[0]) * base.blend;
            spot[1] += (said[1] - each.rest[1]) * base.blend;
          }
          adding.forEach(function (layer) {
            if (!layer.controls) return;
            var more = sample(layer, index, layer.controls);
            spot[0] += (more[0] - each.rest[0]) * layer.blend;
            spot[1] += (more[1] - each.rest[1]) * layer.blend;
          });
          return spot;
        });
      }
      // A bone turned about its own root, in the puppet's space, by `angle`: its frame from
      // its parent made over so.
      function turnBone(index, above, angle) {
        var bone = bones[index];
        var world = above ? joined(above, bone.now) : bone.now;
        var cos = Math.cos(angle), sin = Math.sin(angle), x = world[4], y = world[5];
        var turned = joined([cos, sin, -sin, cos, x - cos * x + sin * y, y - sin * x - cos * y], world);
        bone.now = above ? joined(undone(above), turned) : turned;
      }
      function bend(limb, spots, whole) {
        var chain = limb.chain, top = bones[chain[0]].parent;
        var above = bones[top] ? whole(top, 0) : null;
        function worlds() {
          var into = above, all = [];
          chain.forEach(function (index) {
            into = into ? joined(into, bones[index].now) : bones[index].now;
            all.push(into);
          });
          return all;
        }
        var now = worlds();
        var points = now.map(function (world) { return [world[4], world[5]]; });
        var lengths = [], reach = 0;
        for (var link = 0; link + 1 < points.length; link++) {
          lengths.push(Math.hypot(points[link + 1][0] - points[link][0], points[link + 1][1] - points[link][1]));
          reach += lengths[link];
        }
        if (!(reach > 1e-6)) return;
        var target = spots[limb.target], root = points[0];
        var toward = [target[0] - root[0], target[1] - root[1]], away = Math.hypot(toward[0], toward[1]);
        var wanted = points.map(function (point) { return point.slice(); });
        if (points.length === 3 && !limb.rope) {
          // Two bones: the joint where both reach, on the side the orientation controller
          // (or the animation's own bend) is.
          var first = lengths[0], second = lengths[1];
          var span = Math.max(Math.abs(first - second) + 1e-4, Math.min(first + second - 1e-4, away));
          var heading = Math.atan2(toward[1], toward[0]);
          var opening = Math.acos(Math.max(-1, Math.min(1, (first * first + span * span - second * second) / (2 * first * span))));
          var side = limb.orient >= 0 && spots[limb.orient] ? spots[limb.orient] : points[1];
          var cross = toward[0] * (side[1] - root[1]) - toward[1] * (side[0] - root[0]);
          var joint = heading + (cross >= 0 ? opening : -opening);
          wanted[1] = [root[0] + Math.cos(joint) * first, root[1] + Math.sin(joint) * first];
          var last = Math.atan2(target[1] - wanted[1][1], target[0] - wanted[1][0]);
          wanted[2] = [wanted[1][0] + Math.cos(last) * second, wanted[1][1] + Math.sin(last) * second];
        } else {
          // More bones, or a rope: drawn to the target and back to the root, again and again.
          if (limb.orient >= 0 && spots[limb.orient]) {
            for (var each = 1; each + 1 < wanted.length; each++) {
              wanted[each][0] += (spots[limb.orient][0] - wanted[each][0]) * 0.1;
              wanted[each][1] += (spots[limb.orient][1] - wanted[each][1]) * 0.1;
            }
          }
          for (var round = 0; round < 12; round++) {
            wanted[wanted.length - 1] = target.slice();
            for (var back = wanted.length - 2; back >= 0; back--) pullTo(wanted, back, back + 1, lengths[back]);
            wanted[0] = root.slice();
            for (var on = 1; on < wanted.length; on++) pullTo(wanted, on, on - 1, lengths[on - 1]);
          }
        }
        // Each bone of the limb turned so that the next one's root is where it is wanted.
        for (var turning = 0; turning + 1 < chain.length; turning++) {
          now = worlds();
          var from = [now[turning][4], now[turning][5]], to = [now[turning + 1][4], now[turning + 1][5]];
          var angle = Math.atan2(wanted[turning + 1][1] - from[1], wanted[turning + 1][0] - from[0]) -
                      Math.atan2(to[1] - from[1], to[0] - from[0]);
          turnBone(chain[turning], turning ? now[turning - 1] : above, angle);
        }
        // Past its reach, the last bone points at the target.
        if (limb.turns && away > reach) {
          now = worlds();
          var end = now[now.length - 1];
          var pointing = Math.atan2(end[1], end[0]) + limb.axis;
          var aim = Math.atan2(target[1] - end[5], target[0] - end[4]) - pointing;
          aim = Math.atan2(Math.sin(aim), Math.cos(aim)) * Math.min(1, (away - reach) / limb.reach);
          turnBone(chain[chain.length - 1], now.length > 1 ? now[now.length - 2] : above, aim);
        }
      }
      function pullTo(points, which, toward, length) {
        var dx = points[which][0] - points[toward][0], dy = points[which][1] - points[toward][1];
        var apart = Math.hypot(dx, dy) || 1e-6;
        points[which] = [points[toward][0] + dx / apart * length, points[toward][1] + dy / apart * length];
      }

      // Blend shapes: the picture bent by hand, each corner that takes part moved by its
      // offset times how strongly the animations weigh the shape on this frame.
      var blendShapes = (said.blendShapes || []).map(function (each) { return numbersOf(each.offsets, Float32Array); });
      var shapeSlots = blendShapes.length && said.shapeSlots ? numbersOf(said.shapeSlots, Float32Array) : null;
      function shapeWeights(base, adding) {
        var weights = blendShapes.map(function () { return 0; }), any = false;
        function take(layer, share) {
          if (!layer || !layer.shapes.length) return;
          var moment = momentOf(layer);
          layer.shapes.forEach(function (track) {
            if (!(track.shape >= 0 && track.shape < weights.length)) return;
            var one = track.weights[moment.before], two = track.weights[moment.after];
            if (one === undefined || two === undefined) return;
            weights[track.shape] += (one + (two - one) * moment.share) * share;
            any = true;
          });
        }
        take(base, base ? base.blend : 0);
        adding.forEach(function (layer) { take(layer, layer.blend); });
        return any ? weights : null;
      }

      var places = new Float32Array(count * 2);
      var spots = new Float32Array(count * 2);
      for (var corner = 0; corner < count; corner++) {
        places[corner * 2] = corners[corner * 12];
        places[corner * 2 + 1] = corners[corner * 12 + 1];
        spots[corner * 2] = corners[corner * 12 + 2];
        spots[corner * 2 + 1] = corners[corner * 12 + 3];
      }
      var shape = gl.createVertexArray();
      gl.bindVertexArray(shape);
      var placeBuffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, placeBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, places, gl.DYNAMIC_DRAW);
      gl.enableVertexAttribArray(5);
      gl.vertexAttribPointer(5, 2, gl.FLOAT, false, 0, 0);
      gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
      gl.bufferData(gl.ARRAY_BUFFER, spots, gl.STATIC_DRAW);
      gl.enableVertexAttribArray(6);
      gl.vertexAttribPointer(6, 2, gl.FLOAT, false, 0, 0);
      var triangleBuffer = gl.createBuffer();
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, triangleBuffer);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, triangles, gl.DYNAMIC_DRAW);
      gl.bindVertexArray(null);

      var swaying = bones.some(function (bone) { return bone.sway; });
      var puppet = { shape: shape, count: triangles.length, moving: playing.length > 0 || swaying, layers: playing, bones: bones };
      // Which way round a triangle's corners go when its face is seen: as most go at rest. A
      // puppet may turn part of itself over to hide it — an eye closing folds the eyeball
      // under the lid — and with a material that leaves out backs, what is turned over is
      // not drawn.
      function turn(corners, at) {
        var a = triangles[at], b = triangles[at + 1], c = triangles[at + 2];
        return (corners[b * 2] - corners[a * 2]) * (corners[c * 2 + 1] - corners[a * 2 + 1]) -
               (corners[c * 2] - corners[a * 2]) * (corners[b * 2 + 1] - corners[a * 2 + 1]);
      }
      var facing = 0;
      for (var each = 0; each < triangles.length; each += 3) facing += turn(places, each) >= 0 ? 1 : -1;
      facing = facing >= 0 ? 1 : -1;
      var shown = culls ? new Uint16Array(triangles.length) : null;
      // Its parts, in the order they are drawn — all of it as one where the file does not say
      // or says what does not add up — and where each one's triangles are in what is drawn.
      var parts = (Array.isArray(said.parts) ? said.parts : []).map(function (part) { return [number(part[0], 0), number(part[1], 0)]; });
      var covered = parts.reduce(function (sum, part) { return sum + part[1]; }, 0);
      if (!parts.length || covered !== triangles.length) parts = [[0, triangles.length]];
      puppet.parts = parts.map(function (part) { return part.slice(); });
      // Parts shown only within others.
      puppet.clips = (said.clips || []).map(function (clip) {
        var picture = String(clip.texture || '');
        return { part: number(clip.part, -1), masks: (clip.masks || []).map(function (each) { return number(each, -1); }),
                 picture: picture ? texture('materials/' + picture) : null };
      }).filter(function (clip) { return parts[clip.part] && parts.length > 1; });
      // Where a point to hang things on is as the picture was last posed, in the picture's own
      // pixels from its middle; null for a point the puppet does not have.
      puppet.attachmentNames = Object.keys(points);
      puppet.attachment = function (name) {
        var point = points[name];
        if (!point) return null;
        var bone = bones[point.bone];
        return joined(bone.moved || atRest(point.bone, 0), point.rest);
      };
      // Layers of animation made by scripts: by an animation's name or number, or by what a
      // layer is described by in a scene. One made to play once goes away when it is over.
      puppet.addLayer = function (wanted, config, once) {
        var described = wanted && typeof wanted === 'object' ? wanted : (config || {});
        var asked = wanted && typeof wanted === 'object' ? (wanted.animation !== undefined ? wanted.animation : wanted.name) : wanted;
        var animation = animationOf(asked);
        // A script may name a layer of the object for its animation.
        if (!animation) {
          var named = puppet.findLayer(String(asked));
          animation = named ? named.animation : null;
        }
        if (!animation) return null;
        var layer = makeLayer(animation, described);
        if (described.visible !== undefined) layer.visible = flag(described.visible, true);
        layer.once = !!once;
        playing.push(layer);
        puppet.moving = true;
        if (owner) owner.moving = true;
        changed();
        return layer;
      };
      puppet.removeLayer = function (layer) {
        var at = playing.indexOf(layer);
        if (at < 0) return false;
        playing.splice(at, 1);
        changed();
        return true;
      };
      puppet.findLayer = function (wanted) {
        if (typeof wanted === 'number') return playing[wanted] || null;
        if (wanted && typeof wanted === 'object') return playing.filter(function (layer) { return layer.forScripts === wanted; })[0] || null;
        return playing.filter(function (layer) { return layer.name === wanted; })[0] || null;
      };
      // A layer of animation as scripts have it.
      puppet.scriptLayer = function (layer) {
        if (!layer.forScripts) {
          layer.forScripts = lenient({
            get fps() { return layer.fps; },
            get frameCount() { return layer.frameCount; },
            get duration() { return layer.length / (layer.fps || 30); },
            get name() { return layer.name; },
            set name(value) { layer.name = String(value); },
            get rate() { return layer.speed; },
            set rate(value) { layer.speed = Number(value) || 0; },
            get blend() { return layer.blend; },
            set blend(value) { layer.blend = Math.max(0, Math.min(1, Number(value) || 0)); changed(); },
            get visible() { return layer.visible; },
            set visible(value) { layer.visible = !!value; changed(); },
            play: function () {
              if (layer.done) {
                layer.frame = 0;
                layer.done = false;
              }
              layer.playing = true;
              if (owner) owner.moving = true;
              changed();
            },
            pause: function () { layer.playing = false; },
            stop: function () {
              layer.playing = false;
              layer.frame = 0;
              layer.done = false;
              changed();
            },
            isPlaying: function () { return layer.playing; },
            // The layer's animation, which it plays: the layer itself steers it.
            getAnimation: function () { return layer.forScripts; },
            // Where in the animation it is, its repeats left out.
            getFrame: function () {
              var length = layer.length > 0 ? layer.length : 1;
              if (layer.mode === 'single' || layer.once) return Math.min(layer.frame, length);
              if (layer.mode === 'mirror') {
                var at = layer.frame % (length * 2);
                return at > length ? length * 2 - at : at;
              }
              return layer.frame % length;
            },
            setFrame: function (frame) {
              layer.frame = Math.max(0, Number(frame) || 0);
              layer.done = false;
              changed();
            },
            addEndedCallback: function (callback) { if (typeof callback === 'function') layer.ended.push(callback); }
          });
        }
        return layer.forScripts;
      };
      // What scripts have set of a bone, in place of what the animations say: where it is from
      // its parent and how it is turned and scaled there.
      puppet.overridden = false;
      puppet.boneIndex = function (wanted) {
        if (typeof wanted === 'number') return bones[wanted] ? wanted : -1;
        for (var i = 0; i < bones.length; i++) if (bones[i].name === wanted) return i;
        return -1;
      };
      puppet.localPose = function (index) {
        var bone = bones[index];
        if (!bone) return null;
        var now = bone.now || bone.rest;
        var pose = [now[4], now[5], Math.atan2(now[1], now[0]), Math.sqrt(now[0] * now[0] + now[1] * now[1]), Math.sqrt(now[2] * now[2] + now[3] * now[3])];
        // What a script has set shows from the next frame on, and is read back at once.
        var override = bone.override;
        if (override) {
          if (override.origin) {
            pose[0] = override.origin[0];
            pose[1] = override.origin[1];
          }
          if (override.angle !== undefined) pose[2] = override.angle;
          if (override.scale) {
            pose[3] = override.scale[0];
            pose[4] = override.scale[1];
          }
        }
        return pose;
      };
      puppet.setLocal = function (index, change) {
        var bone = bones[index];
        if (!bone) return;
        var pose = puppet.localPose(index);
        bone.override = bone.override || {};
        if (change.origin) bone.override.origin = change.origin;
        if (change.angle !== undefined) bone.override.angle = change.angle;
        if (change.scale) bone.override.scale = change.scale;
        if (!bone.override.origin) bone.override.origin = [pose[0], pose[1]];
        puppet.overridden = true;
        if (owner) owner.moving = true;
        changed();
      };
      puppet.restOf = function (index) { return atRest(index, 0); };
      puppet.worldOf = function (index) {
        var bone = bones[index];
        return bone ? (bone.moved || atRest(index, 0)) : null;
      };
      // A bone that sways: where the animation puts it, then turned and moved further by what
      // it keeps of its own motion. It is moved in the scene — by its parent, the animation,
      // the object it is on — and lags behind, swings, and comes back as a spring does, or
      // hangs as gravity has it. `above`: where its parent is in the picture; `placed`: where
      // the picture is in the scene.
      function sway(bone, above, placed, passed) {
        var state = bone.sway;
        var m = placed || [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
        var inScene = [m[0], m[1], m[4], m[5], m[12], m[13]];
        var animated = above ? joined(above, bone.now) : bone.now;
        var world = joined(inScene, animated);
        var root = [world[4], world[5]];
        var angle = Math.atan2(world[1], world[0]);
        var tipLocal = state.tip || [50, 0];
        var tip = [world[0] * tipLocal[0] + world[2] * tipLocal[1], world[1] * tipLocal[0] + world[3] * tipLocal[1]];
        var length = Math.max(1, Math.hypot(tip[0], tip[1]));
        var last = state.last;
        // How fast the root moves and turns, and how that changes: what the bone lags behind.
        var push = [0, 0], twist = 0;
        if (last && passed > 0) {
          var step = Math.min(passed, 0.1);
          var velocity = [(root[0] - last.root[0]) / step, (root[1] - last.root[1]) / step];
          var turn = angle - last.angle;
          turn = Math.atan2(Math.sin(turn), Math.cos(turn)) / step;
          if (last.velocity) {
            push = [(velocity[0] - last.velocity[0]) / step, (velocity[1] - last.velocity[1]) / step];
            twist = (turn - last.turn) / step;
          }
          // A jump — a new loop of the animation, a scene put elsewhere — is not a push.
          var most = 20 * SWAY_GRAVITY;
          var strength = Math.hypot(push[0], push[1]);
          if (strength > most) push = [push[0] * most / strength, push[1] * most / strength];
          twist = Math.max(-200, Math.min(200, twist));
          state.last = { root: root, angle: angle, velocity: velocity, turn: turn };
        } else {
          state.last = { root: root, angle: angle, velocity: null, turn: 0 };
        }
        // Gravity as strong as the scene says, and the scene's wind, blowing in gusts.
        var heavy = SWAY_GRAVITY * Math.max(0, number(general.gravitystrength, defaults.general.gravitystrength));
        var pull = state.gravity ? [state.gravity[0] * heavy, state.gravity[1] * heavy] : [0, 0];
        if (flag(general.windenabled, defaults.general.windenabled)) {
          var blowing = numbers(general.winddirection, 3, defaults.general.winddirection);
          var gust = number(general.windstrength, defaults.general.windstrength) * SWAY_WIND * (0.65 + 0.35 * Math.sin(ctx.time * 1.3 + length * 0.01) * Math.sin(ctx.time * 0.37 + 1.7));
          pull = [pull[0] + blowing[0] * gust, pull[1] + blowing[1] * gust];
        }
        var left = Math.min(passed, 0.1);
        while (left > 1e-6) {
          var dt = Math.min(left, 1 / 120);
          left -= dt;
          if (state.turns) {
            // What pulls across the bone, at its tip, turns it.
            var now = Math.atan2(tip[1], tip[0]) + state.angle;
            var across = [-Math.sin(now), Math.cos(now)];
            var force = ((pull[0] - push[0]) * across[0] + (pull[1] - push[1]) * across[1]) / length;
            var spin = force - twist + (-state.stiff * state.angle - state.friction * state.spin) / state.weight;
            state.spin += spin * dt;
            state.angle += state.spin * dt;
            if (state.angle < state.low) { state.angle = state.low; state.spin = Math.max(0, state.spin); }
            if (state.angle > state.high) { state.angle = state.high; state.spin = Math.min(0, state.spin); }
          }
          if (state.moves) {
            for (var axis = 0; axis < 2; axis++) {
              var speedUp = pull[axis] - push[axis] + (-state.moveStiff * state.shift[axis] - state.moveFriction * state.speed[axis]) / state.moveWeight;
              state.speed[axis] += speedUp * dt;
              state.shift[axis] += state.speed[axis] * dt;
            }
            // Hanging free, it goes no further than its own length.
            var far = Math.hypot(state.shift[0], state.shift[1]);
            if (!state.spring && far > length) {
              state.shift = [state.shift[0] * length / far, state.shift[1] * length / far];
              state.speed = [0, 0];
            }
          }
        }
        if (!isFinite(state.angle) || !isFinite(state.shift[0]) || !isFinite(state.shift[1])) puppet.resetSway(bone);
        // Back from the scene into the parent's coordinates: the turn as it is, the move
        // through the parent and the picture.
        var now2 = bone.now.slice();
        if (state.angle) {
          var c = Math.cos(state.angle), s2 = Math.sin(state.angle);
          now2 = [c * now2[0] - s2 * now2[1], s2 * now2[0] + c * now2[1], c * now2[2] - s2 * now2[3], s2 * now2[2] + c * now2[3], now2[4], now2[5]];
        }
        if (state.shift[0] || state.shift[1]) {
          var outer = above ? joined(inScene, above) : inScene;
          var back = undone(outer);
          now2[4] += back[0] * state.shift[0] + back[2] * state.shift[1];
          now2[5] += back[1] * state.shift[0] + back[3] * state.shift[1];
        }
        bone.now = now2;
      }
      puppet.resetSway = function (bone) {
        var state = bone && bone.sway;
        if (!state) return;
        state.angle = state.spin = 0;
        state.shift = [0, 0];
        state.speed = [0, 0];
        state.last = null;
      };
      // A push given by a script: a bone, or all of them, moved and turned faster at once.
      puppet.pushSway = function (index, moving, turning) {
        bones.forEach(function (bone, at) {
          if (!bone.sway || (index >= 0 && at !== index)) return;
          bone.sway.speed[0] += moving[0];
          bone.sway.speed[1] += moving[1];
          bone.sway.spin += turning;
        });
        if (owner) owner.moving = true;
        changed();
      };

      // Puts every corner where the bones are at a moment of the scene.
      var lastSeconds = null;
      puppet.pose = function (seconds, placed) {
        var passed = lastSeconds === null ? 0 : Math.max(0, seconds - lastSeconds);
        lastSeconds = seconds;
        // The editor's timeline holds every animation at its moment.
        if (ctx.timelineAt !== null) {
          playing.forEach(function (layer) { layer.frame = ctx.timelineAt * layer.fps * layer.speed; });
        } else {
          advance(passed);
        }
        playing.forEach(function (layer) {
          if (layer.shows) layer.visible = layer.shows.read() !== false;
        });
        var showing = playing.filter(function (layer) { return layer.visible; });
        if (!showing.length && !puppet.overridden && !swaying && !puppet.held) return;
        var setting = showing.filter(function (layer) { return !layer.adds; });
        var adding = showing.filter(function (layer) { return layer.adds; });
        var once = setting.filter(function (layer) { return layer.once && !layer.done; });
        var base = once[once.length - 1] || setting.filter(function (layer) { return layer.mode !== 'single' || !layer.done; })[0] ||
                   setting[setting.length - 1] || null;
        // Each bone from its parent in this frame: scaled, turned, then moved.
        bones.forEach(function (bone, index) {
          var pose = base ? sample(base, index) : bone.still.slice();
          // What the editor is posing, in place of what plays.
          if (puppet.held) pose = (puppet.held[index] || bone.still).slice();
          else if (base && base.blend < 1) {
            for (var part = 0; part < 7; part++) pose[part] = bone.still[part] + (pose[part] - bone.still[part]) * base.blend;
          }
          if (!puppet.held) adding.forEach(function (layer) {
            var more = sample(layer, index);
            pose[0] += (more[0] - bone.still[0]) * layer.blend;
            pose[1] += (more[1] - bone.still[1]) * layer.blend;
            pose[2] += (more[2] - bone.still[2]) * layer.blend;
            pose[5] += (more[5] - bone.still[5]) * layer.blend;
            pose[6] += (more[6] - bone.still[6]) * layer.blend;
            if (bone.still[3] > 1e-6) pose[3] *= 1 + (more[3] / bone.still[3] - 1) * layer.blend;
            if (bone.still[4] > 1e-6) pose[4] *= 1 + (more[4] / bone.still[4] - 1) * layer.blend;
          });
          var override = bone.override;
          if (override) {
            if (override.origin) {
              pose[0] = override.origin[0];
              pose[1] = override.origin[1];
            }
            if (override.angle !== undefined) pose[2] = override.angle;
            if (override.scale) {
              pose[3] = override.scale[0];
              pose[4] = override.scale[1];
            }
          }
          // Turned about x, then y, then the picture's own axis, and seen straight on: a turn
          // about x squeezes the bone's part up and down, one about y from side to side, and
          // past a quarter turn it is seen from behind.
          var cos = Math.cos(pose[2]), sin = Math.sin(pose[2]);
          var cx = Math.cos(pose[5]), sx = Math.sin(pose[5]), cy = Math.cos(pose[6]), sy = Math.sin(pose[6]);
          bone.now = [cos * cy * pose[3], sin * cy * pose[3],
                      (cos * sy * sx - sin * cx) * pose[4], (sin * sy * sx + cos * cx) * pose[4], pose[0], pose[1]];
          bone.done = false;
        });
        function whole(index, depth) {
          var bone = bones[index];
          if (!bone.done) {
            var parent = bones[bone.parent];
            var above = parent && depth < 64 ? whole(bone.parent, depth + 1) : null;
            if (bone.sway && !puppet.held) sway(bone, above, placed, passed);
            bone.moved = above ? joined(above, bone.now) : bone.now;
            // From where the corner is at rest to where the bone has taken it.
            bone.takes = joined(bone.moved, bone.back);
            bone.done = true;
          }
          return bone.moved;
        }
        // Limbs bent to their controllers before anything hangs on them.
        if (limbs.length && !puppet.held) {
          var spots = controllerSpots(base, adding);
          limbs.forEach(function (limb) { bend(limb, spots, whole); });
        }
        var weights = shapeSlots && !puppet.held ? shapeWeights(base, adding) : null;
        bones.forEach(function (bone, index) { whole(index, 0); });
        for (var corner = 0; corner < count; corner++) {
          var base = corner * 12;
          var x = corners[base], y = corners[base + 1];
          var shapeAt = weights ? shapeSlots[corner] : -1;
          if (shapeAt >= 0) {
            for (var shapeIndex = 0; shapeIndex < weights.length; shapeIndex++) {
              if (!weights[shapeIndex]) continue;
              x += blendShapes[shapeIndex][shapeAt * 2] * weights[shapeIndex];
              y += blendShapes[shapeIndex][shapeAt * 2 + 1] * weights[shapeIndex];
            }
          }
          var newX = 0, newY = 0, total = 0;
          for (var slot = 0; slot < 4; slot++) {
            var weight = corners[base + 8 + slot];
            var bone = bones[corners[base + 4 + slot]];
            if (!(weight > 0) || !bone) continue;
            var takes = bone.takes;
            newX += weight * (takes[0] * x + takes[2] * y + takes[4]);
            newY += weight * (takes[1] * x + takes[3] * y + takes[5]);
            total += weight;
          }
          places[corner * 2] = total > 0 ? newX / total : x;
          places[corner * 2 + 1] = total > 0 ? newY / total : y;
        }
        gl.bindBuffer(gl.ARRAY_BUFFER, placeBuffer);
        gl.bufferSubData(gl.ARRAY_BUFFER, 0, places);
        if (shown) {
          var kept = 0;
          parts.forEach(function (part, index) {
            var from = kept;
            for (var at = part[0]; at < part[0] + part[1]; at += 3) {
              if (turn(places, at) * facing < 0) continue;
              shown[kept++] = triangles[at];
              shown[kept++] = triangles[at + 1];
              shown[kept++] = triangles[at + 2];
            }
            puppet.parts[index] = [from, kept - from];
          });
          gl.bindVertexArray(shape);
          gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, triangleBuffer);
          gl.bufferSubData(gl.ELEMENT_ARRAY_BUFFER, 0, shown.subarray(0, kept));
          gl.bindVertexArray(null);
          puppet.count = kept;
        }
      };
      return puppet;
    }
    return { numbersOf: numbersOf, joined: joined, undone: undone, buildPuppet: buildPuppet };
  }

