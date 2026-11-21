import SwiftUI

@main
struct DictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState.shared

    var body: some Scene {
        Window("Dictation", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 780, minHeight: 560)
        }
        .defaultSize(width: 940, height: 660)
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: "menuBarOnly") ? .suppressed : .presented)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(state.isRecording ? "Остановить диктовку" : "Начать диктовку") { state.toggle() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(state)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(state)
        } label: {
            Image(systemName: state.isRecording ? "waveform.badge.mic" : "mic")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.bootstrap() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.shutdown() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MenuBarContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(state.isRecording ? "Остановить диктовку" : "Начать диктовку") { state.toggle() }
            .disabled(!state.canRecord && !state.isRecording)
        if let c = state.cancelled, !state.isRecording {
            Button("Вернуть отменённую запись (\(RU.duration(c.duration)))") { state.restoreCancelled() }
        }
        Divider()
        Button("Вставить последнюю диктовку") { state.pasteLast() }
            .keyboardShortcut("v", modifiers: [.control, .option])
            .disabled(state.lastText.isEmpty)
        Menu("Недавние") {
            let recent = state.history.recent(5)
            if recent.isEmpty {
                Text("Пока пусто")
            }
            ForEach(recent) { e in
                Button("\(RU.time(e.date)) · \(Self.snippet(e.text))") { state.paste(e.text) }
            }
            Divider()
            Text("Нажми — вставлю туда, где курсор")
        }
        Divider()
        Text("Сегодня: \(RU.chars(state.history.todayCharacters))")
        Text("Всего: \(RU.chars(state.history.archive.totalCharacters))")
        Divider()
        Button("Открыть Dictation") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Menu("Микрофон") {
            MicrophonePicker()
                .pickerStyle(.inline)
                .labelsHidden()
        }
        Button("Настройки…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Выйти") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    static func snippet(_ text: String) -> String {
        let one = text.replacingOccurrences(of: "\n", with: " ")
        return one.count > 48 ? String(one.prefix(48)) + "…" : one
    }
}
