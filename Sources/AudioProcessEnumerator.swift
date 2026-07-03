import AudioToolbox
import CoreAudio
import Foundation

/// A meeting app the user can pick as the capture source.
struct AudioProcessInfo: Identifiable, Hashable {
    let id: AudioObjectID       // the Core Audio process object id
    let pid: pid_t
    let bundleID: String
    let name: String
    let isPlaying: Bool         // currently producing output audio right now
}

enum AudioProcessError: Error {
    case osStatus(OSStatus, String)
    case notFound
}

/// Enumerates processes currently producing audio output and resolves the ones
/// that look like meeting apps, so the user can tap the right one.
///
/// Gotcha handled here: Chrome/Meet and Electron apps play through *helper*
/// processes, so we surface every audio-producing process and tag known bundles,
/// and we also expose "tap all processes matching a bundle prefix".
enum AudioProcessEnumerator {

    /// Known meeting-app bundle-id prefixes → friendly name.
    static let known: [(prefix: String, name: String)] = [
        ("us.zoom.xos", "Zoom"),
        ("com.microsoft.teams2", "Microsoft Teams"),
        ("com.microsoft.teams", "Microsoft Teams (classic)"),
        ("com.google.Chrome", "Google Chrome / Meet"),
        ("com.google.Chrome.helper", "Chrome Helper"),
        ("com.apple.WebKit", "Safari (WebKit)"),
        ("com.apple.Safari", "Safari"),
        ("com.hnc.Discord", "Discord"),
        ("com.webex", "Webex"),
        ("Cisco-Systems.Spark", "Webex"),
    ]

    /// All process objects the HAL currently knows about.
    static func allProcessObjects() throws -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        var st = AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size)
        guard st == noErr else { throw AudioProcessError.osStatus(st, "ProcessObjectList size") }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        st = AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids)
        guard st == noErr else { throw AudioProcessError.osStatus(st, "ProcessObjectList data") }
        return ids
    }

    private static func pid(of obj: AudioObjectID) -> pid_t? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        let st = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value)
        return st == noErr ? value : nil
    }

    private static func bundleID(of obj: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cf: Unmanaged<CFString>?
        let st = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &cf)
        guard st == noErr, let cf else { return nil }
        return cf.takeRetainedValue() as String
    }

    private static func isRunningOutput(_ obj: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let st = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value)
        return st == noErr && value != 0
    }

    private static func friendlyName(for bundleID: String, pid: pid_t) -> String {
        if let match = known.first(where: { bundleID.hasPrefix($0.prefix) }) {
            return match.name
        }
        if let app = NSRunningApplicationBridge.name(forPID: pid) { return app }
        return bundleID.isEmpty ? "PID \(pid)" : bundleID
    }

    /// Selectable capture sources. Unlike a naive "currently playing" filter, we
    /// list every real *user-facing app* process so the user can pick a meeting
    /// app BEFORE it starts making sound — a Core Audio tap happily attaches to a
    /// silent process and begins capturing the moment it plays. Whether a process
    /// is producing audio right now is surfaced via `isPlaying` (shown with a 🔊
    /// and sorted to the top) rather than used to hide it.
    ///
    /// We keep only real apps (a running app with a regular/accessory activation
    /// policy) and drop background audio daemons (coreaudiod, mediaremoted,
    /// avconferenced, …) and ourselves — otherwise the list fills with dozens of
    /// `com.apple.*` services the user would never caption.
    static func activeAudioProcesses() -> [AudioProcessInfo] {
        guard let objs = try? allProcessObjects() else { return [] }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var result: [AudioProcessInfo] = []
        var seenPIDs = Set<pid_t>()
        for obj in objs {
            let bid = bundleID(of: obj) ?? ""
            guard !bid.isEmpty else { continue }
            guard let p = pid(of: obj), p > 0, p != selfPID else { continue }
            // One entry per app pid (helpers still gathered at tap time).
            guard seenPIDs.insert(p).inserted else { continue }
            // Real user-facing app? (Dock or menu-bar/accessory app — not a daemon.)
            guard let app = NSRunningApplication(processIdentifier: p),
                  app.activationPolicy != .prohibited else { continue }
            let name = friendlyName(for: bid, pid: p)
            result.append(AudioProcessInfo(
                id: obj, pid: p, bundleID: bid,
                name: name, isPlaying: isRunningOutput(obj)))
        }
        // Sort: currently-playing first, then known meeting apps, then by name.
        let sorted = result.sorted { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
            let lk = known.contains { lhs.bundleID.hasPrefix($0.prefix) }
            let rk = known.contains { rhs.bundleID.hasPrefix($0.prefix) }
            if lk != rk { return lk }
            return lhs.name < rhs.name
        }
        // Collapse an app's multiple helper processes into ONE picker entry per
        // app (same friendly name → same app; e.g. Chrome/Teams/WeChat run several
        // helpers with distinct pids). We keep the first, which — thanks to the
        // sort — is the currently-playing one if any. Selecting it still taps ALL
        // of that app's helpers via `objectIDs(bundlePrefix:)`.
        var seenNames = Set<String>()
        return sorted.filter { seenNames.insert($0.name).inserted }
    }

    /// All audio process object ids whose bundle id shares `prefix` (e.g. Chrome
    /// main + all its helpers) — pass the whole array to the tap. Includes silent
    /// ones so a chosen-but-not-yet-playing app is fully covered.
    static func objectIDs(bundlePrefix prefix: String) -> [AudioObjectID] {
        guard let objs = try? allProcessObjects() else { return [] }
        return objs.filter { obj in
            bundleID(of: obj)?.hasPrefix(prefix) ?? false
        }
    }
}

/// Tiny bridge so we can get an app name from a pid without importing AppKit
/// everywhere. AppKit is available (this is a menu-bar app).
import AppKit
enum NSRunningApplicationBridge {
    static func name(forPID pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
