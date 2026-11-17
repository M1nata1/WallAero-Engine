  // Scripts are written against Wallpaper Engine's own names: vectors, a few helpers, and
  // objects that stand for the scene, the layer and the app. Those are made here to the same
  // names, as its documentation gives them.

  function vector(names) {
    function Vector(first) {
      var given = arguments;
      var self = this;
      if (typeof first === 'string') {
        var parts = first.trim().split(/\s+/).map(Number);
        names.forEach(function (name, index) { self[name] = isFinite(parts[index]) ? parts[index] : 0; });
      } else if (first && typeof first === 'object') {
        names.forEach(function (name, index) {
          self[name] = typeof first[name] === 'number' ? first[name] : (typeof given[index] === 'number' && index > 0 ? given[index] : 0);
        });
      } else if (given.length <= 1) {
        // One number stands for them all.
        names.forEach(function (name) { self[name] = typeof first === 'number' ? first : 0; });
      } else {
        names.forEach(function (name, index) { self[name] = typeof given[index] === 'number' ? given[index] : 0; });
      }
    }
    var proto = Vector.prototype;
    function each(self, other, change) {
      var result = new Vector(0);
      names.forEach(function (name) {
        result[name] = change(self[name], other !== null && typeof other === 'object' ? (typeof other[name] === 'number' ? other[name] : 0) : other);
      });
      return result;
    }
    function both(change) {
      return function (other) { return each(this, other === undefined ? 0 : other, change); };
    }
    function alone(change) {
      return function () { return each(this, 0, change); };
    }
    proto.copy = alone(function (value) { return value; });
    proto.add = both(function (value, other) { return value + other; });
    proto.subtract = both(function (value, other) { return value - other; });
    proto.multiply = both(function (value, other) { return value * other; });
    proto.divide = both(function (value, other) { return value / other; });
    proto.min = both(Math.min);
    proto.max = both(Math.max);
    proto.mod = both(function (value, other) { return value - other * Math.floor(value / other); });
    proto.step = both(function (value, edge) { return value < edge ? 0 : 1; });
    proto.negate = alone(function (value) { return -value; });
    proto.abs = alone(Math.abs);
    proto.sign = alone(Math.sign);
    proto.round = alone(Math.round);
    proto.floor = alone(Math.floor);
    proto.ceil = alone(Math.ceil);
    proto.fract = alone(function (value) { return value - Math.floor(value); });
    proto.dot = function (other) {
      var self = this, sum = 0;
      names.forEach(function (name) { sum += self[name] * other[name]; });
      return sum;
    };
    proto.lengthSqr = function () { return this.dot(this); };
    proto.length = function () { return Math.sqrt(this.dot(this)); };
    proto.distanceSqr = function (other) { return this.subtract(other).lengthSqr(); };
    proto.distance = function (other) { return this.subtract(other).length(); };
    proto.normalize = function () {
      var length = this.length();
      return length > 0 ? this.divide(length) : this.copy();
    };
    proto.equals = function (other) {
      var self = this;
      return !!other && names.every(function (name) { return self[name] === other[name]; });
    };
    proto.isFinite = function () {
      var self = this;
      return names.every(function (name) { return isFinite(self[name]); });
    };
    proto.mix = function (other, amount) {
      var self = this;
      var result = new Vector(0);
      names.forEach(function (name) {
        var share = typeof amount === 'object' ? amount[name] : amount;
        result[name] = self[name] + (other[name] - self[name]) * share;
      });
      return result;
    };
    proto.clamp = function (least, most) { return this.max(least).min(most); };
    proto.smoothStep = function (least, most) {
      var self = this;
      var result = new Vector(0);
      names.forEach(function (name) {
        var low = typeof least === 'object' ? least[name] : least, high = typeof most === 'object' ? most[name] : most;
        var share = Math.max(0, Math.min(1, (self[name] - low) / (high - low || 1)));
        result[name] = share * share * (3 - 2 * share);
      });
      return result;
    };
    proto.reflect = function (normal) { return this.subtract(normal.multiply(2 * this.dot(normal))); };
    proto.project = function (other) { return other.multiply(this.dot(other) / (other.lengthSqr() || 1)); };
    proto.angleBetween = function (other) {
      return Math.acos(Math.max(-1, Math.min(1, this.dot(other) / ((this.length() * other.length()) || 1)))) * 180 / Math.PI;
    };
    proto.toString = function () {
      var self = this;
      return names.map(function (name) { return self[name]; }).join(' ');
    };
    return Vector;
  }

  var Vec2 = vector(['x', 'y']);
  var Vec3 = vector(['x', 'y', 'z']);
  var Vec4 = vector(['x', 'y', 'z', 'w']);
  // Angles are in degrees, as everywhere in scripts.
  Vec2.prototype.angle = function () { return Math.atan2(this.y, this.x) * 180 / Math.PI; };
  Vec2.prototype.perpendicular = function () { return new Vec2(-this.y, this.x); };
  Vec2.prototype.rotate = function (angle) {
    var cos = Math.cos(angle * Math.PI / 180), sin = Math.sin(angle * Math.PI / 180);
    return new Vec2(this.x * cos - this.y * sin, this.x * sin + this.y * cos);
  };
  Vec3.prototype.cross = function (other) {
    return new Vec3(this.y * other.z - this.z * other.y, this.z * other.x - this.x * other.z, this.x * other.y - this.y * other.x);
  };

  var MODULES = {
    WEMath: {
      smoothStep: function (least, most, value) {
        var share = Math.max(0, Math.min(1, (value - least) / (most - least || 1)));
        return share * share * (3 - 2 * share);
      },
      mix: function (first, second, share) { return first + (second - first) * share; },
      deg2rad: Math.PI / 180,
      rad2deg: 180 / Math.PI
    },
    WEVector: {
      angleVector2: function (angle) { return new Vec2(Math.cos(angle * Math.PI / 180), Math.sin(angle * Math.PI / 180)); },
      vectorAngle2: function (direction) { return Math.atan2(direction.y, direction.x) * 180 / Math.PI; }
    },
    WEColor: {
      // Colors go from 0 to 1 a part; the hue too.
      rgb2hsv: function (rgb) {
        var most = Math.max(rgb.x, rgb.y, rgb.z), least = Math.min(rgb.x, rgb.y, rgb.z);
        var spread = most - least;
        var hue = 0;
        if (spread > 0) {
          if (most === rgb.x) hue = ((rgb.y - rgb.z) / spread) % 6;
          else if (most === rgb.y) hue = (rgb.z - rgb.x) / spread + 2;
          else hue = (rgb.x - rgb.y) / spread + 4;
        }
        hue = (hue / 6 + 1) % 1;
        return new Vec3(hue, most > 0 ? spread / most : 0, most);
      },
      hsv2rgb: function (hsv) {
        function part(shift) {
          var k = (shift + hsv.x * 6) % 6;
          return hsv.z - hsv.z * hsv.y * Math.max(0, Math.min(k, 4 - k, 1));
        }
        return new Vec3(part(5), part(3), part(1));
      },
      normalizeColor: function (rgb) { return new Vec3(rgb.x / 255, rgb.y / 255, rgb.z / 255); },
      expandColor: function (rgb) { return new Vec3(rgb.x * 255, rgb.y * 255, rgb.z * 255); }
    }
  };

  // Anything a script asks of an object that is not made here does nothing and gives
  // nothing, rather than stopping the script.
  function lenient(target) {
    if (typeof Proxy !== 'function') return target;
    return new Proxy(target, {
      get: function (object, name) {
        if (name in object || typeof name !== 'string') return object[name];
        return function () {};
      }
    });
  }

  // The names a script knows the state of the music by. What plays on the Mac is not told to
  // scenes, so a script that asks finds it stopped.
  var MEDIA_PLAYBACK = { PLAYBACK_STOPPED: 0, PLAYBACK_PLAYING: 1, PLAYBACK_PAUSED: 2 };

  // Matrices as scripts have them: numbers by columns, the place in the last one, angles in
  // degrees, turned as the objects of a scene are (about x, then y, then z).
  var DEGREE = Math.PI / 180;
  function times4(a, b) {
    var r = new Array(16);
    for (var column = 0; column < 4; column++) {
      for (var row = 0; row < 4; row++) {
        var sum = 0;
        for (var k = 0; k < 4; k++) sum += a[k * 4 + row] * b[column * 4 + k];
        r[column * 4 + row] = sum;
      }
    }
    return r;
  }
  function euler4(x, y, z) {
    var cx = Math.cos(x * DEGREE), sx = Math.sin(x * DEGREE), cy = Math.cos(y * DEGREE), sy = Math.sin(y * DEGREE);
    var cz = Math.cos(z * DEGREE), sz = Math.sin(z * DEGREE);
    return [cz * cy, sz * cy, -sy, 0,
            cz * sy * sx - sz * cx, sz * sy * sx + cz * cx, cy * sx, 0,
            cz * sy * cx + sz * sx, sz * sy * cx - cz * sx, cy * cx, 0,
            0, 0, 0, 1];
  }
  function Mat4(values) {
    this.m = Array.isArray(values) && values.length === 16 ? values.slice() : [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  }
  Mat4.identity = function () { return new Mat4(); };
  Mat4.fromTranslation = function (v) { return new Mat4([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, v.x || 0, v.y || 0, v.z || 0, 1]); };
  Mat4.fromScale = function (v) {
    var x = typeof v === 'number' ? v : v.x, y = typeof v === 'number' ? v : v.y, z = typeof v === 'number' ? v : (v.z === undefined ? 1 : v.z);
    return new Mat4([x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1]);
  };
  Mat4.fromRotation = function (angle, axis) {
    var length = Math.sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z) || 1;
    var x = axis.x / length, y = axis.y / length, z = axis.z / length;
    var c = Math.cos(angle * DEGREE), s = Math.sin(angle * DEGREE), t = 1 - c;
    return new Mat4([t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0,
                     t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0,
                     t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0,
                     0, 0, 0, 1]);
  };
  Mat4.fromEuler = function (x, y, z) {
    if (x && typeof x === 'object') return new Mat4(euler4(x.x, x.y, x.z));
    return new Mat4(euler4(x || 0, y || 0, z || 0));
  };
  Mat4.fromBasis = function (right, up, forward) {
    return new Mat4([right.x, right.y, right.z, 0, up.x, up.y, up.z, 0, forward.x, forward.y, forward.z, 0, 0, 0, 0, 1]);
  };
  Mat4.lookAt = function (eye, center, up) {
    var f = new Vec3(center.x - eye.x, center.y - eye.y, center.z - eye.z).normalize();
    var r = f.cross(up).normalize();
    var u = r.cross(f);
    return new Mat4([r.x, u.x, -f.x, 0, r.y, u.y, -f.y, 0, r.z, u.z, -f.z, 0,
                     -r.dot(eye), -u.dot(eye), f.dot(eye), 1]);
  };
  Mat4.compose = function (translation, rotation, scale) {
    return Mat4.fromTranslation(translation).multiply(Mat4.fromEuler(rotation)).multiply(Mat4.fromScale(scale));
  };
  Mat4.prototype.translation = function (position) {
    if (position) {
      this.m[12] = position.x || 0;
      this.m[13] = position.y || 0;
      this.m[14] = position.z || 0;
    }
    return new Vec3(this.m[12], this.m[13], this.m[14]);
  };
  Mat4.prototype.right = function () { return new Vec3(this.m[0], this.m[1], this.m[2]); };
  Mat4.prototype.up = function () { return new Vec3(this.m[4], this.m[5], this.m[6]); };
  Mat4.prototype.forward = function () { return new Vec3(this.m[8], this.m[9], this.m[10]); };
  Mat4.prototype.add = function (other) { var o = other.m; return new Mat4(this.m.map(function (v, i) { return v + o[i]; })); };
  Mat4.prototype.subtract = function (other) { var o = other.m; return new Mat4(this.m.map(function (v, i) { return v - o[i]; })); };
  Mat4.prototype.multiply = function (value) {
    if (typeof value === 'number') return new Mat4(this.m.map(function (v) { return v * value; }));
    if (value instanceof Mat4) return new Mat4(times4(this.m, value.m));
    var m = this.m, x = value.x || 0, y = value.y || 0, z = value.z || 0, w = value.w === undefined ? 1 : value.w;
    return new Vec4(m[0] * x + m[4] * y + m[8] * z + m[12] * w, m[1] * x + m[5] * y + m[9] * z + m[13] * w,
                    m[2] * x + m[6] * y + m[10] * z + m[14] * w, m[3] * x + m[7] * y + m[11] * z + m[15] * w);
  };
  Mat4.prototype.translate = function (v) { return this.multiply(Mat4.fromTranslation(v)); };
  Mat4.prototype.rotate = function (angle, axis) { return this.multiply(Mat4.fromRotation(angle, axis)); };
  Mat4.prototype.scale = function (v) { return this.multiply(Mat4.fromScale(v)); };
  Mat4.prototype.transformPoint = function (v) {
    var m = this.m, x = v.x || 0, y = v.y || 0, z = v.z || 0;
    var w = m[3] * x + m[7] * y + m[11] * z + m[15] || 1;
    return new Vec3((m[0] * x + m[4] * y + m[8] * z + m[12]) / w, (m[1] * x + m[5] * y + m[9] * z + m[13]) / w,
                    (m[2] * x + m[6] * y + m[10] * z + m[14]) / w);
  };
  Mat4.prototype.transformDirection = function (v) {
    var m = this.m, x = v.x || 0, y = v.y || 0, z = v.z || 0;
    return new Vec3(m[0] * x + m[4] * y + m[8] * z, m[1] * x + m[5] * y + m[9] * z, m[2] * x + m[6] * y + m[10] * z);
  };
  Mat4.prototype.transpose = function () {
    var m = this.m, r = new Array(16);
    for (var c = 0; c < 4; c++) for (var row = 0; row < 4; row++) r[row * 4 + c] = m[c * 4 + row];
    return new Mat4(r);
  };
  Mat4.prototype.determinant = function () {
    var m = this.m;
    var b0 = m[0] * m[5] - m[1] * m[4], b1 = m[0] * m[6] - m[2] * m[4], b2 = m[0] * m[7] - m[3] * m[4];
    var b3 = m[1] * m[6] - m[2] * m[5], b4 = m[1] * m[7] - m[3] * m[5], b5 = m[2] * m[7] - m[3] * m[6];
    var b6 = m[8] * m[13] - m[9] * m[12], b7 = m[8] * m[14] - m[10] * m[12], b8 = m[8] * m[15] - m[11] * m[12];
    var b9 = m[9] * m[14] - m[10] * m[13], b10 = m[9] * m[15] - m[11] * m[13], b11 = m[10] * m[15] - m[11] * m[14];
    return b0 * b11 - b1 * b10 + b2 * b9 + b3 * b8 - b4 * b7 + b5 * b6;
  };
  Mat4.prototype.inverse = function () {
    var m = this.m;
    var b0 = m[0] * m[5] - m[1] * m[4], b1 = m[0] * m[6] - m[2] * m[4], b2 = m[0] * m[7] - m[3] * m[4];
    var b3 = m[1] * m[6] - m[2] * m[5], b4 = m[1] * m[7] - m[3] * m[5], b5 = m[2] * m[7] - m[3] * m[6];
    var b6 = m[8] * m[13] - m[9] * m[12], b7 = m[8] * m[14] - m[10] * m[12], b8 = m[8] * m[15] - m[11] * m[12];
    var b9 = m[9] * m[14] - m[10] * m[13], b10 = m[9] * m[15] - m[11] * m[13], b11 = m[10] * m[15] - m[11] * m[14];
    var det = b0 * b11 - b1 * b10 + b2 * b9 + b3 * b8 - b4 * b7 + b5 * b6;
    if (!det) return new Mat4();
    var d = 1 / det;
    return new Mat4([
      (m[5] * b11 - m[6] * b10 + m[7] * b9) * d, (m[2] * b10 - m[1] * b11 - m[3] * b9) * d,
      (m[13] * b5 - m[14] * b4 + m[15] * b3) * d, (m[10] * b4 - m[9] * b5 - m[11] * b3) * d,
      (m[6] * b8 - m[4] * b11 - m[7] * b7) * d, (m[0] * b11 - m[2] * b8 + m[3] * b7) * d,
      (m[14] * b2 - m[12] * b5 - m[15] * b1) * d, (m[8] * b5 - m[10] * b2 + m[11] * b1) * d,
      (m[4] * b10 - m[5] * b8 + m[7] * b6) * d, (m[1] * b8 - m[0] * b10 - m[3] * b6) * d,
      (m[12] * b4 - m[13] * b2 + m[15] * b0) * d, (m[9] * b2 - m[8] * b4 - m[11] * b0) * d,
      (m[5] * b7 - m[4] * b9 - m[6] * b6) * d, (m[0] * b9 - m[1] * b7 + m[2] * b6) * d,
      (m[13] * b1 - m[12] * b3 - m[14] * b0) * d, (m[8] * b3 - m[9] * b1 + m[10] * b0) * d
    ]);
  };
  // The scale of each axis, and the angles of what is left once the scale is taken out.
  Mat4.prototype.decompose = function () {
    var m = this.m;
    var sx = Math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]) || 1, sy = Math.sqrt(m[4] * m[4] + m[5] * m[5] + m[6] * m[6]) || 1;
    var sz = Math.sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10]) || 1;
    if (this.determinant() < 0) sx = -sx;
    var r = [m[0] / sx, m[1] / sx, m[2] / sx, m[4] / sy, m[5] / sy, m[6] / sy, m[8] / sz, m[9] / sz, m[10] / sz];
    var y = Math.asin(Math.max(-1, Math.min(1, -r[2])));
    var x, z;
    if (Math.abs(r[2]) < 0.99999) {
      x = Math.atan2(r[5], r[8]);
      z = Math.atan2(r[1], r[0]);
    } else {
      x = Math.atan2(-r[7], r[4]);
      z = 0;
    }
    return { translation: new Vec3(m[12], m[13], m[14]), rotation: new Vec3(x / DEGREE, y / DEGREE, z / DEGREE),
             scale: new Vec3(sx, sy, sz) };
  };
  Mat4.prototype.extractEuler = function () { return this.decompose().rotation; };
  Mat4.prototype.normalMatrix = function () {
    var i = this.inverse().m;
    return new Mat3([i[0], i[4], i[8], i[1], i[5], i[9], i[2], i[6], i[10]]);
  };
  Mat4.prototype.copy = function () { return new Mat4(this.m); };
  Mat4.prototype.equals = function (other) {
    return !!other && other.m && this.m.every(function (v, i) { return Math.abs(v - other.m[i]) < 1e-6; });
  };
  Mat4.prototype.toString = function () { return this.m.join(' '); };

  // A 3×3 matrix for the plane: by columns, the place in the last one, the angle in degrees.
  function times3(a, b) {
    var r = new Array(9);
    for (var column = 0; column < 3; column++) {
      for (var row = 0; row < 3; row++) {
        var sum = 0;
        for (var k = 0; k < 3; k++) sum += a[k * 3 + row] * b[column * 3 + k];
        r[column * 3 + row] = sum;
      }
    }
    return r;
  }
  function Mat3(values) {
    this.m = Array.isArray(values) && values.length === 9 ? values.slice() : [1, 0, 0, 0, 1, 0, 0, 0, 1];
  }
  Mat3.identity = function () { return new Mat3(); };
  Mat3.fromTranslation = function (v) { return new Mat3([1, 0, 0, 0, 1, 0, v.x || 0, v.y || 0, 1]); };
  Mat3.fromScale = function (v) {
    var x = typeof v === 'number' ? v : v.x, y = typeof v === 'number' ? v : v.y;
    return new Mat3([x, 0, 0, 0, y, 0, 0, 0, 1]);
  };
  Mat3.fromRotation = function (angle) {
    var c = Math.cos(angle * DEGREE), s = Math.sin(angle * DEGREE);
    return new Mat3([c, s, 0, -s, c, 0, 0, 0, 1]);
  };
  Mat3.fromBasis = function (right, up) { return new Mat3([right.x, right.y, 0, up.x, up.y, 0, 0, 0, 1]); };
  Mat3.fromMat4 = function (other) {
    var m = other.m;
    return new Mat3([m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]]);
  };
  Mat3.compose = function (translation, rotation, scale) {
    return Mat3.fromTranslation(translation).multiply(Mat3.fromRotation(rotation)).multiply(Mat3.fromScale(scale));
  };
  Mat3.prototype.translation = function (position) {
    if (position) {
      this.m[6] = position.x || 0;
      this.m[7] = position.y || 0;
    }
    return new Vec2(this.m[6], this.m[7]);
  };
  Mat3.prototype.angle = function () { return Math.atan2(this.m[1], this.m[0]) / DEGREE; };
  Mat3.prototype.add = function (other) { var o = other.m; return new Mat3(this.m.map(function (v, i) { return v + o[i]; })); };
  Mat3.prototype.subtract = function (other) { var o = other.m; return new Mat3(this.m.map(function (v, i) { return v - o[i]; })); };
  Mat3.prototype.multiply = function (value) {
    if (typeof value === 'number') return new Mat3(this.m.map(function (v) { return v * value; }));
    if (value instanceof Mat3) return new Mat3(times3(this.m, value.m));
    var m = this.m, x = value.x || 0, y = value.y || 0, z = value.z === undefined ? 1 : value.z;
    return new Vec3(m[0] * x + m[3] * y + m[6] * z, m[1] * x + m[4] * y + m[7] * z, m[2] * x + m[5] * y + m[8] * z);
  };
  Mat3.prototype.translate = function (v) { return this.multiply(Mat3.fromTranslation(v)); };
  Mat3.prototype.rotate = function (angle) { return this.multiply(Mat3.fromRotation(angle)); };
  Mat3.prototype.scale = function (v) { return this.multiply(Mat3.fromScale(v)); };
  Mat3.prototype.transformPoint = function (v) {
    var m = this.m;
    return new Vec2(m[0] * v.x + m[3] * v.y + m[6], m[1] * v.x + m[4] * v.y + m[7]);
  };
  Mat3.prototype.transformDirection = function (v) {
    var m = this.m;
    return new Vec2(m[0] * v.x + m[3] * v.y, m[1] * v.x + m[4] * v.y);
  };
  Mat3.prototype.transpose = function () {
    var m = this.m;
    return new Mat3([m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]);
  };
  Mat3.prototype.determinant = function () {
    var m = this.m;
    return m[0] * (m[4] * m[8] - m[7] * m[5]) - m[3] * (m[1] * m[8] - m[7] * m[2]) + m[6] * (m[1] * m[5] - m[4] * m[2]);
  };
  Mat3.prototype.inverse = function () {
    var m = this.m, det = this.determinant();
    if (!det) return new Mat3();
    var d = 1 / det;
    return new Mat3([
      (m[4] * m[8] - m[5] * m[7]) * d, (m[2] * m[7] - m[1] * m[8]) * d, (m[1] * m[5] - m[2] * m[4]) * d,
      (m[5] * m[6] - m[3] * m[8]) * d, (m[0] * m[8] - m[2] * m[6]) * d, (m[2] * m[3] - m[0] * m[5]) * d,
      (m[3] * m[7] - m[4] * m[6]) * d, (m[1] * m[6] - m[0] * m[7]) * d, (m[0] * m[4] - m[1] * m[3]) * d
    ]);
  };
  Mat3.prototype.decompose = function () {
    var m = this.m;
    var sx = Math.sqrt(m[0] * m[0] + m[1] * m[1]), sy = Math.sqrt(m[3] * m[3] + m[4] * m[4]);
    if (this.determinant() < 0) sy = -sy;
    return { translation: new Vec2(m[6], m[7]), rotation: Math.atan2(m[1], m[0]) / DEGREE, scale: new Vec2(sx, sy) };
  };
  Mat3.prototype.copy = function () { return new Mat3(this.m); };
  Mat3.prototype.equals = function (other) {
    return !!other && other.m && this.m.every(function (v, i) { return Math.abs(v - other.m[i]) < 1e-6; });
  };
  Mat3.prototype.toString = function () { return this.m.join(' '); };

  // A direction from angles on a sphere — around and up, in degrees — and as far as said; and back.
  Vec3.fromSpherical = function (azimuth, elevation, radius) {
    var r = radius === undefined ? 1 : radius, a = (azimuth || 0) * DEGREE, e = (elevation || 0) * DEGREE;
    return new Vec3(r * Math.cos(e) * Math.cos(a), r * Math.sin(e), r * Math.cos(e) * Math.sin(a));
  };
  Vec3.prototype.toSpherical = function () {
    var r = this.length();
    return new Vec3(Math.atan2(this.z, this.x) / DEGREE, r > 0 ? Math.asin(Math.max(-1, Math.min(1, this.y / r))) / DEGREE : 0, r);
  };
  // Bent as light is through a surface, from one medium into one `ratio` times as dense.
  Vec3.prototype.refract = function (normal, ratio) {
    var cos = -this.dot(normal);
    var k = 1 - ratio * ratio * (1 - cos * cos);
    return k < 0 ? new Vec3(0, 0, 0) : this.multiply(ratio).add(normal.multiply(ratio * cos - Math.sqrt(k)));
  };

