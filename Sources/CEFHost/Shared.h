// What the app's process and the page processes agree on.
#pragma once

#include "include/cef_app.h"

namespace wallaero {

// Messages between the two sides.
// To a page process:
//   "scripts"  [list of {source, end, main}]  — the scripts for contexts made from now on
//   "eval"     [id, code]                     — evaluate in the main frame, answer with "result"
// From a page process:
//   "post"     [handler, json]                — window.webkit.messageHandlers.<handler>.postMessage
//   "result"   [id, json or null]
extern const char kScriptsMessage[];
extern const char kEvalMessage[];
extern const char kPostMessage[];
extern const char kResultMessage[];
// The key of the scripts in the extra information a browser is made with.
extern const char kScriptsKey[];

// The app for a helper process: pages get the scripts and the bridge to the app.
CefRefPtr<CefApp> CreateHelperApp();

// Switches every process of Chromium is started with.
void AddCommonSwitches(CefRefPtr<CefCommandLine> commandLine);

}  // namespace wallaero
