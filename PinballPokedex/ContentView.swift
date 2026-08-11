import SwiftUI

enum DexFilter: String, CaseIterable, Identifiable {
    case all = "All", caught = "Caught", seen = "Seen", unknown = "Unknown"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var store: SaveStore
    @EnvironmentObject private var live: LiveBridge
    @State private var filter: DexFilter = .all
    @State private var search = ""
    @State private var modePos: Double = 0          // 0 = Pokédex, 1 = Catch now, 2 = Travel
    @State private var showUnlockConfirm = false
    @State private var showECards = false
    @State private var showBridgeSetup = false
    @State private var bridgePulse = false
    @State private var wasActive = false
    @State private var inactiveAt: Date?            // when the bridge last went quiet (debounces focus-pause blips)
    @State private var gameStartedAt: Date?         // game start, for the travel "opening grace"
    @State private var settledArea: Int?            // last stable area, for detecting real travels
    @State private var launchedAt: Date?            // app-launch time, to treat an in-progress game as a join
    @State private var sawActiveThisLaunch = false  // have we seen a running game since this launch?
    @State private var lastCaught = -1              // last caughtThisGame; a drop = a new game started
    @AppStorage("hasConnectedBridgeOnce") private var hasConnectedBridgeOnce = false
    @AppStorage("gridScale") private var scale: Double = 1.25
    @AppStorage("spriteStyle") private var styleRaw = SpriteStyle.modern.rawValue

