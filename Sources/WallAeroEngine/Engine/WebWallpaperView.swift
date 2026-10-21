import AppKit
import CEFHost
import CoreServices
import WallpaperCore

/// Shows a web wallpaper — a scene or any page of the library — drawn by Chromium.
///
/// Pausing hides the page behind a still of itself: a hidden page stops its animations and its
/// timers, which is what saves the energy, whatever the page is made of.
@MainActor
final class WebWallpaperView: NSView, CEFPageViewDelegate {
    /// Called, on the main thread, when the wallpaper's files change on disk.
    var onContentChange: (() -> Void)?

    /// Set before `show` when the page is rendered for the still picture macOS shows on the lock
    /// screen: a scene then leaves out the layers that are not meant to appear there.
    var rendersStill = false

    /// Set before `show` to let the page have the spectrum of the sound the Mac is playing, if it
    /// asks for it. The wallpaper on the desktop and the editor's preview do; the pictures
    /// rendered off screen do not, and so never set the listening off.
    var hearsSound = false

    /// Called when the page has something to show: it has loaded and its videos have their
    /// first frame. Also called when the page fails to load, and a few seconds after `show` at
    /// the latest, so that whoever keeps the wallpaper out of sight until then never waits for good.
    var onReady: (() -> Void)?

    /// How many frames a second the page's scripts may draw; 0 leaves it to the screen. A page
    /// that draws itself frame by frame costs as much as it draws frames, and most are made to
    /// run at half the screen's sixty. May be changed while the page is shown.
    var frameRate = 0 {
        didSet {
            guard frameRate != oldValue, let webView, let project else { return }
            installUserScripts(in: webView, for: project)
            webView.frameRateLimit = Int32(drawingRate)
            webView.executeScript("window.__wallaeroDrawing && window.__wallaeroDrawing.setFrameRate(\(frameRate))")
        }
    }

    /// The part of the display's density the page is told of; 1 is all of it. A page sizes
    /// what it draws by the density: at 0.5 a canvas has half the width and height. Text and
    /// pictures of the page stay sharp, only what its scripts draw — canvases — is drawn
    /// smaller and stretched. A change shows once the page is loaded anew, which changing it
    /// while the page is shown does.
    var renderScale = 1.0 {
        didSet {
            guard renderScale != oldValue, webView != nil else { return }
            reloadPage()
        }
    }

    /// Makes the web engine refuse to start any video or sound by itself. Chromium is started
    /// with that allowed for every page, so this is kept only for the helper that sets it.
    var mediaNeedsUserAction = false

    // The scene editor shows its preview with this view too. These are set before `show`.
    /// A script added to the page after its own; its `wallaeroEditor` messages go to `onEditorMessage`.
    var editorScript: String?
    var onEditorMessage: (([String: Any]) -> Void)?
    /// The editor owns the scene and pushes it to the page itself. When this is set, a change of
    /// the scene file is reported here instead of being shown.
    var onSceneFileChange: (() -> Void)?

    private var webView: CEFPageView?
    private let stillView = NSImageView()
    /// A picture of the page, behind it. A web view is see-through until its page has drawn,
    /// and on a busy Mac — at login above all — that can take seconds; this picture is what is
    /// seen there then, instead of black. See `show` and `pageHasDrawn`.
    private let backdropView = NSView()
    private var project: WebProject?
    private var watcher: FolderWatcher?

    private var hasLoaded = false
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var isReady = false
    /// Tells a late answer that it belongs to a page that has since been loaded anew.
    private var loadGeneration = 0
    private static let longestWaitForPage: TimeInterval = 3
    private static let longestWaitForLoad: TimeInterval = 20
    private var isFrozen = false
    /// Tells a late snapshot or timer that the state it was made for is gone.
    private var freezeGeneration = 0

    // Requested playback state, applied once the page is there.
    private var isPlaying = false
    private var rate: Float = 1
    private var isMuted = true
    private var volume: Float = 1

