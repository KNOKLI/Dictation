import SwiftUI
import AppKit

/// Плавающая «пилюля» внизу экрана, когда диктуешь в другом приложении.
/// После Esc — «Запись отменена · Вернуть».
@MainActor
final class HUDController {
    private let panel: NSPanel
    private unowned let state: AppState
    /// С запасом под тень. Прозрачные места пропускают клики насквозь.
    static let size = NSSize(width: 460, height: 110)

    init(state: AppState) {
        self.state = state
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: RecordingHUD().environment(state))
        host.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = host
        // Ушёл в другое приложение посреди записи — плашка должна появиться (и спрятаться, когда вернулся)
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
    }

    func update() {
        let active = state.phase == .recording || state.phase == .transcribing || state.undoToastVisible
            || state.cancelAnimating // плашка видна, пока трясётся после Esc
            || state.hudEvent != nil  // и пока показывает ✓ / «пожал плечами»
        guard active, !NSApp.isActive else {
            panel.orderOut(nil)
            stopHoverTracking()
            if state.hudShown { state.hudShown = false }
            return
        }
        if !state.hudShown { state.hudShown = true }
        // 2026-11-25: плашка — на экране, где сейчас мышь (где работает Камиль).
        // NSScreen.main при неактивном приложении — экран старого окна Dictation, поэтому плашку
        // было видно только на одном мониторе.
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - Self.size.width / 2, y: f.minY + 12))
        }
        panel.orderFrontRegardless()
        startHoverTracking()
    }

    // MARK: - Наведение мыши
    // В неактивном приложении SwiftUI .onHover в плашке не срабатывает — проверяем мышь сами, 10 раз в секунду.

    private var hoverTimer: Timer?

    private func startHoverTracking() {
        guard hoverTimer == nil else { return }
        // 30 раз в секунду — ✓ без задержки
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHover() }
        }
    }

    private func stopHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        if state.hudHover { state.hudHover = false }
    }

    private func checkHover() {
        let f = panel.frame
        // плашка прижата к низу окна (отступ 24), раскрытая — до 168 pt шириной; берём с запасом
        let halfWidth = RecordingHUD.pillHeight / 2 + 4 // круг 64 pt
        let zone = NSRect(x: f.midX - halfWidth, y: f.minY + 20, width: halfWidth * 2, height: RecordingHUD.pillHeight + 8)
        let inside = state.isRecording && zone.contains(NSEvent.mouseLocation)
        if inside != state.hudHover {
            withAnimation(.easeInOut(duration: RecordingHUD.hoverLens.time)) { state.hudHover = inside } // «Линза»
        }
    }
}

struct RecordingHUD: View {
    @Environment(AppState.self) private var state
    private var hover: Bool { state.hudHover }

    var body: some View {
        VStack(spacing: 0) {
            // Пока плашки не видно (открыто окно приложения), её содержимое не строится и не
            // перерисовывается на каждое изменение громкости.
            if state.hudShown { pill }
        }
        .padding(.bottom, 24)
        .animation(.smooth(duration: 0.25), value: state.phase)
        .animation(.smooth(duration: 0.25), value: state.undoToastVisible)
        .frame(width: HUDController.size.width, height: HUDController.size.height, alignment: .bottom)
    }

    /// 2026-11-20 (Камиль): вариант 5 «Кружок» из минималистичных (MinPills), крупнее примера:
    /// один стеклянный круг 64 pt. Запись — красное кольцо растёт от голоса; распознавание — синяя дуга
    /// крутится; «Вернуть» — круг со стрелкой ↶.
    static let pillHeight: CGFloat = 64
    /// 2026-11-23 (Камиль): вариант 4 «Кольцо активности» — толстое кольцо 7 pt, значок 16 pt.
    static let ring: CGFloat = 7
    /// Дуга распознавания — доля круга
    static let thinkArc = 0.3
    /// Цвета заданы явно: системные (accentColor) в неактивном приложении становятся серыми.
    static let red = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let blue = Color(red: 0.04, green: 0.52, blue: 1.0)
    /// Системный жёлтый macOS — дуга при «?» (не распознано), 2026-11-25
    static let yellow = Color(red: 1.0, green: 0.8, blue: 0.0)

