  // Building: made by play() with what it shares (`ctx`), handing back what the rest of it uses.
  function makeBuilding(ctx) {
    var hearing = ctx.hearing, listen = ctx.listen, isSet = ctx.isSet, files = ctx.files, json = ctx.json, materialPass = ctx.materialPass, texture = ctx.texture, description = ctx.description, inDepth = ctx.inDepth, bands = ctx.bands;
    // --- Building ---------------------------------------------------------

    ctx.listening = false;



    ctx.all = (description.objects || []).filter(function (object) { return object && typeof object === 'object'; });
    if (!(ctx.sceneWidth > 0 && ctx.sceneHeight > 0) && inDepth && window.innerWidth > 0 && window.innerHeight > 0) {
      // A scene in three dimensions is seen through the screen, whatever its pictures: a
      // first one of 32 by 32 made 3509243656 a blur.
      ctx.sceneWidth = 1920;
      ctx.sceneHeight = Math.round(1920 * window.innerHeight / window.innerWidth);
    }
    if (!(ctx.sceneWidth > 0 && ctx.sceneHeight > 0)) {
      // A scene may leave its size to its first picture.
      var first = ctx.all.filter(function (object) { return object.image; })[0];
      var firstSize = first ? numbers(first.size, 2, 0) : [0, 0];
      if (first && !(firstSize[0] > 0 && firstSize[1] > 0)) {
        // One that is as large as its picture says so only in its picture: a frame of the GIF
        // of Wallpaper Engine's template (843532366, 480 by 300, its middle at 240, 150), or,
        // without a picture to tell, twice as far as the middle it is placed at.
        var firstModel = json(String(plain(first.image) || '')) || {};
        var firstPass = materialPass(firstModel.material) || {};
        var firstPicture = (firstPass.textures || [])[0] ? texture('materials/' + firstPass.textures[0]) : null;
        var firstFrame = firstPicture && firstPicture.frames && firstPicture.frames[0];
        firstSize = firstFrame ? [firstFrame[4], firstFrame[7]] : firstPicture && firstPicture.width > 1 ? [firstPicture.width, firstPicture.height]
                  : numbers(first.origin, 2, 0).map(function (part) { return part * 2; });
      }
      ctx.sceneWidth = firstSize[0] > 0 ? firstSize[0] : 1920;
      ctx.sceneHeight = firstSize[1] > 0 ? firstSize[1] : 1080;
    }
    // A scene with scripts may show what it has hidden; in any other, what is hidden for good
    // is left out.
    ctx.scripted = /"script"\s*:/.test(files['scene.json'] || '');

    return {};
  }

