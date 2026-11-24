import SwiftUI

/// 2026-11-21 (Камиль): анимации событий плашки — числа из конструктора `../Dictation_Плашки` (EventLab).
/// Перенос новых настроек = замена чисел в `RecordingHUD.success/fail/toThink/restore/hoverLens`.
struct EventSpec {
    var amount = 1.0, amount2 = 1.0, time = 0.4, hold = 0.35, spring = 0.5
}

extension RecordingHUD {
    /// «1. Галочка» (удачно)
    static let success = EventSpec(amount: 1, amount2: 1, time: 0.4, hold: 0.35, spring: 0.5)
    /// «1. Пожал плечами» (неудачно)
    static let fail = EventSpec(amount: 1, amount2: 1, time: 0.4, hold: 0.45, spring: 0.5)
    /// «1. Перетекание» (распознавание)
    static let toThink = EventSpec(amount: 0.86, amount2: 1, time: 0.52, hold: 0.35, spring: 0.5)
    /// «1. Перемотка» (вернуть)
    static let restore = EventSpec(amount: 1, amount2: 1, time: 0.45, hold: 0.35, spring: 0.5)
    /// «1. Линза» (наведение)
    static let hoverLens = EventSpec(amount: 0.42, amount2: 1, time: 0.12, hold: 0.35, spring: 0.5)

    /// Сколько плашка остаётся на экране ради «Галочки» / «Пожал плечами» (событие + пауза + уход)
    static var successDuration: Double { success.time + success.hold + 0.3 }
    static var failDuration: Double { fail.time + fail.hold + 0.3 }
}

// MARK: - Математика времени (как в конструкторе)

private func c01(_ x: Double) -> Double { min(1, max(0, x)) }
private func seg(_ t: Double, _ from: Double, _ dur: Double) -> Double {
    dur <= 0 ? (t >= from ? 1 : 0) : c01((t - from) / dur)
}
private func ease(_ x: Double) -> Double {
    let x = c01(x)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}
private func bump(_ t: Double, _ damp: Double) -> Double {
    t <= 0 ? 0 : exp(-t * (4 + damp * 14)) * sin(t * 22) * 1.6
}
private func mixC(_ a: Color, _ b: Color, _ k: Double) -> Color { a.mix(with: b, by: c01(k)) }

private let greenC = Color(red: 0.2, green: 0.78, blue: 0.35)

/// Как выглядит плашка в данный момент
private struct Look {
    enum Tap { case none, toggle, restore }
    var ringB = 0.0, ringColor = RecordingHUD.red, ringRot = -90.0, ringOp = 1.0, trackOp = 1.0
    var icon1 = "mic.fill", icon1Color: Color = .primary, icon1Op = 1.0
    var icon2 = "", icon2Color: Color = .primary, mix = 0.0
    var sx: CGFloat = 1, sy: CGFloat = 1, x: CGFloat = 0, rot = 0.0, op = 1.0, blur: CGFloat = 0
    var tap = Tap.none
    var help = ""
}

/// Плашка-круг: запись, распознавание, «Вернуть» и анимации переходов между ними.
struct HUDPill: View {
    @Environment(AppState.self) private var state

    var body: some View {
        // Кадры по времени нужны только для распознавания и событий. Во время записи кольцо и так
        // обновляется от голоса — без этого плашка 60–120 раз в секунду перерисовывала стекло всю запись.
        // + «Вернуть»: кольцо убывает за 2 с
        let ticking = state.phase == .transcribing || state.hudEvent != nil || state.undoToastVisible
        TimelineView(.animation(paused: !ticking)) { ctx in
            render(look(ticking ? ctx.date : .now))
        }
    }

    // MARK: Что показать

