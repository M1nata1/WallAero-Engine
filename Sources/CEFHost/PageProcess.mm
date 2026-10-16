// The side of a page process: runs the app's scripts in every page before the page's own,
// gives pages `window.webkit.messageHandlers` to talk to the app, and evaluates what the app asks.

#include <map>
#include <string>
#include <vector>

#include "Shared.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_v8.h"

namespace wallaero {

const char kScriptsMessage[] = "wallaero.scripts";
const char kEvalMessage[] = "wallaero.eval";
const char kPostMessage[] = "wallaero.post";
const char kResultMessage[] = "wallaero.result";
const char kScriptsKey[] = "wallaeroScripts";

void AddCommonSwitches(CefRefPtr<CefCommandLine> commandLine) {
  // A page of a wallpaper is opened from its folder and loads the other files of the folder,
  // also as modules; which files it may read is kept to its folder by the app (see Browser.mm).
  commandLine->AppendSwitch("allow-file-access-from-files");
  // A wallpaper starts its videos and sounds by itself; nobody clicks on it.
  commandLine->AppendSwitchWithValue("autoplay-policy", "no-user-gesture-required");
  // Chromium would ask the keychain for a key to store passwords with; there are none here.
  commandLine->AppendSwitch("use-mock-keychain");
  // No asking Google about anything, no extensions, no first-run pages.
  commandLine->AppendSwitch("disable-component-update");
  commandLine->AppendSwitch("disable-extensions");
  commandLine->AppendSwitch("disable-sync");
  commandLine->AppendSwitch("no-first-run");
  commandLine->AppendSwitch("disable-domain-reliability");
  commandLine->AppendSwitch("metrics-recording-only");
}

namespace {

struct Script {
  std::string source;
  bool end = false;
  bool main = false;
};

std::vector<Script> ReadScripts(CefRefPtr<CefListValue> list) {
  std::vector<Script> scripts;
  if (!list) {
    return scripts;
  }
  for (size_t i = 0; i < list->GetSize(); ++i) {
    CefRefPtr<CefDictionaryValue> entry = list->GetDictionary(i);
    if (!entry) {
      continue;
    }
    Script script;
    script.source = entry->GetString("source").ToString();
    script.end = entry->GetBool("end");
    script.main = entry->GetBool("main");
    scripts.push_back(script);
  }
  return scripts;
}

// `__wallaeroPost(handler, json)`: what the page's `postMessage` comes down to.
class PostHandler : public CefV8Handler {
 public:
  bool Execute(const CefString& name,
               CefRefPtr<CefV8Value> object,
               const CefV8ValueList& arguments,
               CefRefPtr<CefV8Value>& retval,
               CefString& exception) override {
    if (arguments.size() < 2 || !arguments[0]->IsString() || !arguments[1]->IsString()) {
      return true;
    }
    CefRefPtr<CefV8Context> context = CefV8Context::GetCurrentContext();
    CefRefPtr<CefFrame> frame = context ? context->GetFrame() : nullptr;
    if (!frame) {
      return true;
    }
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kPostMessage);
    CefRefPtr<CefListValue> list = message->GetArgumentList();
    list->SetString(0, arguments[0]->GetStringValue());
    list->SetString(1, arguments[1]->GetStringValue());
    frame->SendProcessMessage(PID_BROWSER, message);
    return true;
  }

  IMPLEMENT_REFCOUNTING(PostHandler);
};

// Gives the page the same way to talk to the app as WebKit's script message handlers.
const char kBridge[] = R"JS(
(function () {
  var post = window.__wallaeroPost;
  try { delete window.__wallaeroPost; } catch (error) {}
  var handlers = {};
  var messageHandlers = new Proxy({}, {
    get: function (target, name) {
      if (typeof name !== 'string') return undefined;
      return handlers[name] || (handlers[name] = {
        postMessage: function (value) {
          var json = JSON.stringify(value === undefined ? null : value);
          post(name, json === undefined ? 'null' : json);
        }
      });
    }
  });
  Object.defineProperty(window, 'webkit', { value: { messageHandlers: messageHandlers }, configurable: true });
})();
)JS";

