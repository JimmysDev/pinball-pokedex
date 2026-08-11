import Foundation
import Combine
import AppKit

/// Snapshot written by the mGBA Lua bridge (scripts/mgba_bridge.lua) to /tmp.
struct LiveState: Codable, Equatable {
    var active: Bool          // a game is currently running
    var field: Int            // 0 = Ruby, 1 = Sapphire (title selection)
    var area: Int             // AREA_* index, or -1
    var areaName: String      // e.g. "Cave (Sapphire)", "Volcano", "Safari Zone"
    var caughtThisGame: Int
    var registered: Int       // count toward the 100 super-rare gate
    var currentSpecies: Int
    var ereader: [Int]?       // gMain.eReaderBonuses: [guests, rateUp, dxMode, ruin, bonusStage]
    var force: Int?           // gCurrentPinballGame->forceSpecialMons
    var dex: String?          // live SRAM pokedexFlags as hex (one byte/species) — newer bridge only

    /// The live dex flags decoded from `dex`, or nil if the bridge didn't supply them.
    var dexFlags: [UInt8]? {
        guard let dex, dex.count >= 2 else { return nil }
        let chars = Array(dex)
        var out = [UInt8](); out.reserveCapacity(dex.count / 2)
        var i = 0
        while i + 1 < chars.count {
            guard let b = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            out.append(b); i += 2
        }
        return out
    }
}

/// Watches the bridge file and publishes live game state — `nil` when mGBA/the bridge isn't running.
/// Purely a reader; if the bridge is absent the app behaves exactly as before (save-file polling).
@MainActor
final class LiveBridge: ObservableObject {
    @Published private(set) var state: LiveState?
    /// True when the bridge file has gone quiet but mGBA is still running (e.g. you tabbed away and
    /// macOS throttled it). We hold the last `state` and show it as paused rather than dropping it.
    @Published private(set) var paused = false
    /// Whether mGBA itself is running. Lets the UI tell "you're just browsing the dex" apart from
    /// "a game is running and we're blind to it" — only the latter is worth nagging about.
    @Published private(set) var mgbaRunning = false

    static let path = "/tmp/pinball_pokedex_state.json"
    private let staleAfter: TimeInterval = 4
    private var timer: Timer?

    // Area debounce — the opening slot-machine roll cycles the area rapidly; we only adopt an area
    // once it's held steady, and show "Starting…" until then. Kills the cycling + false Travel jumps.
    private var stableArea = -999, pendingArea = -999
    private var stableAreaName = "-"
    private var pendingSince: Date?

    /// Call when a new game starts so the area display re-rolls (shows "Starting…" until it settles).
    func markNewGame() { stableArea = -999; pendingArea = -999; pendingSince = nil }

    private let cmdPath = "/tmp/pinball_pokedex_cmd.json"
    private var cmdSeq = Int(Date().timeIntervalSince1970)

    /// Ask the bridge to set gMain.eReaderBonuses[index] on/off in the running game (session-only).
    func setEReader(_ index: Int, _ on: Bool) { sendCommand(index, on) }

    /// Set forceSpecialMons on the running game — the next Catch 'Em Mode is guaranteed to be a
    /// special mon (Latios/Latias while uncaught). The game never clears it, so it stays on until
    /// you turn it off or the game ends.
    func setForceSpecial(_ on: Bool) { sendCommand(5, on) }

    private func sendCommand(_ index: Int, _ on: Bool) {
        cmdSeq += 1
        let json = "{\"seq\":\(cmdSeq),\"idx\":\(index),\"val\":\(on ? 1 : 0)}"
        try? json.write(toFile: cmdPath, atomically: true, encoding: .utf8)
    }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    private func isMgbaRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier?.localizedCaseInsensitiveContains("mgba") ?? false
                || ($0.localizedName?.localizedCaseInsensitiveContains("mgba") ?? false)
        }
    }

    private func poll() {
        let running = isMgbaRunning()
        if running != mgbaRunning { mgbaRunning = running }
        let fm = FileManager.default
        let mtime = (try? fm.attributesOfItem(atPath: Self.path))?[.modificationDate] as? Date
        let fresh = mtime.map { Date().timeIntervalSince($0) < staleAfter } ?? false
        guard fresh,
              let data = try? Data(contentsOf: URL(fileURLWithPath: Self.path)),
              var s = try? JSONDecoder().decode(LiveState.self, from: data)
        else {
            // Bridge went quiet. If mGBA is still running it's just backgrounded — hold the last state
            // and flag it paused. Only clear when mGBA has actually quit.
            if state != nil && running {
                if !paused { paused = true }
            } else {
                if state != nil { state = nil }
                if paused { paused = false }
                markNewGame()
            }
            return
        }
        if paused { paused = false }
        if s.active {
            if s.area != stableArea {
                if s.area == pendingArea {
                    if let t = pendingSince, Date().timeIntervalSince(t) >= 1.5 {
                        stableArea = s.area; stableAreaName = s.areaName; pendingSince = nil
                    }
                } else {
                    pendingArea = s.area; pendingSince = Date()   // new candidate area; wait for it to hold
                }
            }
            if stableArea == -999 { s.area = -1; s.areaName = "Starting…" } else { s.area = stableArea; s.areaName = stableAreaName }
        } else {
            markNewGame()
        }
        if s != state { state = s }
    }
}
