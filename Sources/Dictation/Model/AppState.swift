import SwiftUI
import AVFoundation
import Carbon
import ServiceManagement

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case loadingModel, needsModel, downloading, idle, recording, transcribing
        case failed(String)
    }

    /// Отменённая через Esc запись — её можно вернуть.
    struct CancelledRecording {
        let samples: [Float]
        let duration: TimeInterval
        let paste: Bool
    }

    static let shared = AppState()

    var phase: Phase = .loadingModel { didSet { hud?.update() } }
    var levels: [Float] = Array(repeating: 0, count: 56)
    var recordingStartedAt: Date?
    var downloadProgress: Double = 0
    var modelReady = false
    /// Микрофон уже отдаёт звук (после «дзынь»).
    var micLive = false
    let history = HistoryStore()
    let historyUI = HistoryUI()
    let vocabulary = Vocabulary()

    // MARK: - Последняя диктовка

    var lastEntryID: DictationEntry.ID?
    /// Какая запись истории сейчас правится (одна на всё приложение).
    var editingEntryID: DictationEntry.ID?
    /// Текст последней диктовки — берём из истории, чтобы правка была видна везде.
    var lastText: String { history.entry(lastEntryID)?.text ?? "" }
    /// Когда текст последний раз попал в буфер / был вставлен.
    var lastDeliveredAt: Date?
    var lastDeliveryPasted = false

    // MARK: - Отмена через Esc

    var cancelled: CancelledRecording?
    var undoToastVisible = false { didSet { hud?.update() } }
    /// Когда показали «Вернуть» (для убывающего кольца)
    var undoShownAt = Date.now
    static let undoSeconds = 2.0
    /// Мышь над плашкой записи — раскрыть ✕ и ✓ (следит HUDController).
    var hudHover = false
    /// Плашка сейчас на экране (ставит HUDController).
    var hudShown = false
    /// После Esc плашка трясётся (анимация отмены) — пока true, она не прячется.
    var cancelAnimating = false { didSet { hud?.update() } }
    /// Запуск тряски в плашке.
    var cancelTrigger = 0
    @ObservationIgnored private var cancelToken = 0

    // MARK: - Анимации событий плашки (2026-11-21, HUDEvents.swift)
    enum HUDEvent { case success, fail }
    /// Удачно / неудачно — плашка держится на экране, пока идёт анимация
    var hudEvent: HUDEvent? { didSet { hud?.update() } }
    var hudEventAt = Date.distantPast
    /// Событие случилось во время распознавания (иначе — сразу после записи)
    var hudEventFromThinking = false
    /// Когда началось распознавание и откуда («Вернуть» или «Готово»)
    var thinkAt = Date.distantPast
    var thinkFromRestore = false
    /// Длина красного кольца в момент «Готово» — с неё «Перетекание» сжимается в дугу
    var stopRing = 0.3
    @ObservationIgnored private var hudEventToken = 0

    private func fireHUD(_ e: HUDEvent, fromThinking: Bool) {
        guard hudShown else { return }
        hudEventToken += 1
        let token = hudEventToken
        hudEventFromThinking = fromThinking
        hudEventAt = .now
        hudEvent = e
        let dur = e == .success ? RecordingHUD.successDuration : RecordingHUD.failDuration
        Task {
            try? await Task.sleep(for: .seconds(dur))
            if token == hudEventToken { hudEvent = nil }
        }
    }

    // MARK: - Настройки

    var language: String = UserDefaults.standard.string(forKey: "language") ?? "ru" {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    var autoPaste: Bool = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoPaste, forKey: "autoPaste")
            if autoPaste && !Paster.isTrusted { Paster.requestTrust() }
        }
    }
    /// После автовставки вернуть в буфер то, что там было до диктовки.
    var restoreClipboard: Bool = UserDefaults.standard.object(forKey: "restoreClipboard") as? Bool ?? true {
        didSet { UserDefaults.standard.set(restoreClipboard, forKey: "restoreClipboard") }
    }
    var voiceCommands: Bool = UserDefaults.standard.object(forKey: "voiceCommands") as? Bool ?? true {
        didSet { UserDefaults.standard.set(voiceCommands, forKey: "voiceCommands") }
    }
    var playSounds: Bool = UserDefaults.standard.object(forKey: "playSounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(playSounds, forKey: "playSounds") }
    }
    var triggerKind: TriggerKeyKind = TriggerKeyKind(rawValue: UserDefaults.standard.string(forKey: "triggerKey") ?? "")
        ?? .rightCommand {
        didSet {
            UserDefaults.standard.set(triggerKind.rawValue, forKey: "triggerKey")
            trigger?.kind = triggerKind
        }
    }
    /// Зажал — говоришь — отпустил. Короткое нажатие всё равно работает как раньше.
    var holdToTalk: Bool = UserDefaults.standard.bool(forKey: "holdToTalk") {
        didSet {
            UserDefaults.standard.set(holdToTalk, forKey: "holdToTalk")
            trigger?.holdEnabled = holdToTalk
        }
    }
    /// Без значка в Dock — только иконка в строке меню.
    var menuBarOnly: Bool = UserDefaults.standard.bool(forKey: "menuBarOnly") {
        didSet {
            UserDefaults.standard.set(menuBarOnly, forKey: "menuBarOnly")
            applyActivationPolicy()
            // после смены политики окно настроек может уйти назад — возвращаем
            DispatchQueue.main.async { NSApp.activate() }
        }
    }
    /// Приветствие-настройка для нового пользователя.
    var showWelcome = false
    var onboarded: Bool = UserDefaults.standard.bool(forKey: "onboarded") {
        didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") }
    }

    // MARK: - Микрофон

    let microphones = MicrophoneList()

    /// UID выбранного микрофона; пусто — системный (как в настройках macOS).
    var microphoneUID: String = UserDefaults.standard.string(forKey: "micUID") ?? "" {
        didSet {
            UserDefaults.standard.set(microphoneUID, forKey: "micUID")
            if let d = microphones.devices.first(where: { $0.uid == microphoneUID }) {
                UserDefaults.standard.set(d.name, forKey: "micName")
            }
            recorder.preferredUID = microphoneUID // сработает со следующей записи
        }
    }

    /// Выбранный микрофон сейчас не подключён.
    var microphoneMissing: Bool {
        !microphoneUID.isEmpty && !microphones.devices.contains { $0.uid == microphoneUID }
    }

    /// Название для интерфейса.
    var microphoneTitle: String {
        if microphoneUID.isEmpty { return "Системный — \(microphones.defaultName)" }
        if let d = microphones.devices.first(where: { $0.uid == microphoneUID }) { return d.name }
        let saved = UserDefaults.standard.string(forKey: "micName") ?? "Микрофон"
        return "\(saved) (не подключён)"
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
    }

    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                // не получилось — переключатель показывает реальное состояние
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    var isRecording: Bool { phase == .recording }
    var canRecord: Bool { modelReady && (phase == .idle || phase == .recording || isFailed) }
    var isFailed: Bool { if case .failed = phase { return true } else { return false } }

    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let engine = WhisperEngine()
    @ObservationIgnored private var trigger: TriggerKey?
    @ObservationIgnored private var sessionKeys: [HotKey] = []
    @ObservationIgnored private var pasteLastKey: HotKey?
    @ObservationIgnored private var hud: HUDController?
    @ObservationIgnored private var downloader: ModelDownloader?
    @ObservationIgnored private var pasteWhenDone = false
    @ObservationIgnored private var isStarting = false
    /// Клавишу отпустили, пока микрофон ещё включался, — запись сразу закрыть, а не оставить висеть.
    @ObservationIgnored private var abortStart = false
    @ObservationIgnored private var recordingSession = 0
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    private static let maxRecording: Double = 10 * 60
    /// Отменённые записи короче этого не предлагаем вернуть.
    private static let undoMinDuration: Double = 3

    // MARK: - Запуск

    func bootstrap() {
        guard trigger == nil else { return }
        applyActivationPolicy()
        // Уже пользуется приложением — приветствие не показываем
        if !onboarded && !history.entries.isEmpty { onboarded = true }
        if !onboarded { showWelcome = true }

        let t = TriggerKey(kind: triggerKind, holdEnabled: holdToTalk)
        t.onTap = { [weak self] in self?.toggleFromHotKey() }
        t.onHoldStart = { [weak self] in
            guard let self, !self.isRecording else { return }
            self.toggleFromHotKey()
        }
        t.onHoldEnd = { [weak self] in
            guard let self else { return }
            if self.isRecording { self.stop() } else if self.isStarting { self.abortStart = true }
        }
        t.onHoldAborted = { [weak self] in
            guard let self else { return }
            if self.isStarting { self.abortStart = true }
            self.cancel(silent: true)
        }
        trigger = t

        // ⌃⌥V — вставить последнюю диктовку в любом приложении
        pasteLastKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            Task { @MainActor in self?.pasteLast() }
        }

        if onboarded && !Paster.isTrusted { Paster.requestTrust() }
        hud = HUDController(state: self)
        preloadSounds()
        lastEntryID = history.entries.first?.id
        recorder.preferredUID = microphoneUID
        recorder.onFirstAudio = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isRecording else { return }
                self.micLive = true
                self.sound("Tink") // «дзынь» = можно говорить
            }
        }
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.push(level) }
        }
        recorder.onFailure = { [weak self] _ in
            MainActor.assumeIsolated {
                // микрофон пропал — распознаём то, что успели записать
                self?.stop()
            }
        }
        Task { await loadModel() }
    }

    func loadModel() async {
        guard ModelInfo.exists else { phase = .needsModel; return }
        phase = .loadingModel
        modelReady = await engine.load(path: ModelInfo.path.path)
        // файл модели битый — предлагаем скачать заново, а не застреваем в ошибке
        phase = modelReady ? .idle : .needsModel
    }

    func shutdown() {
        if isRecording { _ = recorder.stop(); releaseSessionKeys() }
        engine.unload()
        history.flush()
        vocabulary.flush()
    }

    func downloadModel() {
        phase = .downloading
        downloadProgress = 0
        let d = ModelDownloader()
        d.onProgress = { [weak self] p in self?.downloadProgress = p }
        d.onFinish = { [weak self] error in
            guard let self else { return }
            self.downloader = nil
            if let error { self.phase = .failed("Ошибка загрузки: \(error.localizedDescription)"); return }
            Task { await self.loadModel() }
        }
        downloader = d
        d.start()
    }

    // MARK: - Запись

    func toggle() { toggle(paste: false) }

    private func toggleFromHotKey() {
        if isRecording { stop(); return }
        toggle(paste: autoPaste && !NSApp.isActive)
    }

    /// Esc — выбросить запись. Длинную (от 3 с) можно вернуть в течение нескольких секунд.
    func cancel(silent: Bool = false) {
        guard isRecording else { return }
        let samples = recorder.stop()
        let duration = Date.now.timeIntervalSince(recordingStartedAt ?? .now)
        recordingStartedAt = nil
        releaseSessionKeys()
        let canUndo = !silent && duration >= Self.undoMinDuration
        if canUndo { cancelled = CancelledRecording(samples: samples, duration: duration, paste: pasteWhenDone) }
        // 2026-11-21 (Камиль): плашка на экране — сначала трясётся «нет» и уходит, потом «Вернуть»
        let animate = !silent && hudShown
        if animate {
            cancelAnimating = true // до смены фазы — чтобы плашка не спряталась
            cancelTrigger += 1
        }
        phase = .idle
        cancelToken += 1
        let token = cancelToken
        if animate {
            Task {
                // чуть раньше конца: плашка уже почти прозрачна, кадр «в покое» не мелькнёт
                try? await Task.sleep(for: .seconds(max(0.05, RecordingHUD.cancelDuration - 0.02)))
                guard token == cancelToken else { return } // за это время началась новая запись
                if canUndo, cancelled != nil, !isRecording { showUndoToast() } // до снятия тряски — без мигания
                cancelAnimating = false
            }
        } else if canUndo {
            showUndoToast()
        }
    }

    /// «Вернуть» отменённую запись: распознать и вставить как обычно.
    func restoreCancelled() {
        guard let c = cancelled, phase == .idle || isFailed else { return }
        cancelled = nil
        // сначала распознавание, потом прячем «Вернуть» — иначе плашка на миг исчезает и появляется заново
        transcribeAndDeliver(samples: c.samples, duration: c.duration, paste: c.paste, restored: true)
        hideUndoToast()
    }

    private func showUndoToast() {
        undoShownAt = .now
        undoToastVisible = true
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(Self.undoSeconds)) // было 6 с; Камиль: 2 секунды (2026-11-20)
            if !Task.isCancelled { undoToastVisible = false }
        }
    }

    func hideUndoToast() {
        toastTask?.cancel()
        undoToastVisible = false
    }

    /// Пока идёт запись, Esc и Return принадлежат нам.
    private func grabSessionKeys() {
        sessionKeys = [
            HotKey(keyCode: UInt32(kVK_Escape)) { [weak self] in
                Task { @MainActor in self?.cancel() }
            },
            HotKey(keyCode: UInt32(kVK_Return)) { [weak self] in
                Task { @MainActor in if self?.isRecording == true { self?.stop() } }
            },
            HotKey(keyCode: UInt32(kVK_ANSI_KeypadEnter)) { [weak self] in
                Task { @MainActor in if self?.isRecording == true { self?.stop() } }
            },
        ]
    }

    private func releaseSessionKeys() { sessionKeys.removeAll() }

    private func toggle(paste: Bool) {
        if isRecording { stop(); return }
        guard canRecord, !isStarting else { NSSound.beep(); return }
        start(paste: paste)
    }

    private func start(paste: Bool) {
        isStarting = true // защита от двойного нажатия, пока ждём доступ к микрофону
        abortStart = false
        Task {
            defer { isStarting = false }
            guard await Self.microphoneAccess() else {
                phase = .failed("Нет доступа к микрофону. Разреши в Системных настройках → Конфиденциальность → Микрофон.")
                return
            }
            do { try await recorder.start() } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            // новая запись — отменённую уже не вернуть
            cancelled = nil
            hideUndoToast()
            pasteWhenDone = paste
            levels = Array(repeating: 0, count: levels.count)
            recordingStartedAt = .now
            grabSessionKeys()
            micLive = false
            cancelToken += 1        // тряска прошлой отмены больше не нужна
            hudEventToken += 1      // и ✓ / «пожал плечами» прошлой записи
            hudEvent = nil
            cancelAnimating = false
            phase = .recording
            scheduleAutoStop()
            if abortStart { // отпустили клавишу удержания до того, как микрофон ожил
                abortStart = false
                cancel(silent: true)
            }
        }
    }

    /// Если забыл выключить — через 10 минут запись сама заканчивается и сохраняется.
    private func scheduleAutoStop() {
        recordingSession += 1
        let session = recordingSession
        Task {
            try? await Task.sleep(for: .seconds(Self.maxRecording))
            if isRecording && recordingSession == session { stop() }
        }
    }

    private func stop() {
        guard isRecording else { return }
        let samples = recorder.stop()
        releaseSessionKeys()
        let duration = Date.now.timeIntervalSince(recordingStartedAt ?? .now)
        recordingStartedAt = nil
        sound("Pop")
        let level = Double(levels.suffix(3).max() ?? 0)
        stopRing = micLive ? 0.1 + 0.9 * level : 0
        transcribeAndDeliver(samples: samples, duration: duration, paste: pasteWhenDone)
    }

    private func transcribeAndDeliver(samples: [Float], duration: TimeInterval, paste: Bool, restored: Bool = false) {
        // Слишком коротко или тишина — нечего распознавать
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard samples.count > 16_000 / 3, peak > 0.01 else {
            fireHUD(.fail, fromThinking: false) // «пожал плечами» — до смены фазы, чтобы плашка не пропала
            phase = .idle
            return
        }

        thinkAt = .now
        thinkFromRestore = restored
        phase = .transcribing
        Task {
            let raw = await engine.transcribe(samples, language: whisperLanguage, prompt: whisperPrompt)
            guard let raw else {
                // сбой распознавания — не теряем запись молча: её можно вернуть и попробовать ещё раз
                cancelled = CancelledRecording(samples: samples, duration: duration, paste: paste)
                showUndoToast() // до смены фазы — иначе плашка на миг пропадает и заново «прилетает»
                phase = .failed("Не удалось распознать запись — нажми «Вернуть», чтобы попробовать ещё раз")
                return
            }
            let text = postprocess(raw)
            if !text.isEmpty {
                let entry = history.add(text: text, duration: duration)
                lastEntryID = entry.id
                fireHUD(.success, fromThinking: true) // «Галочка» сразу, вставка идёт параллельно
                await deliver(text, paste: paste)
            } else {
                fireHUD(.fail, fromThinking: true)    // распознал пустоту
            }
            phase = .idle
        }
    }

    // MARK: - Текст

    /// Язык для Whisper: «русский + английские слова» распознаём как русский с подсказкой.
    private var whisperLanguage: String { language == "ru-en" ? "ru" : language }

    /// Подсказка для Whisper: помогает с пунктуацией и словами из словаря.
    private var whisperPrompt: String? {
        let terms = vocabulary.promptTerms
        switch language {
        case "ru":
            let base = "Привет! Это диктовка на русском языке, с заглавными буквами, запятыми и точками."
            return terms.isEmpty ? base : base + " Термины: \(terms)."
        case "ru-en":
            let base = "Привет! Это диктовка на русском языке с английскими словами: Excel, Telegram, iPhone, с запятыми и точками."
            return terms.isEmpty ? base : base + " Термины: \(terms)."
        default:
            return terms.isEmpty ? nil : "Glossary: \(terms)."
        }
    }

    /// Чистка → голосовые команды → автозамены.
    func postprocess(_ raw: String) -> String {
        var t = TextCleaner.clean(raw)
        if voiceCommands { t = VoiceCommands.apply(t) }
        t = Replacer.apply(t, rules: vocabulary.replacements)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Вставка

    /// Кладёт текст в буфер и (если просили) вставляет в активное приложение.
    /// С «вернуть буфер» после вставки возвращает то, что там было.
    func deliver(_ text: String, paste: Bool) async {
        if paste && Paster.isTrusted {
            let saved = restoreClipboard ? Paster.snapshot() : nil
            Paster.copy(text)
            let ourChange = Paster.changeCount
            try? await Task.sleep(for: .milliseconds(60))
            Paster.paste()
            lastDeliveredAt = .now
            lastDeliveryPasted = true
            if let saved {
                try? await Task.sleep(for: .milliseconds(450))
                // пользователь успел что-то скопировать сам — не трогаем
                if Paster.changeCount == ourChange { Paster.restore(saved) }
            }
        } else {
            Paster.copy(text)
            lastDeliveredAt = .now
            lastDeliveryPasted = false
            if paste { Paster.requestTrust() }
        }
    }

    /// ⌃⌥V или меню: вставить последнюю диктовку туда, где курсор.
    func pasteLast() {
        guard !lastText.isEmpty else { NSSound.beep(); return }
        paste(lastText)
    }

    /// Вставить текст из истории в активное приложение (из меню в строке меню).
    func paste(_ text: String) {
        Task {
            // меню успевает закрыться и фокус вернуться в прежнее приложение
            try? await Task.sleep(for: .milliseconds(200))
            await deliver(text, paste: !NSApp.isActive)
        }
    }

    // MARK: - Разное

    private func push(_ level: Float) {
        guard isRecording else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func sound(_ name: String) {
        guard playSounds else { return }
        // Звук загружается один раз и играет вне главного потока —
        // раньше NSSound(named:) читал файл и запускал аудио прямо в момент старта записи (~37 мс подвисания).
        Self.soundQueue.async {
            let s = Self.cachedSound(name)
            s?.stop()
            s?.play()
        }
    }

    nonisolated private static let soundQueue = DispatchQueue(label: "dictation.sound", qos: .userInitiated)
    nonisolated(unsafe) private static var sounds: [String: NSSound] = [:]

    /// Вызывается только из soundQueue.
    nonisolated private static func cachedSound(_ name: String) -> NSSound? {
        if let s = sounds[name] { return s }
        let s = NSSound(named: name)
        sounds[name] = s
        return s
    }

    /// Прогрев звуков при запуске, чтобы первая диктовка не ждала загрузки.
    func preloadSounds() {
        for name in ["Tink", "Pop"] { Self.soundQueue.async { _ = Self.cachedSound(name) } }
    }

    static func microphoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    var statusText: String {
        switch phase {
        case .loadingModel: "Загружаю модель…"
        case .needsModel: "Нужна модель распознавания"
        case .downloading: "Скачиваю модель… \(Int(downloadProgress * 100))%"
        case .idle: "Нажми, чтобы начать"
        case .recording: micLive ? "Слушаю…" : "Включаю микрофон…"
        case .transcribing: "Распознаю…"
        case .failed(let message): message
        }
    }
}
