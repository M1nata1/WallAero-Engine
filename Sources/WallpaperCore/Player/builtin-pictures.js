  // --- Wallpaper Engine's own pictures, drawn anew -------------------------------------------
  //
  // Scenes name pictures that come with Wallpaper Engine, not with the scene: halos, drops on
  // glass, fog, fire, leaves, flares, magic circles. They are drawn here to the same measure as
  // Wallpaper Engine's — the same size and kind of edges, the same sheet of frames laid out the
  // same way, the same use of their channels (a map of directions for the maps of how a drop
  // faces) — and the same sort of picture, made from shapes and noise; none of their pixels.

  function builtinSheet(cols, rows, cellWidth, cellHeight, duration, count) {
    var frames = [];
    for (var i = 0; i < (count || cols * rows); i++) {
      frames.push([0, duration, (i % cols) * cellWidth, Math.floor(i / cols) * cellHeight, cellWidth, 0, 0, cellHeight]);
    }
    return frames;
  }
  function smooth01(edge0, edge1, x) {
    var t = Math.max(0, Math.min(1, (x - edge0) / (edge1 - edge0)));
    return t * t * (3 - 2 * t);
  }
  function fbm(x, y, octaves, seed) {
    var value = 0, weight = 0.5, total = 0;
    for (var o = 0; o < octaves; o++) {
      value += weight * smoothNoise(x, y, 4096, seed + o);
      total += weight;
      weight *= 0.5;
      x *= 2.03;
      y *= 2.03;
    }
    return value / total;
  }

  // A picture made pixel by pixel: `shade(u, v)` gives [red, green, blue, alpha] from 0 to 1 for
  // the middle of each pixel, u and v from 0 to 1 from the top left.
  function shaded(width, height, shade) {
    var pixels = new Uint8Array(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var c = shade((x + 0.5) / width, (y + 0.5) / height, x, y);
        var at = (y * width + x) * 4;
        pixels[at] = Math.round(Math.max(0, Math.min(1, c[0])) * 255);
        pixels[at + 1] = Math.round(Math.max(0, Math.min(1, c[1])) * 255);
        pixels[at + 2] = Math.round(Math.max(0, Math.min(1, c[2])) * 255);
        pixels[at + 3] = Math.round(Math.max(0, Math.min(1, c[3])) * 255);
      }
    }
    return pixels;
  }
  // White, as much as `alpha` says: a shape the particle's color tints.
  function whiteShape(width, height, alpha) {
    return shaded(width, height, function (u, v, x, y) { return [1, 1, 1, alpha(u, v, x, y)]; });
  }
  // A map of how a surface faces, as Wallpaper Engine keeps one: across and up in red and green
  // around a half, toward the eye in blue, and where there is a surface at all in alpha.
  function facingMap(width, height, facing) {
    return shaded(width, height, function (u, v, x, y) {
      var f = facing(u, v, x, y);
      if (!f) return [0.5, 0.5, 1, 0];
      var nx = f[0], ny = f[1], nz = Math.sqrt(Math.max(0, 1 - nx * nx - ny * ny));
      return [nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5, f[2]];
    });
  }
  // A picture drawn on a canvas, read back.
  function drawn(width, height, draw) {
    var canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    var context = canvas.getContext('2d');
    draw(context);
    var read = context.getImageData(0, 0, width, height).data;
    return new Uint8Array(read.buffer ? read.buffer.slice(0) : read);
  }
  // Distance from the middle, with the edge of the square at 1.
  function radius(u, v) { var x = u * 2 - 1, y = v * 2 - 1; return Math.sqrt(x * x + y * y); }

  // A drop on glass, in a cell of a sheet: round, its edge wavering a little, of a size of its
  // own. `at` gives where in the cell, as parts of it.
  function dropOf(cell) {
    var size = 0.16 + hash(cell, 1, 41) * 0.24;
    var wobble = [hash(cell, 2, 41), hash(cell, 3, 41), hash(cell, 4, 41), hash(cell, 5, 41)];
    var middle = [0.5 + (hash(cell, 6, 41) - 0.5) * 0.12, 0.5 + (hash(cell, 7, 41) - 0.5) * 0.12];
    return function (u, v) {
      var dx = u - middle[0], dy = v - middle[1];
      var turn = Math.atan2(dy, dx);
      var edge = size * (1 + 0.12 * Math.sin(turn * 2 + wobble[0] * 6.3) * wobble[1] + 0.08 * Math.sin(turn * 3 + wobble[2] * 6.3) * wobble[3]
                         + (dy > 0 ? 0.08 * dy / size : 0));
      return { dx: dx, dy: dy, edge: edge, far: Math.sqrt(dx * dx + dy * dy) };
    };
  }

  // Wallpaper Engine's round glows by their measured opacity from the middle out (0 to 255, at
  // every fortieth of the way to the edge), and their size: a ring of pixels at a time, so each
  // keeps its own core, falloff and outer ring.
  var ROUND_SHAPES = {
    'particle/halo': [64, [235, 235, 233, 230, 227, 224, 218, 211, 203, 195, 187, 177, 165, 154, 143, 132, 120, 107, 96, 85, 75, 66, 56, 48, 41, 34, 28, 23, 19, 15, 12, 10, 8, 6, 4, 3, 2, 2, 1, 1, 1]],
    'particle/halo_2': [64, [255, 255, 253, 242, 223, 194, 156, 117, 93, 80, 74, 70, 65, 61, 57, 53, 49, 44, 40, 36, 32, 29, 25, 22, 19, 17, 14, 12, 10, 8, 7, 6, 5, 4, 3, 2, 2, 2, 1, 1, 1]],
    'particle/halo_3': [64, [255, 255, 255, 255, 255, 254, 222, 134, 101, 80, 63, 48, 35, 25, 18, 12, 9, 7, 6, 7, 8, 10, 13, 17, 20, 23, 25, 26, 26, 25, 23, 19, 16, 12, 8, 6, 3, 2, 1, 0, 0]],
    'particle/halo_4': [128, [224, 202, 154, 100, 63, 48, 43, 42, 41, 39, 37, 36, 34, 32, 30, 28, 26, 24, 22, 20, 19, 17, 15, 14, 12, 11, 9, 9, 7, 6, 5, 5, 4, 3, 3, 2, 2, 1, 1, 1, 1]],
    'particle/halo_5': [64, [0, 0, 3, 8, 12, 18, 25, 33, 42, 50, 59, 68, 78, 88, 98, 107, 118, 128, 139, 149, 158, 168, 178, 187, 196, 204, 212, 217, 218, 212, 197, 172, 137, 97, 64, 37, 19, 8, 3, 1, 0]],
    'particle/halo_6': [128, [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 253, 250, 244, 234, 218, 197, 170, 140, 110, 81, 57, 39, 26, 18, 10, 4, 1, 0]],
    'particle/sharp_halo': [64, [255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 239, 161, 59, 9, 0]],
    'particle/ring': [64, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 6, 26, 71, 140, 209, 248, 245, 204, 135, 66, 22, 5, 1, 0]]
  };

  function builtinPicture(name) {
    name = String(name).toLowerCase().replace(/^materials\//, '').replace(/\.(tex|png|jpg)$/, '');
    var w, h;
    switch (name) {
      case 'particle/halo':
      case 'particle/halo_2':
      case 'particle/halo_3':
      case 'particle/halo_4':
      case 'particle/halo_5':
      case 'particle/halo_6':
      case 'particle/sharp_halo':
      case 'particle/ring':
        var round = ROUND_SHAPES[name];
        return { width: round[0], height: round[0], clamp: true, pixels: whiteShape(round[0], round[0], function (u, v) {
          var at = Math.min(40, radius(u, v) * 40), i = Math.floor(at), part = at - i, line = round[1];
          return (line[i] + (line[Math.min(40, i + 1)] - line[i]) * part) / 255; }) };
      case 'particle/sharp_halo_normal':
        return { width: 64, height: 64, clamp: true, pixels: facingMap(64, 64, function (u, v) {
          var x = u * 2 - 1, y = 1 - v * 2, r = Math.sqrt(x * x + y * y);
          return r < 0.98 ? [x, y, 1 - smooth01(0.92, 0.98, r)] : null; }) };
      case 'particle/chromaticdot':
        return { width: 64, height: 64, clamp: true, pixels: shaded(64, 64, function (u, v) {
          var g = Math.pow(Math.max(0, 1 - radius(u, v)), 1.6) * 0.8; return [g, g, g, 1]; }) };
      case 'particle/sickle':
        return { width: 64, height: 64, clamp: true, pixels: whiteShape(64, 64, function (u, v) {
          var a = Math.hypot(u - 0.5, v - 0.62), b = Math.hypot(u - 0.5, v - 0.74);
          return (1 - smooth01(0.53, 0.56, a)) * smooth01(0.53, 0.56, b) * (v < 0.4 ? 1 : 0); }) };
      case 'particle/drop':
      case 'particle/drop_normal':
        // A drop running down: a round head at the top, its trail narrowing below it.
        var half = function (v) { return v < 0.14 ? Math.sqrt(Math.max(0, 0.14 * 0.14 - (v - 0.14) * (v - 0.14))) / 0.14 * 0.36 : 0.36 * Math.pow(Math.max(0, 1 - (v - 0.14) / 0.84), 1.4); };
        if (name === 'particle/drop') {
          return { width: 32, height: 128, clamp: true, pixels: whiteShape(32, 128, function (u, v) {
            var across = Math.abs(u - 0.5), wide = half(v);
            return wide > 0 ? (1 - smooth01(wide * 0.6, wide, across)) * (0.35 + 0.65 * (1 - smooth01(0.1, 0.95, v))) : 0; }) };
        }
        return { width: 32, height: 128, clamp: true, pixels: facingMap(32, 128, function (u, v) {
          var across = u - 0.5, wide = half(v);
          return wide > 0.004 && Math.abs(across) < wide ? [across / wide * 0.9, v < 0.14 ? (0.14 - v) / 0.14 * 0.6 : -0.1, 1 - smooth01(wide * 0.8, wide, Math.abs(across))] : null; }) };
      case 'particle/normal_ring_smooth':
        return { width: 64, height: 64, clamp: true, pixels: facingMap(64, 64, function (u, v) {
          var x = u * 2 - 1, y = 1 - v * 2, r = Math.sqrt(x * x + y * y);
          if (r < 0.35 || r > 0.95) return null;
          var slope = Math.cos(Math.PI * (r - 0.35) / 0.6) * 0.85;
          return [x / r * slope, y / r * slope, Math.sin(Math.PI * (r - 0.35) / 0.6)]; }) };
      case 'particle/normal_pinch_rotate':
        return { width: 64, height: 64, clamp: true, pixels: facingMap(64, 64, function (u, v) {
          var x = u * 2 - 1, y = 1 - v * 2, r = Math.sqrt(x * x + y * y);
          if (r > 0.98) return null;
          var by = Math.sin(Math.PI * r) * 0.8;
          return [(-y * 0.8 - x * 0.4) * by, (x * 0.8 - y * 0.4) * by, 1 - smooth01(0.8, 0.98, r)]; }) };
      case 'particle/water/rain_drops_sheet':
        return { width: 256, height: 256, clamp: false, frames: builtinSheet(4, 4, 64, 64, 0.0625),
                 pixels: whiteShape(256, 256, function (u, v, x, y) {
                   var cell = Math.floor(y / 64) * 4 + Math.floor(x / 64);
                   var drop = dropOf(cell)((x % 64 + 0.5) / 64, (y % 64 + 0.5) / 64);
                   return 1 - smooth01(drop.edge - 0.025, drop.edge, drop.far); }) };
      case 'particle/water/rain_drops_sheet_normal':
        return { width: 256, height: 256, clamp: false, frames: builtinSheet(4, 4, 64, 64, 0.0625),
                 pixels: facingMap(256, 256, function (u, v, x, y) {
                   var cell = Math.floor(y / 64) * 4 + Math.floor(x / 64);
                   var drop = dropOf(cell)((x % 64 + 0.5) / 64, (y % 64 + 0.5) / 64);
                   if (drop.far >= drop.edge) return null;
                   var out = drop.far / drop.edge;
                   // A drop bends the light as a lens does: the more, the nearer its rim.
                   var slope = out * 0.95;
                   return [drop.dx / Math.max(drop.far, 0.0001) * slope, -drop.dy / Math.max(drop.far, 0.0001) * slope, 1 - smooth01(0.9, 1, out)]; }) };
      case 'particle/fog/fog1':
        // A puff of smoke whirling around a dark middle, sixty-four frames, eight by eight,
        // that turns as it plays and comes back to where it began. As Wallpaper Engine's own
        // sheet measures: a twentieth covered on the whole, about 0.02 in the middle, most
        // (0.13–0.15) halfway out, next to nothing at the rim.
        return { width: 512, height: 512, clamp: false, frames: builtinSheet(8, 8, 64, 64, 0.015625),
                 pixels: whiteShape(512, 512, function (u, v, x, y) {
                   var cell = Math.floor(y / 64) * 8 + Math.floor(x / 64), turn = cell / 64 * 6.283;
                   var dx = (x % 64 + 0.5) / 32 - 1, dy = (y % 64 + 0.5) / 32 - 1, r = Math.sqrt(dx * dx + dy * dy);
                   var a = Math.atan2(dy, dx) + 0.7 * r + 0.3 * Math.sin(turn);
                   var px = r * Math.cos(a), py = r * Math.sin(a);
                   var lumps = fbm(px * 2.6 + Math.cos(turn) * 0.5 + 7, py * 2.6 + Math.sin(turn) * 0.5 + 7, 5, 5);
                   var curl = fbm(px * 6 + Math.sin(turn) * 0.4, py * 6 + Math.cos(turn) * 0.4, 3, 13);
                   var wisp = Math.pow(Math.max(0, lumps - 0.42) * 3, 1.6) * (0.55 + 0.9 * Math.pow(1 - Math.abs(curl * 2 - 1), 3));
                   var ragged = (fbm(px * 2 + Math.cos(turn) * 0.3, py * 2 + Math.sin(turn) * 0.3, 2, 9) - 0.5) * 0.45;
                   var body = smooth01(0.04, 0.42, r) * (1 - smooth01(0.36 + ragged, 0.9 + ragged, r));
                   return Math.min(1, 0.655 * wisp * body + 0.02 * (1 - smooth01(0, 0.2, r))); }) };
      case 'particle/fog/fog3':
        // Smoke curling as it goes: sixty-four frames of one puff, eight by eight.
        var seed = name === 'particle/fog/fog1' ? 3 : 17, shadedFog = name === 'particle/fog/fog3';
        return { width: 512, height: 512, clamp: false, frames: builtinSheet(8, 8, 64, 64, 0.015625),
                 pixels: shaded(512, 512, function (u, v, x, y) {
                   var cell = Math.floor(y / 64) * 8 + Math.floor(x / 64), t = cell / 64;
                   var cu = (x % 64 + 0.5) / 64, cv = (y % 64 + 0.5) / 64;
                   var r = radius(cu, cv);
                   var swirl = fbm(cu * 3 + Math.cos(t * 6.283) * 0.6, cv * 3 + Math.sin(t * 6.283) * 0.6 - t * 0.8, 4, seed);
                   var a = Math.max(0, swirl * 1.6 - 0.45) * (1 - smooth01(0.35, 0.95, r));
                   var g = shadedFog ? 0.55 + 0.45 * (1 - cv) : 1;
                   return [g, g, g, a]; }) };
      case 'particle/fire/fire2':
        // A flame licking upward, thirty-two frames, eight by four.
        return { width: 512, height: 256, clamp: false, frames: builtinSheet(8, 4, 64, 64, 0),
                 pixels: whiteShape(512, 256, function (u, v, x, y) {
                   var cell = Math.floor(y / 64) * 8 + Math.floor(x / 64), t = cell / 32;
                   var cu = (x % 64 + 0.5) / 64, cv = (y % 64 + 0.5) / 64;
                   var rise = 1 - cv;
                   var flicker = fbm(cu * 4, cv * 3 + t * 6, 3, 29) - 0.5;
                   var wide = 0.32 * Math.pow(Math.max(0, 1 - rise), 0.7) * (rise < 0.15 ? rise / 0.15 : 1);
                   var across = Math.abs(cu - 0.5 + flicker * 0.25 * rise);
                   return (1 - smooth01(wide * 0.4, wide, across)) * (1 - smooth01(0.7, 1, rise)); }) };
      case 'particle/debris/debris1':
        // Eight small pieces of rock, each its own shape.
        return { width: 512, height: 64, clamp: true, frames: builtinSheet(8, 1, 64, 64, 0),
                 pixels: drawn(512, 64, function (c) {
                   c.fillStyle = 'rgba(255,255,255,1)';
                   for (var piece = 0; piece < 8; piece++) {
                     var corners = 6 + Math.floor(hash(piece, 1, 43) * 4), size = 9 + hash(piece, 2, 43) * 14;
                     c.beginPath();
                     for (var k = 0; k < corners; k++) {
                       var turn = k / corners * Math.PI * 2, reach = size * (0.6 + 0.4 * hash(piece, k + 3, 43));
                       var px = piece * 64 + 32 + Math.cos(turn) * reach, py = 32 + Math.sin(turn) * reach * 0.8;
                       if (k === 0) c.moveTo(px, py); else c.lineTo(px, py);
                     }
                     c.closePath();
                     c.fill();
                   }
                 }) };
      case 'particle/nature/rosepetals':
        // Five rose petals, pale pink, a little deeper at the foot.
        return { width: 512, height: 128, clamp: false, frames: builtinSheet(5, 1, 102.4, 128, 0.2),
                 pixels: drawn(512, 128, function (c) {
                   for (var petal = 0; petal < 5; petal++) {
                     var mx = petal * 102.4 + 51.2, wide = 26 + hash(petal, 1, 47) * 14, tall = 46 + hash(petal, 2, 47) * 12;
                     c.save();
                     c.translate(mx, 64);
                     c.rotate((hash(petal, 3, 47) - 0.5) * 0.9);
                     var paint = c.createLinearGradient(0, tall, 0, -tall);
                     paint.addColorStop(0, 'rgba(236,164,186,1)');
                     paint.addColorStop(0.5, 'rgba(249,212,224,1)');
                     paint.addColorStop(1, 'rgba(255,240,245,1)');
                     c.fillStyle = paint;
                     c.beginPath();
                     c.moveTo(0, tall);
                     c.bezierCurveTo(-wide * 1.3, tall * 0.2, -wide, -tall * 0.9, 0, -tall * 0.7);
                     c.bezierCurveTo(wide, -tall * 0.9, wide * 1.3, tall * 0.2, 0, tall);
                     c.fill();
                     c.restore();
                   }
                 }) };
      case 'particle/nature/leaves7':
      case 'particle/nature/leaves8':
        // Thirty leaves, six by five, turned every way: broad ones, or narrow ones.
        var narrow = name === 'particle/nature/leaves8';
        return { width: 512, height: 512, clamp: false, frames: builtinSheet(6, 5, 85.334, 102.4, 1 / 30),
                 pixels: drawn(512, 512, function (c) {
                   for (var leaf = 0; leaf < 30; leaf++) {
                     var mx = (leaf % 6) * 85.334 + 42.667, my = Math.floor(leaf / 6) * 102.4 + 51.2;
                     var tall = 36 + hash(leaf, 1, 53) * 8, wide = tall * (narrow ? 0.28 : 0.5) * (0.85 + hash(leaf, 2, 53) * 0.3);
                     var green = 110 + Math.floor(hash(leaf, 3, 53) * 60);
                     c.save();
                     c.translate(mx, my);
                     c.rotate(leaf / 30 * Math.PI * 2);
                     c.fillStyle = 'rgba(' + Math.floor(green * 0.45) + ',' + green + ',' + Math.floor(green * 0.3) + ',1)';
                     c.beginPath();
                     c.moveTo(0, -tall);
                     c.quadraticCurveTo(wide * 1.4, -tall * 0.1, 0, tall);
                     c.quadraticCurveTo(-wide * 1.4, -tall * 0.1, 0, -tall);
                     c.fill();
                     c.strokeStyle = 'rgba(' + Math.floor(green * 0.3) + ',' + Math.floor(green * 0.7) + ',' + Math.floor(green * 0.2) + ',1)';
                     c.lineWidth = 1.5;
                     c.beginPath();
                     c.moveTo(0, -tall * 0.9);
                     c.lineTo(0, tall * 1.1);
                     c.stroke();
                     c.restore();
                   }
                 }) };
      case 'particle/light/flare_0':
        // A sun: a bright round heart, and thin rays all round it.
        return { width: 256, height: 256, clamp: true, pixels: whiteShape(256, 256, function (u, v) {
          var r = radius(u, v), turn = Math.atan2(v - 0.5, u - 0.5);
          var ray = Math.pow(Math.max(0, smoothNoise(turn * 28, 0, 4096, 61)), 6) * 1.6;
          return Math.max(1 - smooth01(0.24, 0.3, r), (0.5 * ray + 0.25) * Math.pow(Math.max(0, 1 - r), 2) * (r > 0.24 ? 1 : 0)); }) };
      case 'particle/light/flare_1':
        // A glint: four long thin rays, four short ones between them, a small bright heart.
        return { width: 256, height: 256, clamp: true, pixels: whiteShape(256, 256, function (u, v) {
          var x = u * 2 - 1, y = v * 2 - 1, r = Math.sqrt(x * x + y * y);
          var straight = Math.max(Math.exp(-Math.abs(y) * 90) * Math.max(0, 1 - Math.abs(x)), Math.exp(-Math.abs(x) * 90) * Math.max(0, 1 - Math.abs(y)));
          var d1 = (x + y) / Math.SQRT2, d2 = (x - y) / Math.SQRT2;
          var slant = Math.max(Math.exp(-Math.abs(d1) * 120) * Math.max(0, 1 - Math.abs(d2) * 2), Math.exp(-Math.abs(d2) * 120) * Math.max(0, 1 - Math.abs(d1) * 2));
          return Math.max(straight, slant * 0.6, Math.exp(-Math.pow(r / 0.04, 2)), 0.15 * Math.pow(Math.max(0, 1 - r * 2), 3)); }) };
      case 'particle/light/flare_2':
        // A ring of light round a dark heart, and a streak across it.
        return { width: 256, height: 256, clamp: true, pixels: whiteShape(256, 256, function (u, v) {
          var x = u * 2 - 1, y = v * 2 - 1, r = Math.sqrt(x * x + y * y);
          var ring = Math.exp(-Math.pow((r - 0.2) / 0.06, 2)), glow = 0.45 * Math.pow(Math.max(0, 1 - r / 0.55), 2) * smooth01(0.08, 0.16, r);
          var streak = Math.exp(-Math.abs(y) * 60) * Math.pow(Math.max(0, 1 - Math.abs(x)), 2) * 0.5;
          return Math.max(ring, glow, streak); }) };
      case 'particle/light/light_shafts_0':
        // Light falling from the top in soft columns, dying away downward.
        return { width: 256, height: 512, clamp: true, pixels: whiteShape(256, 512, function (u, v) {
          var light = 0;
          for (var k = 0; k < 7; k++) {
            var at = 0.25 + hash(k, 1, 59) * 0.5, wide = 0.03 + hash(k, 2, 59) * 0.09;
            light += Math.exp(-Math.pow((u - at) / wide, 2)) * (0.25 + 0.4 * hash(k, 3, 59));
          }
          // As bright against a scene as Wallpaper Engine's own: about a quarter more light
          // where it falls (measured on "Frieren with music").
          return Math.min(1, light) * 0.3 * Math.pow(1 - v, 1.5) * smooth01(0, 0.06, v); }) };
      case 'particle/light/light_shafts_5':
        // Rays out from a point, of many lengths.
        return { width: 256, height: 256, clamp: true, pixels: whiteShape(256, 256, function (u, v) {
          var x = u * 2 - 1, y = v * 2 - 1, r = Math.sqrt(x * x + y * y), turn = Math.atan2(y, x), light = 0;
          for (var k = 0; k < 11; k++) {
            var toward = hash(k, 1, 67) * Math.PI * 2, wide = 0.03 + hash(k, 2, 67) * 0.08, reach = 0.5 + hash(k, 3, 67) * 0.5;
            var off = Math.atan2(Math.sin(turn - toward), Math.cos(turn - toward));
            light += Math.exp(-Math.pow(off / wide, 2)) * Math.max(0, 1 - r / reach);
          }
          return Math.min(1, light * 0.8 + 0.3 * Math.pow(Math.max(0, 1 - r * 2.5), 2)); }) };
      case 'particle/light/light_shafts_6':
        // Two soft columns of light, a dim long one on the left and a bright short one on the
        // right, each coming in over the top sixth and dying away downward (fitted to Wallpaper
        // Engine's own). Soft on every side: a shaft stretched by its system's scale stays a glow.
        return { width: 128, height: 512, clamp: true, pixels: whiteShape(128, 512, function (u, v) {
          function column(strength, at, wide, top, end) {
            return strength * Math.exp(-Math.pow((u - at) / wide, 2)) * smooth01(0, top, v) * (1 - smooth01(top, end, v));
          }
          return Math.min(1, column(0.346, 0.348, 0.117, 0.184, 0.852) + column(0.699, 0.667, 0.134, 0.189, 0.632)); }) };
      case 'particle/beam/beam_2':
        // A thin line of light, with a glow round it, fading at its ends.
        return { width: 32, height: 128, clamp: true, pixels: whiteShape(32, 128, function (u, v) {
          var across = Math.abs(u - 0.5), ends = Math.min(1, Math.min(v, 1 - v) * 6);
          return Math.max(1 - smooth01(0.02, 0.05, across), 0.35 * Math.exp(-across * 14)) * ends; }) };
      case 'particle/magic/glyph_1':
      case 'particle/magic/glyph_2':
        // A magic circle: two rings, a band of runes between them, and for the first a six-pointed
        // star with a hexagon inside, all in glowing lines.
        var star = name === 'particle/magic/glyph_1';
        return { width: 512, height: 512, clamp: true, pixels: drawn(512, 512, function (c) {
          c.strokeStyle = 'rgba(255,255,255,1)';
          c.shadowColor = 'rgba(255,255,255,0.9)';
          c.shadowBlur = 6;
          c.lineWidth = 3;
          [0.9, 0.74].forEach(function (ring) { c.beginPath(); c.arc(256, 256, 256 * ring, 0, Math.PI * 2); c.stroke(); });
          c.lineWidth = 2.2;
          for (var rune = 0; rune < 28; rune++) {
            c.save();
            c.translate(256, 256);
            c.rotate(rune / 28 * Math.PI * 2);
            c.translate(0, -256 * 0.82);
            c.beginPath();
            for (var stroke = 0; stroke < 3; stroke++) {
              var x0 = (hash(rune, stroke * 4, 71) - 0.5) * 22, y0 = (hash(rune, stroke * 4 + 1, 71) - 0.5) * 22;
              var x1 = (hash(rune, stroke * 4 + 2, 71) - 0.5) * 22, y1 = (hash(rune, stroke * 4 + 3, 71) - 0.5) * 22;
              c.moveTo(x0, y0);
              c.lineTo(x1, y1);
            }
            c.stroke();
            c.restore();
          }
          if (star) {
            c.lineWidth = 3;
            [0, Math.PI].forEach(function (shift) {
              c.beginPath();
              for (var k = 0; k <= 3; k++) {
                var turn = shift + k / 3 * Math.PI * 2 - Math.PI / 2;
                var px = 256 + Math.cos(turn) * 256 * 0.72, py = 256 + Math.sin(turn) * 256 * 0.72;
                if (k === 0) c.moveTo(px, py); else c.lineTo(px, py);
              }
              c.stroke();
            });
            c.beginPath();
            for (var k2 = 0; k2 <= 6; k2++) {
              var turn2 = k2 / 6 * Math.PI * 2;
              var qx = 256 + Math.cos(turn2) * 256 * 0.36, qy = 256 + Math.sin(turn2) * 256 * 0.36;
              if (k2 === 0) c.moveTo(qx, qy); else c.lineTo(qx, qy);
            }
            c.stroke();
          }
        }) };
      case 'particle/magic/glyph_4':
        // A soft ring of light, uneven round its way.
        return { width: 512, height: 512, clamp: true, pixels: whiteShape(512, 512, function (u, v) {
          var r = radius(u, v), turn = Math.atan2(v - 0.5, u - 0.5);
          var wobble = 0.04 * (smoothNoise(turn * 3 + 10, 0, 4096, 73) - 0.5);
          return Math.exp(-Math.pow((r - 0.78 - wobble) / 0.07, 2)) * (0.6 + 0.4 * smoothNoise(turn * 5, 1, 4096, 79)); }) };
      case 'particle/shape/star_4_glow':
        // A four-pointed star in a glow.
        return { width: 256, height: 256, clamp: true, pixels: whiteShape(256, 256, function (u, v) {
          var x = u * 2 - 1, y = v * 2 - 1, r = Math.sqrt(x * x + y * y);
          var arms = Math.max(Math.exp(-Math.abs(y) * 40) * Math.pow(Math.max(0, 1 - Math.abs(x)), 2),
                              Math.exp(-Math.abs(x) * 40) * Math.pow(Math.max(0, 1 - Math.abs(y)), 2));
          return Math.max(arms, Math.exp(-Math.pow(r / 0.06, 2)), 0.3 * Math.pow(Math.max(0, 1 - r), 3)); }) };
      case 'gradient/blend_gradient':
      case 'gradient/blend_gradient_reverse':
        // Dark in the middle, light toward the edges — or the other way round.
        var reverse = name === 'gradient/blend_gradient_reverse';
        return { width: 256, height: 256, clamp: true, pixels: shaded(256, 256, function (u, v) {
          var g = Math.min(1, radius(u, v) / Math.SQRT2 * 1.25); if (reverse) g = 1 - g; return [g, g, g, 1]; }) };
    }
    return builtinPicture2(name);
  }

  // The rest of Wallpaper Engine's own pictures, drawn anew to the same measure (see
  // `builtinPicture`). Shapes are worked out from their distance to an outline, so that every
  // edge is smooth at any size; sheets are drawn cell by cell.

  // Signed distance from a point to a polygon, negative inside; its corners in order.
  function polygonDistance(x, y, corners) {
    var best = Infinity, inside = false;
    for (var i = 0, j = corners.length - 1; i < corners.length; j = i++) {
      var ax = corners[j][0], ay = corners[j][1], bx = corners[i][0], by = corners[i][1];
      var ex = bx - ax, ey = by - ay, wx = x - ax, wy = y - ay;
      var t = Math.max(0, Math.min(1, (wx * ex + wy * ey) / (ex * ex + ey * ey || 1)));
      var dx = wx - ex * t, dy = wy - ey * t;
      best = Math.min(best, dx * dx + dy * dy);
      if ((ay > y) !== (by > y) && x < (bx - ax) * (y - ay) / (by - ay) + ax) inside = !inside;
    }
    return (inside ? -1 : 1) * Math.sqrt(best);
  }
  // The corners of a star of `points` points, `outer` and `inner` far from its middle.
  function starCorners(points, outer, inner, turn, stretchY) {
    var corners = [];
    for (var k = 0; k < points * 2; k++) {
      var angle = (turn || 0) - Math.PI / 2 + k * Math.PI / points, reach = k % 2 ? inner : outer;
      corners.push([Math.cos(angle) * reach, Math.sin(angle) * reach * (stretchY || 1)]);
    }
    return corners;
  }
  function regularCorners(sides, reach, turn) {
    var corners = [];
    for (var k = 0; k < sides; k++) {
      var angle = (turn || 0) - Math.PI / 2 + k * Math.PI * 2 / sides;
      corners.push([Math.cos(angle) * reach, Math.sin(angle) * reach]);
    }
    return corners;
  }
  // From a distance to an outline: filled with a smooth edge, and a glow that dies away outside.
  function filledBy(distance, edge) { return 1 - smooth01(-edge, edge, distance); }
  function glowBy(distance, falloff) { return distance <= 0 ? 1 : Math.exp(-distance * falloff); }
  // A shape in a square, `mask(x, y)` with x and y from −1 to 1, y downward.
  function shapeOf(size, mask, clamp) {
    return { width: size, height: size, clamp: clamp !== false, pixels: whiteShape(size, size, function (u, v) { return mask(u * 2 - 1, v * 2 - 1); }) };
  }
  // A sheet: `cell(index, x, y, share)` gives [grey, alpha] — or [r, g, b, a] with `colored` — for
  // a point of a cell, x and y from −1 to 1, `share` how far along the sheet the cell is.
  function sheetOf(cols, rows, cellWidth, cellHeight, duration, cell, count, colored, clamp) {
    var width = Math.round(cols * cellWidth), height = Math.round(rows * cellHeight), total = count || cols * rows;
    var pixels = shaded(width, height, function (u, v, px, py) {
      var col = Math.min(cols - 1, Math.floor(px / cellWidth)), row = Math.min(rows - 1, Math.floor(py / cellHeight));
      var index = row * cols + col;
      if (index >= total) return [0, 0, 0, 0];
      var x = ((px - col * cellWidth) + 0.5) / cellWidth * 2 - 1, y = ((py - row * cellHeight) + 0.5) / cellHeight * 2 - 1;
      var c = cell(index, x, y, index / total);
      return colored ? c : [c[0], c[0], c[0], c[1]];
    });
    return { width: width, height: height, clamp: !!clamp, pixels: pixels, frames: builtinSheet(cols, rows, cellWidth, cellHeight, duration, total) };
  }
  // A sheet drawn on a canvas, cell by cell: `draw(context, index, share)` with the cell's middle
  // at the origin and its half width and height.
  function drawnSheet(cols, rows, cellWidth, cellHeight, duration, draw, count) {
    var width = Math.round(cols * cellWidth), height = Math.round(rows * cellHeight), total = count || cols * rows;
    return { width: width, height: height, clamp: false, frames: builtinSheet(cols, rows, cellWidth, cellHeight, duration, total),
             pixels: drawn(width, height, function (c) {
               for (var i = 0; i < total; i++) {
                 c.save();
                 c.translate((i % cols + 0.5) * cellWidth, (Math.floor(i / cols) + 0.5) * cellHeight);
                 draw(c, i, i / total, cellWidth / 2, cellHeight / 2);
                 c.restore();
               }
             }) };
  }
  // A gradient of a row of colors, `stops` as [share, r, g, b, a] from 0 to 255.
  function gradientOf(stops) {
    return { width: 64, height: 2, clamp: true, pixels: shaded(64, 2, function (u) {
      var k = 1;
      while (k < stops.length - 1 && stops[k][0] < u) k++;
      var a = stops[k - 1], b = stops[k], t = Math.max(0, Math.min(1, (u - a[0]) / ((b[0] - a[0]) || 1)));
      return [1, 2, 3, 4].map(function (i) { return (a[i] + (b[i] - a[i]) * t) / 255; });
    }) };
  }
  // Rays round a point, of lengths and widths of their own: from 0 to 1 at an angle and distance.
  function rays(count, seed, widest, turn, distance, longest) {
    var light = 0;
    for (var k = 0; k < count; k++) {
      var toward = hash(k, 1, seed) * Math.PI * 2, wide = (0.25 + hash(k, 2, seed) * 0.75) * widest, reach = (0.4 + hash(k, 3, seed) * 0.6) * (longest || 1);
      var off = Math.atan2(Math.sin(turn - toward), Math.cos(turn - toward));
      light += Math.exp(-Math.pow(off / wide, 2)) * Math.max(0, 1 - distance / reach) * (0.5 + 0.5 * hash(k, 4, seed));
    }
    return Math.min(1, light);
  }
  // Puffs of smoke, cloud or fog in a cell, curling as the sheet goes on.
  function puff(x, y, share, seed, rounded) {
    var r = Math.sqrt(x * x + y * y);
    var curl = fbm(x * 1.6 + Math.cos(share * 6.283) * 0.5, y * 1.6 + Math.sin(share * 6.283) * 0.5 - share * 0.7, 5, seed);
    return Math.max(0, curl * 1.7 - 0.5) * (1 - smooth01(rounded || 0.3, 0.95, r));
  }
  // A cloud of round billows, as Wallpaper Engine's smoke2 is: a big one in the middle and a
  // ring of smaller ones about it, each with a ragged rim, turning a little as the sheet goes
  // on. Gives [shade, opacity]: the creases between billows darker. Its opacity ring by ring
  // follows the measured one (0.96 to half the radius, 0.49 at three quarters, 0.15 at the
  // rim; a mean of 0.46).
  function billows(x, y, share, seed) {
    var turn = share * 0.9;
    function billow(cx, cy, radius, k) {
      var rag = fbm(x * 4.5 + k * 5.7, y * 4.5 - share * 1.3 + k * 2.3, 4, seed + k) - 0.5;
      return 1 - smooth01(0.55, 1.0, Math.hypot(x - cx, y - cy) / radius + rag * 0.8);
    }
    var opacity = billow(0, 0, 0.64, 0), crease = 0;
    for (var k = 1; k <= 10; k++) {
      var toward = (k / 10) * Math.PI * 2 + (hash(k, 1, seed) - 0.5) * 1.2 + turn;
      var far = 0.34 + hash(k, 2, seed) * 0.32, radius = 0.2 + hash(k, 3, seed) * 0.24;
      var one = billow(Math.cos(toward) * far, Math.sin(toward) * far, radius, k);
      crease = Math.max(crease, Math.min(opacity, one));
      opacity = Math.max(opacity, one);
    }
    return [1 - 0.18 * crease * (1 - opacity * 0.5), Math.min(0.97, opacity)];
  }
  // Torn wisps, as Wallpaper Engine's fog2 is: ridges of a curling noise, kept within a
  // wreath whose opacity ring by ring is the measured one (thickest a third of the way out,
  // a mean of 0.17).
  var FOG2_RINGS = [0.52, 0.62, 0.72, 0.64, 0.44, 0.26, 0.14, 0.08, 0.05, 0.01];
  function wisps(x, y, share, seed) {
    var at = Math.sqrt(x * x + y * y) * 10 - 0.5, ring;
    if (at <= 0) ring = FOG2_RINGS[0];
    else if (at >= 9) ring = FOG2_RINGS[9] * Math.max(0, 1 - (at - 9) * 2);
    else ring = FOG2_RINGS[Math.floor(at)] + (FOG2_RINGS[Math.floor(at) + 1] - FOG2_RINGS[Math.floor(at)]) * (at - Math.floor(at));
    var n = fbm(x * 2.6 + Math.cos(share * 6.283) * 0.6, y * 2.6 + Math.sin(share * 6.283) * 0.6, 5, seed);
    var ridge = 1 - Math.abs(n * 2 - 1);
    return Math.min(1, ring * 1.37 * Math.pow(ridge, 1.6));
  }
  // A flame in a cell, licking up as the sheet goes on.
  function flame(x, y, share, seed, narrow) {
    var rise = (1 - y) / 2;
    var flicker = fbm(x * 2, y * 1.5 + share * 9, 3, seed) - 0.5;
    var wide = (narrow || 0.6) * Math.pow(Math.max(0, 1 - rise), 0.8) * (rise < 0.12 ? rise / 0.12 : 1);
    var across = Math.abs(x + flicker * 0.5 * rise);
    // Torn into tongues, thinner and fainter as they rise.
    var torn = smooth01(0.35, 0.75, fbm(x * 3 + 7, y * 2.5 + share * 9, 4, seed + 1));
    return (1 - smooth01(wide * 0.3, wide, across)) * (1 - smooth01(0.6, 1, rise)) * (0.25 + 0.75 * torn) * (1 - rise * 0.5);
  }
  // A jagged bolt from one side of a cell to the other, as lightning is.
  function boltAt(x, y, index, seed, across) {
    var path = 0, amplitude = 0.5, frequency = 2;
    for (var o = 0; o < 4; o++) {
      path += (smoothNoise(x * frequency * 3 + index * 7.3, index * 3.1 + o, 4096, seed + o) - 0.5) * amplitude;
      amplitude *= 0.5;
      frequency *= 2;
    }
    var off = Math.abs(y - path * 1.2);
    var core = Math.exp(-Math.pow(off / (across || 0.03), 2)), glow = 0.35 * Math.exp(-off * 8);
    return Math.max(core, glow) * (1 - smooth01(0.85, 1, Math.abs(x))) * (hash(index, 9, seed) > 0.15 ? 1 : 0.4);
  }
  // A map of how a band down the picture faces, as a stream of water or a hose does: across it
  // as a tube, `edge(v)` giving its half width and middle at each height.
  function tubeFacing(width, height, edge) {
    return { width: width, height: height, clamp: false, pixels: facingMap(width, height, function (u, v) {
      var e = edge(v), off = (u - e[0]) / e[1];
      return Math.abs(off) < 1 ? [off * 0.9, 0, 1 - smooth01(0.85, 1, Math.abs(off))] : null;
    }) };
  }
  function bandMask(width, height, edge, inner) {
    return { width: width, height: height, clamp: false, pixels: whiteShape(width, height, function (u, v) {
      var e = edge(v), off = Math.abs(u - e[0]) / e[1];
      return (1 - smooth01(0.85, 1, off)) * (inner ? inner(u, v, off) : 1);
    }) };
  }
  function wavyBand(seed, middle, half, waves) {
    return function (v) {
      return [middle + (smoothNoise(v * waves, 0, 4096, seed) - 0.5) * half * 0.8, half * (0.7 + 0.6 * smoothNoise(v * waves * 1.7, 3, 4096, seed + 1))];
    };
  }
  // A leaf in a sheet: its kind of outline, its colors, turned as the sheet goes on.
  function leafOf(c, index, share, halfWidth, halfHeight, kind, palette) {
    var tall = Math.min(halfWidth, halfHeight) * 0.85, color = palette[Math.floor(hash(index, 3, 83) * palette.length)];
    c.rotate(share * Math.PI * 2 + hash(index, 1, 83) * 0.6);
    c.scale(1, 0.4 + 0.6 * Math.abs(Math.cos(share * Math.PI * 3)));
    c.fillStyle = 'rgba(' + color[0] + ',' + color[1] + ',' + color[2] + ',1)';
    c.beginPath();
    if (kind === 'maple') {
      var lobes = [[0, -1], [0.55, -0.55], [0.95, -0.15], [0.5, 0.15], [0.62, 0.55], [0.12, 0.35], [0, 0.95], [-0.12, 0.35], [-0.62, 0.55], [-0.5, 0.15], [-0.95, -0.15], [-0.55, -0.55]];
      lobes.forEach(function (p, i) {
        var dent = i % 2 ? 0.75 : 1;
        if (i === 0) c.moveTo(p[0] * tall * dent, p[1] * tall * dent); else c.lineTo(p[0] * tall * dent, p[1] * tall * dent);
      });
      c.closePath();
    } else if (kind === 'oak') {
      c.moveTo(0, -tall);
      for (var k = 0; k <= 8; k++) {
        var t = k / 8, side = k % 2 ? 0.5 : 0.32;
        c.quadraticCurveTo(tall * side * 1.3, -tall + t * tall * 2 - tall * 0.12, tall * side * 0.8 * Math.sin(t * Math.PI) + 2, -tall + t * tall * 2);
      }
      for (var k2 = 8; k2 >= 0; k2--) {
        var t2 = k2 / 8, side2 = k2 % 2 ? 0.5 : 0.32;
        c.quadraticCurveTo(-tall * side2 * 1.3, -tall + t2 * tall * 2 + tall * 0.12, -tall * side2 * 0.8 * Math.sin(t2 * Math.PI) - 2, -tall + t2 * tall * 2);
      }
    } else {
      var wide = kind === 'narrow' ? 0.28 : 0.5;
      c.moveTo(0, -tall);
      c.quadraticCurveTo(tall * wide * 1.4, -tall * 0.1, 0, tall);
      c.quadraticCurveTo(-tall * wide * 1.4, -tall * 0.1, 0, -tall);
    }
    c.fill();
    c.strokeStyle = 'rgba(' + Math.floor(color[0] * 0.7) + ',' + Math.floor(color[1] * 0.7) + ',' + Math.floor(color[2] * 0.7) + ',1)';
    c.lineWidth = 1.2;
    c.beginPath();
    c.moveTo(0, -tall * 0.85);
    c.lineTo(0, tall * 1.05);
    c.stroke();
  }
  function bubbleShade(x, y, tint) {
    var r = Math.sqrt(x * x + y * y);
    if (r > 0.92) return [0, 0, 0, 0];
    var rim = Math.pow(r / 0.92, 6), shine = Math.exp(-(Math.pow(x + 0.35, 2) + Math.pow(y + 0.38, 2)) / 0.02);
    var c = tint ? [0.8 + 0.2 * Math.sin(x * 6 + 1), 0.8 + 0.2 * Math.sin(y * 5 + 2), 1, 1] : [1, 1, 1, 1];
    c[3] = Math.min(1, 0.08 + rim * 0.8 + shine) * (1 - smooth01(0.88, 0.92, r));
    return c;
  }
  function runeRing(c, middle, reach, count, seed, line) {
    c.lineWidth = line;
    for (var rune = 0; rune < count; rune++) {
      c.save();
      c.translate(middle, middle);
      c.rotate(rune / count * Math.PI * 2);
      c.translate(0, -reach);
      c.beginPath();
      for (var stroke = 0; stroke < 3; stroke++) {
        c.moveTo((hash(rune, stroke * 4, seed) - 0.5) * 22, (hash(rune, stroke * 4 + 1, seed) - 0.5) * 22);
        c.lineTo((hash(rune, stroke * 4 + 2, seed) - 0.5) * 22, (hash(rune, stroke * 4 + 3, seed) - 0.5) * 22);
      }
      c.stroke();
      c.restore();
    }
  }
  function glowingLines(c) {
    c.strokeStyle = 'rgba(255,255,255,1)';
    c.fillStyle = 'rgba(255,255,255,1)';
    c.shadowColor = 'rgba(255,255,255,0.9)';
    c.shadowBlur = 6;
  }

  function builtinPicture2(name) {
    var aa = 0.012;
    var shapes = {
      'particle/shape/arrow_sharp': function (x, y) { return filledBy(polygonDistance(x, y, [[-0.65, 0.12], [0, -0.42], [0.65, 0.12], [0.52, 0.18], [0, -0.24], [-0.52, 0.18]]), aa); },
      'particle/shape/circle_aura': function (x, y) { var r = Math.hypot(x, y); return (1 - smooth01(0.6, 0.72, r)) * (0.5 + 0.5 * fbm(x * 3 + 5, y * 3 + 5, 4, 7)); },
      'particle/shape/circle_flame': function (x, y) {
        var r = Math.hypot(x, y), turn = Math.atan2(y, x), n = smoothNoise(turn * 4 + 20, 0, 4096, 11), w = 0.025 + 0.07 * n * n;
        return Math.exp(-Math.pow((r - 0.72 - (n - 0.5) * 0.08) / w, 2)) * smooth01(0.2, 0.45, smoothNoise(turn * 6 + 40, 1, 4096, 13)); },
      'particle/shape/circle_halo': function (x, y) { var r = Math.hypot(x, y); return 0.28 * Math.exp(-Math.pow((r - 0.86) / 0.1, 2)) + (r < 0.86 ? 0.06 * r : 0); },
      'particle/shape/circle_halo_mid': function (x, y) { var r = Math.hypot(x, y); return Math.max(Math.exp(-Math.pow((r - 0.8) / 0.03, 2)), r < 0.8 ? 0.45 * Math.exp(-(0.8 - r) / 0.12) : 0); },
      'particle/shape/circle_invert': function (x, y) { var r = Math.hypot(x, y); return r < 0.45 ? smooth01(0.44, 0.46, r) : Math.exp(-(r - 0.45) * 4.5) * (1 - smooth01(0.9, 1, r)); },
      'particle/shape/circle_outline': function (x, y) { return Math.exp(-Math.pow((Math.hypot(x, y) - 0.72) / 0.018, 2)); },
      'particle/shape/circle_outline_2': function (x, y) { var r = Math.hypot(x, y); return Math.max(Math.exp(-Math.pow((r - 0.72) / 0.024, 2)), 0.2 * Math.exp(-Math.pow((r - 0.72) / 0.07, 2))); },
      'particle/shape/circle_outline_glow': function (x, y) { var r = Math.hypot(x, y); return Math.max(Math.exp(-Math.pow((r - 0.82) / 0.015, 2)), 0.35 * Math.exp(-Math.pow((r - 0.82) / 0.08, 2))); },
      'particle/shape/circle_ripple': function (x, y) { var r = Math.hypot(x, y), turn = Math.atan2(y, x); return Math.exp(-Math.pow((r - 0.5) / 0.13, 2)) * (0.5 - 0.5 * Math.cos(turn)) ; },
      'particle/shape/circle_wind': function (x, y) {
        // A pinwheel: four blades swept round, a little ragged at their tips.
        var r = Math.hypot(x, y), turn = Math.atan2(y, x) - r * 2.2, blade = Math.pow(Math.max(0, Math.cos(turn * 4)), 0.5);
        return filledBy(r - (0.45 + 0.2 * blade), 0.05) * (0.85 + 0.15 * fbm(x * 4, y * 4, 3, 113)); },
      'particle/shape/circle_wind_line': function (x, y) {
        var r = Math.hypot(x, y), turn = Math.atan2(y, x), light = 0;
        [0.7, 0.76, 0.83].forEach(function (at, k) { light += Math.exp(-Math.pow((r - at - 0.03 * Math.sin(turn * 2 + k)) / 0.008, 2)) * Math.max(0, Math.sin(turn * 2 + k * 2)); });
        return Math.min(1, light); },
      'particle/shape/crescent': function (x, y) { var r = Math.hypot(x, y), w = 0.02 + 0.045 * (1 - y / Math.max(r, 0.001)) / 2; return Math.exp(-Math.pow((r - 0.7) / w, 2)); },
      'particle/shape/crescent_mid': function (x, y) { return filledBy(Math.hypot(x, y) - 0.62, 0.03) * (1 - filledBy(Math.hypot(x - 0.16, y + 0.12) - 0.58, 0.05)); },
      'particle/shape/diamond_glow': function (x, y) { return glowBy(polygonDistance(x, y, regularCorners(4, 0.45)), 6); },
      'particle/shape/diamond_invert': function (x, y) { var d = polygonDistance(x, y, regularCorners(4, 0.45)); return d < 0 ? 0 : Math.exp(-d * 5) * (1 - smooth01(0.9, 1, Math.max(Math.abs(x), Math.abs(y)))); },
      'particle/shape/embers_group': function (x, y) {
        var light = 0;
        for (var k = 0; k < 70; k++) {
          var angle = hash(k, 1, 89) * 6.283, reach = Math.pow(hash(k, 2, 89), 0.7) * 0.8, size = 0.006 + hash(k, 3, 89) * 0.016;
          var d = Math.hypot(x - Math.cos(angle) * reach, y - Math.sin(angle) * reach);
          if (d < size * 3) light = Math.max(light, Math.exp(-Math.pow(d / size, 2)));
        }
        return light; },
      'particle/shape/glass': function (x, y) { var d = polygonDistance(x, y, [[0.42, -0.78], [-0.52, 0.02], [0.12, 0.82]]); return Math.max(filledBy(d, aa), 0.4 * glowBy(d, 14)); },
      'particle/shape/glass_shine': function (x, y) {
        var d = polygonDistance(x, y, [[0.42, -0.78], [-0.52, 0.02], [0.12, 0.82]]), edge = Math.exp(-Math.pow(d / 0.015, 2));
        var stripe = d < 0 ? Math.max(0, Math.sin((x + y * 0.4) * 14)) * 0.8 * smooth01(0.6, 1, Math.max(0, Math.sin((x + y * 0.4) * 14))) : 0;
        return Math.max(edge, stripe); },
      'particle/shape/impact': function (x, y) {
        var r = Math.hypot(x, y), turn = Math.atan2(y, x), spike = Math.pow(Math.max(0, smoothNoise(turn * 9 + 30, 0, 4096, 97)), 5);
        return Math.max(Math.exp(-Math.pow((r - 0.62) / 0.025, 2)), spike * Math.exp(-Math.pow((r - 0.62) / (0.04 + spike * 0.12), 2))); },
      'particle/shape/shockwave': function (x, y) { var r = Math.hypot(x, y); return rays(90, 101, 0.03, Math.atan2(y, x), Math.max(0, r - 0.35) * 1.6, 1) * smooth01(0.3, 0.5, r); },
      'particle/shape/shockwave_center': function (x, y) { var r = Math.hypot(x, y); return Math.max(Math.min(1, rays(60, 103, 0.09, Math.atan2(y, x), r, 0.9) * 1.6), Math.exp(-Math.pow(r / 0.22, 2))); },
      'particle/shape/shockwave_fill': function (x, y) { var r = Math.hypot(x, y), turn = Math.atan2(y, x); var edge = 0.55 + 0.18 * rays(24, 107, 0.08, turn, 0, 1); return Math.max(filledBy(r - edge, 0.04), 0.3 * glowBy(r - edge, 10)); },
      'particle/shape/shockwave_mid': function (x, y) { var r = Math.hypot(x, y); return r < 0.6 ? 0 : rays(50, 109, 0.04, Math.atan2(y, x), (r - 0.6) * 2.5, 1) * smooth01(0.58, 0.64, r); },
      'particle/shape/square_inner': function (x, y) { var m = Math.max(Math.abs(x), Math.abs(y)); return smooth01(0.1, 0.95, m) * (1 - smooth01(0.95, 0.99, m)); },
      'particle/shape/square_invert': function (x, y) { var d = Math.max(Math.abs(x), Math.abs(y)) - 0.42; return d < 0 ? 0 : Math.exp(-d * 6); },
      'particle/shape/star_16': function (x, y) {
        var r = Math.hypot(x, y), turn = Math.atan2(y, x), arms = Math.pow(Math.abs(Math.cos(turn * 8)), 40) * Math.max(0, 1 - r / (Math.abs(Math.cos(turn * 4)) > 0.7 ? 0.95 : 0.7));
        return Math.max(Math.exp(-Math.pow(r / 0.14, 2)), arms); },
      'particle/shape/star_4': function (x, y) { return Math.max(Math.exp(-Math.abs(y) * 140) * Math.pow(Math.max(0, 1 - Math.abs(x)), 2), Math.exp(-Math.abs(x) * 140) * Math.pow(Math.max(0, 1 - Math.abs(y)), 2), Math.exp(-Math.pow(Math.hypot(x, y) / 0.03, 2))); },
      'particle/shape/star_4_thick': function (x, y) { return filledBy(polygonDistance(x, y, starCorners(4, 0.9, 0.12)), aa); },
      'particle/shape/star_4_thick_glow': function (x, y) { var d = polygonDistance(x, y, starCorners(4, 0.8, 0.1)); return Math.max(filledBy(d, aa * 2), 0.35 * glowBy(d, 6)); },
      'particle/shape/star_8': function (x, y) { var r = Math.hypot(x, y), turn = Math.atan2(y, x); var arms = Math.pow(Math.abs(Math.cos(turn * 4)), 60) * Math.max(0, 1 - r / (Math.abs(Math.cos(turn * 2)) > 0.7 ? 0.9 : 0.55)); return Math.max(filledBy(r - 0.08, 0.02), arms); },
      'particle/shape/star_diamond': function (x, y) { return filledBy(polygonDistance(x, y, starCorners(2, 0.36, 0.1)), aa); },
      'particle/shape/star_diamond_glow': function (x, y) { var d = polygonDistance(x, y, starCorners(2, 0.75, 0.12)); return Math.max(filledBy(d, aa), 0.35 * glowBy(d, 10)); },
      'particle/shape/star_thick_glow': function (x, y) { var d = polygonDistance(x, y, starCorners(4, 0.55, 0.28)); return Math.max(filledBy(d, aa * 2), 0.4 * glowBy(d, 7)); },
      'particle/shape/strings': function (x, y) {
        var light = 0;
        [[-0.38, 0.3], [-0.12, 0.6], [0.02, 0.85], [0.28, 0.35]].forEach(function (s) { var wide = 0.025 * Math.max(0, 1 - Math.abs(y) / s[1]); light = Math.max(light, wide > 0 ? 1 - smooth01(wide * 0.5, wide, Math.abs(x - s[0])) : 0); });
        return light; },
      'particle/shape/triangle_glow': function (x, y) { return 1 - smooth01(-0.25, 0.18, polygonDistance(x, y, regularCorners(3, 0.6))); },
      'particle/shape/triangle_inner': function (x, y) { var d = polygonDistance(x, y, regularCorners(3, 0.9)); return d > 0 ? 1 - smooth01(0, aa * 2, d) : smooth01(-0.45, 0, d); },
      'particle/shape/triangle_invert': function (x, y) { var d = polygonDistance(x, y, regularCorners(3, 0.55)); return d < 0 ? 0 : Math.exp(-d * 5); },
      'particle/star': function (x, y) { var r = Math.hypot(x, y); return Math.max(filledBy(r - 0.22, 0.1), Math.min(1, rays(10, 127, 0.16, Math.atan2(y, x), r, 0.95) * 1.5)); },
      'particle/swirl_0': function (x, y) { var r = Math.hypot(x, y), turn = Math.atan2(y, x); return Math.exp(-Math.pow((r - 0.55 - 0.08 * Math.sin(turn)) / 0.12, 2)) * (0.5 + 0.5 * Math.sin(turn + r * 6)); },
      'particle/misc/star_0': function (x, y) { return filledBy(polygonDistance(x, y, starCorners(5, 0.92, 0.38)), aa); },
      'particle/misc/arrow_0': null,
      'particle/magic/glyph_3': null
    };
    var sizes = { 'particle/star': 64, 'particle/swirl_0': 256, 'particle/misc/star_0': 128, 'particle/shape/star_4_thick_glow': 128 };
    if (shapes[name]) return shapeOf(sizes[name] || 256, shapes[name]);

    // Measured on Wallpaper Engine's own sheets: how opaque ring by ring, and how light where
    // they show (luminance where opacity passes 0.3): smoke2 0.95, smoke2light 0.54, fog2
    // 0.5. 3598808038's calm fog, of smoke2, had been a third as thick.
    if (name === 'particle/smoke/smoke2' || name === 'particle/smoke/smoke2light') {
      // The same sheet, only grey.
      var grey = name === 'particle/smoke/smoke2' ? 0.97 : 0.55, seedOf = 137;
      return sheetOf(8, 8, 64, 64, 0.015625, function (i, x, y, share) {
        var b = billows(x, y, share, seedOf);
        return [grey * b[0], b[1]];
      });
    }
    if (name === 'particle/fog/fog2') {
      return sheetOf(8, 8, 64, 64, 0.015625, function (i, x, y, share) { return [0.5, wisps(x, y, share, 157)]; });
    }
    var smoke = { 'particle/smoke/smoke1': [8, 8, 64, 0.015625, 131, false], 'particle/smoke/smoke3': [8, 8, 64, 0, 149, false],
                  'particle/smoke/smoke4': [8, 4, 64, 0.03125, 151, true] };
    if (smoke[name]) {
      var s = smoke[name];
      return sheetOf(s[0], s[1], s[2], s[2], s[3], function (i, x, y, share) {
        var a = puff(x, y, share, s[4]);
        return [s[5] ? 0.6 + 0.4 * (1 - (y + 1) / 2) : 1, a];
      });
    }
    switch (name) {
      // Fire, light, lightning, explosions.
      case 'particle/fire/fire1': return sheetOf(8, 8, 64, 64, 0, function (i, x, y, share) { return [1, flame(x, y, share, 163, 0.6)]; });
      case 'particle/fire/fire3': return sheetOf(16, 8, 32, 64, 0, function (i, x, y, share) { return [1, flame(x * 0.5, y, share, 167, 0.32)]; });
      case 'particle/explosion/explosion1':
        return sheetOf(12, 6, 42.667, 42.667, 0.0138889, function (i, x, y, share) {
          var r = Math.hypot(x, y), grow = 0.7 + share * 0.3, n = fbm(x * 2.5 + share * 3, y * 2.5, 4, 173);
          var a = (1 - smooth01(grow * 0.6, grow, r - (n - 0.5) * 0.5)) * (1 - smooth01(0.75, 1, share)) * (0.7 + 0.3 * n);
          return [Math.max(0.25, 1 - share * 1.2) * (0.7 + 0.3 * n), a];
        }, 72);
      case 'particle/lightning/lightning1': return sheetOf(8, 8, 64, 32, 0, function (i, x, y) { return [1, boltAt(x, y, i, 179, 0.04)]; });
      case 'particle/lightning/lightning2': return sheetOf(4, 8, 128, 32, 0, function (i, x, y) { return [1, boltAt(x, y, i, 181, 0.05)]; });
      case 'particle/lightning/lightning3': return sheetOf(5, 10, 102.4, 51.2, 0.02, function (i, x, y) { return [1, boltAt(x, y, i, 191, 0.03)]; });
      case 'particle/light/light_shafts_1':
        return { width: 256, height: 512, clamp: true, pixels: whiteShape(256, 512, function (u, v) {
          return rays(9, 193, 0.035, Math.atan2(u - 0.5, v + 0.05), 0, 1) * 0.6 * Math.pow(1 - v, 1.2) * smooth01(0, 0.05, v); }) };
      case 'particle/light/light_shafts_2':
        return { width: 256, height: 256, clamp: true, pixels: whiteShape(256, 256, function (u, v) {
          var x = u * 2 - 1, y = v * 2 - 1, r = Math.hypot(x, y); return Math.min(1, rays(22, 197, 0.06, Math.atan2(y, x), r, 1) + 0.6 * Math.exp(-Math.pow(r / 0.15, 2))); }) };
      case 'particle/light/light_shafts_3':
        return { width: 128, height: 512, clamp: true, pixels: whiteShape(128, 512, function (u, v) {
          return rays(5, 199, 0.012, Math.atan2(u - 0.5, v + 0.02), 0, 1) * Math.pow(1 - v, 1.1) * smooth01(0, 0.04, v); }) };
      case 'particle/light/light_shafts_4':
        return { width: 256, height: 256, clamp: true, pixels: whiteShape(256, 256, function (u, v) {
          return Math.min(1, rays(30, 211, 0.08, Math.atan2(u - 0.5, v + 0.1), 0, 1) * 0.8) * Math.pow(1 - v, 0.8) * smooth01(0, 0.08, v); }) };
      case 'particle/beam/beam_0':
        return { width: 32, height: 4, clamp: true, pixels: whiteShape(32, 4, function (u, v) { return Math.min(1, Math.min(u, 1 - u) * 6) * (1 - Math.abs(v - 0.5) * 1.2); }) };
      case 'particle/beam/beam_1':
        return { width: 32, height: 128, clamp: true, pixels: whiteShape(32, 128, function (u, v) { return Math.exp(-Math.pow((u - 0.5) / 0.22, 2)) * Math.min(1, Math.min(v, 1 - v) * 4); }) };
      case 'particle/beam/beam_2_fade':
        // Measured on Wallpaper Engine's own (32×128, luminance and alpha): a core two texels
        // wide, a faint glow either side fading straight to nothing at the edges, all of it
        // brightest halfway along and fading to both ends.
        return { width: 32, height: 128, clamp: true, pixels: whiteShape(32, 128, function (u, v) {
          var a = Math.abs(u - 0.5);
          var across = a < 0.031 ? 1 : 0.172 * Math.max(0, 1 - (a - 0.031) / 0.45);
          return across * Math.exp(-Math.pow((v - 0.51) / 0.25, 2)); }) };
      case 'particle/beam/beam_flower_0':
        return bandMask(128, 512, function () { return [0.5, 0.42]; }, function (u, v) { return smooth01(0.3, 0.7, fbm(u * 6, v * 24, 4, 223)); });
      case 'particle/beam/beam_flower_0_normal': return tubeFacing(128, 512, function () { return [0.5, 0.42]; });
      case 'particle/beam/hose_0_normal': return tubeFacing(256, 256, function () { return [0.5, 0.5]; });
      case 'particle/beam/hose_1': return bandMask(128, 256, wavyBand(227, 0.5, 0.3, 3));
      case 'particle/beam/hose_1_normal': return tubeFacing(128, 256, wavyBand(227, 0.5, 0.3, 3));
      case 'particle/beam/hose_2': return bandMask(256, 1024, wavyBand(229, 0.5, 0.18, 6));
      case 'particle/beam/hose_2_normal': return tubeFacing(256, 1024, wavyBand(229, 0.5, 0.18, 6));
      case 'particle/beam/hose_3':
      case 'particle/beam/hose_4':
      case 'particle/beam/hose_4_bright':
        var brighter = name === 'particle/beam/hose_4_bright';
        return bandMask(256, 256, wavyBand(233, 0.5, 0.38, 2), function (u, v, off) { return (brighter ? 0.8 : 0.5) + (brighter ? 0.2 : 0.5) * fbm(u * 3, v * 3, 4, 239) * (1 - off * 0.5); });
      case 'particle/beam/hose_4_normal': return tubeFacing(256, 256, wavyBand(233, 0.5, 0.38, 2));
      // Normal maps.
      case 'particle/halo_normal_blunt':
      case 'particle/halo_normal_sharp':
        var sharp = name === 'particle/halo_normal_sharp';
        return { width: 64, height: 64, clamp: true, pixels: facingMap(64, 64, function (u, v) {
          var x = u * 2 - 1, y = 1 - v * 2, r = Math.hypot(x, y); if (r > 0.98) return null;
          var slope = sharp ? 0.9 : Math.pow(r, 2.5) * 0.95; return [x / Math.max(r, 0.001) * slope, y / Math.max(r, 0.001) * slope, 1 - smooth01(0.9, 0.98, r)]; }) };
      case 'particle/normal_pinch':
        return { width: 64, height: 64, clamp: true, pixels: facingMap(64, 64, function (u, v) {
          var x = u * 2 - 1, y = 1 - v * 2, r = Math.hypot(x, y); if (r > 0.98) return null;
          var by = -Math.sin(Math.PI * r) * 0.8; return [x / Math.max(r, 0.001) * by, y / Math.max(r, 0.001) * by, 1 - smooth01(0.8, 0.98, r)]; }) };
      case 'particle/normal_ring':
      case 'particle/normal_ring_rotate':
        var turning = name === 'particle/normal_ring_rotate';
        return { width: 64, height: 64, clamp: true, pixels: facingMap(64, 64, function (u, v) {
          var x = u * 2 - 1, y = 1 - v * 2, r = Math.hypot(x, y); if (r < 0.5 || r > 0.95) return null;
          var slope = Math.cos(Math.PI * (r - 0.5) / 0.45) * 0.9, ux = x / r, uy = y / r;
          return turning ? [(-uy * 0.8 + ux * 0.3) * slope, (ux * 0.8 + uy * 0.3) * slope, Math.sin(Math.PI * (r - 0.5) / 0.45)] : [ux * slope, uy * slope, Math.sin(Math.PI * (r - 0.5) / 0.45)]; }) };
      case 'particle/normal_splash':
        return { width: 128, height: 128, clamp: true, pixels: facingMap(128, 128, function (u, v) {
          var x = u * 2 - 1, y = 1 - v * 2, r = Math.hypot(x, y); if (r > 0.97) return null;
          var slope = Math.sin(r * 22) * 0.6 * (1 - r); return [x / Math.max(r, 0.001) * slope, y / Math.max(r, 0.001) * slope, 1 - smooth01(0.85, 0.97, r)]; }) };
      case 'particle/normal_swirl':
        return { width: 256, height: 256, clamp: true, pixels: facingMap(256, 256, function (u, v) {
          var x = u * 2 - 1, y = 1 - v * 2, r = Math.hypot(x, y); if (r > 0.98) return null;
          var turn = Math.atan2(y, x) + r * 6, slope = Math.sin(r * Math.PI) * 0.7; return [Math.cos(turn) * slope, Math.sin(turn) * slope, 1 - smooth01(0.85, 0.98, r)]; }) };
      case 'particle/drop_normal_lighting':
        return builtinPicture('particle/drop_normal');
      case 'particle/bubbles/bubble1normal':
        return { width: 512, height: 512, clamp: false, pixels: facingMap(512, 512, function (u, v, px, py) {
          var x = ((px % 85.334) / 85.334) * 2 - 1, y = 1 - ((py % 102.4) / 102.4) * 2, r = Math.hypot(x, y * 1.2); if (r > 0.92) return null;
          return [x / 0.92, y * 1.2 / 0.92, 1 - smooth01(0.86, 0.92, r)]; }) };
      case 'particle/smoke/smoke2normal':
        return { width: 512, height: 512, clamp: false, pixels: facingMap(512, 512, function (u, v) {
          var e = 0.004, h = function (a, b) { return fbm(a * 8, b * 8, 4, 241); };
          return [(h(u - e, v) - h(u + e, v)) * 8, (h(u, v + e) - h(u, v - e)) * 8, 1]; }) };
      // Bubbles, water.
      case 'particle/bubbles/bubble1': return sheetOf(6, 5, 85.334, 102.4, 1 / 30, function (i, x, y) { return bubbleShade(x, y * 1.2, false); }, 30, true);
      case 'particle/bubbles/bubble2': return sheetOf(5, 6, 102.4, 85.334, 1 / 30, function (i, x, y) { return bubbleShade(x * 1.2, y, true); }, 30, true);
      case 'particle/bubbles/bubble3':
        return sheetOf(8, 8, 64, 64, 0.015625, function (i, x, y, share) {
          var r = Math.hypot(x, y), size = 0.2 + share * 0.5, popped = share > 0.85;
          return [1, popped ? Math.exp(-Math.pow((r - size) / 0.05, 2)) * (1 - share) * 4 : Math.exp(-Math.pow((r - size) / 0.04, 2)) + 0.6 * Math.exp(-(Math.pow(x + size * 0.4, 2) + Math.pow(y + size * 0.4, 2)) / 0.004)];
        });
      case 'particle/water/rain_drops_0':
        return sheetOf(8, 2, 32, 128, 0.125, function (i, x, y) {
          var wide = (y < -0.7 ? Math.sqrt(Math.max(0, 0.09 - Math.pow(y + 0.7, 2))) / 0.3 : Math.pow(Math.max(0, 1 - (y + 0.7) / 1.7), 1.3)) * 0.6;
          var off = x + 0.15 * Math.sin(y * 4 + i);
          return Math.abs(off) < wide ? [off / Math.max(wide, 0.001) * 0.5 + 0.5, 0.5, 1, 1 - smooth01(wide * 0.7, wide, Math.abs(off))] : [0.5, 0.5, 1, 0];
        }, 16, true);
      case 'particle/water/ripple_group':
        return sheetOf(4, 4, 64, 64, 0.0625, function (i, x, y, share) {
          var light = 0;
          for (var k = 0; k < 5; k++) {
            var cx = (hash(k, 1, 251) - 0.5) * 1.4, cy = (hash(k, 2, 251) - 0.5) * 1.4, grow = ((share + hash(k, 3, 251)) % 1);
            light = Math.max(light, Math.exp(-Math.pow((Math.hypot(x - cx, y - cy) - grow * 0.35) / 0.04, 2)) * (1 - grow));
          }
          return [1, light];
        });
      case 'particle/water/ripple_single':
        return sheetOf(7, 2, 32, 32, 0.0714286, function (i, x, y, share) { var r = Math.hypot(x, y); return [1, Math.exp(-Math.pow((r - 0.1 - share * 0.8) / 0.07, 2)) * (1 - share * 0.8)]; });
      case 'particle/water/shower_stream_0':
        return { width: 256, height: 256, clamp: true, pixels: whiteShape(256, 256, function (u, v) {
          var column = Math.floor(u * 64), off = (u * 64) % 1; return (hash(column, 1, 257) > 0.4 ? 1 : 0) * Math.exp(-Math.pow((off - 0.5) / 0.15, 2)) * smooth01(0.2, 0.8, smoothNoise(column * 3, v * 6, 4096, 263)); }) };
      case 'particle/water/shower_stream_0_normal':
        return { width: 256, height: 256, clamp: true, pixels: facingMap(256, 256, function (u) { var off = (u * 64) % 1 - 0.5; return [off * 1.6, 0, 1]; }) };
      case 'particle/water/small_splash':
        return sheetOf(2, 2, 128, 128, 0.25, function (i, x, y) { var r = Math.hypot(x, y), turn = Math.atan2(y, x); return [1, 1 - smooth01(0.3, 0.7, r - 0.15 * smoothNoise(turn * 3 + i * 5, 0, 4096, 269))]; });
      case 'particle/water/splash_0':
      case 'particle/water/splash_1':
        var whiteSplash = name === 'particle/water/splash_1';
        return sheetOf(8, 8, 64, 64, 0.015625, function (i, x, y, share) {
          var light = 0;
          for (var k = 0; k < 14; k++) {
            var turn = -Math.PI / 2 + (hash(k, 1, 271) - 0.5) * 2.4, speed = 0.4 + hash(k, 2, 271) * 0.6;
            var px = Math.cos(turn) * speed * share * 1.4, py = Math.sin(turn) * speed * share * 1.4 + share * share * 1.2 + 0.5;
            light = Math.max(light, Math.exp(-(Math.pow(x - px, 2) + Math.pow(y - py, 2)) / (0.004 + 0.004 * hash(k, 3, 271))));
          }
          var a = light * (1 - smooth01(0.7, 1, share));
          return whiteSplash ? [1, 1, 1, a] : [1, a];
        }, 64, whiteSplash);
      case 'particle/water/splash_1_normal':
        return sheetOf(8, 8, 64, 64, 0.015625, function (i, x, y) { return [x * 0.5 + 0.5, -y * 0.5 + 0.5, 1, 1 - smooth01(0.6, 1, Math.hypot(x, y))]; }, 64, true);
      case 'particle/water/splash_9':
      case 'particle/water/splash_10':
        var frames = name === 'particle/water/splash_9' ? 4 : 3;
        return sheetOf(frames, 1, 128, 128, 1 / frames, function (i, x, y) {
          var r = Math.hypot(x, y), turn = Math.atan2(y, x), edge = 0.45 + 0.25 * fbm(Math.cos(turn) * 2 + i * 4, Math.sin(turn) * 2, 3, 277);
          return [1, 1, 1, (1 - smooth01(edge - 0.08, edge, r)) * (0.5 + 0.5 * fbm(x * 3, y * 3 + i, 3, 281))];
        }, frames, true);
      case 'particle/water/splash_2':
      case 'particle/water/splash_3':
      case 'particle/water/splash_4':
      case 'particle/water/splash_6':
      case 'particle/water/splash_7':
      case 'particle/water/splash_8':
        var splashSeed = { 'particle/water/splash_2': 283, 'particle/water/splash_3': 293, 'particle/water/splash_4': 307, 'particle/water/splash_6': 311, 'particle/water/splash_7': 313, 'particle/water/splash_8': 317 }[name];
        var splashSize = /splash_(2|4)$/.test(name) ? 128 : 256, fine = /splash_(3|4)$/.test(name), arms = name === 'particle/water/splash_8';
        return { width: splashSize, height: splashSize, clamp: true, pixels: whiteShape(splashSize, splashSize, function (u, v) {
          var x = u * 2 - 1, y = v * 2 - 1, r = Math.hypot(x, y), turn = Math.atan2(y, x);
          if (fine) return (1 - smooth01(0.4, 0.95, r)) * smooth01(0.55, 0.75, fbm(x * 9, y * 9, 4, splashSeed));
          var edge = arms ? 0.25 + 0.6 * Math.pow(Math.abs(Math.sin(turn * 3 + 0.4)), 4) : 0.45 + 0.35 * fbm(Math.cos(turn) * 2.5, Math.sin(turn) * 2.5, 4, splashSeed);
          return (1 - smooth01(edge - 0.1, edge, r)) * (0.55 + 0.45 * fbm(x * 4, y * 4, 3, splashSeed + 1)); }) };
      case 'particle/water/splash_5':
        return { width: 128, height: 256, clamp: true, pixels: whiteShape(128, 256, function (u, v) {
          var wide = 0.35 * Math.sin(Math.PI * v) * (0.6 + 0.4 * fbm(v * 4, 0, 3, 331)); return (1 - smooth01(wide * 0.5, wide, Math.abs(u - 0.5))) * (0.5 + 0.5 * fbm(u * 6, v * 10, 3, 337)); }) };
      case 'particle/water/sprinkles_0':
        return shapeOf(256, function (x, y) {
          var light = 0;
          for (var k = 0; k < 160; k++) {
            var angle = hash(k, 1, 347) * 6.283, reach = Math.sqrt(hash(k, 2, 347)) * 0.8, size = 0.01 + hash(k, 3, 347) * 0.02;
            var d = Math.hypot(x - Math.cos(angle) * reach, y - Math.sin(angle) * reach);
            if (d < size * 3) light = Math.max(light, Math.exp(-Math.pow(d / size, 2)) * (0.4 + 0.6 * hash(k, 4, 347)));
          }
          return light; });
      // Nature.
      case 'particle/nature/leaves1': return drawnSheet(6, 5, 85.334, 102.4, 1 / 30, function (c, i, share, hw, hh) { leafOf(c, i, share, hw, hh, 'maple', [[214, 64, 40], [232, 92, 52], [196, 48, 36]]); }, 30);
      case 'particle/nature/leaves2': return drawnSheet(6, 5, 85.334, 102.4, 1 / 30, function (c, i, share, hw, hh) { leafOf(c, i, share, hw, hh, 'narrow', [[222, 88, 70], [204, 70, 60], [236, 120, 96]]); }, 30);
      case 'particle/nature/leaves3': return drawnSheet(6, 5, 85.334, 102.4, 1 / 30, function (c, i, share, hw, hh) { leafOf(c, i, share, hw, hh, 'maple', [[236, 168, 40], [220, 140, 30], [244, 190, 60]]); }, 30);
      case 'particle/nature/leaves4': return drawnSheet(6, 5, 85.334, 102.4, 1 / 30, function (c, i, share, hw, hh) { leafOf(c, i, share, hw, hh, 'maple', [[240, 176, 48], [228, 150, 36], [248, 200, 80]]); }, 30);
      case 'particle/nature/leaves5': return drawnSheet(6, 5, 85.334, 51.2, 1 / 30, function (c, i, share, hw, hh) { leafOf(c, i, share, hw, hh, 'broad', [[216, 96, 76], [200, 80, 64], [228, 116, 92]]); }, 30);
      case 'particle/nature/leaves6': return drawnSheet(6, 5, 85.334, 51.2, 1 / 30, function (c, i, share, hw, hh) { leafOf(c, i, share, hw, hh, 'broad', [[196, 92, 72], [180, 76, 60], [210, 110, 84]]); }, 30);
      case 'particle/nature/leaves9': return drawnSheet(6, 5, 85.334, 102.4, 1 / 30, function (c, i, share, hw, hh) { leafOf(c, i, share, hw, hh, 'oak', [[176, 140, 52], [156, 120, 40], [196, 160, 70]]); }, 30);
      case 'particle/nature/leaves10': return drawnSheet(6, 5, 85.334, 51.2, 1 / 30, function (c, i, share, hw, hh) { leafOf(c, i, share, hw, hh, 'oak', [[214, 150, 52], [196, 128, 40], [228, 170, 70]]); }, 30);
      case 'particle/nature/rain1':
        // Many faint threads of rain a pixel wide, as Wallpaper Engine's own sheet measures:
        // about thirty across a row of a frame, most 0.08 bright and a tenth over 0.2, 0.006 on
        // the whole; each about a fifth of the frame long, scattered evenly up and down it and
        // gathered to its middle across (column bands of 0.001, 0.005, 0.008, 0.012 from the
        // side in). Long threads in a round patch had made 1823900922's rain fall in blots.
        return sheetOf(2, 2, 512, 512, 0.25, function (i, x, y) {
          var at = (x + 1) * 120, lane = Math.floor(at), off = at - lane - 0.5;
          var across = Math.exp(-Math.pow(off / 0.22, 2));
          var patch = (1 - smooth01(0.3, 0.78, Math.abs(x))) * (1 - smooth01(0.62, 0.97, Math.abs(y)));
          if (across * patch < 0.002) return [1, 0];
          var bunch = smoothNoise(lane / 9, i * 7, 4096, 352), sum = 0;
          for (var k = 0; k < 5; k++) {
            if (hash(lane, i * 7 + k, 351) > 0.25 + 0.75 * bunch) continue;
            var start = hash(lane, i * 7 + k + 40, 351) * 2.3 - 1.25, long = 0.3 + hash(lane, i * 7 + k + 80, 351) * 0.22;
            var along = (y - start) / long;
            if (along <= 0 || along >= 1) continue;
            var strength = 0.03 + 0.42 * Math.pow(hash(lane, i * 7 + k + 120, 351), 3);
            sum += strength * Math.sin(along * Math.PI) * (0.4 + 0.6 * smoothNoise(y * 9, lane * 3 + k, 4096, 353));
          }
          return [1, Math.min(1, sum * across * patch)];
        });
      case 'particle/nature/snow':
        return sheetOf(2, 2, 128, 128, 0, function (i, x, y) {
          // A flake of six feathery arms.
          var r = Math.hypot(x, y), turn = Math.atan2(y, x) + i, arm = Math.abs(Math.sin(turn * 3)) * r;
          var fringe = smooth01(0.4, 0.7, fbm(r * 12, Math.abs(Math.sin(turn * 3)) * 6, 3, 359 + i));
          return [1, (1 - smooth01(0.03 + 0.12 * fringe * (1 - r), 0.1 + 0.14 * fringe * (1 - r), arm)) * (1 - smooth01(0.75, 0.9, r))];
        });
      case 'particle/nature/waterplants1':
        return drawnSheet(8, 8, 64, 64, 0.015625, function (c, i, share, hw, hh) {
          c.strokeStyle = 'rgba(110,150,70,1)';
          c.lineWidth = 2;
          for (var blade = 0; blade < 6; blade++) {
            var foot = (blade - 2.5) * 6, sway = Math.sin(share * 6.283 + blade) * 8;
            c.beginPath();
            c.moveTo(foot, hh);
            c.quadraticCurveTo(foot + sway * 0.5, 0, foot + sway, -hh * (0.4 + 0.5 * hash(blade, 1, 353)));
            c.stroke();
          }
        });
      case 'particle/animals/fish1':
        return drawnSheet(4, 4, 128, 128, 0.0625, function (c, i, share, hw) {
          var bend = Math.sin(share * 6.283) * 0.35;
          c.fillStyle = 'rgba(120,128,104,1)';
          c.beginPath();
          c.ellipse(0, 0, hw * 0.55, hw * 0.16, 0, 0, Math.PI * 2);
          c.fill();
          c.save();
          c.translate(-hw * 0.5, 0);
          c.rotate(bend);
          c.beginPath();
          c.moveTo(0, 0);
          c.lineTo(-hw * 0.3, -hw * 0.18);
          c.lineTo(-hw * 0.3, hw * 0.18);
          c.closePath();
          c.fill();
          c.restore();
        });
      case 'particle/animals/jellyfish1':
        return drawnSheet(6, 6, 85.334, 85.334, 0.0277778, function (c, i, share, hw) {
          var pulse = 0.85 + 0.15 * Math.sin(share * 6.283);
          c.fillStyle = 'rgba(220,226,236,0.8)';
          c.beginPath();
          c.ellipse(0, -hw * 0.2, hw * 0.4 * pulse, hw * 0.3 / pulse, 0, Math.PI, 0);
          c.fill();
          c.strokeStyle = 'rgba(220,226,236,0.6)';
          c.lineWidth = 1.2;
          for (var t = -2; t <= 2; t++) {
            c.beginPath();
            c.moveTo(t * hw * 0.12, -hw * 0.2);
            c.quadraticCurveTo(t * hw * 0.12 + Math.sin(share * 6.283 + t) * 6, hw * 0.3, t * hw * 0.1, hw * 0.75);
            c.stroke();
          }
        });
      // Shapes with frames.
      case 'particle/shape/confetti_sheet':
        return sheetOf(4, 4, 64, 64, 0.0625, function (i, x, y, share) {
          var turn = hash(i, 1, 359) * 3, c = Math.cos(turn), s = Math.sin(turn), along = x * c + y * s, across = -x * s + y * c + Math.sin(along * 3 + i) * 0.15;
          var a = (1 - smooth01(0.16, 0.2, Math.abs(across))) * (1 - smooth01(0.5, 0.55, Math.abs(along)));
          return [0.45 + 0.55 * Math.abs(Math.cos(along * 2.5 + i)), a];
        });
      case 'particle/shape/electricity_sheet': return sheetOf(4, 2, 64, 64, 0.125, function (i, x, y) { return [1, boltAt(x * 1.2, y, i, 367, 0.05) * (1 - smooth01(0.5, 0.9, Math.abs(y)))]; });
      case 'particle/shape/sparks_sheet':
      case 'particle/shape/sparks_thick_sheet':
        var thick = name === 'particle/shape/sparks_thick_sheet';
        return sheetOf(2, 2, 128, 128, 0.25, function (i, x, y) {
          var light = 0;
          for (var k = 0; k < 3; k++) {
            var cx = (hash(i, k, 373) - 0.5) * 1.1, cy = (hash(i, k + 3, 373) - 0.5) * 1.1, size = 0.1 + hash(i, k + 6, 373) * (k ? 0.25 : 0.55);
            var d = polygonDistance(x - cx, y - cy, starCorners(4, size, size * (thick ? 0.3 : 0.12)));
            light = Math.max(light, filledBy(d, 0.01), 0.4 * glowBy(d, 14));
          }
          return [1, light];
        });
      case 'particle/misc/energyball':
        return sheetOf(8, 8, 64, 64, 0.015625, function (i, x, y, share) {
          var r = Math.hypot(x, y), turn = Math.atan2(y, x);
          var crackle = Math.pow(Math.max(0, smoothNoise(turn * 5 + share * 30, r * 6, 4096, 379)), 4);
          return [1, Math.max(Math.exp(-Math.pow((r - 0.55) / 0.08, 2)), crackle * (1 - smooth01(0.5, 0.65, r)), 0.3 * Math.exp(-Math.pow(r / 0.3, 2)))];
        });
      case 'particle/misc/wave':
        return sheetOf(8, 4, 64, 64, 0.0416667, function (i, x, y, share) { var r = Math.hypot(x, y); return [1, Math.exp(-Math.pow((r - 0.1 - share * 0.8) / 0.05, 2)) * (1 - share)]; }, 24);
      case 'particle/misc/arrow_0':
        return { width: 32, height: 64, clamp: true, pixels: whiteShape(32, 64, function (u, v) {
          return filledBy(polygonDistance(u * 2 - 1, v * 2 - 1, [[0, -0.95], [0.9, -0.2], [0.35, -0.2], [0.35, 0.95], [-0.35, 0.95], [-0.35, -0.2], [-0.9, -0.2]]), 0.03); }) };
      case 'particle/misc/lambda':
        // The Greek letter, in a heavy hand.
        return { width: 256, height: 256, clamp: true, pixels: drawn(256, 256, function (c) {
          c.strokeStyle = 'rgba(255,255,255,1)';
          c.lineCap = 'butt';
          c.lineWidth = 34;
          c.beginPath(); c.moveTo(70, 30); c.quadraticCurveTo(110, 30, 130, 90); c.lineTo(200, 228); c.stroke();
          c.beginPath(); c.moveTo(128, 100); c.lineTo(56, 228); c.stroke();
        }) };
      case 'particle/magic/glyph_0':
        return { width: 512, height: 512, clamp: true, pixels: drawn(512, 512, function (c) {
          glowingLines(c);
          c.lineWidth = 3;
          [0.9, 0.74, 0.46].forEach(function (ring) { c.beginPath(); c.arc(256, 256, 256 * ring, 0, Math.PI * 2); c.stroke(); });
          runeRing(c, 256, 256 * 0.82, 26, 383, 2.2);
          c.lineWidth = 3;
          [0, Math.PI / 4].forEach(function (turn) {
            c.beginPath();
            for (var k = 0; k <= 4; k++) { var a = turn + k * Math.PI / 2; var px = 256 + Math.cos(a) * 256 * 0.46, py = 256 + Math.sin(a) * 256 * 0.46; if (k === 0) c.moveTo(px, py); else c.lineTo(px, py); }
            c.stroke();
          });
          for (var k2 = 0; k2 < 4; k2++) { var a2 = k2 * Math.PI / 2; c.beginPath(); c.arc(256 + Math.cos(a2) * 256 * 0.46, 256 + Math.sin(a2) * 256 * 0.46, 14, 0, Math.PI * 2); c.stroke(); }
        }) };
      case 'particle/magic/glyph_3':
        return { width: 512, height: 512, clamp: true, pixels: drawn(512, 512, function (c) { glowingLines(c); runeRing(c, 256, 256 * 0.8, 30, 389, 2.6); }) };
      case 'particle/tech/tech_0':
      case 'particle/tech/tech_1':
        var solid = name === 'particle/tech/tech_0';
        return { width: 256, height: 256, clamp: true, pixels: drawn(256, 256, function (c) {
          c.strokeStyle = 'rgba(255,255,255,1)';
          [[0.95, 0, 6.283, 2], [0.8, 0.3, 4.2, solid ? 22 : 2], [0.55, 1.2, 5.6, solid ? 16 : 2], [0.35, 0, 6.283, 2], [0.62, 4.6, 6.1, solid ? 12 : 2]].forEach(function (arc) {
            c.lineWidth = arc[3];
            c.beginPath();
            c.arc(128, 128, 128 * arc[0], arc[1], arc[2]);
            c.stroke();
          });
          c.lineWidth = 2;
          c.beginPath(); c.moveTo(128, 128 - 128 * 0.95); c.lineTo(128, 128 - 128 * 0.35); c.stroke();
        }) };
      // Light thrown through a pattern, as a lamp throws it.
      case 'cookie/flashlight1':
      case 'cookie/flashlight2':
      case 'cookie/flashlight3':
        var lamp = { 'cookie/flashlight1': 401, 'cookie/flashlight2': 409, 'cookie/flashlight3': 419 }[name];
        return { width: 512, height: 512, clamp: true, pixels: shaded(512, 512, function (u, v) {
          var x = u * 2 - 1, y = v * 2 - 1, r = Math.hypot(x, y), turn = Math.atan2(y, x);
          // A lamp's uneven light: blotches and faint rings, a bright spot in the middle.
          var g = (1 - smooth01(0.7, 0.92, r + (fbm(Math.cos(turn) * 2, Math.sin(turn) * 2, 3, lamp + 1) - 0.5) * 0.15))
                  * (0.45 + 0.1 * Math.sin(r * 30) + 0.45 * fbm(x * 2.5, y * 2.5, 4, lamp)) + 0.45 * Math.exp(-Math.pow(r / 0.1, 2));
          return [g, g, g, 1]; }) };
      case 'cookie/flashlight4':
        return { width: 512, height: 512, clamp: true, pixels: shaded(512, 512, function (u, v) {
          var x = u * 2 - 1, y = v * 2 - 1, r = Math.hypot(x, y);
          var g = Math.min(1, (1 - smooth01(0.2, 0.45, r)) + rays(8, 421, 0.05, Math.atan2(y, x), r, 1) * 0.8); return [g, g, g, 1]; }) };
      // Rows of colors, for shaders that color by a value.
      case 'gradient/gradient_fire': return gradientOf([[0, 128, 16, 16, 255], [0.45, 236, 0, 0, 255], [0.65, 255, 96, 16, 255], [1, 250, 204, 36, 255]]);
      case 'gradient/gradient_fire_2': return gradientOf([[0, 255, 255, 255, 0], [0.2, 0, 0, 0, 220], [0.35, 150, 96, 46, 255], [0.8, 164, 66, 22, 255], [1, 32, 12, 4, 60]]);
      case 'gradient/gradient_fire_3': return gradientOf([[0, 18, 10, 10, 255], [0.25, 86, 9, 9, 255], [0.5, 240, 0, 0, 255], [0.75, 250, 202, 32, 255], [1, 255, 244, 200, 255]]);
      case 'gradient/gradient_ferro_fluid': return gradientOf([[0, 0, 0, 0, 255], [0.55, 4, 0, 10, 255], [0.75, 40, 34, 52, 255], [0.85, 0, 0, 2, 255], [1, 0, 0, 0, 255]]);
      case 'gradient/gradient_ghost_flame': return gradientOf([[0, 0, 0, 0, 255], [0.2, 0, 0, 0, 255], [0.25, 164, 22, 100, 228], [0.32, 0, 0, 0, 255], [0.72, 0, 0, 0, 255], [0.75, 255, 216, 252, 60], [0.88, 0, 134, 152, 255], [1, 0, 8, 10, 255]]);
      case 'gradient/gradient_ice': return gradientOf([[0, 114, 190, 255, 255], [0.85, 182, 220, 255, 255], [1, 106, 168, 255, 255]]);
      case 'gradient/gradient_iridescent': return gradientOf([[0, 254, 164, 142, 255], [0.25, 184, 192, 190, 255], [0.45, 70, 172, 255, 255], [0.7, 174, 126, 255, 255], [1, 92, 176, 255, 255]]);
      case 'gradient/gradient_neon': return gradientOf([[0, 0, 186, 255, 255], [0.3, 154, 58, 255, 255], [0.55, 255, 12, 228, 255], [0.8, 255, 160, 68, 255], [1, 255, 224, 6, 255]]);
      case 'gradient/gradient_rainbow': return gradientOf([[0, 255, 0, 0, 255], [0.25, 146, 0, 255, 255], [0.5, 0, 241, 255, 255], [0.75, 112, 255, 0, 255], [0.9, 255, 211, 0, 255], [1, 255, 14, 0, 255]]);
      case 'gradient/gradient_swamp': return gradientOf([[0, 60, 36, 50, 255], [0.25, 60, 42, 58, 255], [0.5, 42, 128, 152, 255], [0.75, 48, 178, 172, 255], [1, 76, 182, 120, 255]]);
      case 'gradient/gradient_swipe_dual': return gradientOf([[0, 0, 0, 0, 255], [0.12, 224, 224, 224, 255], [0.3, 200, 200, 200, 255], [0.6, 10, 10, 10, 255], [1, 0, 0, 0, 255]]);
      case 'gradient/gradient_swipe_wide': return gradientOf([[0, 0, 0, 0, 255], [0.12, 240, 240, 240, 255], [0.55, 10, 10, 10, 255], [1, 0, 0, 0, 255]]);
      case 'gradient/gradient_toon': return gradientOf([[0, 0, 0, 0, 255], [0.7, 0, 0, 0, 255], [0.71, 255, 255, 255, 255], [1, 255, 255, 255, 255]]);
      case 'gradient/gradient_toon_smooth': return gradientOf([[0, 0, 0, 0, 255], [0.5, 10, 10, 10, 255], [0.75, 210, 210, 210, 255], [1, 254, 254, 254, 255]]);
      // Pictures shaders read their numbers from.
      case 'util/flatnormal': return { width: 16, height: 16, clamp: false, pixels: shaded(16, 16, function () { return [0.5, 0.5, 1, 1]; }) };
      case 'util/fur':
        return { width: 128, height: 128, clamp: false, pixels: shaded(128, 128, function (u, v) {
          // Short hairs, laid one way.
          var g = smooth01(0.5, 0.65, smoothNoise(u * 160 + v * 60, v * 14 - u * 6, 4096, 431)) * (0.6 + 0.4 * smoothNoise(u * 30, v * 30, 4096, 433)); return [g, g, g, 1]; }) };
      case 'util/perlin_256':
        return { width: 256, height: 256, clamp: false, pixels: shaded(256, 256, function (u, v) {
          return [0, 1, 2, 3].map(function (k) { return 0.15 + 0.7 * fbm(u * 6 + k * 13, v * 6, 4, 439 + k); }); }) };
      case 'util/uniform_256':
        return { width: 256, height: 256, clamp: false, pixels: shaded(256, 256, function (u, v, x, y) {
          return [0, 1, 2, 3].map(function (k) { return hash(x, y, 443 + k) * 0.5; }); }) };
    }
    return null;
  }

  // How much of its square the drop drawn in place of Wallpaper Engine's sheet of drops takes.
  var DROP_FILL = 0.36;
  function isDropSheet(name) { return /drops?_sheet|droplet|raindrop|water\/[^\/]*drop/.test(name); }

  // The shapes of particles, drawn white on nothing; a particle's own color tints them.
  // A drop on glass, as clear as the glass: a darker rim, a glint where the light falls on it.
  function spritePixels(name, size) {
    var canvas = document.createElement('canvas');
    canvas.width = canvas.height = size;
    var context = canvas.getContext('2d');
    var half = size / 2;
    function glow(x, y, radius, strength) {
      var gradient = context.createRadialGradient(x, y, 0, x, y, radius);
      gradient.addColorStop(0, 'rgba(255,255,255,' + strength + ')');
      gradient.addColorStop(0.4, 'rgba(255,255,255,' + strength * 0.45 + ')');
      gradient.addColorStop(1, 'rgba(255,255,255,0)');
      context.fillStyle = gradient;
      context.fillRect(0, 0, size, size);
    }
    if (/shaft|godray|sunbeam|sunray|light_ray/.test(name)) {
      // Light falling through. Wallpaper Engine's own pictures of it are of a few kinds, told
      // by their number: a soft column of light falling from the top edge (0, and the plainest
      // one, 6), thin rays from a point at the top (1, 3), a wide fan from the top (4) and a
      // burst from the middle (2, 5). Each is drawn here in its shape: rays from where the
      // light comes in, fading as they go. Such a picture is made large and turned.
      var kind = Number((/(\d+)\D*$/.exec(name) || [])[1]);
      // `spread`: how far to either side the rays go, as an angle; `from`: where they start,
      // as a share of the height above the top; `count`, `widths` and `strength` of the rays.
      // Their light dies away downward as Wallpaper Engine's does — most of it in the upper half,
      // next to none at the bottom — and they are as bright, against one another, as its are.
      // How bright they are on a scene was set against Wallpaper Engine's own picture of one
      // ("Frieren with music"): there the light adds about a quarter to the brightness where it
      // falls, warm and in streaks.
      var fan = { 0: { spread: 0.16, from: 0.25, count: 22, widths: [0.05, 0.16], strength: 0.022 },
                  6: { spread: 0.05, from: 0.6, count: 10, widths: [0.12, 0.3], strength: 0.009 },
                  1: { spread: 0.3, from: 0, count: 9, widths: [0.004, 0.02], strength: 0.024 },
                  3: { spread: 0.12, from: 0, count: 6, widths: [0.004, 0.015], strength: 0.028 },
                  4: { spread: 0.95, from: 0, count: 30, widths: [0.01, 0.06], strength: 0.038 } }[kind];
      if (fan) {
        var topX = half, topY = -fan.from * size;
        var reach = size - topY;
        for (var ray = 0; ray < fan.count; ray++) {
          var turn = (hash(ray, 4, 7) * 2 - 1) * fan.spread;
          var wide = (fan.widths[0] + hash(ray, 5, 7) * (fan.widths[1] - fan.widths[0])) * Math.PI;
          var strong = fan.strength * (0.5 + hash(ray, 6, 7));
          // Faded toward where it ends, and where it starts, as light comes in through leaves.
          var fade = context.createRadialGradient(topX, topY, 0, topX, topY, reach);
          // Stops by how far down the picture they are.
          var down = function (share) { return Math.min(1, (fan.from + share) / (1 + fan.from)); };
          fade.addColorStop(0, 'rgba(255,255,255,0)');
          if (down(0) > 0) fade.addColorStop(down(0) * 0.9, 'rgba(255,255,255,0)');
          fade.addColorStop(down(0.12), 'rgba(255,255,255,' + strong + ')');
          fade.addColorStop(down(0.3), 'rgba(255,255,255,' + strong * 0.75 + ')');
          fade.addColorStop(down(0.5), 'rgba(255,255,255,' + strong * 0.3 + ')');
          fade.addColorStop(down(0.75), 'rgba(255,255,255,' + strong * 0.07 + ')');
          fade.addColorStop(1, 'rgba(255,255,255,0)');
          context.fillStyle = fade;
          context.beginPath();
          context.moveTo(topX, topY);
          context.arc(topX, topY, reach, Math.PI / 2 + turn - wide / 2, Math.PI / 2 + turn + wide / 2);
          context.closePath();
          context.fill();
        }
        // Brightest where it comes in.
        var inlet = context.createRadialGradient(half, size * 0.12, 0, half, size * 0.12, size * 0.3);
        inlet.addColorStop(0, 'rgba(255,255,255,' + Math.min(1, fan.strength * 2) + ')');
        inlet.addColorStop(1, 'rgba(255,255,255,0)');
        context.fillStyle = inlet;
        context.fillRect(0, 0, size, size * 0.4);
      } else {
        // A burst: soft rays from the middle outward, of many widths, fading as they go.
        for (var spike = 0; spike < 18; spike++) {
          var toward = hash(spike, 4, 7) * Math.PI * 2;
          var narrow = (0.01 + hash(spike, 5, 7) * 0.05) * Math.PI;
          var bright = 0.12 + hash(spike, 6, 7) * 0.25;
          var burst = context.createRadialGradient(half, half, 0, half, half, half);
          burst.addColorStop(0, 'rgba(255,255,255,0)');
          burst.addColorStop(0.08, 'rgba(255,255,255,' + bright + ')');
          burst.addColorStop(0.55, 'rgba(255,255,255,' + bright * 0.45 + ')');
          burst.addColorStop(1, 'rgba(255,255,255,0)');
          context.fillStyle = burst;
          context.beginPath();
          context.moveTo(half, half);
          context.arc(half, half, half, toward - narrow / 2, toward + narrow / 2);
          context.closePath();
          context.fill();
        }
      }
    } else if (/fog|smoke|cloud|mist|steam|dust|haze/.test(name)) {
      // A puff: many soft blots, more of them toward the middle.
      for (var blot = 0; blot < 40; blot++) {
        var angle = hash(blot, 1, 3) * Math.PI * 2;
        var away = Math.pow(hash(blot, 2, 3), 0.8) * half * 0.55;
        glow(half + Math.cos(angle) * away, half + Math.sin(angle) * away, half * (0.2 + hash(blot, 3, 3) * 0.3), 0.05);
      }
    } else if (isDropSheet(name)) {
      // A drop on glass, as clear as the glass: round, a little fuller toward its foot, its
      // rim darker where it bends the light away. What it shows of what is behind is drawn by
      // the drop's own shader; this is its shape.
      // As on Wallpaper Engine's own sheet of drops, a drop takes a third of its square.
      var reach = half * DROP_FILL;
      var bead = context.createRadialGradient(half, half + reach * 0.06, 0, half, half + reach * 0.06, reach);
      bead.addColorStop(0, 'rgba(255,255,255,1)');
      bead.addColorStop(0.62, 'rgba(250,252,255,1)');
      bead.addColorStop(0.86, 'rgba(176,184,194,1)');
      bead.addColorStop(0.95, 'rgba(120,128,138,0.9)');
      bead.addColorStop(1, 'rgba(120,128,138,0)');
      context.fillStyle = bead;
      context.beginPath();
      context.ellipse(half, half + reach * 0.06, reach * 0.95, reach, 0, 0, Math.PI * 2);
      context.fill();
    } else if (/rain|drop|streak|line|trail|beam|ray/.test(name)) {
      var streak = context.createLinearGradient(0, 0, 0, size);
      streak.addColorStop(0, 'rgba(255,255,255,0)');
      streak.addColorStop(0.5, 'rgba(255,255,255,0.9)');
      streak.addColorStop(1, 'rgba(255,255,255,0)');
      context.fillStyle = streak;
      context.fillRect(half - size * 0.04, 0, size * 0.08, size);
    } else if (/fire|flame|blaze|burn/.test(name)) {
      // A flame: a tongue rising from a bright foot, frayed at its edges.
      for (var tongue = 0; tongue < 24; tongue++) {
        var rise = hash(tongue, 5, 9);
        var sway = (hash(tongue, 6, 9) - 0.5) * half * 0.5 * rise;
        glow(half + sway, size * (0.72 - rise * 0.5), half * (0.32 - rise * 0.2), 0.16 * (1 - rise * 0.6));
      }
    } else if (/halo|glow|light|dot|spark|ember|orb|bokeh|firefl/.test(name)) {
      // A halo: a small bright core in a faint glow, as light seen through a lens is.
      var halo = context.createRadialGradient(half, half, 0, half, half, half);
      halo.addColorStop(0, 'rgba(255,255,255,1)');
      halo.addColorStop(0.08, 'rgba(255,255,255,0.85)');
      halo.addColorStop(0.2, 'rgba(255,255,255,0.3)');
      halo.addColorStop(0.5, 'rgba(255,255,255,0.08)');
      halo.addColorStop(1, 'rgba(255,255,255,0)');
      context.fillStyle = halo;
      context.fillRect(0, 0, size, size);
    } else if (/star|sparkle|flare|twinkle/.test(name)) {
      glow(half, half, half * 0.5, 1);
      context.fillStyle = 'rgba(255,255,255,0.8)';
      [[1, 0.06], [0.06, 1]].forEach(function (arm) {
        context.beginPath();
        context.ellipse(half, half, half * arm[0], half * arm[1], 0, 0, Math.PI * 2);
        context.fill();
      });
    } else if (/leaf|leaves|foliage/.test(name)) {
      // A leaf: pointed at both ends, a little lighter along its middle, on a short stalk.
      context.translate(half, half);
      context.rotate(Math.PI / 5);
      context.beginPath();
      context.moveTo(-half * 0.82, 0);
      context.quadraticCurveTo(-half * 0.1, -half * 0.62, half * 0.82, 0);
      context.quadraticCurveTo(-half * 0.1, half * 0.62, -half * 0.82, 0);
      context.closePath();
      var body = context.createLinearGradient(0, -half * 0.4, 0, half * 0.4);
      body.addColorStop(0, 'rgba(205,205,205,0.95)');
      body.addColorStop(0.5, 'rgba(255,255,255,0.95)');
      body.addColorStop(1, 'rgba(175,175,175,0.95)');
      context.fillStyle = body;
      context.fill();
      context.strokeStyle = 'rgba(255,255,255,0.9)';
      context.lineWidth = size / 64;
      context.beginPath();
      context.moveTo(-half * 0.95, 0);
      context.lineTo(half * 0.7, 0);
      context.stroke();
    } else if (/petal|feather|confetti|flake/.test(name)) {
      context.fillStyle = 'rgba(255,255,255,0.95)';
      context.beginPath();
      context.ellipse(half, half, half * 0.85, half * 0.4, Math.PI / 5, 0, Math.PI * 2);
      context.fill();
    } else {
      // A soft round dot: snow, sparks, lights, and whatever has no shape of its own here.
      glow(half, half, half, 1);
    }
    return context.getImageData(0, 0, size, size).data;
  }

