import SwiftUI

/// "What can I catch right now?" — everything not yet caught, organised by the **area** where you'd
/// get it (using the decompilation's wild-encounter tables). Evolutions sit under the area where you
/// catch their base form; when the base has been discovered it's shown (dimmed) as an anchor so you
/// remember who it is, followed by its evolutions. Tiles are colour-coded by field — purple Both,
/// red Ruby, blue Sapphire. While a game runs, the current area + table is pulled to the top.
struct CatchGuideView: View {
    var embedded = false                         // true = shown inside the slider pager (no Done / fixed frame)
    @EnvironmentObject private var store: SaveStore
    @EnvironmentObject private var live: LiveBridge
    @AppStorage("spriteStyle") private var styleRaw = SpriteStyle.modern.rawValue
    @Environment(\.dismiss) private var dismiss

    private var style: SpriteStyle { SpriteStyle(rawValue: styleRaw) ?? .modern }
    private let cols = [GridItem(.adaptive(minimum: 98, maximum: 128), spacing: 10)]
    private let fieldRank = ["Both": 0, "Ruby": 1, "Sapphire": 2]

    private struct Item: Identifiable {
        let entry: DexEntry; let field: String; let caption: String?
        let familyKey: String; let isEvolve: Bool; var isReminder = false; var dimmed = false
        var id: String { "\(entry.id)\(isReminder ? "-r" : "")\(dimmed ? "-d" : "")" }
    }
    private struct Section: Identifiable {
        let title: String; let sub: String?; let symbol: String; let tint: Color
        let items: [Item]; var highlight: Color? = nil; var id: String { title }
    }

