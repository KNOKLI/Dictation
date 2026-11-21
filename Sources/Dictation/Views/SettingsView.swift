import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var trusted = Paster.isTrusted

    var body: some View {
        @Bindable var state = state
        Form {
            SwiftUI.Section {
                MicrophonePicker()
            } header: {
                Text("Микрофон")
            } footer: {
                Text(state.microphoneMissing
                     ? "Выбранный микрофон не подключён — пока запись идёт с системного. Подключишь — переключится сам."
                     : "«Системный» — тот, что выбран в настройках macOS.")
            }

            SwiftUI.Section {
                Picker("Язык", selection: $state.language) {
                    Text("Русский").tag("ru")
                    Text("Русский + английские слова").tag("ru-en")
                    Text("Английский").tag("en")
                    Text("Определять автоматически").tag("auto")
                }
                Toggle("Голосовые команды", isOn: $state.voiceCommands)
                LabeledContent("Модель", value: ModelInfo.displayName)
                LabeledContent("Размер", value: ModelInfo.sizeDescription)
                LabeledContent("Работает") {
                    Label("Локально, без интернета", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                Button("Показать модель в Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ModelInfo.path])
                }
            } header: {
                Text("Распознавание")
            } footer: {
                Text("«Русский + английские слова» — для речи с терминами вроде Excel или pull request; свои слова добавляй в «Словарь». Голосовые команды: \(VoiceCommands.help).")
            }

            SwiftUI.Section {
                Toggle("Вставлять текст в активное приложение", isOn: $state.autoPaste)
                Toggle("Возвращать прежнее содержимое буфера", isOn: $state.restoreClipboard)
                    .disabled(!state.autoPaste)
                if state.autoPaste && !trusted {
                    HStack {
                        Label("Нужен доступ в «Универсальный доступ»", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Разрешить") {
                            Paster.requestTrust()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                LabeledContent("Вставить последнюю диктовку") { KeyCap("⌃⌥V") }
            } header: {
                Text("Вставка")
            } footer: {
                Text(state.autoPaste && state.restoreClipboard
                     ? "После вставки в буфер вернётся то, что ты копировал раньше. Последнюю диктовку всегда можно вставить ещё раз: ⌃⌥V или меню в строке меню."
                     : "Текст диктовки остаётся в буфере обмена.")
            }

            SwiftUI.Section {
                Picker("Клавиша диктовки", selection: $state.triggerKind) {
                    ForEach(TriggerKeyKind.allCases) { k in Text(k.title).tag(k) }
                }
                Toggle("Удерживать клавишу и говорить", isOn: $state.holdToTalk)
                LabeledContent("Закончить и сохранить") { KeyCap("Return") }
                LabeledContent("Отменить запись") { KeyCap("Esc") }
                Toggle("Звуки начала и конца записи", isOn: $state.playSounds)
                Toggle("Открывать при входе в систему", isOn: $state.launchAtLogin)
            } header: {
                Text("Управление")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.holdToTalk
                         ? "Коротко нажал — начать/закончить. Зажал и держишь — запись идёт, пока держишь; отпустил — текст вставлен."
                         : "Нажал — начать, нажал ещё раз — закончить.")
                    Text("Return и Esc перехватываются только во время записи. Отменённую запись длиннее 3 секунд можно вернуть.")
                    if state.triggerKind == .fn {
                        Text("Fn может быть занята системой: в Системных настройках → Клавиатура для клавиши 🌐 выбери «Ничего не делать».")
                            .foregroundStyle(.orange)
                    }
                }
            }

            SwiftUI.Section {
                Toggle("Только в строке меню", isOn: $state.menuBarOnly)
                Button("Показать приветствие") {
                    openWindow(id: "main")
                    NSApp.activate()
                    state.showWelcome = true
                }
            } header: {
                Text("Вид")
            } footer: {
                Text("Без значка в Dock. Окно и настройки открываются из значка микрофона в строке меню.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 680)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = Paster.isTrusted
        }
    }
}

/// Выбор микрофона — один и тот же в настройках, строке меню и окне.
struct MicrophonePicker: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Picker("Микрофон", selection: $state.microphoneUID) {
            Text("Системный — \(state.microphones.defaultName)").tag("")
            Divider()
            ForEach(state.microphones.devices) { device in
                Text(device.name).tag(device.uid)
            }
            if state.microphoneMissing {
                Text(state.microphoneTitle).tag(state.microphoneUID)
            }
        }
    }
}
