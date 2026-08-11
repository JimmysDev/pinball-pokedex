import Foundation

/// One Pokémon as it appears in the Pinball R&S dex.
/// `num` is the *pinball* dex number (1...205) which equals the save-array index + 1.
/// `natdex` is the National Dex number, used only to pick the sprite asset.
/// One wild-encounter location, from the decompilation's gWildMonLocations table.
struct CatchArea: Decodable, Hashable {
    let biome: String   // Forest / Plains / Ocean / Cave / Safari / Volcano / Lake / Wilderness / Ruins
    let field: String   // "Ruby" / "Sapphire" / "Both"
    let lights: String  // "3" or "2 & 3"
}

struct Pokemon: Decodable, Identifiable, Hashable {
    let num: Int          // pinball dex number, 1...205
    let name: String
    let natdex: Int       // national dex number (sprite filename)
    let field: String     // overall "Ruby" / "Sapphire" / "Both"
    let method: String    // human-readable summary (detail view)
    let catchAreas: [CatchArea]   // authoritative wild locations (empty if not wild-catchable)
    let egg: String?      // field the egg appears on ("Ruby"/"Sapphire"/"Both"), else nil
    let evolvesFrom: String?      // immediate pre-evolution name, else nil
    let rarity: Int?      // 1 (common) … 3 (rare); nil → treated as 1

    enum CodingKeys: String, CodingKey {
        case num, name, natdex, field, method, egg, evolvesFrom, rarity
        case catchAreas = "catch"
    }

    var id: Int { num }
    /// Rarity as 1…5 stars (defaults to 1 if the data didn't supply it).
    var stars: Int { min(5, max(1, rarity ?? 1)) }
    /// Index into gMain_saveData.pokedexFlags[].
    var saveIndex: Int { num - 1 }
    /// True for the four non-Hoenn bonus guests (Chikorita, Cyndaquil, Totodile, Aerodactyl).
    var isGuest: Bool { num >= 202 }
    var isCatchable: Bool { !catchAreas.isEmpty }
    var isEgg: Bool { egg != nil }
}

/// Which artwork set to show: the modern Gen-III sprites, or the original in-game dex portraits.
enum SpriteStyle: String {
    case modern, original
    var opposite: SpriteStyle { self == .modern ? .original : .modern }
    var label: String { self == .modern ? "Modern" : "In-game" }
}

/// Collapsed three-state status the UI cares about, derived from the raw flag byte.
/// Raw values from the decompilation (include/variables.h):
///   SPECIES_UNSEEN=0, SPECIES_SEEN=1, SPECIES_SHARED=2, SPECIES_SHARED_AND_SEEN=3, SPECIES_CAUGHT=4
enum DexState: Int, Comparable {
    case unknown = 0
    case seen = 1
    case caught = 2

    static func from(flag: UInt8) -> DexState {
        switch flag {
        case 4:        return .caught          // SPECIES_CAUGHT
        case 1, 2, 3:  return .seen             // SEEN / SHARED / SHARED_AND_SEEN
        default:       return .unknown          // SPECIES_UNSEEN
        }
    }

    var label: String {
        switch self {
        case .caught:  return "Caught"
        case .seen:    return "Seen"
        case .unknown: return "Unknown"
        }
    }

    static func < (lhs: DexState, rhs: DexState) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A Pokémon paired with its current status in the loaded save.
struct DexEntry: Identifiable, Hashable {
    let pokemon: Pokemon
    let state: DexState
    var id: Int { pokemon.num }
}

/// Static dex data bundled with the app (built from the pret/pokepinballrs decompilation
/// for ordering + flag semantics, PokeAPI for National Dex numbers, and the altissimo
/// guide for catch methods).
enum PokedexData {
    static let all: [Pokemon] = {
        guard let url = Bundle.main.url(forResource: "pokedex", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Pokemon].self, from: data)
        else {
            assertionFailure("pokedex.json missing from bundle")
            return []
        }
        return list.sorted { $0.num < $1.num }
    }()
}

/// An SF Symbol that reads as a given biome — a quick visual cue for "which area am I in".
/// (We don't bundle the game's official area artwork; these stand in for it.)
func biomeSymbol(_ biome: String) -> String {
    switch biome {
    case "Forest":     return "tree.fill"
    case "Plains":     return "sun.max.fill"
    case "Cave":       return "mountain.2.fill"
    case "Ocean":      return "water.waves"
    case "Volcano":    return "flame.fill"
    case "Safari":     return "pawprint.fill"
    case "Lake":       return "drop.fill"
    case "Wilderness": return "sun.dust.fill"
    case "Ruins":      return "building.columns.fill"
    default:           return "mappin.circle.fill"
    }
}

/// Travel-mode area loops (Bulbapedia in-game order). Left loop advances 1 area, right loop advances 2.
enum TravelData {
    static let loops: [String: [String]] = [
        "Ruby":     ["Forest", "Volcano", "Plains", "Ocean", "Safari", "Cave"],
        "Sapphire": ["Forest", "Lake", "Plains", "Wilderness", "Ocean", "Cave"],
    ]
    /// Where the left loop (advance 1) and right loop (advance 2) take you from `biome` on `field`.
    static func nextStops(field: String, biome: String) -> (left: String, right: String)? {
        guard let loop = loops[field], let i = loop.firstIndex(of: biome) else { return nil }
        return (loop[(i + 1) % loop.count], loop[(i + 2) % loop.count])
    }
}
