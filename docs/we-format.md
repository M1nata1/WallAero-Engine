# Wallpaper Engine's format: where each rule is implemented

Every rule of Wallpaper Engine's scene format the app knows, and the side that implements it.
The split (architecture plan, stage 5):

- **Swift**: whatever does not change while a scene plays. That covers the binary files (`.pkg`,
  `.tex`, `.mdl`), the shape of the JSON, default values, how materials and effects inherit,
  and the names of files. The player is handed the scene already read.
- **The player (JS)**: whatever is worked out while a scene plays. That covers settings, combos,
  curves, bones and scripts. When the editor needs one of these values, Swift asks the same JS
  code for it instead of keeping a copy.

A row marked **both** is a rule written twice. Stage 5 is done when no row says **both**.

Last surveyed: 2026-11-19, on `WallAero-Engine-v-4.1` (after v4.0).

## Read once (belongs to Swift)

| # | Rule | Swift | Player | Now | Goes to |
|---|------|-------|--------|-----|---------|
| 1 | `.pkg` package: entries, offsets | `WallpaperEnginePackage` | — | Swift | Swift |
| 2 | `.tex` texture: formats, mipmaps, LZ4, DXT, sprite frames, embedded video | `WallpaperEngineTexture` | reads what files.json says (`pictures`, `frames`, `video`) | Swift | Swift |
| 3 | `.mdl` puppet and model: corners, bones, weights, animations, IK, blend shapes | `WallpaperEnginePuppet`, `WallpaperEnginePuppetRig.mdl` | plays the numbers handed over | Swift | Swift |
| 4 | File names: Windows case, `\` as `/`, composed accents | `WallpaperEngineScene.key`, `WallpaperEngineDocument.key` | `key()` on every name it looks up | **both** | Swift: the read scene carries normalized names only |
| 5 | A value's shape: plain, or `{value, user, animation, script}`; `user` as a name or `{name, condition}` | `JSONValue.plain`, `EngineUserProperties`, `WallpaperEngineScript.rawValue`, `WallpaperEngineAnimation.rawValue`, `WallpaperEngineScene.settingNames` | `plain()`, `values.js`, `live-values.js` | **both** | Swift: each value arrives in one shape, with what stands behind it named |
| 6 | Object defaults: origin 0, scale 1, angles 0, alpha 1, color 1, visible, size, parallax | `EngineTimelineView` (`fallback:`), `EngineEditorBindings` (`default:`) | `numbers(x, n, fallback)` in `pictures.js`, `models.js`, `particles.js`, `texts.js`, `camera.js` | **both** | Swift |
| 7 | Particle component defaults: emitter rate and distances, initializer ranges, operator times | `ParticleComponentKind.all` (`EngineParticleEditor`) | `particles.js` (`number(said.min, 20)` and others) | **both** | Swift |
| 8 | Material inheritance: model → material → `passes[0]`; textures by slot (instance, then `usertextures`, then own); `blending`, `depthtest` | `WallpaperEngineMask.effectTexture`, `WallpaperEnginePuppetRig` (material combos) | `pictures.js` `buildImage`, `models.js` (2 places), `particles.js`, `building.js` | **both** (and five times in JS) | Swift |
| 9 | Effect inheritance: effect file → passes → each pass's material; scene pass overrides `combos`, `constantshadervalues`, `textures`, `usertextures`; `fbos`; `bind`; `command: copy` | `WallpaperEngineEffects` (writes its own), `WallpaperEngineMask` (slots) | `pictures.js` `buildEffects`, `player-api.js` `describeEffect`, `editor.js` | **both** (three times in JS) | Swift |
| 10 | Scene size: `general.orthogonalprojection`, else the first picture's size (its frame, its texture, twice its origin), else 1920×1080; 3D scenes 1920 wide | `WallpaperEngineDocument.size` (only 1920×1080 as fallback) | `building.js` | **both, and they differ** | Swift, using the player's rule (it matches WE) |
| 11 | Lights counted into `general.lightconfig` | `WallpaperEngineDocument+Objects` | — | Swift | Swift |
| 12 | Settings a scene uses: `user` names, names in scripts | `WallpaperEngineScene.settingNames` | — | Swift | Swift |
| 13 | What is left out (models that cannot be read, puppets without bones) | `WallpaperEngineScene.leftOut` | — | Swift | Swift |
| 14 | Shader annotations: a uniform's JSON comment (`material`, `default`, `combo`, `require`, `options`), default texture of a slot | — | `glsl.js` `annotations`, `effects.js` | Player | Player for now; stage 8 (one shader translator) |
| 15 | An effect described for the editor: values, switches, masks | — | `player-api.js` `describeEffect` | Player | stays with 14 |

## Worked out while playing (belongs to the player)

| # | Rule | Swift | Player | Now | Goes to |
|---|------|-------|--------|-----|---------|
| 16 | Timeline curve: keys, handles, `magic`, modes loop/mirror/single, `wraploop`, `relative` | `WallpaperEngineAnimation.numbers`, `.reach`, `span`, `along` (editor timeline and inspector) | `curves.js` `curveOf` | **both** | Player; the editor asks it through a light `JSContext` |
| 17 | Bones: hierarchy to world transforms, skinning of the corners | `WallpaperEnginePuppetRig.posedPoints`, `posedTransforms`, `localPoses` (rig editor overlay) | `puppets.js` | **both** | Player for skinning (the editor asks through the `bones` query); the editor's own keys and how they ease stay in Swift, which bakes them into the `.mdl` |
| 18 | A value bound to a setting with a choice: `user.condition` equals the setting | writes it (`EngineUserProperties`) | `values.js` | Player | Player |
| 19 | Shader combos and `#if` | — | `glsl.js` | Player | Player (stage 8) |
| 20 | Scripts: their API, expressions, declared properties | reads what the player found (`WallpaperEngineScriptSetting`) | `scene-scripts.js`, `script-math.js`, `scripts.js` | Player | Player |
| 21 | Audio response, pointer, parallax, camera paths, fog | — | `hearing.js`, `mouse.js`, `pointer-moves.js`, `camera.js`, `models.js` | Player | Player |

## Not a scene rule

| # | Rule | Swift | Player | Note |
|---|------|-------|--------|------|
| 22 | When a setting is shown in the settings window: `project.json` `condition`, an Angular expression | `WallpaperEngineCondition` | — | The plan proposed making this a wrapper over the player. The player never evaluates it, because it only decides what the settings window shows. So it has one implementation and stays in Swift. |

## Order of work

1. Shared cases first. `Tests/Fixtures/we-format/<rule>.json` gives the input and the expected
   result. For a **both** row, both implementations must pass the same file before either is
   removed.
2. Runtime rows (16, 17). The editor calls the player's code, and the Swift copy goes.
3. Static rows (4–10), one at a time. Swift writes the read scene into `files.json` (format 2) and
   the player stops reading the raw `scene.json`, materials and effects for that rule. The
   editor's live changes (`setSceneFile`, `setFiles`, `editorUpdate`) go through the same Swift
   reading before they reach the player.
4. Each step is checked with `scripts/compare.sh` and against Wallpaper Engine (`scripts/we/`).
