// DCThemePicker — graphical theme picker for Double Commander.
// Compiled by dc_theme_picker.sh with swiftc into a local binary (picker-ui/DCThemePicker).
// Shows a grid of cards (thumbnail + name) read from ~/bin/dc-theme/themes/*.json
// and the matching <name>.thumb.png. On selection: if DC is running it asks for the mode
// (now/stage), and launches dc_theme_phoenix.sh detached (survives the DC quit).
//
// Usage: DCThemePicker [--selftest]   (--selftest: lists the detected themes and exits, no UI)

import SwiftUI
import AppKit

let scriptDir = NSString(string: "~/bin/dc-theme").expandingTildeInPath
let themesDir = scriptDir + "/themes"
let phoenixPath = scriptDir + "/dc_theme_phoenix.sh"
let logPath = scriptDir + "/phoenix.log"
let dcAppName = "Double Commander"

struct Theme: Identifiable, Hashable {
    let name: String
    let thumbPath: String?
    var id: String { name }
    var displayName: String {
        name.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

// Same allowlist as dc_theme_apply.py / dc_theme_phoenix.sh: without this, a theme
// name with quotes/`;`/`$()` could inject commands when passed through Process/AppleScript.
func isValidThemeName(_ name: String) -> Bool {
    !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }
}

func loadThemes() -> [Theme] {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: themesDir) else { return [] }
    return entries
        .filter { $0.hasSuffix(".json") }
        .map { String($0.dropLast(5)) }
        .filter(isValidThemeName)
        .sorted()
        .map { name in
            let thumb = themesDir + "/" + name + ".thumb.png"
            return Theme(name: name, thumbPath: fm.fileExists(atPath: thumb) ? thumb : nil)
        }
}

func dcIsRunning() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-f", dcAppName]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

func launchPhoenixDetached(theme: String, mode: String) {
    // Only called with names already validated by isValidThemeName (see choose()).
    // Process.arguments doesn't go through a shell, so nothing needs escaping;
    // the process is not awaited (no waitUntilExit) so it survives the DC/picker quit.
    if !FileManager.default.fileExists(atPath: logPath) {
        FileManager.default.createFile(atPath: logPath, contents: nil)
    }
    let logHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
    logHandle?.seekToEndOfFile()

    let p = Process()
    p.executableURL = URL(fileURLWithPath: phoenixPath)
    p.arguments = [theme, mode]
    p.standardOutput = logHandle
    p.standardError = logHandle
    do {
        try p.run()
    } catch {
        let alert = NSAlert()
        alert.messageText = "Could not apply the theme"
        alert.informativeText = "Could not launch \(phoenixPath): \(error.localizedDescription)"
        alert.alertStyle = .critical
        alert.runModal()
    }
}

// Asks for the mode when DC is running. Returns "now", "stage" or nil (cancel).
func askMode(for theme: Theme) -> String? {
    let alert = NSAlert()
    alert.messageText = "Apply \u{201C}\(theme.displayName)\u{201D}"
    alert.informativeText = "Double Commander is open. To see the complete theme, it has to be closed and reopened (tabs are preserved)."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Quit and apply now")
    alert.addButton(withTitle: "On next launch")
    alert.addButton(withTitle: "Cancel")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return "now"
    case .alertSecondButtonReturn: return "stage"
    default: return nil
    }
}

struct ThemeCard: View {
    let theme: Theme
    let action: (Theme) -> Void
    @State private var hovering = false

    var body: some View {
        Button { action(theme) } label: {
            VStack(spacing: 10) {
                Group {
                    if let path = theme.thumbPath, let img = NSImage(contentsOfFile: path) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(280.0 / 153.0, contentMode: .fit)
                    } else {
                        ZStack {
                            Rectangle().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                        .aspectRatio(280.0 / 153.0, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                VStack(spacing: 2) {
                    Text(theme.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(theme.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(hovering ? Color.accentColor.opacity(0.10)
                                   : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(hovering ? Color.accentColor : Color(nsColor: .separatorColor),
                                  lineWidth: hovering ? 2 : 1)
            )
            .scaleEffect(hovering ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Apply the \(theme.name) theme")
    }
}

struct ContentView: View {
    let themes = loadThemes()

    var columns: [GridItem] {
        let n = min(3, max(1, themes.count))
        return Array(repeating: GridItem(.fixed(304), spacing: 16), count: n)
    }

    var body: some View {
        VStack(spacing: 16) {
            if themes.isEmpty {
                Text("No themes in \(themesDir)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(40)
            } else {
                Text("Choose a theme")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(themes) { theme in
                        ThemeCard(theme: theme, action: choose)
                    }
                }
            }
            HStack {
                Text("Click a card to apply the theme")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { NSApp.terminate(nil) }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    func choose(_ theme: Theme) {
        var mode = "now"
        if dcIsRunning() {
            guard let m = askMode(for: theme) else { return }
            mode = m
        }
        launchPhoenixDetached(theme: theme.name, mode: mode)
        NSApp.terminate(nil)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct DCThemePickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        if CommandLine.arguments.contains("--selftest") {
            let themes = loadThemes()
            print("themesDir: \(themesDir)")
            for t in themes {
                print("\(t.name)\tthumb=\(t.thumbPath ?? "MISSING")")
            }
            print("dcIsRunning: \(dcIsRunning())")
            exit(themes.isEmpty ? 1 : 0)
        }
    }

    var body: some Scene {
        WindowGroup("Double Commander Theme") {
            ContentView()
                .fixedSize()
        }
        .windowResizability(.contentSize)
    }
}
