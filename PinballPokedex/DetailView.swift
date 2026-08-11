import SwiftUI

/// The detail popover. Opening it is the first reveal: identity + which **table** (conveyed by the
/// red (Ruby) / blue (Sapphire) / split (Both) background). The exact catch method stays behind the
/// deliberate second level, "How to get it".
struct DetailView: View {
    let entry: DexEntry
    var style: SpriteStyle = .modern
    @State private var showMethod = false

    private var mon: Pokemon { entry.pokemon }

    /// The catch method, worded for clarity: "GET lights", "or" instead of "&", and a note that
    /// fewer GET lights mean better odds (a smaller pool of possible species) when there's a choice.
    private var methodText: String {
        var t = mon.method
            .replacingOccurrences(of: " & ", with: " or ")
            .replacingOccurrences(of: "lights)", with: "GET lights)")
            .replacingOccurrences(of: "light)", with: "GET light)")
        if mon.catchAreas.contains(where: { $0.lights.contains("&") }) {
            t += " — fewer lights = better odds."
        }
        return t
    }

    private static let ruby = Color(red: 0.82, green: 0.13, blue: 0.18)
    private static let sapphire = Color(red: 0.10, green: 0.34, blue: 0.80)

    private var tableLabel: String {
        switch mon.field {
        case "Ruby":     return "Ruby Table"
        case "Sapphire": return "Sapphire Table"
        default:         return "Both Tables"
        }
    }

    private var background: LinearGradient {
        let colors: [Color]
        switch mon.field {
        case "Ruby":     colors = [Self.ruby.opacity(0.96), Self.ruby.opacity(0.78)]
        case "Sapphire": colors = [Self.sapphire.opacity(0.96), Self.sapphire.opacity(0.78)]
        default:         colors = [Self.ruby, Self.sapphire]   // appears on both tables
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SpriteView(mon: mon, mode: .color, style: style)   // revealed in full colour
                    .frame(width: 72, height: 72)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.9)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(mon.name).font(.title2.bold())
                    Text("#\(String(format: "%03d", mon.num)) · Natl. #\(mon.natdex)")
                        .font(.caption).monospacedDigit().opacity(0.85)
                    statusPill
                }
                Spacer(minLength: 0)
            }

            // Which table — the headline of the first reveal.
            HStack(spacing: 6) {
                Image(systemName: "circle.circle.fill")
                Text(tableLabel).fontWeight(.semibold)
                if mon.isGuest {
                    Text("· bonus guest").opacity(0.85).font(.subheadline)
                }
                Spacer()
            }
            .font(.headline)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.18)))

            Divider().overlay(.white.opacity(0.4))

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showMethod.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showMethod ? 90 : 0))
                        .font(.caption.bold())
                    Text("How to get it").font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMethod {
                Text(methodText)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.18)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(background)
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.state.badgeSymbol).font(.caption2)
            Text(entry.state.label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.22)))
    }
}