    private var currentFieldName: String? {
        guard let s = live.state, s.active else { return nil }
        return s.field == 0 ? "Ruby" : "Sapphire"
    }
    private var currentBiome: String? {   // biome names now match the bridge directly
        guard let s = live.state, s.active else { return nil }
        return s.areaName.split(separator: " ").first.map(String.init)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded { header; Divider() }   // in the slider pager the title row is redundant
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    travelRow
                    let sections = build()
                    if sections.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(.yellow)
                            Text("You've caught every Pokémon. 🎉").font(.title3.bold())
                        }.frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(sections) { sectionView($0) }
                    }
                }.padding(16)
            }
        }
        .frame(minWidth: embedded ? nil : 580, maxWidth: embedded ? .infinity : nil,
               minHeight: embedded ? nil : 620, maxHeight: embedded ? .infinity : nil)
    }

    /// A very small row showing where the left (advance 1) / right (advance 2) loop takes you from here.
    @ViewBuilder private var travelRow: some View {
        if let cf = currentFieldName, let biome = currentBiome, let stops = TravelData.nextStops(field: cf, biome: biome) {
            HStack(spacing: 18) {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.up.left").foregroundStyle(.green)
                    Text("Left").fontWeight(.semibold).foregroundStyle(.green)
                    Text(stops.left).foregroundStyle(.primary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.up.right").foregroundStyle(.orange)
                    Text("Right").fontWeight(.semibold).foregroundStyle(.orange)
                    Text(stops.right).foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
            }
            .font(.caption2).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.brown.opacity(0.10)))
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "binoculars.fill").foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 1) {
                Text("What can I catch right now?").font(.headline)
                Text("\(store.entries.filter { $0.state != .caught }.count) still to catch")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let s = live.state, s.active {
                Label(s.areaName, systemImage: currentBiome.map(biomeSymbol) ?? "location.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(.blue))
            }
            Spacer()
            if !embedded { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(14)
    }

    private static let bothSplit = LinearGradient(
        stops: [.init(color: .red, location: 0.5), .init(color: .blue, location: 0.5)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Self.bothSplit).frame(width: 11, height: 11); Text("Both").font(.caption2) }
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(.red).frame(width: 11, height: 11); Text("Ruby").font(.caption2) }
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(.blue).frame(width: 11, height: 11); Text("Sapphire").font(.caption2) }
            HStack(spacing: 4) { Image(systemName: "arrow.up.forward.circle.fill").font(.caption2).foregroundStyle(.green); Text("evolve").font(.caption2) }
            Spacer()
        }.foregroundStyle(.secondary)
    }

    private func sectionView(_ s: Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: s.symbol).foregroundStyle(s.tint)
                Text(s.title).font(.headline)
                Text("\(s.items.count)").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            if let sub = s.sub { Text(sub).font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(s.items) {
                    PokemonCell(entry: $0.entry, scale: 0.95, style: style, caption: $0.caption,
                                fieldName: $0.field, isReminder: $0.isReminder, dimmed: $0.dimmed, isEvolve: $0.isEvolve)
                }
            }
        }
        .padding(s.highlight != nil ? 8 : 0)
        .background(RoundedRectangle(cornerRadius: 12).fill((s.highlight ?? .clear).opacity(s.highlight != nil ? 0.10 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder((s.highlight ?? .clear).opacity(s.highlight != nil ? 0.8 : 0), lineWidth: 2))
    }

    // MARK: - Data

    private func build() -> [Section] {
        let byName = Dictionary(uniqueKeysWithValues: PokedexData.all.map { ($0.name, $0) })
        let stateByName = Dictionary(uniqueKeysWithValues: store.entries.map { ($0.pokemon.name, $0.state) })
        func base(_ m: Pokemon) -> Pokemon {
            var cur = m, n = 0
            while !cur.isCatchable, !cur.isEgg, let f = cur.evolvesFrom, let pre = byName[f], n < 8 { cur = pre; n += 1 }
            return cur
        }
        func discovered(_ name: String) -> Bool { (stateByName[name] ?? .unknown) != .unknown }

        var byBiome = [String: [Item]]()
        var eggItems = [Item](), special = [Item]()

        for e in store.entries {
            let m = e.pokemon
            let dim = e.state == .caught && !store.sessionCaught.contains(m.saveIndex)   // caught (not new) → darkened
            if !m.isCatchable, !m.isEgg, m.evolvesFrom == nil {
                special.append(Item(entry: e, field: m.field, caption: nil, familyKey: m.name, isEvolve: false, dimmed: dim)); continue
            }
            if m.isCatchable {
                for a in m.catchAreas {
                    byBiome[a.biome, default: []].append(Item(entry: e, field: a.field, caption: nil, familyKey: m.name, isEvolve: false, dimmed: dim))
                }
            } else if let eggF = m.egg {
                eggItems.append(Item(entry: e, field: eggF, caption: nil, familyKey: m.name, isEvolve: false, dimmed: dim))
            } else {                                   // pure evolution → place under its base's area(s)
                let b = base(m)
                // "from X" names the DIRECT pre-evolution (so it sits right after that mon in the
                // family group), only while this one is still uncaught and the pre-evo is discovered.
                let cap = (e.state != .caught && (m.evolvesFrom.map(discovered) ?? false)) ? "from \(m.evolvesFrom!)" : nil
                if b.isCatchable {
                    for a in b.catchAreas {
                        byBiome[a.biome, default: []].append(Item(entry: e, field: a.field, caption: cap, familyKey: b.name, isEvolve: true, dimmed: dim))
                    }
                } else if let eggF = b.egg {
                    eggItems.append(Item(entry: e, field: eggF, caption: cap, familyKey: b.name, isEvolve: true, dimmed: dim))
                } else {
                    special.append(Item(entry: e, field: m.field, caption: nil, familyKey: m.name, isEvolve: false, dimmed: dim))
                }
            }
        }

        // Order a group by family (purple→red→blue, then base #), injecting a dimmed base anchor
        // when the base is already caught (so it isn't in the list) but discovered.
        func arrange(_ items: [Item]) -> [Item] {
            var fam = [String: [Item]]()
            for it in items { fam[it.familyKey, default: []].append(it) }
            func key(_ k: String) -> (Int, Int) {
                let fr = fam[k]!.map { fieldRank[$0.field] ?? 9 }.min() ?? 9
                return (fr, byName[k]?.num ?? 9999)
            }
            var result = [Item]()
            for k in fam.keys.sorted(by: { key($0) < key($1) }) {
                var members = fam[k]!.sorted {
                    $0.isEvolve != $1.isEvolve ? !$0.isEvolve : $0.entry.pokemon.num < $1.entry.pokemon.num
                }
                let hasTarget = members.contains { !$0.isEvolve }
                if !hasTarget, discovered(k), let pk = byName[k], let st = stateByName[k] {
                    let f = members.first?.field ?? pk.field
                    result.append(Item(entry: DexEntry(pokemon: pk, state: st), field: f,
                                       caption: "evolve this ↓", familyKey: k, isEvolve: false, isReminder: true))
                }
                result += members
            }
            return result
        }

        var sections = [Section]()
        let cf = currentFieldName

        // "New this game" — each new dex entry (in colour), with its DIRECT uncaught evolutions shown
        // right after it as silhouettes ("from X", green border) so you can see what you can now evolve
        // it into. (Re-catches of mons you already own can't be detected from the save.)
        let evoOf = Dictionary(grouping: PokedexData.all.filter { $0.evolvesFrom != nil }, by: { $0.evolvesFrom! })
        var newItems = [Item]()
        for e in store.entries.filter({ store.sessionCaught.contains($0.pokemon.saveIndex) })
                              .sorted(by: { $0.pokemon.num < $1.pokemon.num }) {
            newItems.append(Item(entry: e, field: e.pokemon.field, caption: nil, familyKey: e.pokemon.name, isEvolve: false))
            for evo in (evoOf[e.pokemon.name] ?? []).sorted(by: { $0.num < $1.num }) {
                let st = stateByName[evo.name] ?? .unknown
                if st != .caught {
                    newItems.append(Item(entry: DexEntry(pokemon: evo, state: st), field: e.pokemon.field,  // base's table colour
                                         caption: "from \(e.pokemon.name)", familyKey: e.pokemon.name, isEvolve: true))
                }
            }
        }
        let newCount = newItems.filter { !$0.isEvolve }.count
        if !newItems.isEmpty {
            sections.append(Section(title: "New this game", sub: "\(newCount) new — green border = now evolvable from them.",
                                    symbol: "checkmark.seal.fill", tint: .green, items: newItems, highlight: .green))
        }

        // 1) Current area — the full roster on your table here: still-to-catch + already-caught (darkened),
        //    each evolution sitting right after the base it comes from.
        if let cf, let biome = currentBiome {
            let here = arrange((byBiome[biome] ?? []).filter { $0.field == cf || $0.field == "Both" })
            if !here.isEmpty {
                sections.append(Section(title: "Current area — \(biome) (\(cf))", sub: "Dimmed = already caught.",
                                        symbol: "location.fill", tint: .blue, items: here, highlight: .blue))
            }
        }
        // 2) Hatchable now — current-table eggs.
        if let cf {
            let now = arrange(eggItems.filter { $0.field == cf || $0.field == "Both" })
            if !now.isEmpty {
                sections.append(Section(title: "Hatchable now", sub: "Hatch at the EGG hole on this table.",
                                        symbol: "oval.portrait.fill", tint: .blue, items: now, highlight: .blue))
            }
        }

        // 3) Every biome — full roster: still-to-catch + already-caught (darkened), so nothing vanishes.
        let order = ["Forest", "Plains", "Ocean", "Cave", "Volcano", "Lake", "Safari", "Wilderness", "Ruins"]
        for biome in order {
            let items = arrange(byBiome[biome] ?? [])
            if !items.isEmpty {
                sections.append(Section(title: biome, sub: nil, symbol: "mappin.circle.fill", tint: .secondary, items: items))
            }
        }
        // 4) Eggs (the other table when playing, else all).
        let restEggs = cf == nil ? eggItems : eggItems.filter { !($0.field == cf || $0.field == "Both") }
        if !restEggs.isEmpty {
            sections.append(Section(title: "From eggs", sub: cf == nil ? "Hatch at the EGG hole." : "Eggs for the other table.",
                                    symbol: "oval.portrait.fill", tint: .orange, items: arrange(restEggs)))
        }
        // 5) Special.
        if !special.isEmpty {
            sections.append(Section(title: "Special", sub: "Legendaries, Jirachi & bonus guests.", symbol: "sparkles", tint: .purple,
                                    items: special.sorted { ($0.entry.pokemon.num) < ($1.entry.pokemon.num) }))
        }
        return sections
    }
}
