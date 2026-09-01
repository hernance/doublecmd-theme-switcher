// DCThemePicker — selector grafico de temas para Double Commander.
// Compilado por dc_theme_picker.sh con swiftc a un binario local (picker-ui/DCThemePicker).
// Muestra una grilla de tarjetas (miniatura + nombre) leyendo ~/bin/dc-theme/themes/*.json
// y su <nombre>.thumb.png. Al elegir: si DC esta corriendo pregunta el modo (now/stage),
// y dispara dc_theme_phoenix.sh detached (sobrevive al quit de DC).
//
// Uso: DCThemePicker [--selftest]   (--selftest: lista los temas detectados y sale, sin UI)

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

// Mismo allowlist que dc_theme_apply.py / dc_theme_phoenix.sh: sin esto, un nombre de
// tema con comillas/`;`/`$()` podria inyectar comandos al pasar por Process/AppleScript.
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
    // Se llama solo con nombres ya validados por isValidThemeName (ver choose()).
    // Process.arguments no pasa por un shell, asi que no hace falta escapar nada;
    // no se espera el proceso (sin waitUntilExit) para que sobreviva al quit de DC/picker.
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
    try? p.run()
}

// Pregunta el modo cuando DC esta corriendo. Devuelve "now", "stage" o nil (cancelar).
func askMode(for theme: Theme) -> String? {
    let alert = NSAlert()
    alert.messageText = "Aplicar \u{201C}\(theme.displayName)\u{201D}"
    alert.informativeText = "Double Commander est\u{00E1} abierto. Para ver el tema completo hay que cerrarlo y volver a abrirlo (los tabs se mantienen)."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Cerrar y aplicar ahora")
    alert.addButton(withTitle: "Al pr\u{00F3}ximo inicio")
    alert.addButton(withTitle: "Cancelar")
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
        .help("Aplicar el tema \(theme.name)")
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
                Text("No hay temas en \(themesDir)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(40)
            } else {
                Text("Eleg\u{00ED} un tema")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(themes) { theme in
                        ThemeCard(theme: theme, action: choose)
                    }
                }
            }
            HStack {
                Text("Un click en la tarjeta aplica el tema")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancelar") { NSApp.terminate(nil) }
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
        WindowGroup("Tema de Double Commander") {
            ContentView()
                .fixedSize()
        }
        .windowResizability(.contentSize)
    }
}
