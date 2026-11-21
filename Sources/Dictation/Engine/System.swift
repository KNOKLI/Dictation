import AppKit
import Carbon
import ApplicationServices

/// Глобальная клавиша через Carbon. Перехватывает нажатие — в активное приложение оно не уходит.
/// Используется для Esc / Return, пока идёт запись.
final class HotKey {
    nonisolated(unsafe) private static var actions: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var handlerInstalled = false
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    private var ref: EventHotKeyRef?
    private let id: UInt32

    init(keyCode: UInt32, modifiers: UInt32 = 0, action: @escaping () -> Void) {
        HotKey.installHandlerOnce()
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action
        let hkID = EventHotKeyID(signature: OSType(0x4449_4354), id: id) // 'DICT'
        RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.actions[id] = nil
    }

    private static func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            HotKey.actions[hk.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Какой клавишей включать диктовку.
enum TriggerKeyKind: String, CaseIterable, Identifiable {
    case rightCommand, rightOption, rightControl, rightShift, fn
    var id: String { rawValue }

    var title: String {
        switch self {
        case .rightCommand: "Правый ⌘"
        case .rightOption: "Правый ⌥"
        case .rightControl: "Правый ⌃"
        case .rightShift: "Правый ⇧"
        case .fn: "Fn (🌐)"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightCommand: UInt16(kVK_RightCommand)
        case .rightOption: UInt16(kVK_RightOption)
        case .rightControl: UInt16(kVK_RightControl)
        case .rightShift: UInt16(kVK_RightShift)
        case .fn: UInt16(kVK_Function)
        }
    }

    /// Бит «эта сторона клавиатуры» во флагах (приходит и от настоящей клавиатуры, и от программ).
    var deviceMask: UInt? {
        switch self {
        case .rightCommand: 0x10
        case .rightOption: 0x40
        case .rightControl: 0x2000
        case .rightShift: 0x04
        case .fn: nil
        }
    }

    /// Та же клавиша слева — если зажата, это сочетание, а не наша клавиша.
    var otherSideMask: UInt {
        switch self {
        case .rightCommand: 0x08
        case .rightOption: 0x20
        case .rightControl: 0x01
        case .rightShift: 0x02
        case .fn: 0
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand: .command
        case .rightOption: .option
        case .rightControl: .control
        case .rightShift: .shift
        case .fn: .function
        }
    }
}

/// Клавиша-модификатор для диктовки.
/// Короткое нажатие (без других клавиш) — начать/закончить.
/// Если включено удержание: держишь дольше 0,3 с — идёт запись, отпустил — готово.
/// Нажал ещё какую-то клавишу, пока держишь, — это было сочетание (⌘C и т.п.), запись отменяется.
/// Глобальное отслеживание требует «Универсальный доступ».
@MainActor
final class TriggerKey {
    var kind: TriggerKeyKind { didSet { reset() } }
    var holdEnabled: Bool
    var onTap: () -> Void = {}
    var onHoldStart: () -> Void = {}
    var onHoldEnd: () -> Void = {}
    var onHoldAborted: () -> Void = {}

    private var monitors: [Any] = []
    private var pressedAt: Date?
    private var interrupted = false
    private var holding = false
    private var isDown = false
    private var holdTimer: DispatchWorkItem?
    private var timer: Timer?
    private static let holdDelay = 0.3

    init(kind: TriggerKeyKind, holdEnabled: Bool) {
        self.kind = kind
        self.holdEnabled = holdEnabled
        // локально (наше окно активно) — работает всегда
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] e in
            self?.handle(e); return e
        } as Any)
        installGlobalWhenTrusted()
    }

    /// Глобальный монитор не начнёт работать, если доступ выдали позже, — поэтому ждём доступа.
    private func installGlobalWhenTrusted() {
        if Paster.isTrusted { installGlobal(); return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, Paster.isTrusted else { return }
                t.invalidate()
                self.installGlobal()
            }
        }
    }

    private func installGlobal() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
        }) { monitors.append(m) }
    }

    private func interrupt() {
        interrupted = true
        holdTimer?.cancel()
        if holding { holding = false; onHoldAborted() }
    }

    private func reset() {
        holdTimer?.cancel()
        pressedAt = nil
        isDown = false
        holding = false
    }

    /// Нажата ли сейчас наша клавиша — по биту стороны во флагах (номер клавиши приходит не всегда).
    private func keyIsDown(_ e: NSEvent) -> Bool {
        if let mask = kind.deviceMask { return e.modifierFlags.rawValue & mask != 0 }
        // Fn: своё событие приходит с кодом 63
        return e.keyCode == kind.keyCode ? e.modifierFlags.contains(.function) : isDown
    }

    /// Зажато что-то ещё (другой модификатор или та же клавиша слева) — значит, это сочетание.
    private func otherModifiers(_ e: NSEvent) -> Bool {
        let all: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
        if !e.modifierFlags.intersection(all.subtracting(kind.flag)).isEmpty { return true }
        return e.modifierFlags.rawValue & kind.otherSideMask != 0
    }

    private func handle(_ e: NSEvent) {
        if e.type == .keyDown {
            if pressedAt != nil { interrupt() }
            return
        }
        let down = keyIsDown(e)
        if down && !isDown {
            // нажали
            isDown = true
            pressedAt = .now
            interrupted = otherModifiers(e)
            guard holdEnabled, !interrupted else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.pressedAt != nil, !self.interrupted else { return }
                    self.holding = true
                    self.onHoldStart()
                }
            }
            holdTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: work)
        } else if !down && isDown {
            // отпустили
            isDown = false
            holdTimer?.cancel()
            guard let t = pressedAt else { return }
            pressedAt = nil
            if holding {
                holding = false
                onHoldEnd()
            } else if !interrupted && Date.now.timeIntervalSince(t) < (holdEnabled ? Self.holdDelay : 0.6) {
                onTap()
            }
        } else if down && otherModifiers(e) {
            interrupt() // держим нашу клавишу и зажали ещё модификатор — это сочетание
        }
    }
}

