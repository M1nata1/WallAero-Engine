import WallAeroApp

// The app: all of it lives in WallAeroApp. The developer's helpers and tests are in
// WallAeroTestHost, which is not shipped.
MainActor.assumeIsolated {
    WallAeroEngineApp.launch()
}
