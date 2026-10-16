// The app's side of Chromium: starting it, keeping its work going on the main run loop, and
// pages drawn off screen whose frames are shown in a layer.

#import "CEFHost.h"

#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>

#include <map>
#include <mutex>
#include <string>
#include <vector>

#include "Shared.h"
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/wrapper/cef_library_loader.h"

@class CEFPageView;

@interface CEFPageView ()
- (void)browserCreated:(CefRefPtr<CefBrowser>)browser;
- (void)browserClosed;
- (void)loadEnded:(int)httpStatus;
- (void)loadFailed:(NSString *)error;
- (void)received:(CefRefPtr<CefProcessMessage>)message;
- (void)paintSurface:(IOSurfaceRef)surface;
- (CGSize)pageSize;
- (CGFloat)pageScale;
@end

namespace {

bool gRunning = false;
bool gLibraryLoaded = false;

// MARK: - The message loop

// Chromium's work for the app's process is done on the main run loop, when Chromium asks for it
// and a few times a second besides.
class Pump {
 public:
  static void Schedule(int64_t delayMs) {
    dispatch_async(dispatch_get_main_queue(), ^{
      ScheduleOnMain(delayMs);
    });
  }

  static void ScheduleOnMain(int64_t delayMs) {
    if (!gRunning) {
      return;
    }
    if (delayMs <= 0) {
      DoWork();
      return;
    }
    if (delayMs > 1000 / 30) {
      delayMs = 1000 / 30;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
      DoWork();
    });
  }

  static void DoWork() {
    static bool working = false;
    if (!gRunning || working) {
      return;
    }
    working = true;
    CefDoMessageLoopWork();
    working = false;
  }
};

// MARK: - The app in the app's process

class BrowserApp : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

  void OnBeforeCommandLineProcessing(const CefString& process_type,
                                     CefRefPtr<CefCommandLine> command_line) override {
    wallaero::AddCommonSwitches(command_line);
  }

  void OnScheduleMessagePumpWork(int64_t delay_ms) override { Pump::Schedule(delay_ms); }

  IMPLEMENT_REFCOUNTING(BrowserApp);
};

// MARK: - A page's client