    @ViewBuilder
    private var pill: some View {
        // 2026-11-21: запись / распознавание / «Вернуть» и анимации событий — HUDPill (HUDEvents.swift)
        HUDPill()
        // 2026-11-20 (Камиль): появление «Желе» (вариант 1 из DropPills, улучшенная «Капля»):
        // летит снизу вытянутой, при «ударе» сплющивается и упруго колышется.
        // Числа — из конструктора `../Dictation_Плашки` (AnimLab): Камиль присылает строку
        // «rise 44, overshoot 6, …» — меняем только `Self.appear`, код не трогаем.
        .keyframeAnimator(initialValue: Jelly(), trigger: jellyTrigger) { content, v in
            content
                .scaleEffect(x: v.sx, y: v.sy, anchor: .bottom)
                .offset(y: v.y)
                .blur(radius: v.blur)
                .opacity(v.op)
        } keyframes: { _ in
            let p = Self.appear
            let settle = Spring(response: 0.4, dampingRatio: p.bounce)
            KeyframeTrack(\Jelly.y) {
                MoveKeyframe(CGFloat(p.rise))
                CubicKeyframe(CGFloat(-p.overshoot), duration: p.flyTime)
                SpringKeyframe(0, duration: 0.5, spring: Spring(response: 0.5, dampingRatio: min(1, p.bounce + 0.25)))
            }
            KeyframeTrack(\Jelly.sy) {
                MoveKeyframe(CGFloat(1 - p.squash))
                CubicKeyframe(CGFloat(1 + p.stretch), duration: p.flyTime * 0.83)   // летит — вытянута
                CubicKeyframe(CGFloat(1 - p.impact), duration: max(0.001, p.impactTime)) // удар — сплющена
                SpringKeyframe(1, duration: p.settleTime, spring: settle)
            }
            KeyframeTrack(\Jelly.sx) {
                MoveKeyframe(CGFloat(1 + p.squash * 0.82))
                CubicKeyframe(CGFloat(1 - p.stretch * 0.73), duration: p.flyTime * 0.83)
                CubicKeyframe(CGFloat(1 + p.impact * 0.8), duration: max(0.001, p.impactTime))
                SpringKeyframe(1, duration: p.settleTime, spring: settle)
            }
            KeyframeTrack(\Jelly.op) {
                MoveKeyframe(p.fromEdge ? 1 : 0)
                LinearKeyframe(1, duration: max(0.001, p.fade))
            }
            KeyframeTrack(\Jelly.blur) {
                MoveKeyframe(CGFloat(p.blur))
                CubicKeyframe(0, duration: 0.35)
            }
        }
        .mask { // «из-под края»: снизу обрезано по краю экрана (плашка на 24 pt выше)
            Rectangle().padding(EdgeInsets(top: -300, leading: -300,
                                           bottom: Self.appear.fromEdge ? -24 : -300, trailing: -300))
        }
        .opacity(jellyArmed ? 1 : 0) // пока анимация не запущена — не мигать готовым кругом
        .shadow(color: .black.opacity(0.18), radius: 9, y: 3)
        .onAppear { jellyTrigger += 1; jellyArmed = true }   // каждый раз, когда плашка появляется
        .onDisappear { jellyArmed = false }
        // 2026-11-21 (Камиль): отмена по Esc — «1. Тряска» из конструктора (числа — `Self.cancelAnim`)
        .keyframeAnimator(initialValue: Shake(), trigger: state.cancelTrigger) { content, v in
            content
                .overlay { Circle().fill(Self.red.opacity(0.35 * v.red)).allowsHitTesting(false) }
                .scaleEffect(x: v.sx * v.scale, y: v.scale / max(0.5, v.sx))
                .rotationEffect(.degrees(v.rot), anchor: .bottom)
                .offset(x: v.x, y: v.y)
                .blur(radius: v.blur)
                .opacity(v.op)
        } keyframes: { _ in
            let p = Self.cancelAnim
            let n = min(4, max(0, Int(p.shakes.rounded())))
            let shake = n > 0 ? p.shakeTime : 0
            let seg = n > 0 ? p.shakeTime / Double(2 * n) : 0.001
            // i-й толчок: +, −, +, −…, каждый слабее; последний возвращает в 0
            let d: (Int) -> Double = { i in i < 2 * n ? seg : 0.001 }
            let v: (Int, Double) -> Double = { i, a in
                i < 2 * n - 1 ? (i % 2 == 0 ? 1 : -1) * a * pow(p.decay, Double(i / 2)) : 0
            }
            KeyframeTrack(\Shake.x) {
                MoveKeyframe(0)
                CubicKeyframe(CGFloat(v(0, p.amp)), duration: d(0)); CubicKeyframe(CGFloat(v(1, p.amp)), duration: d(1))
                CubicKeyframe(CGFloat(v(2, p.amp)), duration: d(2)); CubicKeyframe(CGFloat(v(3, p.amp)), duration: d(3))
                CubicKeyframe(CGFloat(v(4, p.amp)), duration: d(4)); CubicKeyframe(CGFloat(v(5, p.amp)), duration: d(5))
                CubicKeyframe(CGFloat(v(6, p.amp)), duration: d(6)); CubicKeyframe(CGFloat(v(7, p.amp)), duration: d(7))
            }
            KeyframeTrack(\Shake.rot) {
                MoveKeyframe(0)
                CubicKeyframe(v(0, p.rot), duration: d(0)); CubicKeyframe(v(1, p.rot), duration: d(1))
                CubicKeyframe(v(2, p.rot), duration: d(2)); CubicKeyframe(v(3, p.rot), duration: d(3))
                CubicKeyframe(v(4, p.rot), duration: d(4)); CubicKeyframe(v(5, p.rot), duration: d(5))
                CubicKeyframe(v(6, p.rot), duration: d(6)); CubicKeyframe(v(7, p.rot), duration: d(7))
            }
            KeyframeTrack(\Shake.sx) {
                MoveKeyframe(1)
                CubicKeyframe(CGFloat(1 + v(0, p.wobble)), duration: d(0)); CubicKeyframe(CGFloat(1 + v(1, p.wobble)), duration: d(1))
                CubicKeyframe(CGFloat(1 + v(2, p.wobble)), duration: d(2)); CubicKeyframe(CGFloat(1 + v(3, p.wobble)), duration: d(3))
                CubicKeyframe(CGFloat(1 + v(4, p.wobble)), duration: d(4)); CubicKeyframe(CGFloat(1 + v(5, p.wobble)), duration: d(5))
                CubicKeyframe(CGFloat(1 + v(6, p.wobble)), duration: d(6)); CubicKeyframe(CGFloat(1 + v(7, p.wobble)), duration: d(7))
            }
            KeyframeTrack(\Shake.red) {
                MoveKeyframe(0)
                CubicKeyframe(p.red, duration: 0.08)
                CubicKeyframe(0, duration: shake + p.exitTime)
            }
            // уход; в самом конце — сразу обратно в покой (плашка к этому моменту уже спрятана
            // или сменилась на «Вернуть», которой нужен нормальный вид)
            KeyframeTrack(\Shake.scale) {
                MoveKeyframe(1); LinearKeyframe(1, duration: shake)
                CubicKeyframe(CGFloat(p.exitScale), duration: p.exitTime)
                LinearKeyframe(CGFloat(p.exitScale), duration: 0.05)
                MoveKeyframe(1)
            }
            KeyframeTrack(\Shake.y) {
                MoveKeyframe(0); LinearKeyframe(0, duration: shake)
                CubicKeyframe(CGFloat(p.exitDrop), duration: p.exitTime)
                LinearKeyframe(CGFloat(p.exitDrop), duration: 0.05)
                MoveKeyframe(0)
            }
            KeyframeTrack(\Shake.blur) {
                MoveKeyframe(0); LinearKeyframe(0, duration: shake)
                CubicKeyframe(CGFloat(p.exitBlur), duration: p.exitTime)
                LinearKeyframe(CGFloat(p.exitBlur), duration: 0.05)
                MoveKeyframe(0)
            }
            KeyframeTrack(\Shake.op) {
                MoveKeyframe(1); LinearKeyframe(1, duration: shake)
                CubicKeyframe(0, duration: p.exitTime)
                LinearKeyframe(0, duration: 0.05)
                MoveKeyframe(1)
            }
        }
        .allowsHitTesting(!state.cancelAnimating)
    }