    /// Whether the page has a listener for the sound, and whether it is being given any.
    private var pageWantsSound = false
    private var isHearingSound = false
    /// Whether the page wants to know what music plays, and whether it is being told.
    private var pageWantsMedia = false
    private var isToldMedia = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        autoresizingMask = [.width, .height]
        stillView.imageScaling = .scaleAxesIndependently
        stillView.autoresizingMask = [.width, .height]
        stillView.frame = bounds
        stillView.isHidden = true
        backdropView.wantsLayer = true
        backdropView.layer?.contentsGravity = .resizeAspectFill
        backdropView.layer?.masksToBounds = true
        backdropView.autoresizingMask = [.width, .height]
        backdropView.frame = bounds
        backdropView.isHidden = true
        addSubview(backdropView)
        addSubview(stillView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Content

    /// - Parameter backdrop: a picture of the page as it looked before, the library's own, to
    ///   be seen until the page has drawn itself.
    func show(_ project: WebProject, backdrop: NSImage? = nil, watchingForChanges: Bool = true) {
        unload()
        self.project = project
        backdropView.layer?.contents = backdrop
        backdropView.isHidden = backdrop == nil
        if project.isScene {
            // Scenes made by an older version of the app get the current page and runtime.
            _ = try? SceneProject.refreshGeneratedFiles(in: project.folder)
        }

        // Chromium starts with the first page it is to draw: a Mac showing only scenes and
        // videos never runs it.
        Chromium.start()
        let webView = CEFPageView(frame: bounds)
        webView.autoresizingMask = [.width, .height]
        webView.delegate = self
        // The page may load the files of its own folder and no others.
        webView.readableFolders = [project.folder.path]
        webView.frameRateLimit = Int32(drawingRate)
        webView.audioMuted = isMuted
        // The editor's preview is worked with the mouse; a wallpaper on the desktop is told of
        // the pointer by `PointerForwarder`.
        webView.forwardsMouse = editorScript != nil
        installUserScripts(in: webView, for: project)
        // See-through until the page has drawn: black, or the picture behind, shows instead of a
        // white flash.
        addSubview(webView, positioned: .below, relativeTo: stillView)
        self.webView = webView
        beginLoading()
        webView.load(project.entryURL)

        if watchingForChanges {
            watcher = FolderWatcher(folder: project.folder) { [weak self] paths in
                self?.filesDidChange(paths)
            }
        }
    }

    func unload() {
        watcher = nil
        freezeGeneration += 1
        loadGeneration += 1
        isReady = false
        webView?.delegate = nil
        webView?.close()
        webView?.removeFromSuperview()
        webView = nil
        project = nil
        hasLoaded = false
        isFrozen = false
        stillView.image = nil
        stillView.isHidden = true
        backdropView.isHidden = true
        backdropView.layer?.contents = nil
        pageWantsSound = false
        pageWantsMedia = false
        updateListening()
        resumeLoadWaiters()
    }

    /// Returns once the page has finished loading (or failed to), or after `longestWaitForLoad`
    /// whatever became of it: whoever waits — an import drawing a thumbnail — goes on in the end.
    func waitUntilLoaded() async {
        guard webView != nil, !hasLoaded else { return }
        await withCheckedContinuation { loadWaiters.append($0) }
    }

    /// Runs a script in the page, once it is there.
    func evaluate(_ script: String) {
        guard hasLoaded else { return }
        webView?.executeScript(script)
    }

    /// What a script evaluates to in the page; nil if it fails or the page is not there.
    func value(of script: String) async -> Any? {
        guard hasLoaded, let webView else { return nil }
        let json: String? = await withCheckedContinuation { continuation in
            webView.evaluateScript(script) { continuation.resume(returning: $0) }
        }
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Whether the page is hidden behind a still of itself, as it is while paused.
    var isShowingStill: Bool { !stillView.isHidden }

    /// A picture of the page as it looks now.
    func snapshot() async -> CGImage? {
        webView?.copySnapshot()
    }

    /// The page as last drawn, at the view's size in points.
    private func still() -> NSImage? {
        guard let image = webView?.copySnapshot() else { return nil }
        return NSImage(cgImage: image, size: bounds.size)
    }

    /// How many frames a second Chromium draws the page at: the app's rate, or else the screen's.
    private var drawingRate: Int {
        if frameRate > 0 { return frameRate }
        return max(60, window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60)
    }

    // MARK: - Playback settings

    func setPlaying(_ playing: Bool, rate: Float) {
        isPlaying = playing
        if rate != self.rate {
            self.rate = rate
            applyHostSettings()
        }
        applyPlaying()
        updateListening()
    }

    func setAudio(muted: Bool, volume: Float) {
        guard muted != isMuted || volume != self.volume else { return }
        isMuted = muted
        self.volume = volume
        webView?.audioMuted = muted
        applyHostSettings()
    }

    private func applyHostSettings() {
        guard hasLoaded else { return }
        webView?.executeScript("window.__wallaeroHost && window.__wallaeroHost.apply(\(hostSettingsJSON))")
    }

    /// What the page's media is to do: `playing` is false while the wallpaper is paused.
    private var hostSettingsJSON: String {
        "{rate: \(rate), muted: \(isMuted), volume: \(max(0, min(1, volume))), playing: \(!isFrozen)}"
    }

    private func applyPlaying() {
        guard hasLoaded, let webView else { return }
        if isPlaying, isFrozen {
            isFrozen = false
            freezeGeneration += 1
            let generation = freezeGeneration
            webView.pageHidden = false
            applyHostSettings() // lets the videos run again
            // The page takes a moment to draw again; the still covers it until then.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.freezeGeneration == generation else { return }
                self.stillView.isHidden = true
                self.stillView.image = nil
            }
        } else if !isPlaying, !isFrozen {
            isFrozen = true
            freezeGeneration += 1
            let generation = freezeGeneration
            applyHostSettings() // stands the videos still; hiding the page does not always
            // A moment for the videos' last frame to be drawn before the picture is taken.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.freezeGeneration == generation else { return }
                self.stillView.image = self.still()
                self.stillView.isHidden = false
                self.webView?.pageHidden = true
            }
        }
    }