/// Буфер обмена и вставка в активное приложение.
enum Paster {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Копия всего, что сейчас в буфере (текст, картинки, файлы), — чтобы вернуть после вставки.
    static func snapshot() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem]) {
        NSPasteboard.general.clearContents()
        if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
    }

    static var changeCount: Int { NSPasteboard.general.changeCount }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Нажимает ⌘V (по коду клавиши — работает и в русской раскладке).
    static func paste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Чистит типичные «галлюцинации» Whisper на тишине.
enum TextCleaner {
    private static let junk = ["субтитр", "dimatorzok", "продолжение следует", "редактор субтитров",
                               // Whisper иногда повторяет нашу подсказку вместо текста
                               "диктовка на русском языке", "с заглавными буквами, запятыми",
                               "с английскими словами", "термины:"]

    static func clean(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: #"\[[^\]]*\]|\*[^*]*\*|\((?:музыка|смех|аплодисменты)[^)]*\)"#,
                                         with: "", options: [.regularExpression, .caseInsensitive])
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentences = t.replacingOccurrences(of: #"([.!?…])\s+"#, with: "$1\n", options: .regularExpression)
            .split(separator: "\n").map(String.init)
        let kept = sentences.filter { s in
            let low = s.lowercased()
            if s.count < 80 && junk.contains(where: { low.contains($0) }) { return false }
            // обрывок нашей подсказки «Термины: …» (Whisper на тишине выдаёт «Терминат» и т.п.)
            if s.count < 40 && low.hasPrefix("термин") { return false }
            return true
        }
        t = kept.joined(separator: " ")
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RU {
    /// 1 символ, 2 символа, 5 символов
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return one }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
        return many
    }

    static func number(_ n: Int) -> String {
        n.formatted(.number.locale(Locale(identifier: "ru_RU")))
    }

    static func chars(_ n: Int) -> String {
        "\(number(n)) \(plural(n, "символ", "символа", "символов"))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// «23:40» — всегда 24 часа, независимо от настроек системы.
    static func time(_ d: Date) -> String { timeFormatter.string(from: d) }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s < 60 { return "\(s) с" }
        if s < 3600 { return "\(s / 60) мин \(s % 60) с" }
        return "\(s / 3600) ч \((s % 3600) / 60) мин"
    }
}
