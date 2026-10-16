// The program Chromium starts its other processes with: pages, graphics, sound, the network.
// It lies in the app's helper bundles, next to the framework it loads.

#include "Shared.h"
#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"

int main(int argc, char* argv[]) {
  CefScopedLibraryLoader library;
  if (!library.LoadInHelper()) {
    return 1;
  }
  CefMainArgs args(argc, argv);
  return CefExecuteProcess(args, wallaero::CreateHelperApp(), nullptr);
}