// Hands what Chromium says about a page to its view. Holds the view weakly: a view that is gone
// has nothing more to hear.
class PageClient : public CefClient,
                   public CefRenderHandler,
                   public CefLifeSpanHandler,
                   public CefLoadHandler,
                   public CefRequestHandler,
                   public CefResourceRequestHandler,
                   public CefDisplayHandler {
 public:
  explicit PageClient(CEFPageView *view) : view_(view) {}

  void Detach() { view_ = nil; }

  // The folders whose files the page may read, as real paths ending in "/". Set on the main
  // thread, read on Chromium's input-output thread.
  void SetReadableFolders(std::vector<std::string> folders) {
    std::lock_guard<std::mutex> lock(foldersLock_);
    folders_ = std::move(folders);
  }

  CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }

  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                CefProcessId source_process,
                                CefRefPtr<CefProcessMessage> message) override {
    CEFPageView *view = view_;
    [view received:message];
    return true;
  }

  // Render handler.
  void GetViewRect(CefRefPtr<CefBrowser> browser, CefRect& rect) override {
    CEFPageView *view = view_;
    CGSize size = view ? [view pageSize] : CGSizeMake(800, 600);
    rect = CefRect(0, 0, MAX(1, (int)lround(size.width)), MAX(1, (int)lround(size.height)));
  }

  bool GetScreenInfo(CefRefPtr<CefBrowser> browser, CefScreenInfo& info) override {
    CEFPageView *view = view_;
    CGSize size = view ? [view pageSize] : CGSizeMake(800, 600);
    info.device_scale_factor = view ? (float)[view pageScale] : 2;
    info.depth = 24;
    info.depth_per_component = 8;
    info.rect = CefRect(0, 0, (int)lround(size.width), (int)lround(size.height));
    info.available_rect = info.rect;
    return true;
  }

  void OnPaint(CefRefPtr<CefBrowser> browser,
               PaintElementType type,
               const RectList& dirtyRects,
               const void* buffer,
               int width,
               int height) override {}

  void OnAcceleratedPaint(CefRefPtr<CefBrowser> browser,
                          PaintElementType type,
                          const RectList& dirtyRects,
                          const CefAcceleratedPaintInfo& info) override {
    if (type != PET_VIEW) {
      return;
    }
    CEFPageView *view = view_;
    [view paintSurface:(IOSurfaceRef)info.shared_texture_io_surface];
  }

  // Life span.
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int popup_id,
                     const CefString& target_url,
                     const CefString& target_frame_name,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures& popupFeatures,
                     CefWindowInfo& windowInfo,
                     CefRefPtr<CefClient>& client,
                     CefBrowserSettings& settings,
                     CefRefPtr<CefDictionaryValue>& extra_info,
                     bool* no_javascript_access) override {
    return true;  // a wallpaper opens no windows
  }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    CEFPageView *view = view_;
    if (view) {
      [view browserCreated:browser];
    } else {
      browser->GetHost()->CloseBrowser(true);
    }
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    CEFPageView *view = view_;
    [view browserClosed];
  }

  // Load handler.
  void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int httpStatusCode) override {
    if (!frame->IsMain()) {
      return;
    }
    CEFPageView *view = view_;
    [view loadEnded:httpStatusCode];
  }

  void OnLoadError(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode,
                   const CefString& errorText,
                   const CefString& failedUrl) override {
    if (!frame->IsMain() || errorCode == ERR_ABORTED) {
      return;
    }
    CEFPageView *view = view_;
    NSString *text = [NSString stringWithUTF8String:errorText.ToString().c_str()];
    [view loadFailed:[NSString stringWithFormat:@"%@ (%d)", text, (int)errorCode]];
  }

  // Request handler: the files a page may read.
  CefRefPtr<CefResourceRequestHandler> GetResourceRequestHandler(CefRefPtr<CefBrowser> browser,
                                                                 CefRefPtr<CefFrame> frame,
                                                                 CefRefPtr<CefRequest> request,
                                                                 bool is_navigation,
                                                                 bool is_download,
                                                                 const CefString& request_initiator,
                                                                 bool& disable_default_handling) override {
    return this;
  }

  ReturnValue OnBeforeResourceLoad(CefRefPtr<CefBrowser> browser,
                                   CefRefPtr<CefFrame> frame,
                                   CefRefPtr<CefRequest> request,
                                   CefRefPtr<CefCallback> callback) override {
    std::string url = request->GetURL().ToString();
    if (url.rfind("file:", 0) != 0) {
      return RV_CONTINUE;
    }
    NSURL *fileURL = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]];
    char real[PATH_MAX];
    if (!fileURL.path || !realpath(fileURL.path.fileSystemRepresentation, real)) {
      return RV_CANCEL;
    }
    std::string path = std::string(real) + "/";
    std::lock_guard<std::mutex> lock(foldersLock_);
    for (const std::string& folder : folders_) {
      if (path.rfind(folder, 0) == 0) {
        return RV_CONTINUE;
      }
    }
    return RV_CANCEL;
  }

  // Display handler: what pages write to their console, for whoever runs the app from a terminal.
  bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                        cef_log_severity_t level,
                        const CefString& message,
                        const CefString& source,
                        int line) override {
    if (level >= LOGSEVERITY_WARNING && getenv("WALLAERO_CONSOLE")) {
      fprintf(stderr, "[page] %s (%s:%d)\n", message.ToString().c_str(), source.ToString().c_str(), line);
    }
    return true;
  }

 private:
  __weak CEFPageView *view_;
  std::mutex foldersLock_;
  std::vector<std::string> folders_;

  IMPLEMENT_REFCOUNTING(PageClient);
};

}  // namespace

