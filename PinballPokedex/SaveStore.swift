import Foundation
import SwiftUI
import AppKit

/// Loads the save, watches it for changes (polling, as requested), and publishes dex state.
@MainActor
final class SaveStore: ObservableObject {
    @Published private(set) var entries: [DexEntry]
    @Published private(set) var saveURL: URL?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var usedBackup = false
    @Published private(set) var errorMessage: String?
    @Published var actionMessage: String?
    /// saveIndices of species caught during the current game — kept visible in the guide as "just caught".
    /// Persisted so restarting the app mid-game doesn't lose them.
    @Published private(set) var sessionCaught: Set<Int> = [] {
        didSet { UserDefaults.standard.set(Array(sessionCaught), forKey: Self.sessionKey) }
    }
    private static let sessionKey = "sessionCaughtIndices"
    private var caughtBaseline: Set<Int>?
    // Hold a newly-caught Pokémon's reveal until the in-game catch animation has played.
    private let revealDelay: TimeInterval = 5
    private var lastFlags: [UInt8] = []
    private var revealedCaught: Set<Int> = []
    private var pendingReveal: [Int: DexState] = [:]   // saveIndex -> state to keep showing until reveal

    private let bookmarkKey = "saveFileBookmark"
    private var pollTimer: Timer?
    private var lastFingerprint: String?
    private var isAccessing = false
    private var savFlags: [UInt8] = []     // latest flags read from the .sav (for verifying live dex + fallback)
    private var lastLiveApply: Date?       // when verified live SRAM dex last drove the display
    private var liveTrusted = false        // did the last live dex pass the consistency check?
    private var lastCaughtThisGame = -1    // in-game catch counter, the authority on "fresh game?"

    /// True while verified live SRAM dex is the source (the .sav poll stands down).
    var liveActive: Bool { liveTrusted && (lastLiveApply.map { Date().timeIntervalSince($0) < 3 } ?? false) }
    /// Sticky: the bridge has supplied verified live dex at least once this run. Once true, the session
    /// is managed purely by the live feed, so a brief drop (cmd-tab) can't reset it.
    private(set) var everHadLiveDex = false

    init() {
        entries = PokedexData.all.map { DexEntry(pokemon: $0, state: .unknown) }
        if let saved = UserDefaults.standard.array(forKey: Self.sessionKey) as? [Int] {
            sessionCaught = Set(saved)          // restore "caught this game" across an app restart
        }
        if let url = resolveBookmark() ?? Self.defaultSaveURL {
            setSaveURL(url, persistBookmark: false)
        }
    }

    // MARK: - Derived counts

    var total: Int { entries.count }                                   // 205
    var caughtCount: Int { entries.filter { $0.state == .caught }.count }
    var seenCount: Int { entries.filter { $0.state == .seen }.count }
    var unknownCount: Int { entries.filter { $0.state == .unknown }.count }
    /// In-game completion is measured over the 201 Hoenn entries (the 4 guests don't count).
    var completionCaught: Int { entries.filter { $0.state == .caught && !$0.pokemon.isGuest }.count }
    var completionTotal: Int { entries.filter { !$0.pokemon.isGuest }.count } // 201

    // MARK: - File selection

    static var defaultSaveURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let name = "Pokemon Pinball - Ruby & Sapphire (USA).sav"
        // ~/GBA is not TCC-protected (unlike ~/Documents), so reading it triggers no permission prompt.
        let candidates = [
            home.appendingPathComponent("GBA").appendingPathComponent(name),
            home.appendingPathComponent("Documents/Game Boy Advance").appendingPathComponent(name),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Presents an Open panel so the user can point at their .sav.
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Pokémon Pinball R&S save"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let dir = saveURL?.deletingLastPathComponent() { panel.directoryURL = dir }
        if panel.runModal() == .OK, let url = panel.url {
            setSaveURL(url, persistBookmark: true)
        }
    }

    func reloadNow() { load() }

    // MARK: - Save editing (the only feature that writes the .sav)

    /// True while any of the four bonus guests is still locked (unseen) in the save.
    var canUnlockGuests: Bool { entries.contains { $0.pokemon.isGuest && $0.state == .unknown } }

