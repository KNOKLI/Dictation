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
        // 2026-11-23 (Камиль): вариант 5 «Виджет» из `../Dictation_Дизайны` (MenuGallery) — панель вместо меню.
        // Прежнее системное меню — `MenuBarClassic` (вернуть: убрать эту строку и поставить его выше).
        .menuBarExtraStyle(.window)
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

/// Прежнее системное меню (до 2026-11-23)
struct MenuBarClassic: View {
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

/// 2026-11-23 (Камиль): меню в строке меню — вариант 5 «Виджет»: крупно «сегодня», график недели,
/// большая кнопка «Диктовать», микрофон, снизу значки (Недавние, Открыть, Настройки, Выйти).
struct MenuBarContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private static let blue = Color(red: 0.04, green: 0.52, blue: 1.0)
    private static let red = Color(red: 1.0, green: 0.27, blue: 0.23)
    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEEEE"
        return f
    }()

    /// Закрыть панель — фокус вернётся в прошлое приложение (важно для вставки)
    private func close() { NSApp.keyWindow?.close() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                recordButton
                if let c = state.cancelled, !state.isRecording {
                    Button {
                        close(); state.restoreCancelled()
                    } label: {
                        Label("Вернуть отменённую запись (\(RU.duration(c.duration)))", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Self.blue)
                    }
                    .buttonStyle(.plain)
                }
                micRow
            }
            .padding(14)
            Divider().padding(.horizontal, 10)
            footer.padding(.vertical, 4).padding(.horizontal, 6)
        }
        .frame(width: 300)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Сегодня").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(RU.number(state.history.todayCharacters))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("символов · всего \(RU.number(state.history.archive.totalCharacters))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            week
        }
    }

    /// График 7 дней, сегодня — синим
    private var week: some View {
        let days = state.history.lastDays(7)
        let top = max(1, days.map(\.characters).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let today = i == days.count - 1
                VStack(spacing: 3) {
                    Capsule()
                        .fill(today ? AnyShapeStyle(Self.blue) : AnyShapeStyle(.primary.opacity(0.35)))
                        .frame(width: 8, height: max(4, CGFloat(d.characters) / CGFloat(top) * 40))
                    Text(Self.weekday.string(from: d.day)).font(.system(size: 9))
                        .foregroundStyle(today ? .primary : .secondary)
                }
                .help("\(RU.chars(d.characters))")
            }
        }
        .frame(height: 56, alignment: .bottom)
    }

    private var recordButton: some View {
        Button {
            if !state.isRecording { close() } // запись — в то приложение, где был курсор
            state.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: state.isRecording ? "stop.fill" : "mic.fill")
                    .contentTransition(.symbolEffect(.replace))
                Text(state.isRecording ? "Остановить" : "Диктовать")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Capsule().fill(state.isRecording ? Self.red : Self.blue))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!state.canRecord && !state.isRecording)
        .opacity(!state.canRecord && !state.isRecording ? 0.5 : 1)
        .help("Правый ⌘ — в любом приложении")
    }

    private var micRow: some View {
        HStack(spacing: 6) {
            Menu {
                MicrophonePicker().pickerStyle(.inline).labelsHidden()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic").foregroundStyle(.secondary)
                    Text(state.microphoneTitle).font(.system(size: 12)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer()
            Button {
                close(); state.pasteLast()
            } label: {
                Text("⌃⌥V").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(state.lastText.isEmpty)
            .help("Вставить последнюю диктовку")
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Menu {
                let recent = state.history.recent(5)
                if recent.isEmpty { Text("Пока пусто") }
                ForEach(recent) { e in
                    Button("\(RU.time(e.date)) · \(MenuBarClassic.snippet(e.text))") { close(); state.paste(e.text) }
                }
                Divider()
                Text("Нажми — вставлю туда, где курсор")
            } label: {
                footIcon("clock")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Недавние")
            .frame(maxWidth: .infinity)

            footButton("macwindow", "Открыть Dictation") {
                close(); openWindow(id: "main"); NSApp.activate()
            }
            footButton("gearshape", "Настройки") {
                close(); NSApp.activate(); openSettings()
            }
            footButton("power", "Выйти") { NSApp.terminate(nil) }
        }
    }

    private func footIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 14)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).frame(height: 30).contentShape(.rect)
    }

    private func footButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { footIcon(icon) }
            .buttonStyle(.plain)
            .help(help)
            .frame(maxWidth: .infinity)
    }
}