    @State private var jellyTrigger = 0
    @State private var jellyArmed = false
    private var onlyUndo: Bool { state.undoToastVisible && !state.isRecording && state.phase != .transcribing }

    /// Запись: красное кольцо по громкости голоса вокруг микрофона.
    /// Наведёшь мышь — микрофон сменится на ✓: нажал — готово (Esc — отменить).
    private var recording: some View {
        let level = CGFloat(state.levels.suffix(3).max() ?? 0)
        return Button { state.toggle() } label: {
            circle {
                Circle().trim(from: 0, to: state.micLive ? 0.1 + 0.9 * level : 0)
                    .stroke(Self.red, style: StrokeStyle(lineWidth: Self.ring, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.15), value: level)
            } icon: {
                Image(systemName: hover ? "checkmark" : "mic.fill")
                    .font(.system(size: hover ? 17 : 18, weight: hover ? .bold : .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .opacity(state.micLive ? 1 : 0.5)
            }
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help("Готово — Return · Отменить — Esc")
    }

    /// Стеклянный круг с серой дорожкой кольца, цветным кольцом и значком в центре
    private func circle<R: View, I: View>(@ViewBuilder ring: () -> R, @ViewBuilder icon: () -> I) -> some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.12), lineWidth: Self.ring)
            ring()
            icon() // размер задаёт каждый значок сам (18 pt — смотрится в круге 64)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .frame(width: Self.pillHeight, height: Self.pillHeight)
        // стекло — общее, снаружи (pill), чтобы круг мог расти из бусины
    }
}

