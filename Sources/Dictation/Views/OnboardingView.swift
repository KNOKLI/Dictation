import SwiftUI
import AVFoundation

/// Приветствие для нового пользователя: модель → микрофон → универсальный доступ → проверка.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var trusted = Paster.isTrusted
    @State private var startCount = 0

    private var tested: Bool { state.history.entries.count > startCount }

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            VStack(spacing: 6) {
                Text("Добро пожаловать в Dictation")
                    .font(.largeTitle.bold())
                Text("Диктовка на русском прямо на этом Mac — без интернета и подписок.\nНесколько шагов, и можно говорить.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Step(number: 1, title: "Модель распознавания", done: state.modelReady,
                     detail: state.modelReady ? "Готова: \(ModelInfo.displayName), работает без интернета."
                                              : "Скачивается один раз, ~575 МБ.") {
                    if state.phase == .downloading {
                        ProgressView(value: state.downloadProgress)
                    } else if state.phase == .needsModel {
                        Button("Скачать модель") { state.downloadModel() }
                            .buttonStyle(.glassProminent)
                    } else if state.phase == .loadingModel {
                        ProgressView().controlSize(.small)
                    }
                }

                Step(number: 2, title: "Микрофон", done: micStatus == .authorized,
                     detail: micStatus == .denied
                        ? "Доступ запрещён — включи Dictation в Системных настройках → Конфиденциальность → Микрофон."
                        : "Нужен, чтобы слышать тебя. Звук никуда не отправляется.") {
                    if micStatus == .authorized {
                        MicrophonePicker().labelsHidden().frame(maxWidth: 260)
                    } else if micStatus == .notDetermined {
                        Button("Разрешить микрофон") {
                            Task {
                                _ = await AppState.microphoneAccess()
                                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                            }
                        }
                        .buttonStyle(.glassProminent)
                    } else {
                        Button("Открыть настройки") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                    }
                }

                Step(number: 3, title: "Универсальный доступ", done: trusted,
                     detail: "Чтобы клавиша «\(state.triggerKind.title)» работала в любом приложении, а текст сам вставлялся туда, где курсор.") {
                    if !trusted {
                        Button("Открыть настройки") {
                            Paster.requestTrust()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }

                Step(number: 4, title: "Проверка", done: tested,
                     detail: tested ? "«\(state.lastText)»"
                                    : "Нажми «\(state.triggerKind.title)», скажи «Привет, это проверка» и нажми ещё раз (или Return).") {
                    if state.isRecording {
                        Label(state.micLive ? "Слушаю…" : "Включаю микрофон…", systemImage: "waveform")
                            .foregroundStyle(.red)
                    } else if state.phase == .transcribing {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            HStack {
                Button("Пропустить") { finish() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Начать пользоваться") { finish() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        }
        .padding(32)
        .frame(width: 580)
        .onAppear { startCount = state.history.entries.count }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            trusted = Paster.isTrusted
        }
    }

    private func finish() {
        state.onboarded = true
        state.showWelcome = false
    }
}

private struct Step<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    let detail: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(.quaternary))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .animation(.snappy, value: done)

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }
}
