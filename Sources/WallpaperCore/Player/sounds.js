  // Sounds: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeSounds(ctx) {
    var soundFiles = ctx.soundFiles, live = ctx.live, also = ctx.also, standing = ctx.standing, mix = ctx.mix;
    // --- Sounds -----------------------------------------------------------

    ctx.players = [];

    // A sound of the scene plays as the page's own sound would: the app decides whether it is
    // heard and how loud, as for any wallpaper, and the scene how loud next to its other sounds.
    function buildSound(object, thing) {
      var list = (Array.isArray(object.sound) ? object.sound : [object.sound]).map(function (name) {
        return soundFiles[key(String(plain(name) || ''))];
      }).filter(Boolean);
      var name = thing.name;
      if (!list.length) {
        note('“' + name + '”: its sound is not in the scene');
        return null;
      }
      also(thing, 'volume', live(object.volume, 1, 1, thing));
      var mode = key(plain(object.playbackmode) || 'loop');
      var least = number(object.mintime, 0), most = number(object.maxtime, 0);
      var audio = document.createElement('audio');
      var index = 0;
      var timer = 0;
      var wanted = !flag(object.startsilent, false); // until a script says otherwise
      var loud = -1;
      audio.style.display = 'none';
      audio.preload = 'auto';
      audio.loop = mode === 'loop' && list.length === 1;

      function start() {
        var started = audio.play();
        if (started && started['catch']) started['catch'](function () {});
      }
      audio.addEventListener('ended', function () {
        if (ctx.stopped) return;
        if (mode === 'single') {
          wanted = false;
          return;
        }
        // The next one, or any one after a pause, as the scene says.
        index = mode === 'random' ? Math.floor(Math.random() * list.length) : (index + 1) % list.length;
        timer = setTimeout(function () {
          audio.src = encodeURI(list[index]);
          if (wanted && standing(thing).visible) start();
        }, mode === 'random' ? mix(least, most, Math.random()) * 1000 : 0);
      });
      audio.addEventListener('error', function () { note('“' + name + '”: this web engine cannot play ' + list[index].replace(/^.*\./, '.') + ' sound'); });
      if (mode === 'random') index = Math.floor(Math.random() * list.length);

      // Plays while the scene shows the object, it is not turned all the way down and nothing
      // has stopped it, as loud as the scene says: a share of what the app lets the wallpaper have.
      thing.settle = function () {
        var share = Math.max(0, Math.min(1, thing.state.volume[0]));
        if (share !== loud) {
          loud = share;
          audio.wallaeroShare = share;
          var host = window.__wallaeroHost;
          if (host && host.apply) host.apply({});
          else audio.volume = share;
        }
        // One turned all the way down is not played at all: playing it unheard keeps the
        // Mac's sound awake for nothing.
        var sounds = wanted && share > 0 && standing(thing).visible;
        if (sounds && audio.paused && !audio.ended) start();
        if (!sounds && !audio.paused) audio.pause();
      };
      thing.sound = {
        play: function () {
          wanted = true;
          if (audio.ended) audio.currentTime = 0;
          thing.settle();
        },
        pause: function () {
          wanted = false;
          thing.settle();
        },
        stop: function () {
          wanted = false;
          thing.settle();
          try {
            audio.currentTime = 0;
          } catch (error) {}
        },
        isPlaying: function () { return !audio.paused && !audio.ended; }
      };
      audio.src = encodeURI(list[index]);
      document.body.appendChild(audio);
      ctx.players.push({ audio: audio, stop: function () { clearTimeout(timer); audio.pause(); audio.remove(); } });
      thing.draw = thing.settle;
      thing.settle();
      return thing;
    }

    return { buildSound: buildSound };
  }