    // MARK: - Pointer

    /// Tells the page what the mouse did; see `PointerForwarder`. The point is in the view,
    /// from its top left corner. A paused wallpaper is told nothing.
    func pointer(_ kind: PointerForwarder.Kind, at point: CGPoint) {
        guard hasLoaded, isPlaying, !isFrozen else { return }
        let place = String(format: "%.1f, %.1f", point.x, point.y)
        webView?.executeScript("window.__wallaeroHost && window.__wallaeroHost.pointer('\(kind.rawValue)', \(place))")
    }

    // MARK: - Sound

    private func hostMessage(_ message: [String: Any]) {
        if let wanted = message["sound"] as? Bool {
            pageWantsSound = wanted
            updateListening()
        }
        if let wanted = message["media"] as? Bool {
            pageWantsMedia = wanted
            updateListening()
        }
        if message["ready"] != nil {
            pageIsReady()
        }
        if message["drawn"] != nil {
            pageHasDrawn()
        }
    }

    private func updateListening() {
        updateSound()
        updateMedia()
    }

    /// The page is told what music plays while it asks and is playing; a paused one is told
    /// again when it plays.
    private func updateMedia() {
        let wanted = pageWantsMedia && hasLoaded && isPlaying
        guard wanted != isToldMedia else { return }
        isToldMedia = wanted
        if wanted {
            NowPlaying.shared.addListener(self) { [weak self] script in
                self?.webView?.executeScript(script)
            }
        } else {
            NowPlaying.shared.removeListener(self)
        }
    }

    /// The page is given the sound only while it asks for it and is playing: listening to the
    /// Mac for a paused wallpaper would be for nothing.
    private func updateSound() {
        let wanted = hearsSound && pageWantsSound && hasLoaded && isPlaying
        guard wanted != isHearingSound else { return }
        isHearingSound = wanted
        if wanted {
            SoundSpectrum.shared.addListener(self) { [weak self] script in
                self?.webView?.executeScript(script)
            }
        } else {
            SoundSpectrum.shared.removeListener(self)
        }
    }

    // MARK: - Loading