class PageApp : public CefApp, public CefRenderProcessHandler {
 public:
  CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }

  void OnBrowserCreated(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefDictionaryValue> extra_info) override {
    if (extra_info && extra_info->HasKey(kScriptsKey)) {
      scripts_[browser->GetIdentifier()] = ReadScripts(extra_info->GetList(kScriptsKey));
    }
  }

  void OnBrowserDestroyed(CefRefPtr<CefBrowser> browser) override {
    scripts_.erase(browser->GetIdentifier());
  }

  void OnContextCreated(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefV8Context> context) override {
    CefRefPtr<CefV8Value> global = context->GetGlobal();
    global->SetValue("__wallaeroPost", CefV8Value::CreateFunction("__wallaeroPost", new PostHandler()),
                     V8_PROPERTY_ATTRIBUTE_NONE);
    Run(context, kBridge, "wallaero://bridge");
    auto found = scripts_.find(browser->GetIdentifier());
    if (found == scripts_.end()) {
      return;
    }
    bool isMain = frame->IsMain();
    int index = 0;
    for (const Script& script : found->second) {
      ++index;
      if (script.main && !isMain) {
        continue;
      }
      std::string url = "wallaero://script/" + std::to_string(index);
      if (script.end) {
        // Once the document has been read, as WebKit's scripts "at document end".
        std::string deferred =
            "(function (run) { if (document.readyState === 'loading') "
            "document.addEventListener('DOMContentLoaded', run, { once: true }); else run(); })"
            "(function () {\n" + script.source + "\n});";
        Run(context, deferred, url);
      } else {
        Run(context, script.source, url);
      }
    }
  }

  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                CefProcessId source_process,
                                CefRefPtr<CefProcessMessage> message) override {
    const std::string name = message->GetName();
    CefRefPtr<CefListValue> arguments = message->GetArgumentList();
    if (name == kScriptsMessage) {
      scripts_[browser->GetIdentifier()] = ReadScripts(arguments->GetList(0));
      return true;
    }
    if (name == kEvalMessage) {
      int id = arguments->GetInt(0);
      CefRefPtr<CefProcessMessage> reply = CefProcessMessage::Create(kResultMessage);
      reply->GetArgumentList()->SetInt(0, id);
      reply->GetArgumentList()->SetNull(1);
      CefRefPtr<CefFrame> main = browser->GetMainFrame();
      CefRefPtr<CefV8Context> context = main ? main->GetV8Context() : nullptr;
      if (context && context->Enter()) {
        CefRefPtr<CefV8Value> value;
        CefRefPtr<CefV8Exception> exception;
        if (context->Eval(arguments->GetString(1), "wallaero://eval", 1, value, exception) && value &&
            !value->IsUndefined() && !value->IsFunction()) {
          CefRefPtr<CefV8Value> json = context->GetGlobal()->GetValue("JSON");
          CefRefPtr<CefV8Value> stringify = json ? json->GetValue("stringify") : nullptr;
          if (stringify && stringify->IsFunction()) {
            CefV8ValueList list;
            list.push_back(value);
            CefRefPtr<CefV8Value> text = stringify->ExecuteFunction(json, list);
            if (text && text->IsString()) {
              reply->GetArgumentList()->SetString(1, text->GetStringValue());
            }
          }
        }
        context->Exit();
      }
      if (main) {
        main->SendProcessMessage(PID_BROWSER, reply);
      }
      return true;
    }
    return false;
  }

 private:
  static void Run(CefRefPtr<CefV8Context> context, const std::string& code, const std::string& url) {
    CefRefPtr<CefV8Value> value;
    CefRefPtr<CefV8Exception> exception;
    if (!context->Eval(code, url, 1, value, exception) && exception) {
      fprintf(stderr, "[wallaero] script %s: %s\n", url.c_str(), exception->GetMessage().ToString().c_str());
    }
  }

  std::map<int, std::vector<Script>> scripts_;

  IMPLEMENT_REFCOUNTING(PageApp);
};

}  // namespace

CefRefPtr<CefApp> CreateHelperApp() {
  return new PageApp();
}

}  // namespace wallaero