    private func look(_ date: Date) -> Look {
        var L = Look()
        if let ev = state.hudEvent {
            let t = date.timeIntervalSince(state.hudEventAt)
            if state.hudEventFromThinking { thinking(&L, date) } else { frozenRecording(&L, t) }
            switch ev {
            case .success: success(&L, t, date)
            case .fail: fail(&L, t)
            }
        } else if state.phase == .transcribing {
            thinking(&L, date)
            L.help = "Распознаю"
        } else if state.isRecording || state.cancelAnimating {
            recording(&L)
        } else if state.undoToastVisible {
            // кольцо «Вернуть» убывает — видно, сколько осталось
            let left = 1 - date.timeIntervalSince(state.undoShownAt) / AppState.undoSeconds
            L.ringB = max(0, min(1, left)); L.ringColor = RecordingHUD.blue
            L.icon1 = "arrow.uturn.backward"; L.icon1Color = RecordingHUD.blue
            L.tap = .restore
            L.help = "Вернуть отменённую запись"
        }
        return L
    }

    /// Запись: красное кольцо по громкости; мышь на плашке — ✓
    private func recording(_ L: inout Look) {
        let level = Double(state.levels.suffix(3).max() ?? 0)
        L.ringB = state.micLive ? 0.1 + 0.9 * level : 0
        // мышь на плашке — ✓ (быстрая смена прозрачностью, а не системной анимацией значка — та медленнее)
        L.icon1 = "mic.fill"; L.icon2 = "checkmark"; L.mix = state.hudHover ? 1 : 0
        L.icon1Op = state.micLive ? 1 : 0.5
        L.tap = state.cancelAnimating ? .none : .toggle
        L.help = "Готово — Return · Отменить — Esc"
    }

    /// Запись закончилась ничем — кольцо замерло и сереет
    private func frozenRecording(_ L: inout Look, _ t: Double) {
        L.ringB = 0.35
        L.ringColor = mixC(RecordingHUD.red, .gray, seg(t, 0, 0.2))
    }

    /// Угол дуги распознавания: после «Готово» — разгон («Перетекание»), после «Вернуть» — после перемотки
    private func thinkRot(_ date: Date) -> Double {
        let t = date.timeIntervalSince(state.thinkAt)
        if state.thinkFromRestore {
            return -90 + 360 * max(0, t - RecordingHUD.restore.time)
        }
        let p = RecordingHUD.toThink, T = max(0.05, p.time)
        return t < T ? -90 + 360 * p.amount * t * t / (2 * T) : -90 + 360 * p.amount * (T / 2 + t - T)
    }

    /// Распознавание + переходы в него
    private func thinking(_ L: inout Look, _ date: Date) {
        let t = date.timeIntervalSince(state.thinkAt)
        L.ringB = RecordingHUD.thinkArc; L.ringColor = RecordingHUD.blue; L.ringRot = thinkRot(date)
        L.icon1 = "waveform"
        if state.thinkFromRestore {
            // «1. Перемотка»: тряска задом наперёд, потом крутится дуга
            let p = RecordingHUD.restore, T = max(0.05, p.time)
            if t < T {
                let k = seg(t, 0, T)
                L.x = CGFloat(p.amount * 11 * sin(k * .pi * 2 * 3) * k)
                L.icon1 = "arrow.uturn.backward"; L.icon1Color = RecordingHUD.blue
                L.icon2 = "waveform"; L.mix = seg(t, T * 0.7, T * 0.3)
                L.ringOp = 0; L.trackOp = 0
            } else {
                L.ringOp = seg(t, T, 0.2); L.trackOp = L.ringOp
            }
        } else {
            // «1. Перетекание»: красное кольцо сжимается в дугу и синеет, микрофон → волна
            let p = RecordingHUD.toThink, T = max(0.05, p.time)
            if t < T {
                let k = ease(seg(t, 0, T))
                L.ringB = state.stopRing + (RecordingHUD.thinkArc - state.stopRing) * k
                L.ringColor = mixC(RecordingHUD.red, RecordingHUD.blue, k)
                L.icon1 = "mic.fill"; L.icon2 = "waveform"; L.mix = seg(t, T * 0.3, T * 0.4)
            }
        }
    }