    /// Enables the four bonus guests (Chikorita/Cyndaquil/Totodile/Aerodactyl) by raising their
    /// pokedexFlags to SPECIES_SHARED (2) — exactly what trading records with an e-Reader owner does.
    /// Backs up the save first; never lowers a flag. After this they spawn in catch-em mode once you
    /// have ~100 registered and 5 caught in a session (~1% per chance — the card rate-boosts aren't
    /// stored in the save, so they can't be replicated here).
    func unlockGuests() {
        guard let url = saveURL else { return }
        do {
            let original = try Data(contentsOf: url)
            guard original.count >= SaveParser.backupOffset + SaveParser.structSize else {
                throw SaveParser.ParseError.tooSmall
            }
            let backupURL = try backUpSave(url, original)

            var bytes = [UInt8](original)
            let guestIndices = PokedexData.all.filter { $0.isGuest }.map { $0.saveIndex }   // 201…204
            for base in [SaveParser.primaryOffset, SaveParser.backupOffset] {
                for gi in guestIndices where bytes[base + gi] < 2 { bytes[base + gi] = 2 }
                bumpSaveCounter(&bytes, base: base)
                writeChecksum(&bytes, base: base)
            }
            try Data(bytes).write(to: url)
            load()
            actionMessage = "Enabled the 4 guests — they'll appear in catch-em mode once you have 100 in the dex + 5 caught this session. Backup: \(backupURL.lastPathComponent)"
        } catch {
            errorMessage = "Couldn't edit save: \(error.localizedDescription)"
        }
    }

