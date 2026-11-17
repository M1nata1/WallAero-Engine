  // ------------------------------------------------------------------ pictures made here
  //
  // Textures a scene names without bringing them: Wallpaper Engine has them, a scene's
  // package does not. They are drawn here to the same purpose — a flat color, noise, the soft
  // shapes particles are made of — and so look alike, not the same.

  // A value that is the same every time for the same place: noise that does not change from
  // one start of the wallpaper to the next.
  function hash(x, y, seed) {
    var h = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263) ^ Math.imul(seed | 0, 2147483647);
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
  }

  // Smooth noise that repeats every `period` cells, so that a texture of it tiles.
  function wrapped(cell, period) {
    return ((cell % period) + period) % period;
  }
  function smoothNoise(x, y, period, seed) {
    var x0 = Math.floor(x), y0 = Math.floor(y);
    var fx = x - x0, fy = y - y0;
    fx = fx * fx * (3 - 2 * fx);
    fy = fy * fy * (3 - 2 * fy);
    var left = wrapped(x0, period), right = wrapped(x0 + 1, period);
    var up = wrapped(y0, period), down = wrapped(y0 + 1, period);
    var a = hash(left, up, seed), b = hash(right, up, seed);
    var c = hash(left, down, seed), d = hash(right, down, seed);
    var top = a + (b - a) * fx;
    var bottom = c + (d - c) * fx;
    return top + (bottom - top) * fy;
  }

  // Clouds: noise of gradients — soft, without the blots noise of values has — of several
  // sizes laid over one another, grey around the middle. Each size repeats across the
  // picture, so that it tiles; the gradients of its cells are worked out once.
  function cloudsPixels(size) {
    var values = new Float64Array(size * size);
    var weight = 0.6, cells = 4;
    for (var octave = 0; octave < 6; octave++) {
      var gx = new Float64Array(cells * cells), gy = new Float64Array(cells * cells);
      for (var cy = 0; cy < cells; cy++) {
        for (var cx = 0; cx < cells; cx++) {
          var angle = hash(cx, cy, octave + 1) * Math.PI * 2;
          gx[cy * cells + cx] = Math.cos(angle);
          gy[cy * cells + cx] = Math.sin(angle);
        }
      }
      for (var y = 0; y < size; y++) {
        var py = y / size * cells, y0 = Math.floor(py), fy = py - y0;
        var uy = fy * fy * fy * (fy * (fy * 6 - 15) + 10);
        var up = (y0 % cells) * cells, down = ((y0 + 1) % cells) * cells;
        for (var x = 0; x < size; x++) {
          var px = x / size * cells, x0 = Math.floor(px), fx = px - x0;
          var ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10);
          var left = x0 % cells, right = (x0 + 1) % cells;
          var a = gx[up + left] * fx + gy[up + left] * fy;
          var b = gx[up + right] * (fx - 1) + gy[up + right] * fy;
          var c = gx[down + left] * fx + gy[down + left] * (fy - 1);
          var d = gx[down + right] * (fx - 1) + gy[down + right] * (fy - 1);
          var top = a + (b - a) * ux;
          var bottom = c + (d - c) * ux;
          values[y * size + x] += weight * (top + (bottom - top) * uy);
        }
      }
      weight *= 0.5;
      cells *= 2;
    }
    var pixels = new Uint8Array(size * size * 4);
    for (var i = 0; i < size * size; i++) {
      var shade = Math.round(Math.max(0, Math.min(1, 0.5 + values[i])) * 255);
      pixels[i * 4] = pixels[i * 4 + 1] = pixels[i * 4 + 2] = shade;
      pixels[i * 4 + 3] = 255;
    }
    return pixels;
  }

  function noisePixels(size) {
    var pixels = new Uint8Array(size * size * 4);
    for (var i = 0; i < size * size * 4; i++) {
      pixels[i] = Math.round(hash(i % (size * 4), Math.floor(i / (size * 4)), 7) * 255);
    }
    return pixels;
  }

  // A ramp from black to white: down the picture, or across it.
  function rampPixels(size, across, reverse) {
    var pixels = new Uint8Array(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var share = (across ? x : y) / (size - 1);
        var shade = Math.round((reverse ? 1 - share : share) * 255);
        var at = (y * size + x) * 4;
        pixels[at] = pixels[at + 1] = pixels[at + 2] = shade;
        pixels[at + 3] = 255;
      }
    }
    return pixels;
  }

  // The colors of a soap film, across the picture: for effects that color by how bright.
  function rainbowPixels(size) {
    var pixels = new Uint8Array(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var turn = x / size * Math.PI * 2;
        var at = (y * size + x) * 4;
        pixels[at] = Math.round((0.72 + 0.28 * Math.cos(turn)) * 255);
        pixels[at + 1] = Math.round((0.72 + 0.28 * Math.cos(turn - 2.094)) * 255);
        pixels[at + 2] = Math.round((0.72 + 0.28 * Math.cos(turn + 2.094)) * 255);
        pixels[at + 3] = 255;
      }
    }
    return pixels;
  }

  // Cells, as light on the floor of a pool is: bright where two cells meet. It repeats, so a
  // texture of it tiles; `soft` makes the lines wide and faint, for a glow.
  function cellsPixels(size, soft) {
    var cells = 6;
    var points = [];
    for (var cy = 0; cy < cells; cy++) {
      for (var cx = 0; cx < cells; cx++) {
        points.push([(cx + 0.15 + 0.7 * hash(cx, cy, 71)) / cells, (cy + 0.15 + 0.7 * hash(cx, cy, 73)) / cells]);
      }
    }
    var pixels = new Uint8Array(size * size * 4);
    var reach = (soft ? 0.5 : 0.22) / cells;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        var u = (x + 0.5) / size, v = (y + 0.5) / size;
        var nearest = 9, second = 9;
        var homeX = Math.floor(u * cells), homeY = Math.floor(v * cells);
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            var gx = homeX + dx, gy = homeY + dy;
            var point = points[((gy % cells) + cells) % cells * cells + ((gx % cells) + cells) % cells];
            // The point of a cell beyond the edge is the one of the cell at the other edge.
            var px = point[0] + Math.floor(gx / cells), py = point[1] + Math.floor(gy / cells);
            var far = Math.sqrt((px - u) * (px - u) + (py - v) * (py - v));
            if (far < nearest) {
              second = nearest;
              nearest = far;
            } else if (far < second) {
              second = far;
            }
          }
        }
        var edge = Math.max(0, 1 - (second - nearest) / reach);
        var shade = Math.round(Math.pow(edge, soft ? 1.5 : 3) * 255);
        var at = (y * size + x) * 4;
        pixels[at] = pixels[at + 1] = pixels[at + 2] = shade;
        pixels[at + 3] = 255;
      }
    }
    return pixels;
  }