/// Форма плашки в момент появления
private struct Jelly {
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var y: CGFloat = 0
    var op: Double = 1
    var blur: CGFloat = 0
}

/// Настройки появления «Капля» — те же имена, что в конструкторе AnimLab.
struct DropAppear {
    var rise = 44.0, overshoot = 6.0, flyTime = 0.24
    var squash = 0.55, stretch = 0.22, impact = 0.2, impactTime = 0.12
    var bounce = 0.45, settleTime = 0.6, fade = 0.12, blur = 0.0
    var fromEdge = false
}

extension RecordingHUD {
    /// 2026-11-21: «Желе (в приложении)» из конструктора.
    static let appear = DropAppear()

    /// 2026-11-21 (Камиль): «1. Тряска» (отмена): amp 11, rot 0, wobble 0, shakes 3, shakeTime 0.43,
    /// decay 0.7, red 0.15, exitTime 0.25, exitScale 0.7, exitDrop 0, exitBlur 4
    static let cancelAnim = CancelAppear(amp: 11, rot: 0, wobble: 0, shakes: 3, shakeTime: 0.43, decay: 0.7,
                                         red: 0.15, exitTime: 0.25, exitScale: 0.7, exitDrop: 0, exitBlur: 4)
    /// Сколько длится тряска + уход (AppState ждёт столько, прежде чем спрятать плашку / показать «Вернуть»)
    static var cancelDuration: Double {
        (cancelAnim.shakes >= 1 ? cancelAnim.shakeTime : 0) + cancelAnim.exitTime
    }
}

/// Настройки отмены — те же имена, что в конструкторе AnimLab.
struct CancelAppear {
    var amp, rot, wobble, shakes, shakeTime, decay, red, exitTime, exitScale, exitDrop, exitBlur: Double
}

/// Состояние плашки во время тряски
private struct Shake {
    var x: CGFloat = 0, rot: Double = 0, sx: CGFloat = 1, scale: CGFloat = 1
    var y: CGFloat = 0, op: Double = 1, blur: CGFloat = 0, red: Double = 0
}

extension RecordingHUD {
}

/// Значок в цветном круге 38 pt (как в варианте «Как Siri»).
private struct PillIcon: View {
    let color: Color
    let symbol: String
    var animated = false

    // 2026-11-20 (Камиль, вариант 3 «Цвета иконки» из GlowPills): круг и свечение в цветах иконки
    // приложения — синий, фиолетовый, розовый — медленно переливаются. `color` больше не используется.
    var body: some View {
        TimelineView(.animation) { ctx in
            let colors = Brand.angular(ctx.date.timeIntervalSinceReferenceDate)
            ZStack {
                Circle().fill(colors).frame(width: 40, height: 40).blur(radius: 12).opacity(0.8)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: animated)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(colors))
            }
            .frame(width: 38, height: 38)
        }
    }
}

