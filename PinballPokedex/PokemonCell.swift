import SwiftUI

extension DexState {
    var accent: Color {
        switch self {
        case .caught:  return .green
        case .seen:    return .orange
        case .unknown: return .gray
        }
    }
    var badgeSymbol: String {
        switch self {
        case .caught:  return "circle.circle.fill"   // pokéball-ish
        case .seen:    return "eye.fill"
        case .unknown: return "info.circle.fill"      // the "i" affordance to reveal
        }
    }
}

/// One grid tile. Caught = color sprite + name; Seen = grayscale + name; Unknown = silhouette + "???"
/// with an (i) badge. Tapping any tile opens the detail popover (which reveals an unknown).
struct PokemonCell: View {
    let entry: DexEntry
    var scale: Double = 1.0
    var style: SpriteStyle = .modern
    var caption: String? = nil
    var fieldName: String? = nil   // catch guide colours the border by field: red Ruby, blue Sapphire, diagonal Both
    var isReminder: Bool = false   // a discovered base shown as the anchor for its evolutions
    var dimmed: Bool = false       // already-caught (not new this game): shown darkened, in colour
    var isEvolve: Bool = false     // obtained by evolving a caught base (not catching) → green-bordered
    @State private var showDetail = false

    /// Border by field. "Both" = a clean diagonal split along the top-right↔bottom-left line
    /// (red on the top-left edges, blue on the bottom-right), drawn geometrically so it stays
    /// corner-to-corner regardless of the cell's aspect ratio.
    @ViewBuilder private var borderOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        switch fieldName {
        case "Both":
            ZStack {
                shape.strokeBorder(Color.red.opacity(0.9), lineWidth: 2.5).clipShape(DiagHalf(upperLeft: true))
                shape.strokeBorder(Color.blue.opacity(0.9), lineWidth: 2.5).clipShape(DiagHalf(upperLeft: false))
            }
        case "Ruby":     shape.strokeBorder(Color.red.opacity(0.9), lineWidth: 2.5)
        case "Sapphire": shape.strokeBorder(Color.blue.opacity(0.9), lineWidth: 2.5)
        default:         shape.strokeBorder(state.accent.opacity(state == .unknown ? 0.25 : 0.55), lineWidth: 1.5)
        }
    }

    private var mon: Pokemon { entry.pokemon }
    private var state: DexState { entry.state }

    private var spriteMode: SpriteMode {
        switch state {
        case .caught:  return .color
        case .seen:    return .grayscale
        case .unknown: return .silhouette
        }
    }

    var body: some View {
        Button { showDetail = true } label: { card }
            .buttonStyle(.plain)
            .help(state == .unknown ? "Tap to reveal #\(mon.num)" : mon.name)
            .popover(isPresented: $showDetail, arrowEdge: .bottom) {
                DetailView(entry: entry, style: style)
            }
    }

    /// Rarity rating: `mon.stars` gold stars (1–5) — more stars = rarer.
    private var rarityStars: some View {
        HStack(spacing: 0.5) {
            ForEach(0..<mon.stars, id: \.self) { _ in
                Image(systemName: "star.fill").font(.system(size: 5)).foregroundStyle(Color.yellow)
            }
        }
        .fixedSize()
        .help("Rarity: \(mon.stars)/5")
    }

    private var card: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Text(String(format: "#%03d", mon.num))
                    .font(.caption2).monospacedDigit()
                    .lineLimit(1).fixedSize()          // never wrap the number
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                rarityStars
                Spacer(minLength: 2)
                Image(systemName: state.badgeSymbol)
                    .font(.caption)
                    .foregroundStyle(state == .unknown ? Color.accentColor : state.accent)
            }

            SpriteView(mon: mon, mode: spriteMode, style: style)
                .frame(height: 58 * scale)
                .padding(.vertical, 2)

            Text(state == .unknown ? "???" : mon.name)
                .font(.caption).fontWeight(.medium)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(state == .unknown ? .secondary : .primary)

            if let caption {
                Text(caption)
                    .font(.caption2).fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .opacity(isReminder ? 0.6 : (dimmed ? 0.4 : 1))   // dimmed = already caught (not new this game)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay { borderOverlay }
    }
}

/// The half of a rect on one side of the top-right↔bottom-left diagonal.
struct DiagHalf: Shape {
    var upperLeft: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if upperLeft {                          // triangle TL · TR · BL
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        } else {                                // triangle TR · BR · BL
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}
