import SwiftUI

/// 2026-11-24 (Камиль): V7 «Герой и полки» — сверху синяя карточка с кнопкой записи и состоянием,
/// ниже полки «Недавние» (4 карточки, нажатие копирует) и «Сегодня» (3 плитки).
/// Прежний Q1 (одна кнопка) — `_backup-2026-11-24-V7/DictationView.swift`.
struct DictationView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let history = state.history
        let recent = history.recent(4)
        let week = history.lastDays(7).reduce(0) { $0 + $1.characters }
        VStack(alignment: .leading, spacing: V7.gap) {
            HeroCard(symbol: "waveform", height: 260) {
                bigButton.frame(width: 190)
                VStack(alignment: .leading, spacing: 10) {
                    heroTitle
                    heroSubtitle
                    if state.cancelled != nil && !state.isRecording && state.phase != .transcribing {
                        Button {
                            state.restoreCancelled()
                        } label: {
                            Label("Вернуть отменённую запись (\(RU.duration(state.cancelled?.duration ?? 0)))",
                                  systemImage: "arrow.uturn.backward")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .buttonStyle(.glass)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(.smooth(duration: 0.35), value: state.phase)

            if state.phase == .needsModel || state.phase == .downloading {
                ModelCard()
            }

            ShelfTitle(title: "Недавние", count: recent.isEmpty ? "" : RU.number(history.entries.count))
                .padding(.top, 6)
            if recent.isEmpty {
                Text("Здесь появятся последние диктовки. Нажми кнопку или \(state.triggerKind.title) — и говори.")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .background(.background.secondary, in: .rect(cornerRadius: V7.radius, style: .continuous))
            } else {
                HStack(spacing: V7.gap) {
                    ForEach(recent) { EntryCard(entry: $0) }
                    ForEach(recent.count..<4, id: \.self) { _ in Color.clear }
                }
                .frame(minHeight: 130, maxHeight: 160)
            }

            ShelfTitle(title: "Сегодня").padding(.top, 6)
            let today = history.entries.filter { Calendar.current.isDateInToday($0.date) }
            HStack(spacing: V7.gap) {
                StatTile(icon: "sun.max", value: RU.number(history.todayCharacters), label: "символов сегодня", highlight: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(today.isEmpty ? "Сегодня ещё не диктовал" : "\(today.count) \(RU.plural(today.count, "диктовка", "диктовки", "диктовок"))")
                            .font(.system(size: 17, weight: .semibold))
                        if let last = today.first {
                            Text("последняя в \(RU.time(last.date)) · \(RU.duration(today.reduce(0) { $0 + $1.duration })) речи")
                                .font(.system(size: 13.5)).foregroundStyle(.secondary)
                        }
                    }
                }
                StatTile(icon: "calendar", value: RU.number(week), label: "за неделю") {
                    WeekBars(days: history.lastDays(7)).frame(maxHeight: 150)
                }
                StatTile(icon: "gauge.with.dots.needle.67percent",
                         value: history.charsPerMinute > 0 ? RU.number(history.charsPerMinute) : "—",
                         label: "символов в минуту") {
                    if history.charsPerMinute > 0 {
                        let top = Double(max(history.charsPerMinute, 200))
                        VStack(spacing: 6) {
                            MeterRow(title: "Диктовка", value: RU.number(history.charsPerMinute),
                                     fraction: Double(history.charsPerMinute) / top, strong: true)
                            MeterRow(title: "Печать", value: "≈ 200", fraction: 200 / top)
                        }
                    }
                }
            }
            .frame(minHeight: 140, maxHeight: .infinity)
        }
        .padding(.horizontal, V7.pad).padding(.top, 8).padding(.bottom, V7.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Заголовок «героя»: готов / слушаю + волна / распознаю / ошибка
    @ViewBuilder
    private var heroTitle: some View {
        switch state.phase {
        case .recording:
            HStack(spacing: 18) {
                Text("Слушаю").font(.system(size: 40, weight: .bold))
                MirrorWave(levels: state.levels, count: 40, height: 56)
                    .foregroundStyle(Color.accentColor)
                    .opacity(state.micLive ? 1 : 0.3)
            }
            .transition(.blurReplace)
        case .transcribing:
            HStack(spacing: 18) {
                FocusShimmer(text: "Распознаю…")
                FocusThinking().frame(height: 56).scaleEffect(0.8, anchor: .leading)
            }
            .transition(.blurReplace)
        default:
            if state.isFailed || state.phase == .loadingModel || state.phase == .needsModel || state.phase == .downloading {
                Text(state.statusText)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(state.isFailed ? Color.red : Color.primary)
                    .lineLimit(2)
            } else {
                Text("Готов слушать").font(.system(size: 40, weight: .bold)).transition(.blurReplace)
            }
        }
    }

    /// Подпись и клавиши под заголовком
    @ViewBuilder
    private var heroSubtitle: some View {
        if state.isRecording {
            HStack(spacing: 10) {
                KeyCap("Return"); Text("готово").foregroundStyle(.secondary)
                KeyCap("Esc"); Text("отменить").foregroundStyle(.secondary)
                Button("Отменить") { state.cancel() }
                    .buttonStyle(.glass)
                    .padding(.leading, 6)
            }
            .font(.system(size: 14))
        } else {
            Text("Говори — текст сам появится там, где курсор.")
                .font(.system(size: 17)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                KeyCap(state.triggerKind.title); Text(state.holdToTalk ? "нажми или держи" : "начать").foregroundStyle(.secondary)
                KeyCap("Esc"); Text("отменить").foregroundStyle(.secondary)
                KeyCap("⌃⌥V"); Text("вставить ещё раз").foregroundStyle(.secondary)
            }
            .font(.system(size: 13.5))
            .padding(.top, 2)
        }
    }

    /// Большая круглая кнопка со «свечением»: синяя — начать, красная — готово
    private var bigButton: some View {
        let tint = state.isRecording ? Color.red : Color.accentColor
        return Button { state.toggle() } label: {
            ZStack {
                ForEach(0..<3, id: \.self) { k in
                    Circle().stroke(tint.opacity(0.22 - Double(k) * 0.06), lineWidth: 1.5)
                        .frame(width: 118 + CGFloat(k + 1) * 30)
                }
                Circle().fill(tint.opacity(0.18)).frame(width: 140)
                Image(systemName: state.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 118, height: 118)
                    .background(Circle().fill(tint))
                    .shadow(color: tint.opacity(0.5), radius: 22, y: 8)
            }
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!state.canRecord && !state.isRecording)
        .opacity(!state.canRecord && !state.isRecording ? 0.45 : 1)
        .help(state.isRecording ? "Готово — Return" : "Начать диктовку")
        .animation(.smooth(duration: 0.25), value: state.isRecording)
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