    private func backUpSave(_ url: URL, _ data: Data) throws -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmmss"
        let name = url.deletingPathExtension().lastPathComponent
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(name) (backup \(f.string(from: Date()))).sav")
        try data.write(to: backupURL)
        return backupURL
    }

    private func bumpSaveCounter(_ bytes: inout [UInt8], base: Int) {
        let p = base + 0x270   // u32 saveChangeCounter
        var c = UInt32(bytes[p]) | UInt32(bytes[p+1]) << 8 | UInt32(bytes[p+2]) << 16 | UInt32(bytes[p+3]) << 24
        c &+= 1
        bytes[p] = UInt8(c & 0xFF); bytes[p+1] = UInt8((c >> 8) & 0xFF)
        bytes[p+2] = UInt8((c >> 16) & 0xFF); bytes[p+3] = UInt8((c >> 24) & 0xFF)
    }

    /// Replicates SaveFile_WriteToSram: sum 16-bit LE words (checksum field zeroed), fold, complement.
    private func writeChecksum(_ bytes: inout [UInt8], base: Int) {
        let ck = base + 0x26E
        bytes[ck] = 0; bytes[ck + 1] = 0
        var sum: UInt32 = 0
        var i = base; let end = base + SaveParser.structSize
        while i + 1 < end { sum &+= UInt32(bytes[i]) | (UInt32(bytes[i+1]) << 8); i += 2 }
        sum = (sum & 0xFFFF) &+ (sum >> 16)
        let val = UInt16(truncatingIfNeeded: ~((sum >> 16) &+ sum))
        bytes[ck] = UInt8(val & 0xFF); bytes[ck + 1] = UInt8(val >> 8)
    }

    // MARK: - Loading & watching

    private func setSaveURL(_ url: URL, persistBookmark: Bool) {
        stopAccessing()
        saveURL = url
        isAccessing = url.startAccessingSecurityScopedResource()
        if persistBookmark {
            // Plain bookmark (app is not sandboxed); good enough to remember the location.
            if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(data, forKey: bookmarkKey)
            }
        }
        lastFingerprint = nil
        load()
        startPolling()
    }

    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func startPolling() {
        pollTimer?.invalidate()
        // mGBA only flushes the .sav on an in-game save, so a gentle poll is plenty.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.loadIfChanged() }
        }
    }

    private func fingerprint(of url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attrs[.size] as? Int) ?? -1
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        return "\(size)-\(mtime)"
    }

    private func loadIfChanged() {
        guard let url = saveURL else { return }
        let fp = fingerprint(of: url)
        if fp != nil, fp == lastFingerprint { return }
        load()
    }

    private func load() {
        guard let url = saveURL else { return }
        lastFingerprint = fingerprint(of: url)
        do {
            let data = try Data(contentsOf: url, options: .uncached)
            let parsed = try SaveParser.parse(data)
            savFlags = parsed.flags                 // always keep the latest .sav for verification + fallback
            usedBackup = parsed.usedBackup
            // When live SRAM dex is driving, don't override with the lagging .sav. And never regress to
            // a stale .sav that's behind what we already show (e.g. a brief live drop on cmd-tab).
            if !liveActive, caughtSet(parsed.flags).isSuperset(of: caughtSet(lastFlags)) {
                apply(flags: parsed.flags)
                lastUpdated = Date()
            }
            errorMessage = nil
        } catch {
            // Keep whatever we last showed (a mid-write read can transiently fail).
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Apply dex flags read live from SRAM via the bridge — but only if they pass a consistency check
    /// against the .sav (valid flag values, and every species the save says caught is also caught live).
    /// If the check fails (e.g. a wrong RAM address returning garbage), we ignore them and keep using
    /// the save file. `caughtThisGame` (the in-game catch counter) tells us when a fresh game starts.
    func applyLiveDex(_ flags: [UInt8], caughtThisGame: Int, active: Bool) {
        guard liveConsistent(flags) else { liveTrusted = false; return }
        liveTrusted = true
        everHadLiveDex = true
        lastLiveApply = Date()
        lastUpdated = Date()
        errorMessage = nil
        let count = active ? caughtThisGame : 0
        let prev = lastCaughtThisGame
        lastCaughtThisGame = count
        let newGame = (prev < 0 && count == 0) || (prev >= 0 && count < prev)
        if newGame {
            lastFlags = flags
            let caught = currentCaught()
            caughtBaseline = caught
            revealedCaught = caught
            pendingReveal.removeAll()
            sessionCaught.removeAll()
            rebuildEntries()
        } else if flags != lastFlags {
            apply(flags: flags)
        }
    }

    /// Safety gate for live dex: reject invalid flag bytes and anything that contradicts the save.
    private func liveConsistent(_ flags: [UInt8]) -> Bool {
        let n = SaveParser.numSpecies
        guard flags.count >= n else { return false }
        for i in 0..<n where flags[i] > 4 { return false }                       // only 0…4 are valid flags
        if savFlags.count >= n {
            for i in 0..<n where savFlags[i] == 4 && flags[i] != 4 { return false } // live must include every saved catch
        }
        return true
    }

    private func apply(flags: [UInt8]) {
        lastFlags = flags
        let rawCaught = Set(PokedexData.all.filter {
            let f = $0.saveIndex < flags.count ? flags[$0.saveIndex] : 0
            return DexState.from(flag: f) == .caught
        }.map { $0.saveIndex })

        if caughtBaseline == nil {
            // First load: whatever's already caught shows immediately (no delay, not "this session").
            caughtBaseline = rawCaught
            revealedCaught = rawCaught
        } else {
            // A genuinely new catch — hold its reveal until the in-game catch animation has played,
            // so the app doesn't spoil it. Keep showing its pre-catch look until the timer fires.
            for idx in rawCaught.subtracting(revealedCaught) where pendingReveal[idx] == nil {
                let prior = entries.first { $0.pokemon.saveIndex == idx }?.state ?? .seen
                pendingReveal[idx] = (prior == .caught ? .seen : prior)
                DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) { [weak self] in
                    guard let self, self.pendingReveal[idx] != nil else { return }   // cancelled by a session reset
                    self.pendingReveal[idx] = nil
                    self.revealedCaught.insert(idx)
                    if self.caughtBaseline?.contains(idx) == false { self.sessionCaught.insert(idx) }
                    self.rebuildEntries()
                }
            }
        }
        rebuildEntries()
    }

    private func caughtSet(_ flags: [UInt8]) -> Set<Int> {
        Set(PokedexData.all.filter {
            let f = $0.saveIndex < flags.count ? flags[$0.saveIndex] : 0
            return DexState.from(flag: f) == .caught
        }.map { $0.saveIndex })
    }
    private func currentCaught() -> Set<Int> { caughtSet(lastFlags) }

    /// Called when the live bridge sees a game start or end. Re-baselines "this session" to whatever is
    /// currently caught, so the highlight only ever tracks the current game — and doesn't linger after
    /// you finish a game or quit mGBA. Any in-flight reveal timers are cancelled (their guard checks
    /// `pendingReveal`); everything actually caught is shown as caught immediately.
    func resetLiveSession() {
        let caught = currentCaught()
        caughtBaseline = caught
        revealedCaught = caught
        pendingReveal.removeAll()
        if !sessionCaught.isEmpty { sessionCaught.removeAll() }
        rebuildEntries()
    }

    /// Rebuilds the published dex from the last-read flags, holding back any catch still inside its
    /// reveal delay (shown in its pre-catch state until the timer fires).
    private func rebuildEntries() {
        entries = PokedexData.all.map { mon in
            let flag = mon.saveIndex < lastFlags.count ? lastFlags[mon.saveIndex] : 0
            var st = DexState.from(flag: flag)
            if st == .caught, !revealedCaught.contains(mon.saveIndex) {
                st = pendingReveal[mon.saveIndex] ?? .seen   // not revealed yet → keep its prior look
            }
            return DexEntry(pokemon: mon, state: st)
        }
    }

    private func stopAccessing() {
        if isAccessing { saveURL?.stopAccessingSecurityScopedResource() }
        isAccessing = false
    }
}
