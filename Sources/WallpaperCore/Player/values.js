  // ------------------------------------------------------------------ values

  // The wallpaper's settings as they are set now, by the names the scene knows them under.
  var properties = {};

  // A value as a scene gives it. One that a setting of the wallpaper, an animation or a script
  // stands behind is written as an object with the value inside; a setting, if the wallpaper
  // has it, takes the place of that value. A setting may also stand behind a yes or no by
  // being at one certain choice.
  function plain(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value) || !('value' in value || 'user' in value)) return value;
    var user = value.user;
    var name = user && typeof user === 'object' ? user.name : user;
    if (typeof name === 'string' && Object.prototype.hasOwnProperty.call(properties, name)) {
      var given = properties[name];
      if (user && typeof user === 'object' && user.condition !== undefined) return String(given) === String(user.condition);
      return given;
    }
    return value.value;
  }

  function number(value, fallback) {
    value = plain(value);
    if (typeof value === 'number' && isFinite(value)) return value;
    if (typeof value === 'string' && value.trim() !== '' && isFinite(Number(value))) return Number(value);
    if (typeof value === 'boolean') return value ? 1 : 0;
    return fallback;
  }

  // Several numbers written as one text, "990.000 540.000 0.000" or "0.0, 1.0", or one number
  // for them all.
  function numbers(value, count, fallback) {
    value = plain(value);
    var list = [];
    if (typeof value === 'number') {
      for (var i = 0; i < count; i++) list.push(value);
    } else if (typeof value === 'string') {
      list = value.split(/[\s,]+/).filter(function (part) { return part !== ''; }).map(Number).filter(function (n) { return isFinite(n); });
    } else if (Array.isArray(value)) {
      list = value.map(Number).filter(function (n) { return isFinite(n); });
    }
    var result = [];
    for (var j = 0; j < count; j++) {
      result.push(j < list.length ? list[j] : (Array.isArray(fallback) ? fallback[j] : fallback));
    }
    return result;
  }

  function flag(value, fallback) {
    value = plain(value);
    if (value === 'true' || value === '1') return true;
    if (value === 'false' || value === '0') return false;
    return typeof value === 'boolean' ? value : (typeof value === 'number' ? value !== 0 : fallback);
  }

  function key(name) {
    var plain = String(name).replace(/\\/g, '/').toLowerCase();
    return plain.normalize ? plain.normalize('NFC') : plain;
  }