// MARK: - Runtime

@implementation CEFRuntime

+ (BOOL)startWithFrameworksFolder:(NSString *)frameworksFolder
                      cacheFolder:(NSString *)cacheFolder
                    debuggingPort:(int)debuggingPort {
  if (gRunning) {
    return YES;
  }
  NSString *framework = [frameworksFolder stringByAppendingPathComponent:@"Chromium Embedded Framework.framework"];
  NSString *library = [framework stringByAppendingPathComponent:@"Chromium Embedded Framework"];
  if (!gLibraryLoaded) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:library] || !cef_load_library(library.fileSystemRepresentation)) {
      NSLog(@"Chromium is not there: %@", library);
      return NO;
    }
    gLibraryLoaded = true;
  }
  NSString *appName = [NSBundle mainBundle].infoDictionary[@"CFBundleName"] ?: @"WallAero Engine";
  NSString *helper = [frameworksFolder stringByAppendingPathComponent:
      [NSString stringWithFormat:@"%@ Helper.app/Contents/MacOS/%@ Helper", appName, appName]];

  CefMainArgs args(0, nullptr);
  CefSettings settings;
  settings.no_sandbox = true;
  settings.external_message_pump = true;
  settings.windowless_rendering_enabled = true;
  settings.command_line_args_disabled = true;
  settings.persist_session_cookies = false;
  // WALLAERO_CEF_LOG=<file> writes Chromium's own log there, for a developer.
  const char *logFile = getenv("WALLAERO_CEF_LOG");
  settings.log_severity = logFile ? LOGSEVERITY_VERBOSE : LOGSEVERITY_DISABLE;
  if (logFile && logFile[0] == '/') {
    CefString(&settings.log_file) = logFile;
  }
  settings.background_color = 0;
  settings.remote_debugging_port = debuggingPort;
  CefString(&settings.browser_subprocess_path) = helper.UTF8String;
  CefString(&settings.framework_dir_path) = framework.UTF8String;
  CefString(&settings.main_bundle_path) = [NSBundle mainBundle].bundlePath.UTF8String;
  [[NSFileManager defaultManager] createDirectoryAtPath:cacheFolder withIntermediateDirectories:YES attributes:nil error:nil];
  // Chromium compares the two folders by their real paths (the temporary folder lies behind a link).
  char real[PATH_MAX];
  if (realpath(cacheFolder.fileSystemRepresentation, real)) {
    cacheFolder = [NSString stringWithUTF8String:real];
  }
  CefString(&settings.root_cache_path) = cacheFolder.UTF8String;
  CefString(&settings.cache_path) = [cacheFolder stringByAppendingPathComponent:@"Pages"].UTF8String;
  NSString *language = [NSLocale preferredLanguages].firstObject ?: @"en";
  CefString(&settings.locale) = language.UTF8String;

  if (!CefInitialize(args, settings, new BrowserApp(), nullptr)) {
    NSLog(@"Chromium did not start");
    return NO;
  }
  gRunning = true;
  // Besides when Chromium asks for it, a few times a second.
  [NSTimer scheduledTimerWithTimeInterval:1.0 / 30 repeats:YES block:^(NSTimer *timer) {
    if (!gRunning) {
      [timer invalidate];
      return;
    }
    Pump::DoWork();
  }];
  return YES;
}

+ (BOOL)isRunning {
  return gRunning;
}

+ (void)shutdown {
  if (!gRunning) {
    return;
  }
  // Pages still open are closed by Chromium itself; a few rounds of work let them go.
  for (int i = 0; i < 20; i++) {
    CefDoMessageLoopWork();
    [NSThread sleepForTimeInterval:0.01];
  }
  gRunning = false;
  CefShutdown();
}

@end

// MARK: - Application

@interface CEFApplication () <CefAppProtocol>
@end

@implementation CEFApplication {
  BOOL _handlingSendEvent;
}

