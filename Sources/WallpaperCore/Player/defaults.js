  // ------------------------------------------------------------------ defaults
  //
  // What a value is taken to be when a scene's file does not say it: one table, kept here once.
  // The app reads the same table (WallpaperEngineDefaults.swift), so what its editor shows of a
  // value left unsaid is what the player plays. The table is plain JSON, up to the last `;` of
  // this file, so that both can read it.
  //
  // object: what every object takes; text, sound, light: what objects of those kinds take.
  // particles: by part of a system — its emitters, what sets a new particle up (initializers, by
  // name, and what all of them take), what changes one as it lives (operators, likewise),
  // remapping, collisions, and the system's own values.
  var defaults = {
    "object": {
      "scale": 1,
      "angles": 0,
      "alpha": 1,
      "color": 1,
      "visible": true,
      "parallaxDepth": 1,
      "brightness": 1,
      "colorBlendMode": 0,
      "alignment": "center",
      "solid": true,
      "copybackground": true,
      "clampuvs": false,
      "queuemode": "sequential"
    },
    "text": {
      "text": "",
      "pointsize": 32,
      "horizontalalign": "center",
      "verticalalign": "center",
      "padding": 0,
      "opaquebackground": false,
      "backgroundcolor": 0,
      "limitwidth": false,
      "maxwidth": 0,
      "limitrows": false,
      "maxrows": 1,
      "limituseellipsis": false,
      "spacing": 0,
      "outline": false,
      "outlinecolor": 0,
      "outlinethickness": 1,
      "dropshadow": false,
      "dropshadowcolor": 0,
      "dropshadowoffset": 0,
      "dropshadowsize": 0,
      "dropshadowopacity": 1,
      "blur": false,
      "blursize": 0
    },
    "sound": {
      "startsilent": false,
      "mintime": 0,
      "maxtime": 0,
      "volume": 1,
      "playbackmode": "loop"
    },
    "light": {
      "light": "lpoint"
    },
    "particles": {
      "initializer": {
        "exponent": 1
      },
      "initializers": {
        "lifetimerandom": {
          "min": 1,
          "max": 1
        },
        "sizerandom": {
          "min": 20,
          "max": 20
        },
        "alpharandom": {
          "min": 1,
          "max": 1
        },
        "velocityrandom": {
          "min": 0,
          "max": 0
        },
        "rotationrandom": {
          "min": 0,
          "max": [
            0,
            0,
            6.283185307179586
          ]
        },
        "angularvelocityrandom": {
          "min": 0,
          "max": 0
        },
        "turbulentvelocityrandom": {
          "forward": [
            0,
            1,
            0
          ],
          "offset": 0,
          "scale": 1,
          "speedmin": 100,
          "speedmax": 250,
          "timescale": 1
        },
        "mapsequencearoundcontrolpoint": {
          "count": 1,
          "speedmin": 0,
          "speedmax": 0
        },
        "hsvcolorrandom": {
          "huemin": 0,
          "huemax": 1,
          "saturationmin": 0,
          "saturationmax": 1,
          "valuemin": 0,
          "valuemax": 1
        },
        "mapsequencebetweencontrolpoints": {
          "count": 2,
          "controlpointstart": 0,
          "controlpointend": 1
        },
        "positionoffsetrandom": {
          "distance": 0
        },
        "inheritcontrolpointvelocity": {
          "controlpoint": 0,
          "min": 1,
          "max": 1
        },
        "colorrandom": {
          "min": 255,
          "max": 255
        }
      },
      "remapping": {
        "inputrangemin": 0,
        "inputrangemax": 1,
        "outputrangemin": 0,
        "outputrangemax": 1,
        "inputcontrolpoint0": 0,
        "inputcontrolpoint1": 1
      },
      "operator": {
        "starttime": 0,
        "endtime": 1,
        "frequencymin": 0,
        "frequencymax": 10,
        "phasemin": 0,
        "phasemax": 6.283185307179586
      },
      "operators": {
        "movement": {
          "gravity": 0,
          "drag": 0
        },
        "angularmovement": {
          "force": 0,
          "drag": 0
        },
        "alphafade": {
          "fadeintime": 0.5,
          "fadeouttime": 0.5
        },
        "sizechange": {
          "startvalue": 1,
          "endvalue": 0
        },
        "alphachange": {
          "startvalue": 1,
          "endvalue": 0
        },
        "colorchange": {
          "startvalue": 1,
          "endvalue": 1
        },
        "oscillatealpha": {
          "scalemin": 0,
          "scalemax": 1
        },
        "oscillatesize": {
          "scalemin": 0.8,
          "scalemax": 1.2
        },
        "oscillateposition": {
          "mask": [
            1,
            1,
            0
          ],
          "scalemin": 1,
          "scalemax": 1
        },
        "turbulence": {
          "scale": 0.01,
          "timescale": 1,
          "speedmin": 100,
          "speedmax": 200,
          "mask": [
            1,
            1,
            0
          ]
        },
        "controlpointattract": {
          "controlpoint": 0,
          "scale": 0,
          "threshold": 0,
          "origin": 0
        },
        "vortex": {
          "controlpoint": 0,
          "offset": 0,
          "distanceinner": 0,
          "distanceouter": 0,
          "speedinner": 0,
          "speedouter": 0,
          "axis": [
            0,
            0,
            1
          ]
        },
        "remapvalue": {
          "transforminputscale": 1,
          "outputrangemin": 0,
          "outputrangemax": 1,
          "inputrangemin": 0,
          "inputrangemax": 1
        },
        "capvelocity": {
          "maxspeed": 100,
          "blendinstart": 0,
          "blendinend": 0
        },
        "reducemovementnearcontrolpoint": {
          "controlpoint": 0,
          "distanceinner": 0,
          "distanceouter": 100,
          "reductioninner": 1,
          "reductionouter": 0
        },
        "maintaindistancetocontrolpoint": {
          "controlpoint": 0,
          "distance": 100,
          "variablestrength": 5
        },
        "maintaindistancebetweencontrolpoints": {
          "controlpointstart": 0,
          "controlpointend": 1,
          "variablestrength": 5
        },
        "boids": {
          "neighborthreshold": 50,
          "cohesionfactor": 1,
          "separationfactor": 1,
          "alignmentfactor": 0
        }
      },
      "collision": {
        "origin": 0,
        "distance": 0,
        "size": 100,
        "radius": 100,
        "bouncefactor": 0.5,
        "bouncefactorslide": 0
      },
      "emitter": {
        "controlpoint": 0,
        "origin": 0,
        "directions": 1,
        "distancemin": 0,
        "distancemax": 256,
        "sign": 0,
        "rate": 5,
        "instantaneous": 0,
        "speedmin": 0,
        "speedmax": 0,
        "duration": 0,
        "delay": 0,
        "flags": 0
      },
      "system": {
        "maxcount": 100,
        "flags": 0,
        "sequencemultiplier": 1,
        "starttime": 0
      }
    }
  };
