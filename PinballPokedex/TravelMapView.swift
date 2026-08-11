import SwiftUI

/// The Travel-mode area loop. Each field has 6 areas you cycle through (you start on a random one),
/// plus the Ruins as the special stop reached by travelling the same direction repeatedly.
struct TravelMapView: View {
    var embedded = false                         // true = shown inside the slider pager (no Done / fixed frame)
    @EnvironmentObject private var store: SaveStore
    @EnvironmentObject private var live: LiveBridge
    @AppStorage("spriteStyle") private var styleRaw = SpriteStyle.modern.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var field = "Ruby"

    private var style: SpriteStyle { SpriteStyle(rawValue: styleRaw) ?? .modern }

    // The 6-area loop per field, in Bulbapedia's documented in-game order (Ruins is the special 7th).
    private var loops: [String: [String]] { TravelData.loops }

    private var currentBiome: String? {
        guard let s = live.state, s.active else { return nil }
        return s.areaName.split(separator: " ").first.map(String.init)
    }
    private var liveField: String? {
        guard let s = live.state, s.active else { return nil }
        return s.field == 0 ? "Ruby" : "Sapphire"
    }

    private func speciesIn(_ biome: String) -> [DexEntry] {
        store.entries.filter { e in
            e.pokemon.catchAreas.contains { $0.biome == biome && ($0.field == field || $0.field == "Both") }
        }.sorted { $0.pokemon.num < $1.pokemon.num }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "tram.fill").foregroundStyle(.brown)
                Text("Travel map").font(.headline)
                Spacer()
                Picker("", selection: $field) { Text("Ruby").tag("Ruby"); Text("Sapphire").tag("Sapphire") }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                if !embedded { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            }
            .padding(14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let cb = currentBiome, field == liveField, let loop = loops[field], let idx = loop.firstIndex(of: cb) {
                        nextStops(current: cb, left: loop[(idx + 1) % loop.count], right: loop[(idx + 2) % loop.count])
                    }
                    mechanic
                    ForEach(Array((loops[field] ?? []).enumerated()), id: \.element) { i, biome in
                        areaCard(biome, stop: i + 1, isCurrent: biome == currentBiome)
                        Image(systemName: "arrow.down").font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                    areaCard("Ruins", stop: 7, isCurrent: currentBiome == "Ruins", isRuins: true)
                }
                .padding(16)
            }
        }
        .frame(minWidth: embedded ? nil : 560, maxWidth: embedded ? .infinity : nil,
               minHeight: embedded ? nil : 620, maxHeight: embedded ? .infinity : nil)
        .onReceive(live.$state) { s in   // auto-follow the table you're actually playing
            if let s, s.active {
                let f = s.field == 0 ? "Ruby" : "Sapphire"
                if f != field { field = f }
            }
        }
    }

    private var mechanic: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How travel works", systemImage: "info.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.blue)
            Text("You start in a **random** area. Light Travel, then take the **left loop to advance 1 area** or the **right loop to advance 2** — that's your two choices each stop. Keep going the **same direction (~5–6 times)** to reach the **Ruins**, where the legendaries live. Volbeat (Ruby) / Illumise (Sapphire) paints the area when you arrive.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.10)))
    }

    private func nextStops(current: String, left: String, right: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("You're in \(current) — where next?", systemImage: "arrow.triangle.branch").font(.subheadline.weight(.bold))
            HStack(spacing: 12) {
                destBox(dir: "Left loop", note: "advances 1 area", to: left, icon: "arrow.turn.up.left", color: .green)
                destBox(dir: "Right loop", note: "advances 2 areas", to: right, icon: "arrow.turn.up.right", color: .orange)
            }
            Text("Keep taking the same loop to advance further each time — repeat enough and you reach the Ruins.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.12)))
    }

    private func destBox(dir: String, note: String, to: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(dir, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(to).font(.title3.bold())
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.15)))
    }

    private func areaCard(_ biome: String, stop: Int, isCurrent: Bool, isRuins: Bool = false) -> some View {
        let mons = speciesIn(biome)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(stop)").font(.caption.bold().monospacedDigit())
                    .frame(width: 20, height: 20).background(Circle().fill(isRuins ? Color.purple : Color.secondary.opacity(0.3)))
                Image(systemName: isRuins ? "building.columns.fill" : "mappin.circle.fill").foregroundStyle(isRuins ? .purple : .secondary)
                Text(biome).font(.headline)
                Text("\(mons.count)").font(.subheadline).foregroundStyle(.secondary)
                if isCurrent {
                    Label("you're here", systemImage: "location.fill").font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(.blue))
                }
                Spacer()
            }
            if isRuins {
                Text("Reached by travelling one direction repeatedly. Regirock/Regice/Registeel/Beldum, and Jirachi via the slots.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !mons.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 56), spacing: 6)], spacing: 6) {
                    ForEach(mons) { e in
                        SpriteView(mon: e.pokemon,
                                   mode: e.state == .caught ? .color : (e.state == .seen ? .grayscale : .silhouette),
                                   style: style)
                            .frame(height: 40)
                            .help(e.state == .unknown ? "#\(e.pokemon.num)" : e.pokemon.name)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isCurrent ? Color.blue : .clear, lineWidth: 2))
    }
}