- (BOOL)isHandlingSendEvent {
  return _handlingSendEvent;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  _handlingSendEvent = handlingSendEvent;
}

- (void)sendEvent:(NSEvent *)event {
  CefScopedSendingEvent sendingEventScoper;
  [super sendEvent:event];
}

@end

// MARK: - User scripts

@implementation CEFUserScript

- (instancetype)initWithSource:(NSString *)source atDocumentEnd:(BOOL)atDocumentEnd mainFrameOnly:(BOOL)mainFrameOnly {
  if ((self = [super init])) {
    _source = [source copy];
    _atDocumentEnd = atDocumentEnd;
    _mainFrameOnly = mainFrameOnly;
  }
  return self;
}

@end

// MARK: - Page view

@implementation CEFPageView {
  CefRefPtr<PageClient> _client;
  CefRefPtr<CefBrowser> _browser;
  NSURL *_pendingURL;
  NSMutableArray<NSString *> *_pendingScripts;
  std::map<int, void (^)(NSString *)> _evaluations;
  int _lastEvaluation;
  id<MTLDevice> _device;
  id<MTLCommandQueue> _queue;
  // Frames are copied into these in turn, so the layer never shows one being written.
  IOSurfaceRef _surfaces[3];
  int _nextSurface;
  IOSurfaceRef _shown;
  BOOL _closed;
  NSTrackingArea *_tracking;
}

- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.wantsLayer = YES;
    self.layer.contentsGravity = kCAGravityResize;
    self.layer.opaque = NO;
    _userScripts = @[];
    _readableFolders = @[];
    _frameRateLimit = 60;
    _pendingScripts = [NSMutableArray array];
    _device = MTLCreateSystemDefaultDevice();
    _queue = [_device newCommandQueue];
  }
  return self;
}

- (void)dealloc {
  [self close];
  for (int i = 0; i < 3; i++) {
    if (_surfaces[i]) {
      CFRelease(_surfaces[i]);
    }
  }
}

- (BOOL)isFlipped {
  return YES;
}

// Made with the first page, so that the page's process gets the scripts with it: a browser
// made on a blank page would have its first page drawn by another process, one never told.
- (void)createBrowserWithURL:(NSURL *)url {
  if (!gRunning || _client) {
    return;
  }
  _client = new PageClient(self);
  self.readableFolders = _readableFolders;
  CefWindowInfo info;
  info.SetAsWindowless(nullptr);
  info.shared_texture_enabled = true;
  CefBrowserSettings settings;
  settings.windowless_frame_rate = _frameRateLimit;
  settings.background_color = 0;
  CefRefPtr<CefDictionaryValue> extra = CefDictionaryValue::Create();
  extra->SetList(wallaero::kScriptsKey, [self scriptList]);
  CefBrowserHost::CreateBrowser(info, _client.get(), url.absoluteString.UTF8String, settings, extra, nullptr);
}

- (CefRefPtr<CefListValue>)scriptList {
  CefRefPtr<CefListValue> list = CefListValue::Create();
  size_t index = 0;
  for (CEFUserScript *script in _userScripts) {
    CefRefPtr<CefDictionaryValue> entry = CefDictionaryValue::Create();
    entry->SetString("source", script.source.UTF8String);
    entry->SetBool("end", script.atDocumentEnd);
    entry->SetBool("main", script.mainFrameOnly);
    list->SetDictionary(index++, entry);
  }
  return list;
}

- (void)setUserScripts:(NSArray<CEFUserScript *> *)userScripts {
  _userScripts = [userScripts copy];
  if (_browser) {
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(wallaero::kScriptsMessage);
    message->GetArgumentList()->SetList(0, [self scriptList]);
    _browser->GetMainFrame()->SendProcessMessage(PID_RENDERER, message);
  }
}