    private func beginLoading() {
        isReady = false
        loadGeneration += 1
        let generation = loadGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longestWaitForPage) { [weak self] in
            guard let self, self.loadGeneration == generation else { return }
            self.pageIsReady()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longestWaitForLoad) { [weak self] in
            guard let self, self.loadGeneration == generation, !self.hasLoaded, !self.loadWaiters.isEmpty else { return }
            Log.playback.error("The web wallpaper \(self.project?.folder.lastPathComponent ?? "?", privacy: .public) did not load in time")
            self.resumeLoadWaiters()
        }
    }

    private func pageIsReady() {
        guard !isReady, webView != nil else { return }
        isReady = true
        if !isFrozen {
            // The picture that covered a page loading anew has done its job.
            stillView.isHidden = true
            stillView.image = nil
        }
        onReady?()
    }

    /// The page has drawn frames of its own, so the picture behind it has done its job. It is
    /// taken away rather than left there: a page with see-through parts would show it for good.
    /// The frames take a moment more to reach the screen, hence the short wait.
    private func pageHasDrawn() {
        guard !backdropView.isHidden else { return }
        let generation = loadGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.loadGeneration == generation else { return }
            self.backdropView.isHidden = true
            self.backdropView.layer?.contents = nil
        }
    }

    /// A page is blank while it loads again. A picture of how it looked covers that; a paused
    /// wallpaper already has its still in front.
    private func coverWhileLoading() {
        guard stillView.isHidden, let image = still() else { return }
        stillView.image = image
        stillView.isHidden = false
    }

    // MARK: - Page set-up

    private func installUserScripts(in webView: CEFPageView, for project: WebProject) {
        var source = Self.bridgeScript.replacingOccurrences(of: "__HOST_SETTINGS__", with: hostSettingsJSON)
        if project.isScene, let scene = Self.sceneJSON(in: project.folder) {
            // File pages cannot fetch files, so the scene is handed to the runtime directly.
            source += "\nwindow.wallaeroScene = \(scene);"
        }
        if rendersStill {
            source += "\nwindow.wallaeroStill = true;"
        }
        let drawing = Self.drawingScript
            .replacingOccurrences(of: "__FRAME_RATE__", with: String(max(0, frameRate)))
            .replacingOccurrences(of: "__RENDER_SCALE__", with: String(max(0.05, min(1, renderScale))))
        var scripts = [
            CEFUserScript(source: drawing, atDocumentEnd: false, mainFrameOnly: false),
            CEFUserScript(source: source, atDocumentEnd: false, mainFrameOnly: true),
            CEFUserScript(source: Self.frameScript, atDocumentEnd: false, mainFrameOnly: false),
        ]
        if let editorScript {
            scripts.append(CEFUserScript(source: editorScript, atDocumentEnd: true, mainFrameOnly: true))
        }
        webView.userScripts = scripts
    }

    /// The scene file's text, if it is valid JSON; it goes to the page as is, unknown keys and all.
    private static func sceneJSON(in folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(SceneProject.sceneFileName)),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs before the page's own scripts. Keeps every video and sound of the page at the app's
    /// speed and volume, and stands in for the parts of Wallpaper Engine's API pages rely on.
    private static let bridgeScript = #"""
    (function () {
      var host = __HOST_SETTINGS__;
      function applyTo(media) {
        if (!(media instanceof HTMLMediaElement)) return;
        // A paused wallpaper's videos stand still at speed zero. Hiding the page stops its
        // scripts and animations, but a video goes on playing, unseen, if the window was covered
        // already when the page was hidden — as it is whenever windows over the desktop are why
        // the wallpaper pauses. Speed zero rather than a pause: a paused video in a hidden page
        // is dropped by the web engine and starts from its beginning afterwards.
        var rate = host.playing === false ? 0 : host.rate;
        if (media.playbackRate !== rate) {
          if (rate > 0) media.defaultPlaybackRate = rate;
          media.playbackRate = rate;
        }
        if (media.muted !== host.muted) media.muted = host.muted;
        // A sound of a Wallpaper Engine scene has a loudness of its own next to the scene's
        // other sounds; it gets that share of the wallpaper's volume.
        var volume = host.volume * (typeof media.wallaeroShare === 'number' ? media.wallaeroShare : 1);
        if (media.volume !== volume) media.volume = volume;
        // A muted video whose audio track is still enabled keeps the audio hardware running,
        // and with it the Mac awake. Switching the track off lets both rest.
        if (media.audioTracks) {
          var audible = !host.muted && host.volume > 0;
          for (var i = 0; i < media.audioTracks.length; i++) {
            if (media.audioTracks[i].enabled !== audible) media.audioTracks[i].enabled = audible;
          }
        }
        start(media);
      }
      // A video marked `autoplay` is started from here instead of by the web engine, which
      // may hold such a video back (a web engine does in some modes, such as WebKit in Low
      // Power Mode); `apply` is how the app does that once the page has loaded.
      var autoplaying = new WeakSet();
      function start(media) {
        if (media.autoplay) {
          media.autoplay = false;
          autoplaying.add(media);
        }
        if (autoplaying.has(media) && media.paused && !media.ended && !media.played.length) {
          var started = media.play();
          if (started && started.catch) started.catch(function () {});
        }
      }
      function applyAll() {
        var all = document.querySelectorAll('video, audio');
        for (var i = 0; i < all.length; i++) applyTo(all[i]);
      }
      // Media events do not bubble, but they can be caught on the way down.
      ['loadstart', 'loadedmetadata', 'play', 'ratechange'].forEach(function (name) {
        document.addEventListener(name, function (event) { applyTo(event.target); }, true);
      });
      // A page made for Wallpaper Engine is told when the wallpaper pauses and plays again, so
      // that it can stop what it does on timers; so is such a page in a frame, as the background
      // of a scene.
      var paused = false;
      function tellPaused() {
        if ((host.playing === false) === paused) return;
        paused = !paused;
        var pages = [window];
        Array.prototype.forEach.call(document.querySelectorAll('iframe'), function (frame) { pages.push(frame.contentWindow); });
        pages.forEach(function (page) {
          try {
            var listener = page.wallpaperPropertyListener;
            if (listener && typeof listener.setPaused === 'function') listener.setPaused(paused);
          } catch (error) {}
        });
      }
      window.__wallaeroHost = {
        apply: function (settings) {
          for (var key in settings) host[key] = settings[key];
          applyAll();
          tellPaused();
        },
        // For a page that knows the app: a video to be played without ever being marked `autoplay`.
        autoplay: function (media) {
          autoplaying.add(media);
          applyTo(media);
        },
        pointer: function (kind, x, y) { pointer(kind, x, y); },
        // The speed the wallpaper plays at, for what on the page keeps its own time.
        get rate() { return host.playing === false ? 0 : host.rate; }
      };
      // The pointer. A wallpaper lies under the desktop's icons, so the web engine gets no
      // mouse for it; the app says where the pointer is over the desktop and when its button
      // goes down and comes up, and the page is sent the events a mouse would have made.
      var pressedOn = [];  // what the button went down on
      var lastOver = [];   // what the pointer was last over
      function placesAt(x, y) {
        var places = [];
        function look(page, view, x, y) {
          var element = page.elementFromPoint(x, y) || page.documentElement;
          if (element.tagName === 'IFRAME') {
            try {
              var box = element.getBoundingClientRect();
              if (element.contentDocument) return look(element.contentDocument, element.contentWindow, x - box.left, y - box.top);
            } catch (error) {}
          }
          places.push({ element: element, view: view, x: x, y: y });
        }
        look(document, window, x, y);
        // The page of a scene lies behind the scene's layers. It gets the pointer too when a
        // layer is over it: the page is the wallpaper, the layer only stands on it.
        var behind = document.querySelector('#wallaero-background > iframe');
        if (behind && places[0].view === window) {
          try {
            var frame = behind.getBoundingClientRect();
            look(behind.contentDocument, behind.contentWindow, x - frame.left, y - frame.top);
          } catch (error) {}
        }
        return places;
      }
      function send(place, names, buttons) {
        names.forEach(function (name) {
          var isPointer = name.indexOf('pointer') === 0;
          // Made in the page the event goes to, so that the page takes it for one of its own.
          var Event = isPointer ? place.view.PointerEvent : place.view.MouseEvent;
          if (!Event || !place.element.isConnected) return;
          var details = { bubbles: true, cancelable: true, composed: true, view: place.view, detail: name === 'click' ? 1 : 0,
                          clientX: place.x, clientY: place.y, screenX: place.x, screenY: place.y, button: 0, buttons: buttons };
          if (isPointer) {
            details.pointerId = 1;
            details.pointerType = 'mouse';
            details.isPrimary = true;
            details.pressure = buttons ? 0.5 : 0;
          }
          try {
            place.element.dispatchEvent(new Event(name, details));
          } catch (error) {
            console.error(error);
          }
        });
      }
      function pointer(kind, x, y) {
        if (kind === 'leave') {
          lastOver.forEach(function (place) { send(place, ['pointerout', 'pointerleave', 'mouseout', 'mouseleave'], 0); });
          lastOver = [];
          return;
        }
        var places = placesAt(x, y);
        if (kind === 'down') {
          pressedOn = places;
          places.forEach(function (place) { send(place, ['pointerdown', 'mousedown'], 1); });
        } else if (kind === 'up') {
          places.forEach(function (place, index) {
            send(place, ['pointerup', 'mouseup'], 0);
            // A click is a press and a release on the same thing.
            if (pressedOn[index] && pressedOn[index].element === place.element) send(place, ['click'], 0);
          });
          pressedOn = [];
        } else {
          places.forEach(function (place) { send(place, ['pointermove', 'mousemove'], pressedOn.length ? 1 : 0); });
        }
        lastOver = places;
      }
      // The app keeps a wallpaper out of sight until there is something to see, and a page
      // that loads anew covered until then. It is told when the page has loaded and every
      // video on it has its first frame.
      window.addEventListener('load', function () {
        var waiting = 1;
        function settle() {
          if (--waiting > 0) return;
          var told = false;
          function post(message) {
            try {
              window.webkit.messageHandlers.wallaeroHost.postMessage(message);
            } catch (error) {}
          }
          function tell() {
            if (told) return;
            told = true;
            post({ ready: true });
          }
          // Two frames on, the picture has been drawn, and the app is told so apart from being
          // told the page is ready: a hidden page draws no frames, hence the timer, and on a
          // busy Mac the timer comes first while there is still nothing to see.
          requestAnimationFrame(function () {
            requestAnimationFrame(function () {
              tell();
              post({ drawn: true });
            });
          });
          setTimeout(tell, 150);
        }
        Array.prototype.forEach.call(document.querySelectorAll('video'), function (video) {
          if (video.readyState >= 2 || video.error || !(video.currentSrc || video.src)) return;
          waiting++;
          var counted = false;
          function once() {
            if (counted) return;
            counted = true;
            settle();
          }
          video.addEventListener('loadeddata', once);
          video.addEventListener('error', once);
        });
        settle();
      });
      // Wallpaper Engine's way for a page to follow the sound: the listener gets 128 numbers,
      // 64 bands of the left channel and 64 of the right, low notes first, each from 0 to 1.
      // Here they describe whatever the Mac is playing. The app is told when a page listens,
      // so the Mac's sound is not picked up for pages that have no use for it.
      var soundListeners = [];
      function tellAboutSound() {
        try {
          window.webkit.messageHandlers.wallaeroHost.postMessage({ sound: soundListeners.length > 0 });
        } catch (error) {}
      }
      window.wallpaperRegisterAudioListener = function (listener) {
        if (typeof listener !== 'function') return;
        // A scene's layer is rebuilt when it is edited; `owner` is the element whose script is
        // registering, so that the listener goes when the element does.
        soundListeners.push({ call: listener, owner: window.__wallaeroHost.owner || null });
        if (soundListeners.length === 1) tellAboutSound();
      };
      window.__wallaeroHost.sound = function (levels) {
        var kept = soundListeners.filter(function (entry) { return !entry.owner || entry.owner.isConnected; });
        if (kept.length !== soundListeners.length) {
          soundListeners = kept;
          if (!kept.length) tellAboutSound();
        }
        kept.forEach(function (entry) {
          try {
            entry.call(levels);
          } catch (error) {
            console.error(error);
          }
        });
      };
      // What music plays, as Wallpaper Engine tells its pages: whether there is any, what it
      // is, its cover and the colors of it, whether it plays, and where it has got to. The app
      // is asked for it once a page listens.
      window.wallpaperMediaIntegration = { PLAYBACK_STOPPED: 0, PLAYBACK_PLAYING: 1, PLAYBACK_PAUSED: 2 };
      var mediaListeners = [];
      var media = null;
      function tellAboutMedia() {
        try {
          window.webkit.messageHandlers.wallaeroHost.postMessage({ media: mediaListeners.length > 0 });
        } catch (error) {}
      }
      function css(color) {
        var parts = Array.isArray(color) ? color : [0, 0, 0];
        return 'rgb(' + parts.slice(0, 3).map(function (part) { return Math.round(Math.max(0, Math.min(1, part)) * 255); }).join(', ') + ')';
      }
      // What a listener of each kind is told of the music as it is now.
      function mediaEvent(kind, from) {
        if (kind === 'status') return { enabled: !!from.enabled };
        if (kind === 'properties') {
          return { title: from.title || '', artist: from.artist || '', subTitle: from.subTitle || '', albumTitle: from.albumTitle || '',
                   albumArtist: from.albumArtist || '', genres: from.genres || '', contentType: from.contentType || '' };
        }
        if (kind === 'thumbnail') {
          var colors = from.colors || {};
          return { thumbnail: from.thumbnail || '', primaryColor: css(colors.primary), secondaryColor: css(colors.secondary),
                   tertiaryColor: css(colors.tertiary), textColor: css(colors.text || [1, 1, 1]),
                   highContrastColor: css(colors.highContrast || [1, 1, 1]) };
        }
        if (kind === 'playback') return { state: from.state || 0 };
        return { position: from.position || 0, duration: from.duration || 0 };
      }
      function tellMedia(kind, event) {
        var kept = mediaListeners.filter(function (entry) { return !entry.owner || entry.owner.isConnected; });
        if (kept.length !== mediaListeners.length) {
          mediaListeners = kept;
          if (!kept.length) tellAboutMedia();
        }
        kept.forEach(function (entry) {
          if (entry.kind !== kind) return;
          try {
            entry.call(event);
          } catch (error) {
            console.error(error);
          }
        });
      }
      function registerMedia(kind) {
        return function (listener) {
          if (typeof listener !== 'function') return;
          var entry = { kind: kind, call: listener, owner: window.__wallaeroHost.owner || null };
          mediaListeners.push(entry);
          if (mediaListeners.length === 1) tellAboutMedia();
          // One that comes late hears at once how things stand.
          if (media) setTimeout(function () {
            try { listener(mediaEvent(kind, media)); } catch (error) { console.error(error); }
          }, 0);
        };
      }
      window.wallpaperRegisterMediaStatusListener = registerMedia('status');
      window.wallpaperRegisterMediaPropertiesListener = registerMedia('properties');
      window.wallpaperRegisterMediaThumbnailListener = registerMedia('thumbnail');
      window.wallpaperRegisterMediaPlaybackListener = registerMedia('playback');
      window.wallpaperRegisterMediaTimelineListener = registerMedia('timeline');
      window.__wallaeroHost.media = function (message) {
        if (message.timeline) {
          if (media) {
            media.position = message.timeline.position;
            media.duration = message.timeline.duration;
          }
          tellMedia('timeline', mediaEvent('timeline', message.timeline));
          return;
        }
        var before = media;
        media = message;
        // Each kind of listener hears of what has changed for it; at first, of everything.
        ['status', 'properties', 'thumbnail', 'playback'].forEach(function (kind) {
          var event = mediaEvent(kind, message);
          if (!before || JSON.stringify(event) !== JSON.stringify(mediaEvent(kind, before))) tellMedia(kind, event);
        });
        tellMedia('timeline', mediaEvent('timeline', message));
      };
    })();
    """#

    /// Runs first, in the page and in every page in a frame of it. Keeps what the page's scripts
    /// draw within the frame rate and the density the app allows.
    ///
    /// A page draws by asking for the next frame of the screen, sixty times a second. Here it
    /// is let through as often as the app's frame rate has it and left waiting the rest of the
    /// time, so a frame not let through costs nothing: nothing is drawn, and the web engine
    /// has nothing new to put on the screen. Videos and animations written in CSS are not
    /// drawn by scripts and go on as they are.
    private static let drawingScript = #"""
    (function () {
      var drawing = window.__wallaeroDrawing = {
        frameRate: __FRAME_RATE__,
        // Tells this page and the pages in its frames.
        setFrameRate: function (rate) {
          drawing.frameRate = rate;
          for (var i = 0; i < window.frames.length; i++) {
            try {
              window.frames[i].__wallaeroDrawing.setFrameRate(rate);
            } catch (error) {}
          }
        }
      };
      var request = window.requestAnimationFrame;
      if (typeof request === 'function') {
        request = request.bind(window);
        var waiting = new Map(); // what the page asked to be called with the next frame
        var lastId = 0;
        var asked = false;
        var last = -1e9;
        var frame = function (now) {
          asked = false;
          var rate = drawing.frameRate;
          if (rate > 0) {
            var interval = 1000 / rate;
            var elapsed = now - last;
            // Too soon after the frame before: the page waits for the screen's next one. The
            // few milliseconds off allow for frames of the screen that come a little early.
            if (elapsed < interval - 3) {
              asked = true;
              request(frame);
              return;
            }
            // Kept in step with the rate rather than with this frame, so that being late once
            // does not make every frame after it late.
            var late = elapsed - interval;
            last = late > 0 && late < interval ? now - late : now;
          }
          var callbacks = waiting;
          waiting = new Map();
          callbacks.forEach(function (callback) {
            try {
              callback(now);
            } catch (error) {
              // Reported as the page's own error, without keeping the other callbacks back.
              setTimeout(function () { throw error; });
            }
          });
        };
        window.requestAnimationFrame = function (callback) {
          waiting.set(++lastId, callback);
          if (!asked) {
            asked = true;
            request(frame);
          }
          return lastId;
        };
        window.cancelAnimationFrame = function (id) { waiting.delete(id); };
      }
      // The density the page is told of: this part of the display's own.
      var scale = __RENDER_SCALE__;
      if (scale > 0 && scale < 1) {
        var own = Object.getOwnPropertyDescriptor(window, 'devicePixelRatio') ||
                  Object.getOwnPropertyDescriptor(Object.getPrototypeOf(window), 'devicePixelRatio');
        var real = window.devicePixelRatio;
        try {
          Object.defineProperty(window, 'devicePixelRatio', {
            configurable: true,
            enumerable: true,
            get: function () { return (own && own.get ? own.get.call(window) : real) * scale; }
          });
        } catch (error) {}
      }
    })();
    """#

    /// What a page in a frame is given: a scene shows a wallpaper made for Wallpaper Engine in
    /// one. Such a page asks for the sound like any other; the page on top hears it for it,
    /// and the listener goes when the frame does.
    private static let frameScript = #"""
    (function () {
      if (window === window.top) return;
      window.wallpaperRegisterAudioListener = function (listener) {
        if (typeof listener !== 'function') return;
        try {
          var host = window.top.__wallaeroHost;
          var owner = host.owner;
          host.owner = window.frameElement;
          window.top.wallpaperRegisterAudioListener(listener);
          host.owner = owner;
        } catch (error) {}
      };
      window.wallpaperMediaIntegration = { PLAYBACK_STOPPED: 0, PLAYBACK_PLAYING: 1, PLAYBACK_PAUSED: 2 };
      ['wallpaperRegisterMediaStatusListener', 'wallpaperRegisterMediaPropertiesListener',
       'wallpaperRegisterMediaThumbnailListener', 'wallpaperRegisterMediaPlaybackListener',
       'wallpaperRegisterMediaTimelineListener'].forEach(function (name) {
        window[name] = function (listener) {
          if (typeof listener !== 'function') return;
          try {
            var host = window.top.__wallaeroHost;
            var owner = host.owner;
            host.owner = window.frameElement;
            window.top[name](listener);
            host.owner = owner;
          } catch (error) {}
        };
      });
    })();
    """#

    // MARK: - CEFPageViewDelegate

    func pageView(_ view: CEFPageView, didFinishLoadingWithError error: String?) {
        guard view === webView else { return }
        if let error {
            Log.playback.error("Cannot show the web wallpaper \(self.project?.folder.lastPathComponent ?? "?", privacy: .public): \(error, privacy: .public)")
            pageDidSettle()
            pageIsReady()
            return
        }
        if let properties = project?.userPropertiesJSON {
            // The wallpaper's own settings, at the values its author chose.
            view.executeScript("""
            (function (properties) {
              var listener = window.wallpaperPropertyListener;
              if (listener && typeof listener.applyUserProperties === 'function') listener.applyUserProperties(properties);
            })(\(properties));
            """)
        }
        pageDidSettle()
    }

    func pageView(_ view: CEFPageView, didReceiveMessage json: String, forHandler handler: String) {
        guard view === webView, let data = json.data(using: .utf8),
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return
        }
        switch handler {
        case "wallaeroHost": hostMessage(message)
        case "wallaeroEditor": onEditorMessage?(message)
        default: break
        }
    }

    private func pageDidSettle() {
        hasLoaded = true
        applyHostSettings()
        updateListening()
        resumeLoadWaiters()
        if isPlaying {
            applyPlaying()
        } else {
            // Paused from the start: let the page draw its first frame, then freeze on it.
            let generation = freezeGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, self.freezeGeneration == generation else { return }
                self.applyPlaying()
            }
        }
    }

    private func resumeLoadWaiters() {
        let waiters = loadWaiters
        loadWaiters = []
        waiters.forEach { $0.resume() }
    }

    // MARK: - Live reload

    private func filesDidChange(_ paths: [String]) {
        guard let project, let webView else { return }
        // Saving a file safely writes a hidden temporary one first and renames it; those are not
        // changes to the wallpaper, and neither is Finder's own bookkeeping.
        let names = Set(paths.map { ($0 as NSString).lastPathComponent }).filter { !$0.hasPrefix(".") && !$0.contains(".sb-") }
        guard !names.isEmpty else { return }
        if project.isScene, names == [SceneProject.sceneFileName] {
            if let onSceneFileChange {
                onSceneFileChange()
                return
            }
            // Only the scene changed: redraw it in place, so the video does not start over.
            installUserScripts(in: webView, for: project)
            if let scene = Self.sceneJSON(in: project.folder) {
                webView.executeScript("window.wallaero && window.wallaero.setScene(\(scene))")
            }
        } else {
            reloadPage()
        }
        onContentChange?()
    }

    /// Loads the page anew, from its files as they are now, behind a picture of how it looked.
    private func reloadPage() {
        guard let project, let webView, let reread = WebProject(folder: project.folder) else { return }
        self.project = reread
        installUserScripts(in: webView, for: reread)
        hasLoaded = false
        pageWantsSound = false
        pageWantsMedia = false
        updateListening()
        beginLoading()
        coverWhileLoading()
        webView.pageHidden = false
        isFrozen = false
        freezeGeneration += 1
        webView.readableFolders = [reread.folder.path]
        webView.load(reread.entryURL)
    }
}

/// Reports changes to the files of a folder, at any depth, a moment after they happen.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let handler: ([String]) -> Void

    init?(folder: URL, handler: @escaping ([String]) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info, let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handler(Array(paths.prefix(count)))
        }
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                               FSEventStreamCreateFlags(flags)) else {
            return nil
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