private struct HUDButton: View {
    let icon: String
    let help: String
    let prominent: Bool
    var size: CGFloat = 32
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.37, weight: .bold))
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: size, height: size)
                .background {
                    Circle().fill(prominent ? AnyShapeStyle(Color.accentColor.gradient)
                                            : AnyShapeStyle(.primary.opacity(hover ? 0.16 : 0.08)))
                }
                .scaleEffect(hover ? 1.06 : 1)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in withAnimation(.snappy(duration: 0.15)) { hover = h } }
    }
}

/// Цвета иконки приложения.
enum Brand {
    static let blue = Color(red: 0.33, green: 0.42, blue: 1.00)
    static let purple = Color(red: 0.62, green: 0.32, blue: 0.98)
    static let pink = Color(red: 1.00, green: 0.36, blue: 0.62)
    static let gradient = LinearGradient(colors: [blue, purple, pink], startPoint: .leading, endPoint: .trailing)
    /// Медленно вращающийся круговой градиент иконки (плашки «Цвета иконки»)
    static func angular(_ t: Double) -> AngularGradient {
        AngularGradient(colors: [blue, purple, pink, blue], center: .center, angle: .degrees(t * 40))
    }
}

/// «Думающая» волна: по полоскам бежит синусоида, цвет — градиент иконки.
private struct ThinkingWave: View {
    private let count = 9

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    let wave = 0.5 + 0.5 * sin(t * 5.5 - Double(i) * 0.7)
                    Capsule()
                        .frame(width: 3, height: 4 + 14 * wave)
                }
            }
            .frame(height: 20)
            .foregroundStyle(Brand.gradient)
        }
    }
}

/// Текст с мягким бегущим бликом. Яркость не опускается ниже 65% — всегда читается.
private struct ShimmerText: View {
    let text: String

    var body: some View {
        TimelineView(.animation) { ctx in
            let period = 2.0
            let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let x = -0.4 + p * 1.8
            Text(text)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.primary)
                .mask {
                    LinearGradient(colors: [.black.opacity(0.65), .black, .black.opacity(0.65)],
                                   startPoint: UnitPoint(x: x - 0.35, y: 0.5),
                                   endPoint: UnitPoint(x: x + 0.35, y: 0.5))
                }
        }
    }
}

/// Короткая симметричная волна: в центре выше, к краям ниже.
private struct HUDWave: View {
    let levels: [Float]
    var count = 13
    var height: CGFloat = 22
    var spacing: CGFloat = 3
    var bar: CGFloat = 3

    var body: some View {
        let recent = Array(levels.suffix(count))
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                let env = 0.45 + 0.55 * sin(Double.pi * (Double(i) + 0.5) / Double(count))
                let v = i < recent.count ? Double(recent[i]) : 0
                Capsule()
                    .fill(.primary.opacity(0.85))
                    .frame(width: bar, height: max(bar, CGFloat(v * env) * height))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.12), value: recent)
    }
}

/// Красная точка записи: серая, пока микрофон включается; потом мягко «дышит».
private struct RecDot: View {
    let live: Bool
    var body: some View {
        TimelineView(.animation(paused: !live)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(live ? Color.red : Color.secondary)
                .frame(width: 7, height: 7)
                .opacity(live ? 0.6 + 0.4 * (0.5 + 0.5 * sin(t * 3)) : 1)
        }
        .frame(width: 7, height: 7)
    }
}

/// Распознавание в плашке: три точки бегут волной, цвета иконки.
private struct FocusDots: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    let p = 0.5 + 0.5 * sin(t * 6 - Double(i) * 0.9)
                    Circle()
                        .fill([Brand.blue, Brand.purple, Brand.pink][i])
                        .frame(width: 7, height: 7)
                        .scaleEffect(0.75 + 0.35 * p)
                        .opacity(0.45 + 0.55 * p)
                }
            }
        }
    }
}

struct WaveformView: View {
    var levels: [Float]
    var barWidth: CGFloat = 4
    var spacing: CGFloat = 3
    var height: CGFloat = 40

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .frame(width: barWidth, height: max(barWidth, CGFloat(levels[i]) * height))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.12), value: levels)
    }
}