- (void)browserCreated:(CefRefPtr<CefBrowser>)browser {
  if (_closed) {
    browser->GetHost()->CloseBrowser(true);
    return;
  }
  _browser = browser;
  CefRefPtr<CefBrowserHost> host = browser->GetHost();
  host->SetAudioMuted(_audioMuted);
  host->WasHidden(_pageHidden);
  // Scripts set while the browser was being made.
  [self setUserScripts:_userScripts];
  if (_pendingURL) {
    NSURL *url = _pendingURL;
    _pendingURL = nil;
    [self loadURL:url];
  }
  host->WasResized();
}

- (void)browserClosed {
  _browser = nullptr;
}

- (void)loadURL:(NSURL *)url {
  _hasDrawn = NO;
  if (!_client) {
    [self createBrowserWithURL:url];
    return;
  }
  if (!_browser) {
    _pendingURL = url;
    return;
  }
  _browser->GetMainFrame()->LoadURL(url.absoluteString.UTF8String);
}

- (void)loadEnded:(int)httpStatus {
  NSArray *scripts = [_pendingScripts copy];
  [_pendingScripts removeAllObjects];
  for (NSString *script in scripts) {
    [self executeScript:script];
  }
  [self.delegate pageView:self didFinishLoadingWithError:nil];
}

- (void)loadFailed:(NSString *)error {
  [self.delegate pageView:self didFinishLoadingWithError:error];
}

- (void)executeScript:(NSString *)script {
  if (!_browser) {
    return;
  }
  _browser->GetMainFrame()->ExecuteJavaScript(script.UTF8String, "wallaero://app", 1);
}

- (void)evaluateScript:(NSString *)script completion:(void (^)(NSString *))completion {
  if (!_browser) {
    completion(nil);
    return;
  }
  int identifier = ++_lastEvaluation;
  _evaluations[identifier] = [completion copy];
  CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(wallaero::kEvalMessage);
  message->GetArgumentList()->SetInt(0, identifier);
  message->GetArgumentList()->SetString(1, script.UTF8String);
  _browser->GetMainFrame()->SendProcessMessage(PID_RENDERER, message);
}

- (void)received:(CefRefPtr<CefProcessMessage>)message {
  const std::string name = message->GetName();
  CefRefPtr<CefListValue> arguments = message->GetArgumentList();
  if (name == wallaero::kPostMessage) {
    NSString *handler = [NSString stringWithUTF8String:arguments->GetString(0).ToString().c_str()];
    NSString *json = [NSString stringWithUTF8String:arguments->GetString(1).ToString().c_str()];
    if (handler && json) {
      [self.delegate pageView:self didReceiveMessage:json forHandler:handler];
    }
  } else if (name == wallaero::kResultMessage) {
    int identifier = arguments->GetInt(0);
    auto found = _evaluations.find(identifier);
    if (found == _evaluations.end()) {
      return;
    }
    void (^completion)(NSString *) = found->second;
    _evaluations.erase(found);
    NSString *json = nil;
    if (arguments->GetType(1) == VTYPE_STRING) {
      json = [NSString stringWithUTF8String:arguments->GetString(1).ToString().c_str()];
    }
    completion(json);
  }
}

- (void)close {
  if (_closed) {
    return;
  }
  _closed = YES;
  if (_client) {
    _client->Detach();
  }
  if (_browser) {
    _browser->GetHost()->CloseBrowser(true);
    _browser = nullptr;
  }
  auto evaluations = _evaluations;
  _evaluations.clear();
  for (auto& entry : evaluations) {
    entry.second(nil);
  }
}

// MARK: Size and density

- (CGSize)pageSize {
  return self.bounds.size;
}

- (CGFloat)pageScale {
  return self.window ? self.window.backingScaleFactor : (NSScreen.mainScreen.backingScaleFactor ?: 2);
}

- (void)setFrameSize:(NSSize)newSize {
  [super setFrameSize:newSize];
  if (_browser) {
    _browser->GetHost()->WasResized();
  }
}

