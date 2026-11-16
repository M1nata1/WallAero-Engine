import Foundation

/// What the whole Mac's chips spend, read from IOReport's "Energy Model" channels as Activity
/// Monitor does, without root: CPU, GPU, Neural Engine and memory, in watts over a while. For
/// `--freeze … --timing`, beside how long frames take. It is the whole Mac's — the app's own
/// wallpaper and anything else running count too, so only runs made alike compare.
final class PowerSample {
    private typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias Subscribe = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary,
                                                   UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> OpaquePointer?
    private typealias Samples = @convention(c) (OpaquePointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias Delta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias Text = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias Integer = @convention(c) (CFDictionary, Int32) -> Int64

    private let samples: Samples, delta: Delta, name: Text, unit: Text, integer: Integer
    private let subscription: OpaquePointer
    private let channels: CFMutableDictionary
    private var first: CFDictionary?
    private var begun = Date()

    init?() {
        guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW),
              let copy = dlsym(library, "IOReportCopyChannelsInGroup"), let subscribe = dlsym(library, "IOReportCreateSubscription"),
              let samples = dlsym(library, "IOReportCreateSamples"), let delta = dlsym(library, "IOReportCreateSamplesDelta"),
              let name = dlsym(library, "IOReportChannelGetChannelName"), let unit = dlsym(library, "IOReportChannelGetUnitLabel"),
              let integer = dlsym(library, "IOReportSimpleGetIntegerValue")
        else { return nil }
        self.samples = unsafeBitCast(samples, to: Samples.self)
        self.delta = unsafeBitCast(delta, to: Delta.self)
        self.name = unsafeBitCast(name, to: Text.self)
        self.unit = unsafeBitCast(unit, to: Text.self)
        self.integer = unsafeBitCast(integer, to: Integer.self)
        guard let channels = unsafeBitCast(copy, to: CopyChannels.self)("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return nil }
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let subscription = unsafeBitCast(subscribe, to: Subscribe.self)(nil, channels, &subscribed, 0, nil) else { return nil }
        self.channels = subscribed?.takeRetainedValue() ?? channels
        self.subscription = subscription
    }

    func start() {
        first = samples(subscription, channels, nil)?.takeRetainedValue()
        begun = Date()
    }

    /// Watts since `start`, by part: "cpu", "gpu", "ane", "dram" and "total".
    func watts() -> [String: Double] {
        guard let first, let last = samples(subscription, channels, nil)?.takeRetainedValue(),
              let change = delta(first, last, nil)?.takeRetainedValue() as? [String: Any],
              let list = change["IOReportChannels"] as? [CFDictionary]
        else { return [:] }
        let seconds = max(0.001, Date().timeIntervalSince(begun))
        var joules: [String: Double] = [:]
        for channel in list {
            let title = name(channel)?.takeUnretainedValue() as String? ?? ""
            let part: String
            switch title {
            case "CPU Energy": part = "cpu"
            case "GPU Energy": part = "gpu"
            case _ where title.hasPrefix("ANE"): part = "ane"
            case _ where title.hasPrefix("DRAM"): part = "dram"
            default: continue
            }
            let scale: Double
            switch unit(channel)?.takeUnretainedValue() as String? ?? "" {
            case "mJ": scale = 1e-3
            case "uJ", "µJ": scale = 1e-6
            case "nJ": scale = 1e-9
            default: scale = 1e-3
            }
            joules[part, default: 0] += Double(integer(channel, 0)) * scale
        }
        var result = joules.mapValues { $0 / seconds }
        result["total"] = result.values.reduce(0, +)
        return result
    }
}
