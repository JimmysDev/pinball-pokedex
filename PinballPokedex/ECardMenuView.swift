import SwiftUI
import AppKit

/// Loads & caches the cropped e-Reader card artwork bundled in Resources/ecards (ecard0…4.png).
/// Real card scans, cropped to just the inner illustration. idx 4 (Bonus Stage) has no scan yet.
private enum ECardArt {
    private static var cache: [Int: NSImage] = [:]
    static func image(_ idx: Int) -> NSImage? {
        if let img = cache[idx] { return img }
        guard let url = Bundle.main.url(forResource: "ecard\(idx)", withExtension: "png", subdirectory: "ecards")
                ?? Bundle.main.url(forResource: "ecard\(idx)", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[idx] = img
        return img
    }
}

/// Toggle the five e-Reader bonus flags live in the running game (via the bridge, which writes
/// gMain.eReaderBonuses). Session-only — they reset when the game is powered off.
struct ECardMenuView: View {
    @EnvironmentObject private var live: LiveBridge
    @Environment(\.dismiss) private var dismiss
    @State private var optimistic: [Int: Bool] = [:]   // shown until the live flag catches up

    private struct Card { let idx: Int; let name: String; let effect: String; let icon: String; let color: Color }
    private let cards: [Card] = [
        .init(idx: 1, name: "Encounter Rate Up",
              effect: "Doubles rare & guest spawn odds (1% → 2%). Heads-up: this halves Pichu's egg odds (2% → 1%) — a genuine game bug.",
              icon: "chart.line.uptrend.xyaxis", color: .green),
        .init(idx: 0, name: "Special Guests",
              effect: "Forces a guest you're missing (Chikorita / Cyndaquil / Totodile / Aerodactyl) to appear in catch-em mode. One-shot — flips back off once one spawns.",
              icon: "person.3.fill", color: .purple),
        .init(idx: 3, name: "Ruin Area",
              effect: "Unlocks the Ruins area from the start instead of travelling there. Takes effect on your next game.",
              icon: "building.columns.fill", color: .brown),
        .init(idx: 2, name: "DX Mode",
              effect: "Deluxe start — bonus-field select at launch plus DX ball-upgrade visuals. Takes effect on your next game.",
              icon: "sparkles", color: .yellow),
        .init(idx: 4, name: "Bonus Stage",
              effect: "Jump straight into a bonus stage (Groudon / Kyogre / Rayquaza rounds).",
              icon: "gift.fill", color: .orange),
    ]

    private var connected: Bool { live.state?.ereader != nil }
    private func liveVal(_ idx: Int) -> Int {
        guard let er = live.state?.ereader, idx < er.count else { return 0 }
        return er[idx]
    }
    private func binding(_ idx: Int) -> Binding<Bool> {
        Binding(get: { optimistic[idx] ?? (liveVal(idx) != 0) },
                set: { on in optimistic[idx] = on; live.setEReader(idx, on) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "creditcard.fill").foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("e-Reader Bonuses").font(.headline)
                    Text("Toggle the card bonuses live in your game · session-only").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(14)
            Divider()

            if !connected {
                VStack(spacing: 10) {
                    Image(systemName: "bolt.horizontal.circle").font(.largeTitle).foregroundStyle(.orange)
                    Text("Bridge not sending e-Reader data").font(.headline)
                    Text("Load the mGBA bridge (with e-Reader support) while a game is running, then reopen this.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: 360).frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        forceRow
                        Divider().padding(.vertical, 2)
                        ForEach(cards, id: \.idx) { row($0) }
                        Text("These live in RAM only, so they reset when the game is powered off (not saved). Beating Rayquaza does not set any of them — only these toggles (or scanning the real cards) do.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }.padding(16)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 540)
        .onReceive(live.$state) { s in
            for (idx, want) in optimistic {
                let liveOn = idx == 5
                    ? (s?.force ?? 0) != 0
                    : (s?.ereader?.indices.contains(idx) == true ? s!.ereader![idx] : 0) != 0
                if liveOn == want { optimistic.removeValue(forKey: idx) }   // live caught up → drop override
            }
        }
    }

    /// Not an e-Reader card — `forceSpecialMons` is a dev flag the ROM reads but never writes, so
    /// setting it skips the 1-in-100 roll entirely and guarantees the next Catch 'Em Mode is a
    /// special mon (Latios on Ruby / Latias on Sapphire while uncaught).
    private var forceRow: some View {
        let live0 = (live.state?.force ?? 0) != 0
        let on = Binding(get: { optimistic[5] ?? live0 },
                         set: { v in optimistic[5] = v; live.setForceSpecial(v) })
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.pink.opacity(0.16))
                Image(systemName: "wand.and.stars").font(.system(size: 24, weight: .bold)).foregroundStyle(.pink)
            }
            .frame(width: 132, height: 84)
            VStack(alignment: .leading, spacing: 3) {
                Text("Force Special Mon").font(.headline)
                Text("Guarantees the next Catch 'Em Mode is a special mon — Latios (Ruby) / Latias (Sapphire) while uncaught, otherwise a random guest. Skips the 1-in-100 roll and the 5-caught requirement. Stays on until you switch it off, so flip it back after the catch.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: on).labelsHidden().toggleStyle(.switch)
                .disabled(live.state?.active != true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.pink.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.pink.opacity(0.25), lineWidth: 1))
    }

    /// The card's real inner artwork (cropped scan). idx 4 (Bonus Stage) isn't scanned yet, so it
    /// shows a themed placeholder instead.
    private func cardArt(_ c: Card) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(c.color.opacity(0.14))
            if let img = ECardArt.image(c.idx) {
                Image(nsImage: img).resizable().scaledToFit().padding(3)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: c.icon).font(.system(size: 22, weight: .bold)).foregroundStyle(c.color)
                    Text("no scan yet").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 132, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.black.opacity(0.12), lineWidth: 1))
    }

    private func row(_ c: Card) -> some View {
        HStack(spacing: 14) {
            cardArt(c)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.name).font(.headline)
                Text(c.effect).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: binding(c.idx)).labelsHidden().toggleStyle(.switch)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