- (void)viewDidChangeBackingProperties {
  [super viewDidChangeBackingProperties];
  if (_browser) {
    _browser->GetHost()->NotifyScreenInfoChanged();
    _browser->GetHost()->WasResized();
  }
}

- (void)setPageHidden:(BOOL)pageHidden {
  _pageHidden = pageHidden;
  if (_browser) {
    _browser->GetHost()->WasHidden(pageHidden);
  }
}

- (void)setAudioMuted:(BOOL)audioMuted {
  _audioMuted = audioMuted;
  if (_browser) {
    _browser->GetHost()->SetAudioMuted(audioMuted);
  }
}

- (void)setFrameRateLimit:(int)frameRateLimit {
  _frameRateLimit = MAX(1, MIN(240, frameRateLimit));
  if (_browser) {
    _browser->GetHost()->SetWindowlessFrameRate(_frameRateLimit);
  }
}

- (void)setReadableFolders:(NSArray<NSString *> *)readableFolders {
  _readableFolders = [readableFolders copy];
  std::vector<std::string> folders;
  for (NSString *folder in _readableFolders) {
    char real[PATH_MAX];
    if (realpath(folder.fileSystemRepresentation, real)) {
      folders.push_back(std::string(real) + "/");
    }
  }
  if (_client) {
    _client->SetReadableFolders(folders);
  }
}

// MARK: Frames

- (void)paintSurface:(IOSurfaceRef)source {
  if (!source || _closed) {
    return;
  }
  size_t width = IOSurfaceGetWidth(source), height = IOSurfaceGetHeight(source);
  IOSurfaceRef target = _surfaces[_nextSurface];
  if (!target || IOSurfaceGetWidth(target) != width || IOSurfaceGetHeight(target) != height) {
    if (target) {
      CFRelease(target);
    }
    NSDictionary *properties = @{
      (id)kIOSurfaceWidth: @(width),
      (id)kIOSurfaceHeight: @(height),
      (id)kIOSurfaceBytesPerElement: @4,
      (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
    };
    target = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (!target) {
      return;
    }
    CFTypeRef colorSpace = IOSurfaceCopyValue(source, kIOSurfaceColorSpace);
    if (colorSpace) {
      IOSurfaceSetValue(target, kIOSurfaceColorSpace, colorSpace);
      CFRelease(colorSpace);
    }
    _surfaces[_nextSurface] = target;
  }
  MTLTextureDescriptor *descriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
  descriptor.usage = MTLTextureUsageShaderRead;
  descriptor.storageMode = MTLStorageModeShared;
  id<MTLTexture> from = [_device newTextureWithDescriptor:descriptor iosurface:source plane:0];
  id<MTLTexture> to = [_device newTextureWithDescriptor:descriptor iosurface:target plane:0];
  if (!from || !to) {
    return;
  }
  id<MTLCommandBuffer> commands = [_queue commandBuffer];
  id<MTLBlitCommandEncoder> blit = [commands blitCommandEncoder];
  [blit copyFromTexture:from toTexture:to];
  [blit endEncoding];
  [commands commit];
  // The frame's surface goes back to Chromium when this returns.
  [commands waitUntilCompleted];

  _shown = target;
  _nextSurface = (_nextSurface + 1) % 3;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.layer.contents = (__bridge id)target;
  [CATransaction commit];
  _hasDrawn = YES;
}

- (CGImageRef)copySnapshot {
  IOSurfaceRef surface = _shown;
  if (!surface) {
    return NULL;
  }
  IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
  size_t width = IOSurfaceGetWidth(surface), height = IOSurfaceGetHeight(surface);
  size_t bytesPerRow = IOSurfaceGetBytesPerRow(surface);
  NSData *data = [NSData dataWithBytes:IOSurfaceGetBaseAddress(surface) length:bytesPerRow * height];
  IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
  CGImageRef image = CGImageCreate(width, height, 8, 32, bytesPerRow, space,
                                   (CGBitmapInfo)kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaPremultipliedFirst,
                                   provider, NULL, false, kCGRenderingIntentDefault);
  CGDataProviderRelease(provider);
  CGColorSpaceRelease(space);
  return image;
}

// MARK: Mouse, for the editor's preview

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_tracking) {
    [self removeTrackingArea:_tracking];
    _tracking = nil;
  }
  if (_forwardsMouse) {
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                             options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                                                     NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self
                                            userInfo:nil];
    [self addTrackingArea:_tracking];
  }
}

