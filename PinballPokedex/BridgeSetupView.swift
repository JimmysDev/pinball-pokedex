import SwiftUI
import AppKit

/// The mGBA Lua bridge ships inside the app bundle, so the line we hand the user always matches the
/// bridge the app actually speaks (a hand-maintained copy drifts and silently loses features).
enum BridgeScript {
    static var url: URL? { Bundle.main.url(forResource: "mgba_bridge", withExtension: "lua") }

    /// What you paste into mGBA's Scripting "Run" box. Safe to re-run.
    static var loadLine: String {
        guard let p = url?.path else { return "dofile(\"…/scripts/mgba_bridge.lua\")" }
        return "dofile(\"\(p)\")"
    }

    static func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(loadLine, forType: .string)
    }

    static func revealInFinder() {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Walks through loading the bridge into mGBA. The status row at the bottom flips to green the
/// moment the bridge starts publishing, so you get confirmation without leaving mGBA.
struct BridgeSetupView: View {
    @EnvironmentObject private var live: LiveBridge
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var connected: Bool { live.state != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Live bridge setup").font(.headline)
                    Text("Lets the app read your running game — area, catches and the e-Reader toggles")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    step(1, "Open your game in mGBA", "Load the ROM and start playing as usual.")
                    step(2, "Open Tools ▸ Scripting", "A console window with a “Run” box at the bottom.")
                    step(3, "Paste this line into the Run box and press Run", nil)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(BridgeScript.loadLine)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.25)))
                        HStack {
                            Button {
                                BridgeScript.copyToPasteboard()
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                            } label: {
                                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Reveal in Finder") { BridgeScript.revealInFinder() }
                            Spacer()
                        }
                    }
                    .padding(.leading, 30)

                    step(4, "Keep playing", "The chip in the header turns green and the guides go live.")

                    Label("You must re-run this every time you relaunch mGBA, and after a Reset — the script lives in mGBA's memory, not your save.",
                          systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(16)
            }

            Divider()
            HStack(spacing: 8) {
                Image(systemName: connected ? "checkmark.circle.fill" : "circle.dotted")
                    .foregroundStyle(connected ? .green : .secondary)
                Text(connected ? "Connected — the bridge is sending live data."
                               : (live.mgbaRunning ? "Waiting for the script… mGBA is running."
                                                   : "Waiting — mGBA isn't running yet."))
                    .font(.callout).foregroundStyle(connected ? .primary : .secondary)
                Spacer()
            }
            .padding(14)
            .background(connected ? Color.green.opacity(0.10) : Color.clear)
        }
        .frame(minWidth: 540, minHeight: 480)
    }

    private func step(_ n: Int, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