    private var style: SpriteStyle { SpriteStyle(rawValue: styleRaw) ?? .modern }
    private let pikachu = PokedexData.all.first { $0.num == 156 }
    private let cyndaquil = PokedexData.all.first { $0.num == 203 }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 104 * scale, maximum: 150 * scale), spacing: 12)]
    }

    private func setScale(_ v: Double) { scale = min(2.2, max(0.7, (v * 100).rounded() / 100)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let msg = store.actionMessage { actionBanner(msg) }
            modeSlider
            Divider()
            pager
        }
        .frame(minWidth: 640, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowAccessor(autosaveName: "PinballPokedexMain"))   // remember size + position
        .onReceive(live.$state) { s in
            // Once the bridge has ever worked, the chip stops saying "Set up live bridge" — from then
            // on being off is a normal state, not something the user needs teaching about.
            if s != nil && !hasConnectedBridgeOnce { hasConnectedBridgeOnce = true }
            // Verified live SRAM dex → reflect catches instantly + drive "new this game" off the
            // in-game catch counter. If it fails the consistency check, the store ignores it.
            if let s, let flags = s.dexFlags {
                store.applyLiveDex(flags, caughtThisGame: s.caughtThisGame, active: s.active)
            }
            // Reliable new-game signal: the in-game catch counter reset to/towards 0. Force Catch now and
            // restart the travel opening-grace, so the opening slot's area-cycling can't fling us to Travel.
            if let s, s.active {
                if lastCaught >= 0, s.caughtThisGame < lastCaught {
                    setMode(.catchNow)
                    gameStartedAt = Date()
                    settledArea = nil
                    live.markNewGame()        // re-roll the area display (suppress slot cycling)
                }
                lastCaught = s.caughtThisGame
            }
            // Once live dex is in play it self-manages the session (off the catch counter), so a brief
            // drop (cmd-tab away) must NOT reset it. Only the no-bridge path resets on transitions.
            let liveManaged = store.everHadLiveDex
            let active = s?.active ?? false
            if active && !wasActive {
                if !sawActiveThisLaunch {
                    // First running game we see this launch. If it's already there at/near launch we're
                    // joining a game in progress (e.g. the app was rebuilt mid-play) → KEEP the restored
                    // session. If it only appears well after launch, it's a fresh game → reset.
                    sawActiveThisLaunch = true
                    let joinedInProgress = (launchedAt.map { Date().timeIntervalSince($0) } ?? 0) < 5
                    if joinedInProgress {
                        setMode(.catchNow)
                        gameStartedAt = Date()   // grace so the area-debounce settle isn't read as a travel
                        settledArea = nil
                    } else {
                        if !liveManaged { store.resetLiveSession() }
                        setMode(.catchNow)
                        gameStartedAt = Date()
                        settledArea = nil
                    }
                } else {
                    // Already saw a game this launch: a brief reconnect (focus pause) is a resume; a
                    // long gap is a genuine new game.
                    let gap = inactiveAt.map { Date().timeIntervalSince($0) } ?? .infinity
                    if gap > 6 {
                        if !liveManaged { store.resetLiveSession() }
                        setMode(.catchNow)
                        gameStartedAt = Date()          // start the travel grace (skip the opening slot)
                        settledArea = nil
                    }
                }
                inactiveAt = nil
            } else if !active && wasActive {
                inactiveAt = Date()
                // No live dex: clear "this session" if the game stays gone (real end/quit), not a brief pause.
                if !liveManaged {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [store, live] in
                        if !(live.state?.active ?? false) { store.resetLiveSession() }
                    }
                }
            }
            // No auto-switch to Travel: the only signal we have (the area changing) fires AFTER you've
            // already travelled, which is too late and sticky. Travel stays manual until we can detect
            // travel-mode activation from RAM (pending the bridge `dbg` capture). The Travel pane still
            // shows your current area + left/right options whenever you open it.
            wasActive = active
        }
        .onAppear {
            // Record launch time so an already-running game is treated as a join (keeps the restored
            // session) rather than a new game. The session now clears only on a real new-game/end.
            if launchedAt == nil { launchedAt = Date() }
        }
        .sheet(isPresented: $showECards) {
            ECardMenuView().environmentObject(live)
        }
        .sheet(isPresented: $showBridgeSetup) {
            BridgeSetupView().environmentObject(live)
        }
        .alert("Enable the Johto starters & Aerodactyl?", isPresented: $showUnlockConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Back up & enable") { store.unlockGuests() }
        } message: {
            Text("This edits your save — a timestamped backup is saved next to it first. Quit mGBA before doing this so it doesn't overwrite the change.\n\nIt marks the four guests as 'seen via trade' (exactly like trading with an e-Reader owner). They then appear in catch-em mode once you've registered 100 Pokémon and caught 5 in a session — you still catch them yourself. Catch Latias/Latios first (they're higher-priority spawns).")
        }
    }

    private func setMode(_ m: AppMode) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { modePos = Double(m.rawValue) }
    }

    // MARK: Mode slider + pager

    private var modeSlider: some View {
        HStack(spacing: 12) {
            if let s = live.state, s.active { liveChip(s) }
            Spacer(minLength: 8)
            ModeSlider(pos: $modePos).frame(maxWidth: 380)
            Spacer(minLength: 8)
            dexCounter
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    /// Big caught / total counter on the right of the slider row.
    private var dexCounter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(store.completionCaught)").font(.title.bold().monospacedDigit())
                .foregroundStyle(store.completionCaught == store.completionTotal ? Color.green : Color.primary)
            Text("/\(store.completionTotal)").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            Text("caught").font(.caption).foregroundStyle(.secondary).padding(.leading, 2)
        }
        .help("\(store.completionCaught) of \(store.completionTotal) Hoenn-dex Pokémon caught")
    }

    /// Compact current-area chip that sits at the left of the mode-slider row (instead of a full
    /// banner). Icon + area + catches-this-game; the 100-dex super-rare gate is in the tooltip.
    private func liveChip(_ s: LiveState) -> some View {
        let biome = s.areaName.split(separator: " ").first.map(String.init) ?? "-"
        let paused = live.paused
        let tint: Color = paused ? .gray : (s.field == 0 ? .red : .blue)
        return Label("\(s.areaName) · \(s.caughtThisGame)", systemImage: paused ? "pause.circle.fill" : biomeSymbol(biome))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(paused ? Color.secondary : Color.primary)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.18)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
            .opacity(paused ? 0.65 : 1)
            .help(paused ? "Paused — mGBA is in the background; live state held until you return."
                  : (s.registered >= 100
                     ? "\(s.registered)/100 registered — super-rares can appear · \(s.caughtThisGame) caught this game"
                     : "\(s.registered)/100 registered · \(s.caughtThisGame) caught this game"))
    }

    private var pager: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                pokedexPanel.frame(width: geo.size.width, height: geo.size.height)
                CatchGuideView(embedded: true).frame(width: geo.size.width, height: geo.size.height)
                TravelMapView(embedded: true).frame(width: geo.size.width, height: geo.size.height)
            }
            .offset(x: -CGFloat(modePos) * geo.size.width)
        }
        .clipped()
    }

    private var pokedexPanel: some View {
        VStack(spacing: 0) {
            statsBar
            controls
            Divider()
            if store.saveURL == nil { emptyPrompt } else { grid }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("dexicon")
                .resizable()
                .interpolation(.none)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pinball Pokédex").font(.title2.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let err = store.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .lineLimit(2).frame(maxWidth: 240, alignment: .trailing)
            }
            bridgeChip
            Button { showECards = true } label: { Image(systemName: "creditcard") }
                .help("e-Reader bonuses")
            Button { store.reloadNow() } label: { Image(systemName: "arrow.clockwise") }
                .help("Reload now")
            Button { store.chooseFile() } label: { Label("Open…", systemImage: "folder") }
                .help("Choose a different .sav")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// mGBA is running but the bridge isn't — a game is going and we're blind to it. This is the only
    /// state worth drawing attention to; with mGBA closed you're just browsing the dex, so stay calm.
    private var bridgeNagging: Bool { live.state == nil && live.mgbaRunning }

    /// Shows whether the mGBA Lua bridge is live, and doubles as the way to (re)load it. Re-loading
    /// is a chore you repeat on every mGBA relaunch, so "Copy bridge script" is one click from here.
    private var bridgeChip: some View {
        let connected = live.state != nil
        let title = connected ? "Live" : (hasConnectedBridgeOnce ? "Bridge off" : "Set up live bridge")
        let icon = connected ? "dot.radiowaves.left.and.right"
                             : (bridgeNagging ? "exclamationmark.triangle.fill" : "bolt.horizontal.circle")
        let tint: Color = connected ? .green : (bridgeNagging ? .orange : .secondary)
        return Menu {
            Button("Copy bridge script") { BridgeScript.copyToPasteboard() }
            Button("Setup guide…") { showBridgeSetup = true }
            Divider()
            Button("Reveal script in Finder") { BridgeScript.revealInFinder() }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(bridgeNagging ? .semibold : .medium))
                .foregroundStyle(tint)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .scaleEffect(bridgePulse ? 1.14 : 1)
        .help(connected
              ? "mGBA live bridge connected — live area, catch tracking and the e-Reader toggles are active."
              : (bridgeNagging
                 ? "mGBA is running but the bridge isn't loaded — click to copy the script or open the guide."
                 : "Live bridge isn't loaded. Click for the setup guide. It must be re-run each time you relaunch mGBA."))
        .onChange(of: bridgeNagging) { nag in if nag { firePulse() } }
        .onAppear { if bridgeNagging { firePulse() } }
    }

    /// Three pulses, then rest — a permanent loop next to something you stare at while playing gets
    /// irritating, but a static badge alone is easy to miss when it first appears.
    private func firePulse() {
        withAnimation(.easeInOut(duration: 0.42).repeatCount(3, autoreverses: true)) { bridgePulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { bridgePulse = false }
    }

    private var subtitle: String {
        guard let url = store.saveURL else { return "No save loaded" }
        var s = url.lastPathComponent
        if store.usedBackup { s += "  ·  backup copy" }
        if let t = store.lastUpdated {
            let f = DateFormatter(); f.timeStyle = .medium
            s += "  ·  updated \(f.string(from: t))"
        }
        return s
    }

    private func actionBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            Text(msg).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { store.actionMessage = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.green.opacity(0.12))
    }

    // MARK: Stats

    private var statsBar: some View {
        HStack(spacing: 10) {
            chip("Caught", store.caughtCount, .green, "circle.circle.fill")
            chip("Seen", store.seenCount, .orange, "eye.fill")
            chip("Unknown", store.unknownCount, .gray, "questionmark")
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Dex \(store.completionCaught) / \(store.completionTotal) caught")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                ProgressView(value: Double(store.completionCaught),
                             total: Double(max(store.completionTotal, 1)))
                    .frame(width: 180)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func chip(_ title: String, _ count: Int, _ color: Color, _ symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption2).foregroundStyle(color)
            Text("\(count)").font(.subheadline.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("", selection: $filter) {
                ForEach(DexFilter.allCases) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 340)

            Spacer(minLength: 8)

            johtoToggle
            styleToggle
            zoomControl

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search name or #number", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    @ViewBuilder private var johtoToggle: some View {
        if let cyndaquil {
            let on = !store.canUnlockGuests          // on = the four guests are enabled in the save
            Button {
                if store.canUnlockGuests { showUnlockConfirm = true }
            } label: {
                SpriteView(mon: cyndaquil, mode: on ? .color : .grayscale, style: .modern)
                    .frame(width: 30, height: 24)
                    .opacity(on ? 1 : 0.85)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(on ? "Johto starters: enabled in your save"
                     : "Johto starters: locked — click to enable Chikorita/Cyndaquil/Totodile/Aerodactyl in your save")
        }
    }

    @ViewBuilder private var styleToggle: some View {
        if let pikachu {
            Button {
                styleRaw = style.opposite.rawValue
            } label: {
                // The icon shows Pikachu in the style you'll switch TO.
                SpriteView(mon: pikachu, mode: .color, style: style.opposite)
                    .frame(width: 30, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Sprites: \(style.label) — click for \(style.opposite.label) style")
        }
    }

    private var zoomControl: some View {
        HStack(spacing: 4) {
            Button { setScale(scale - 0.15) } label: { Image(systemName: "minus") }
                .disabled(scale <= 0.71)
            Text("\(Int((scale * 100).rounded()))%")
                .font(.caption.monospacedDigit()).frame(width: 38)
            Button { setScale(scale + 0.15) } label: { Image(systemName: "plus") }
                .disabled(scale >= 2.19)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .help("Resize the grid")
    }

    // MARK: Grid

    private var filtered: [DexEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let digits = q.filter(\.isNumber)
        return store.entries.filter { e in
            switch filter {
            case .all: break
            case .caught:  if e.state != .caught  { return false }
            case .seen:    if e.state != .seen    { return false }
            case .unknown: if e.state != .unknown { return false }
            }
            guard !q.isEmpty else { return true }
            // Names of unknown mons stay hidden, so they only match by number.
            let nameMatch = e.state != .unknown && e.pokemon.name.lowercased().contains(q)
            let numMatch = !digits.isEmpty && String(e.pokemon.num).contains(digits)
            return nameMatch || numMatch
        }
    }

    private var grid: some View {
        ScrollView {
            if filtered.isEmpty {
                Text("Nothing matches.")
                    .foregroundStyle(.secondary).padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filtered) { PokemonCell(entry: $0, scale: scale, style: style) }
                }
                .padding(16)
            }
        }
    }

    // MARK: Empty

    private var emptyPrompt: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray.and.arrow.down").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Point me at your save file").font(.title3.bold())
            Text("Choose your Pokémon Pinball: Ruby & Sapphire .sav.\nIt usually lives next to the ROM in your mGBA folder.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).font(.callout)
            Button { store.chooseFile() } label: { Label("Open Save File…", systemImage: "folder") }
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Persists the window's frame (size + position) across launches via AppKit's frame autosave.
struct WindowAccessor: NSViewRepresentable {
    let autosaveName: String
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window {
                w.setFrameAutosaveName(autosaveName)
                w.setFrameUsingName(autosaveName)
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum AppMode: Int, CaseIterable, Identifiable {
    case pokedex, catchNow, travel
    var id: Int { rawValue }
    var title: String { ["Pokédex", "Catch now", "Travel"][rawValue] }
    var icon: String { ["square.grid.2x2.fill", "binoculars.fill", "tram.fill"][rawValue] }
}

/// A 3-position slider — click a segment or drag the thumb. `pos` is continuous (0…2) so the pager
/// content can track the thumb 1:1 while dragging, and springs to the nearest mode on release.
struct ModeSlider: View {
    @Binding var pos: Double
    private let modes = AppMode.allCases

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let seg = w / CGFloat(modes.count)
            let live = Int(pos.rounded())
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: (h - 6) / 2, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: seg - 6, height: h - 6)
                    .offset(x: CGFloat(pos) * seg + 3)
                HStack(spacing: 0) {
                    ForEach(modes) { m in
                        Label(m.title, systemImage: m.icon)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(live == m.rawValue ? Color.white : Color.secondary)
                            .frame(width: seg, height: h)
                    }
                }
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        pos = Double(min(max(0, v.location.x / seg - 0.5), CGFloat(modes.count - 1)))
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { pos = pos.rounded() }
                    }
            )
        }
        .frame(height: 36)
    }
}
