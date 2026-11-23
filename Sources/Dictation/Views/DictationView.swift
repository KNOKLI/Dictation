import SwiftUI

/// Дизайн «Фокус»: огромный счётчик символов, одна кнопка, большая волна во время записи.
struct DictationView: View {
    @Environment(AppState.self) private var state

    // 2026-11-24 (Камиль): Q1 «Только главное» — одна большая кнопка и одна подпись.
    // Прежний «Фокус» (счётчик, последняя диктовка) — `_backup-2026-11-24-Q1/DictationView.swift`.
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            top.frame(height: 120)
            Spacer().frame(height: 22)
            bigButton
            caption.padding(.top, 18)
            if state.cancelled != nil && !state.isRecording && state.phase != .transcribing {
                Button {
                    state.restoreCancelled()
                } label: {
                    Text("Вернуть отменённую запись (\(RU.duration(state.cancelled?.duration ?? 0)))")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 18)
                .transition(.opacity)
            }
            if state.phase == .needsModel || state.phase == .downloading {
                ModelCard().padding(.top, 24).frame(maxWidth: 520)
            }
            Spacer(minLength: 20)
            Spacer().frame(height: 120)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.35), value: state.phase)
    }

    /// Над кнопкой: волна во время записи, «Распознаю…», или сообщение (ошибка / загрузка модели)
    @ViewBuilder
    private var top: some View {
        switch state.phase {
        case .recording:
            MirrorWave(levels: state.levels, height: 90)
                .foregroundStyle(.primary)
                .opacity(state.micLive ? 1 : 0.3)
                .transition(.blurReplace)
        case .transcribing:
            VStack(spacing: 16) {
                FocusThinking().frame(height: 80)
                FocusShimmer(text: "Распознаю…")
            }
            .transition(.blurReplace)
        default:
            if state.isFailed || state.phase == .loadingModel || state.phase == .needsModel
                || state.phase == .downloading {
                Text(state.statusText)
                    .font(.system(size: 17))
                    .foregroundStyle(state.isFailed ? .red : .secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                Color.clear
            }
        }
    }

    /// Большая круглая кнопка: синяя — начать, красная — готово
    private var bigButton: some View {
        Button { state.toggle() } label: {
            Image(systemName: state.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 110, height: 110)
                .background(Circle().fill(state.isRecording ? Color.red : Color.accentColor))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!state.canRecord && !state.isRecording)
        .opacity(!state.canRecord && !state.isRecording ? 0.45 : 1)
        .help(state.isRecording ? "Готово — Return" : "Начать диктовку")
        .animation(.smooth(duration: 0.25), value: state.isRecording)
    }

    /// Одна подпись под кнопкой
    @ViewBuilder
    private var caption: some View {
        if state.isRecording {
            HStack(spacing: 14) {
                Text("Return — готово").foregroundStyle(.secondary)
                Button("Отменить") { state.cancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Esc")
            }
            .font(.system(size: 17))
        } else {
            Text("Нажми или \(state.triggerKind.title)")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Кнопки

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            if state.isRecording {
                Button { state.cancel() } label: {
                    Label("Отменить", systemImage: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
                .transition(.scale.combined(with: .opacity))
            }
            Button { state.toggle() } label: {
                Label(state.isRecording ? "Готово" : "Начать диктовку",
                      systemImage: state.isRecording ? "checkmark" : "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.horizontal, 18).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(state.isRecording ? .red : .accentColor)
            .controlSize(.extraLarge)
            .disabled(!state.canRecord && !state.isRecording)
        }
        .animation(.smooth(duration: 0.3), value: state.isRecording)
    }

    private var hints: some View {
        Group {
            if state.isRecording {
                HStack(spacing: 6) {
                    KeyCap("Return"); Text("готово")
                    Text("·").foregroundStyle(.quaternary)
                    KeyCap("Esc"); Text("отменить")
                }
            } else {
                HStack(spacing: 6) {
                    Text("или")
                    KeyCap(state.triggerKind.title)
                    Text(state.holdToTalk ? "— нажми или держи в любом приложении" : "в любом приложении")
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Последняя диктовка — тихая цитата, действия при наведении

private struct LastDictation: View {
    @Environment(AppState.self) private var state
    @State private var hover = false
    @State private var copied = false
    @State private var editing = false

    var body: some View {
        let text = state.lastText
        VStack(alignment: .leading, spacing: 10) {
            if editing, let id = state.lastEntryID {
                EntryEditor(entryID: id) { editing = false }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "quote.opening")
                        .foregroundStyle(.tertiary)
                    Text(text)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    Text(caption(text))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Group {
                        Button("Изменить", systemImage: "pencil") { editing = true }
                        Button {
                            Paster.copy(text)
                            copied = true
                            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                        } label: {
                            Label(copied ? "Готово" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .opacity(hover || copied ? 1 : 0)
                }
                .padding(.leading, 26)
            }
        }
        .padding(14)
        .background(.primary.opacity(hover || editing ? 0.04 : 0), in: .rect(cornerRadius: 16))
        .onHover { h in withAnimation(.smooth(duration: 0.2)) { hover = h } }
        .onChange(of: state.lastEntryID) { _, _ in editing = false }
    }

    /// «Вставлено в 11:43 · 21 символ · изменено» — без лишних точек.
    private func caption(_ text: String) -> String {
        var parts: [String] = []
        if let at = state.lastDeliveredAt {
            parts.append(state.lastDeliveryPasted ? "Вставлено в \(RU.time(at))" : "Скопировано в \(RU.time(at))")
        }
        parts.append(RU.chars(text.count))
        if state.history.entry(state.lastEntryID)?.isEdited == true { parts.append("изменено") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Волны

/// Большая зеркальная волна по реальному звуку: в центре выше, к краям ниже.
/// Рисуется одним Canvas (раньше — 56 отдельных капсул с анимацией, их раскладка на каждом кадре
/// грузила главный поток во время записи). Плавность — сглаживанием к новым уровням на каждом кадре.
struct MirrorWave: View {
    let levels: [Float]
    var count = 56
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 4
    var height: CGFloat = 90
    @State private var smoother = WaveSmoother()

    var body: some View {
        let target = Array(levels.suffix(count))
        let width = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let values = smoother.step(toward: target, count: count, now: ctx.date)
                var x = (size.width - width) / 2
                for i in 0..<count {
                    let env = 0.35 + 0.65 * sin(Double.pi * (Double(i) + 0.5) / Double(count))
                    let h = max(barWidth, CGFloat(values[i] * env) * height)
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                    g.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .foreground)
                    x += barWidth + spacing
                }
            }
        }
        .frame(width: width, height: height)
    }
}

/// Плавно подтягивает отображаемые уровни к реальным (~60 мс), как раньше делала анимация.
final class WaveSmoother {
    private var current: [Double] = []
    private var last: Date?

    func step(toward target: [Float], count: Int, now: Date) -> [Double] {
        if current.count != count { current = Array(repeating: 0, count: count) }
        let dt = min(0.1, max(0, now.timeIntervalSince(last ?? now)))
        last = now
        let k = 1 - exp(-dt / 0.06)
        let offset = count - target.count
        for i in 0..<count {
            let t = i >= offset && i - offset < target.count ? Double(target[i - offset]) : 0
            current[i] += (t - current[i]) * k
        }
        return current
    }
}

/// Распознавание: мягкая бегущая волна в цветах иконки.
private struct FocusThinking: View {
    private let count = 40

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { i in
                    let env = 0.35 + 0.65 * sin(Double.pi * (Double(i) + 0.5) / Double(count))
                    let w = 0.25 + 0.75 * (0.5 + 0.5 * sin(t * 4.5 - Double(i) * 0.35))
                    Capsule().frame(width: 3, height: max(3, 70 * w * env))
                }
            }
            .foregroundStyle(Brand.gradient)
        }
    }
}

private struct FocusShimmer: View {
    let text: String
    var body: some View {
        TimelineView(.animation) { ctx in
            let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
            let x = -0.4 + p * 1.8
            Text(text)
                .font(.title2.weight(.medium))
                .mask {
                    LinearGradient(colors: [.black.opacity(0.6), .black, .black.opacity(0.6)],
                                   startPoint: UnitPoint(x: x - 0.35, y: 0.5),
                                   endPoint: UnitPoint(x: x + 0.35, y: 0.5))
                }
        }
    }
}

// MARK: - Карточка модели

private struct ModelCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Модель распознавания", systemImage: "cpu")
                .font(.headline)
            Text("\(ModelInfo.displayName) работает полностью на этом Mac, без интернета. Нужно скачать один раз (~575 МБ).")
                .foregroundStyle(.secondary)
            if state.phase == .downloading {
                ProgressView(value: state.downloadProgress)
            } else {
                Button("Скачать модель") { state.downloadModel() }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
    }
}

struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary, in: .rect(cornerRadius: 6))
    }
}

/// Выбор микрофона в панели инструментов главного окна (виден во всех разделах).
struct MicrophoneToolbarMenu: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Menu {
            MicrophonePicker()
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            Label(state.microphoneTitle,
                  systemImage: state.microphoneMissing ? "mic.slash" : "mic")
                .labelStyle(.titleAndIcon)
        }
        .help("Выбрать микрофон")
    }
}