    /// «1. Галочка»: дуга замыкается, волна → ✓, пружинка, уход
    private func success(_ L: inout Look, _ t: Double, _ date: Date) {
        let p = RecordingHUD.success, T = max(0.05, p.time)
        let close = ease(seg(t, 0, T))
        let r = thinkRot(date).truncatingRemainder(dividingBy: 360)
        let r0 = r < 0 ? r + 360 : r
        let target = r0 < 270 ? 270.0 : 630.0
        L.ringRot = r0 + (target - r0) * close
        L.ringB = RecordingHUD.thinkArc + (1 - RecordingHUD.thinkArc) * close
        L.ringColor = mixC(RecordingHUD.blue, greenC, p.amount2 * close)
        L.icon1 = "waveform"; L.icon1Color = .primary
        L.icon2 = "checkmark"; L.icon2Color = mixC(.primary, greenC, p.amount2)
        L.mix = seg(t, T * 0.5, T * 0.3)
        L.ringOp = 1; L.trackOp = 1; L.x = 0
        let b = bump(t - T, p.spring)
        L.sx = 1 + CGFloat(p.amount * 0.12 * b); L.sy = L.sx
        exitOut(&L, t - T - p.hold)
    }

    /// «1. Пожал плечами»: присел, «?», уход
    private func fail(_ L: inout Look, _ t: Double) {
        let p = RecordingHUD.fail, T = max(0.05, p.time)
        let b = bump(t * 0.4 / T, p.spring)
        L.sy = 1 - CGFloat(p.amount * 0.25 * b); L.sx = 1 + CGFloat(p.amount * 0.15 * b)
        L.icon2 = "questionmark"; L.mix = seg(t, 0, 0.15)
        // 2026-11-25 (Камиль): дуга при «?» — жёлтая (плавно из синей)
        L.ringColor = mixC(L.ringColor, RecordingHUD.yellow, seg(t, 0, 0.15))
        exitOut(&L, t - T - p.hold)
    }

    private func exitOut(_ L: inout Look, _ t: Double) {
        guard t > 0 else { return }
        let k = ease(seg(t, 0, 0.28))
        L.op *= 1 - k
        let s = CGFloat(1 - 0.2 * k)
        L.sx *= s; L.sy *= s
        L.blur += CGFloat(3 * k)
    }

    // MARK: Как нарисовать

    private func render(_ L: Look) -> some View {
        let lens = state.hudHover && state.isRecording ? 1 + 0.15 * RecordingHUD.hoverLens.amount : 1
        return face(L)
            .frame(width: RecordingHUD.pillHeight, height: RecordingHUD.pillHeight)
            .glassEffect(L.tap == .restore ? .regular.interactive() : .regular, in: .circle)
            .scaleEffect(CGFloat(lens)) // «1. Линза»: под мышью чуть больше (анимирует HUDController)
            .scaleEffect(x: L.sx, y: L.sy, anchor: .bottom)
            .rotationEffect(.degrees(L.rot), anchor: .bottom)
            .offset(x: L.x)
            .blur(radius: L.blur)
            .opacity(L.op)
            .help(L.help)
    }

    @ViewBuilder
    private func face(_ L: Look) -> some View {
        let content = ZStack {
            ZStack {
                Circle().stroke(.primary.opacity(0.1 * L.trackOp), lineWidth: RecordingHUD.ring)
                Circle().trim(from: 0, to: max(0, L.ringB))
                    .stroke(L.ringColor, style: StrokeStyle(lineWidth: RecordingHUD.ring, lineCap: .round))
                    .rotationEffect(.degrees(L.ringRot))
                    .opacity(L.ringOp)
                    .animation(L.tap == .toggle ? .smooth(duration: 0.15) : nil, value: L.ringB) // запись — плавно за голосом
            }
            .padding(9)
            ZStack {
                Image(systemName: L.icon1)
                    .foregroundStyle(L.icon1Color)
                    .opacity(L.icon1Op * (1 - L.mix))
                if !L.icon2.isEmpty {
                    Image(systemName: L.icon2).foregroundStyle(L.icon2Color).opacity(L.mix)
                }
            }
            .font(.system(size: 16, weight: .semibold))
        }
        .frame(width: RecordingHUD.pillHeight, height: RecordingHUD.pillHeight)
        .contentShape(.circle)

        switch L.tap {
        case .toggle: Button { state.toggle() } label: { content }.buttonStyle(.plain)
        case .restore: Button { state.restoreCancelled() } label: { content }.buttonStyle(.plain)
        case .none: content
        }
    }
}