- (void)setForwardsMouse:(BOOL)forwardsMouse {
  _forwardsMouse = forwardsMouse;
  [self updateTrackingAreas];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
  return _forwardsMouse;
}

- (NSView *)hitTest:(NSPoint)point {
  return _forwardsMouse ? [super hitTest:point] : nil;
}

static uint32_t Modifiers(NSEvent *event) {
  uint32_t flags = 0;
  NSEventModifierFlags modifiers = event.modifierFlags;
  if (modifiers & NSEventModifierFlagShift) flags |= EVENTFLAG_SHIFT_DOWN;
  if (modifiers & NSEventModifierFlagControl) flags |= EVENTFLAG_CONTROL_DOWN;
  if (modifiers & NSEventModifierFlagOption) flags |= EVENTFLAG_ALT_DOWN;
  if (modifiers & NSEventModifierFlagCommand) flags |= EVENTFLAG_COMMAND_DOWN;
  NSUInteger buttons = [NSEvent pressedMouseButtons];
  if (buttons & 1) flags |= EVENTFLAG_LEFT_MOUSE_BUTTON;
  if (buttons & 2) flags |= EVENTFLAG_RIGHT_MOUSE_BUTTON;
  if (buttons & 4) flags |= EVENTFLAG_MIDDLE_MOUSE_BUTTON;
  return flags;
}

- (CefMouseEvent)mouseEvent:(NSEvent *)event {
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  CefMouseEvent mouse;
  mouse.x = (int)lround(point.x);
  mouse.y = (int)lround(point.y);
  mouse.modifiers = Modifiers(event);
  return mouse;
}

- (void)click:(NSEvent *)event button:(CefBrowserHost::MouseButtonType)button up:(BOOL)up {
  if (!_forwardsMouse || !_browser) return;
  _browser->GetHost()->SendMouseClickEvent([self mouseEvent:event], button, up, (int)MAX(1, event.clickCount));
}

- (void)move:(NSEvent *)event leaving:(BOOL)leaving {
  if (!_forwardsMouse || !_browser) return;
  _browser->GetHost()->SendMouseMoveEvent([self mouseEvent:event], leaving);
}

- (void)mouseDown:(NSEvent *)event { [self.window makeFirstResponder:self]; [self click:event button:MBT_LEFT up:NO]; }
- (void)mouseUp:(NSEvent *)event { [self click:event button:MBT_LEFT up:YES]; }
- (void)rightMouseDown:(NSEvent *)event { [self click:event button:MBT_RIGHT up:NO]; }
- (void)rightMouseUp:(NSEvent *)event { [self click:event button:MBT_RIGHT up:YES]; }
- (void)mouseMoved:(NSEvent *)event { [self move:event leaving:NO]; }
- (void)mouseDragged:(NSEvent *)event { [self move:event leaving:NO]; }
- (void)rightMouseDragged:(NSEvent *)event { [self move:event leaving:NO]; }
- (void)mouseEntered:(NSEvent *)event { [self move:event leaving:NO]; }
- (void)mouseExited:(NSEvent *)event { [self move:event leaving:YES]; }

- (void)scrollWheel:(NSEvent *)event {
  if (!_forwardsMouse || !_browser) return;
  CGFloat scale = event.hasPreciseScrollingDeltas ? 1 : 40;
  _browser->GetHost()->SendMouseWheelEvent([self mouseEvent:event], (int)lround(event.scrollingDeltaX * scale),
                                           (int)lround(event.scrollingDeltaY * scale));
}

@end
