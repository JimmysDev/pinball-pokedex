import Foundation

/// Result of decoding a Pokémon Pinball: Ruby & Sapphire SRAM save (.sav).
struct ParsedSave {
    /// One byte per species, length `SaveParser.numSpecies` (205), indexed by pinball dex (num-1).
    let flags: [UInt8]
    /// Which 672-byte copy validated (primary at 0x4, or the backup at 0x2A4).
    let usedBackup: Bool
}

/// Decodes the save's Pokédex flags.
///
/// Layout reverse-engineered from the pret/pokepinballrs decompilation (src/save.c, include/main.h):
/// the 32 KB SRAM holds two redundant copies of `struct SaveData` (672 bytes each) — primary at
/// file offset 0x4, backup at 0x2A4 — each validated by a 10-byte "POKEPINAGB" signature and a
/// 16-bit folded checksum. `pokedexFlags[NUM_SPECIES]` is the first field of the struct (relative
/// offset 0), so it sits at file offset 0x4 (primary) / 0x2A4 (backup).
enum SaveParser {
    static let numSpecies = 205          // NUM_SPECIES
    static let structSize = 672          // sizeof(struct SaveData)
    static let primaryOffset = 0x4
    static let backupOffset = 0x2A4
    static let pokedexFlagsOffset = 0x0  // within the struct
    static let signatureOffset = 0x264   // within the struct
    static let signature = Array("POKEPINAGB".utf8)

    enum ParseError: Error, LocalizedError {
        case tooSmall
        case noValidCopy

        var errorDescription: String? {
            switch self {
            case .tooSmall:    return "File is too small to be a Pinball R&S save."
            case .noValidCopy: return "Neither save copy passed its signature/checksum check. Is this the right .sav, and has the game saved at least once?"
            }
        }
    }

    static func parse(_ data: Data) throws -> ParsedSave {
        let bytes = [UInt8](data)
        guard bytes.count >= backupOffset + structSize else { throw ParseError.tooSmall }

        for (base, isBackup) in [(primaryOffset, false), (backupOffset, true)] {
            if isValid(bytes, base: base) {
                let start = base + pokedexFlagsOffset
                return ParsedSave(flags: Array(bytes[start ..< start + numSpecies]),
                                  usedBackup: isBackup)
            }
        }
        throw ParseError.noValidCopy
    }

    /// Validates one 672-byte copy: signature match + checksum folds to 0xFFFF.
    private static func isValid(_ bytes: [UInt8], base: Int) -> Bool {
        guard base + structSize <= bytes.count else { return false }

        for i in 0..<signature.count where bytes[base + signatureOffset + i] != signature[i] {
            return false
        }

        // Sum of all 16-bit little-endian words across the struct (the stored checksum field is
        // part of the sum); fold the carry. A valid save folds to 0xFFFF. See SaveFile_WriteToSram.
        var sum: UInt32 = 0
        var i = base
        let end = base + structSize
        while i + 1 < end {
            sum &+= UInt32(bytes[i]) | (UInt32(bytes[i + 1]) << 8)
            i += 2
        }
        sum = (sum & 0xFFFF) &+ (sum >> 16)
        return (sum & 0xFFFF) == 0xFFFF
    }
}
