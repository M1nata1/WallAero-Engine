#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Chromium in the app's process. Pages are drawn by Chromium's own processes, started from the
/// helper apps that lie next to the framework.
@interface CEFRuntime : NSObject

/// Loads "Chromium Embedded Framework.framework" from `frameworksFolder` (where the helper apps
/// lie too) and starts Chromium. `cacheFolder` keeps what pages store; a folder no other running
/// copy of the app uses. `debuggingPort` above 0 opens Chromium's developer tools on that port.
/// Returns NO when the framework is missing or does not start.
+ (BOOL)startWithFrameworksFolder:(NSString *)frameworksFolder
                      cacheFolder:(NSString *)cacheFolder
                    debuggingPort:(int)debuggingPort;
@property (class, readonly) BOOL isRunning;
/// Closes every page and stops Chromium; for when the app quits.
+ (void)shutdown;

@end

/// The application object Chromium needs: it has to know when the app is handing on an event.
/// Created as `CEFApplication.shared` before anything else asks for `NSApplication.shared`.
@interface CEFApplication : NSApplication
@end

/// A script run in every page before the page's own (or once its document is read, `atDocumentEnd`),
/// in frames too unless `mainFrameOnly`.
@interface CEFUserScript : NSObject
- (instancetype)initWithSource:(NSString *)source atDocumentEnd:(BOOL)atDocumentEnd mainFrameOnly:(BOOL)mainFrameOnly;
@property (readonly, copy) NSString *source;
@property (readonly) BOOL atDocumentEnd;
@property (readonly) BOOL mainFrameOnly;
@end

@class CEFPageView;

NS_SWIFT_UI_ACTOR
@protocol CEFPageViewDelegate <NSObject>
/// The main frame has loaded; `error` is set when it could not.
- (void)pageView:(CEFPageView *)view didFinishLoadingWithError:(nullable NSString *)error;
/// What the page sent with `window.webkit.messageHandlers.<handler>.postMessage(value)`, as JSON.
- (void)pageView:(CEFPageView *)view didReceiveMessage:(NSString *)json forHandler:(NSString *)handler;
@end

/// A page drawn by Chromium off screen; its frames are shown in this view's layer.
NS_SWIFT_UI_ACTOR
@interface CEFPageView : NSView

@property (nullable, weak) id<CEFPageViewDelegate> delegate;
/// Run in every page loaded from now on. Changing them does not reload the page.
@property (nonatomic, copy) NSArray<CEFUserScript *> *userScripts;
/// The folders whose files the page may load; any other file is refused. Pages from the web
/// are not limited by it.
@property (nonatomic, copy) NSArray<NSString *> *readableFolders;
/// Mouse and wheel events over the view go to the page (the editor's preview); a wallpaper on
/// the desktop is told of the pointer through its scripts instead.
@property (nonatomic) BOOL forwardsMouse;
/// The most frames a second Chromium draws the page at.
@property (nonatomic) int frameRateLimit;
/// Whether the page draws and plays: a hidden page stops its animations and timers.
@property (nonatomic) BOOL pageHidden;
/// Whether the page's sound is heard.
@property (nonatomic) BOOL audioMuted;
/// Whether the page has drawn anything yet.
@property (readonly) BOOL hasDrawn;

- (void)loadURL:(NSURL *)url;
- (void)executeScript:(NSString *)script;
/// What the script comes to, as JSON; nil when it fails, comes to nothing or the page is gone.
- (void)evaluateScript:(NSString *)script completion:(void (^)(NSString *_Nullable json))completion;
/// The page as it was last drawn.
- (nullable CGImageRef)copySnapshot CF_RETURNS_RETAINED;
/// Closes the page for good.
- (void)close;

@end

NS_ASSUME_NONNULL_END
