import SwiftUI
import AppKit

/// Loads & caches sprites in either style:
///  - modern:   bundled Gen-III sprites, named by National Dex number (`sprites/<natdex>.png`)
///  - original: the game's own dex portraits, named by pinball number (`portraits/<num>.png`)
enum SpriteCache {
    private static var cache: [String: NSImage] = [:]

    static func image(mon: Pokemon, style: SpriteStyle) -> NSImage? {
        let (sub, name): (String, String) = style == .modern
            ? ("sprites", String(mon.natdex))
            : ("portraits", String(mon.num))
        let key = "\(sub)/\(name)"
        if let img = cache[key] { return img }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: sub)
                ?? Bundle.main.url(forResource: name, withExtension: "png"),
              let img = NSImage(contentsOf: url)
        else { return nil }
        cache[key] = img
        return img
    }
}

enum SpriteMode {
    case color       // caught / revealed
    case grayscale   // seen-only
    case silhouette  // unknown
}

/// Renders a sprite in one of three looks. Silhouette is derived from the sprite's
/// alpha at render time, so no separate silhouette assets are needed.
struct SpriteView: View {
    let mon: Pokemon
    let mode: SpriteMode
    var style: SpriteStyle = .modern

    var body: some View {
        Group {
            if let img = SpriteCache.image(mon: mon, style: style) {
                switch mode {
                case .color:
                    sprite(img)
                case .grayscale:
                    sprite(img).saturation(0).opacity(0.92)
                case .silhouette:
                    Color.primary.opacity(0.78)
                        .mask(sprite(img))
                }
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
    }

    private func sprite(_ img: NSImage) -> some View {
        Image(nsImage: img)
            .resizable()
            .interpolation(.none)   // keep the pixel art crisp when scaled up
            .scaledToFit()
    }
}
