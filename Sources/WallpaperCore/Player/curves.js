  // ------------------------------------------------------------------ values that change
  //
  // A value of a scene — where a picture is, how see-through, what a text says — is written
  // plainly, or with something behind it: a setting of the wallpaper, an animation that changes
  // it over time, a script that works it out. All three come as an object with the plain value
  // inside, which is what `plain` gives; the rest is done here.

  // An animation of a value: for each of its numbers a list of moments, with the number at
  // each and how the curve leaves one moment and arrives at the next.
  //
  //   { c0: [{ frame, value, front: { enabled, magic, x, y }, back: { enabled, magic, x, y } }, …],
  //     c1: …, options: { fps, length, mode, wraploop }, relative }
  //
  // A handle says where a curve leaving or reaching its moment is drawn towards, as Wallpaper
  // Engine's own editor draws it: across, in halves of the way to the moment on that side, so
  // from 0 to 2; up and down, in the value's own numbers. A handle marked `magic` is one that
  // editor works out when moments change; what it worked out is written like any other. With
  // `wraploop` the curve goes on from its last moment to its first, one length later,
  // arriving as the first leaves, so that a loop has no jump. With `relative` the numbers are
  // counted from what the scene says.
  function curveOf(animation) {
    if (!animation || typeof animation !== 'object') return null;
    var channels = [];
    Object.keys(animation).forEach(function (name) {
      var channel = /^c(\d+)$/.exec(name);
      if (!channel || !Array.isArray(animation[name])) return;
      var keys = animation[name].filter(function (each) { return each && isFinite(Number(each.frame)) && isFinite(Number(each.value)); })
        .map(function (each) {
          function handle(said) {
            return said && said.enabled ? { x: Number(said.x) || 0, y: Number(said.y) || 0 } : null;
          }
          return { frame: Number(each.frame), value: Number(each.value), front: handle(each.front), back: handle(each.back) };
        })
        .sort(function (first, second) { return first.frame - second.frame; });
      if (keys.length) channels[Number(channel[1])] = keys;
    });
    if (!channels.length) return null;
    var options = animation.options || {};
    var rate = Number(options.fps) > 0 ? Number(options.fps) : 30;
    var length = Number(options.length) > 0 ? Number(options.length) : 0;
    channels.forEach(function (keys) { length = Math.max(length, options.length > 0 ? 0 : keys[keys.length - 1].frame); });
    var mode = String(options.mode || 'loop').toLowerCase();
    var wraps = mode === 'loop' && options.wraploop === true && length > 0;
    var relative = animation.relative === true;

    // The moment before or after one of a curve's: with `wraploop`, round the end.
    function beside(keys, index, by) {
      var other = keys[index + by];
      if (other) return other;
      if (!wraps) return null;
      other = by > 0 ? keys[0] : keys[keys.length - 1];
      var arrival = by > 0 && other.front ? { x: -other.front.x, y: -other.front.y } : other.back;
      return { frame: other.frame + by * length, value: other.value, front: other.front, back: arrival };
    }

    function along(first, second, third, fourth, t) {
      var rest = 1 - t;
      return rest * rest * rest * first + 3 * rest * rest * t * second + 3 * rest * t * t * third + t * t * t * fourth;
    }

    // The value between two moments.
    function span(from, to, frame) {
      var wide = to.frame - from.frame;
      if (!(wide > 0)) return to.value;
      if (!from.front && !to.back) return from.value + (to.value - from.value) * (frame - from.frame) / wide;
      // A curve drawn with two handles; the moment along it is looked for, then its height.
      var x1 = from.frame, y1 = from.value, x2 = to.frame, y2 = to.value;
      if (from.front) {
        x1 += Math.max(0, Math.min(2, from.front.x)) * wide / 2;
        y1 += from.front.y;
      }
      if (to.back) {
        x2 += Math.max(-2, Math.min(0, to.back.x)) * wide / 2;
        y2 += to.back.y;
      }
      var low = 0, high = 1;
      for (var step = 0; step < 24; step++) {
        var middle = (low + high) / 2;
        if (along(from.frame, x1, x2, to.frame, middle) < frame) low = middle;
        else high = middle;
      }
      return along(from.value, y1, y2, to.value, (low + high) / 2);
    }

    function at(keys, frame) {
      var last = keys.length - 1;
      if (frame <= keys[0].frame) {
        var before = beside(keys, 0, -1);
        return before && frame < keys[0].frame ? span(before, keys[0], frame) : keys[0].value;
      }
      if (frame >= keys[last].frame) {
        var after = beside(keys, last, 1);
        return after && frame > keys[last].frame ? span(keys[last], after, frame) : keys[last].value;
      }
      var index = 1;
      while (keys[index].frame < frame) index++;
      return span(keys[index - 1], keys[index], frame);
    }

    // The numbers at a moment, in seconds since the scene began; a number the animation
    // does not have is left as `base` has it.
    function valueAt(seconds, base) {
      var frame = seconds * rate;
      if (length > 0) {
        if (mode === 'mirror') {
          frame = frame % (length * 2);
          if (frame > length) frame = length * 2 - frame;
        } else if (mode === 'single') {
          frame = Math.min(frame, length);
        } else {
          frame = frame % length;
        }
      }
      var result = base.slice();
      channels.forEach(function (keys, index) {
        if (index < result.length) result[index] = (relative ? base[index] : 0) + at(keys, frame);
      });
      return result;
    }
    // How it plays: the name scripts know it by, whether it waits for one of them to start
    // it, and the value of the same object whose animation it plays along with.
    valueAt.called = typeof options.name === 'string' ? options.name : '';
    valueAt.startsPaused = options.startpaused === true;
    valueAt.mode = mode;
    valueAt.rate = rate;
    valueAt.frames = length;
    valueAt.follows = options.parent && typeof options.parent === 'object' && typeof options.parent.key === 'string' ? options.parent.key : '';
    valueAt.events = (Array.isArray(options.events) ? options.events : [])
      .filter(function (event) { return event && typeof event.name === 'string' && isFinite(Number(event.frame)); })
      .map(function (event) { return { name: event.name, frame: Number(event.frame) }; });
    return valueAt;
  }

  // --- What a script of a scene has to work with ----------------------------------------
  //
