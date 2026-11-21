import AVFoundation
import Accelerate

/// Пишет выбранный микрофон через AVCaptureSession.
/// Система сама отдаёт звук в 16 кГц моно float — ровно то, что ждёт Whisper,
/// для любого устройства (встроенный микрофон, AirPods, iPhone, USB).
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let audioQueue = DispatchQueue(label: "dictation.audio", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "dictation.session", qos: .userInitiated)
    private var input: AVCaptureDeviceInput?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var running = false
    private var observers: [NSObjectProtocol] = []

    /// UID выбранного микрофона; пусто — системный. Задаётся с главного потока.
    var preferredUID = ""
    /// Громкость 0…1, вызывается с аудио-потока.
    var onLevel: ((Float) -> Void)?
    /// Пришёл первый звук — микрофон реально заработал (iPhone включается до ~4 с). С аудио-потока.
    var onFirstAudio: (() -> Void)?
    private var gotFirstAudio = false
    /// Запись не может продолжаться (микрофонов не осталось или сбой системы).
    var onFailure: ((Error) -> Void)?

    enum RecorderError: LocalizedError {
        case noInput, cannotUse(String)
        var errorDescription: String? {
            switch self {
            case .noInput: "Не найден микрофон"
            case .cannotUse(let name): "Не удалось включить микрофон «\(name)»"
            }
        }
    }

    override init() {
        super.init()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: audioQueue)
        if session.canAddOutput(output) { session.addOutput(output) }

        let nc = NotificationCenter.default
        // Выдернули микрофон посреди записи — продолжаем с другого, записанное не теряется
        observers.append(nc.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil,
                                        queue: .main) { [weak self] note in
            guard let self, self.running,
                  let gone = note.object as? AVCaptureDevice,
                  gone.uniqueID == self.input?.device.uniqueID else { return }
            self.switchInput(excluding: gone.uniqueID)
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session,
                                        queue: .main) { [weak self] note in
            guard let self, self.running else { return }
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error ?? RecorderError.noInput
            self.running = false
            self.onFailure?(error)
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Подключение микрофона (открытие устройства, настройка сессии) — целиком в фоне:
    /// раньше оно шло в главном потоке и окно на мгновение подвисало в момент нажатия.
    func start() async throws {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            samples.reserveCapacity(16_000 * 60)
        }
        guard let device = Self.pickDevice(preferredUID: preferredUID) else { throw RecorderError.noInput }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.setInput(device)
                    self.audioQueue.async { self.gotFirstAudio = false }
                    self.running = true
                    self.session.startRunning()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func stop() -> [Float] {
        sessionQueue.sync { self.session.stopRunning() }
        audioQueue.sync {} // дождаться последних кусочков звука — конец фразы не обрезается
        running = false
        return lock.withLock {
            let result = samples
            samples = [] // освобождаем память сразу
            return result
        }
    }

    // MARK: - Устройства

    /// Выбранный микрофон, если подключён, иначе системный.
    private static func pickDevice(preferredUID: String, excluding: String? = nil) -> AVCaptureDevice? {
        if !preferredUID.isEmpty, preferredUID != excluding,
           let d = AVCaptureDevice(uniqueID: preferredUID), d.isConnected { return d }
        if let d = AVCaptureDevice.default(for: .audio), d.isConnected, d.uniqueID != excluding { return d }
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio,
                                                position: .unspecified)
            .devices.first { $0.isConnected && $0.uniqueID != excluding }
    }

    private func setInput(_ device: AVCaptureDevice) throws {
        if input?.device.uniqueID == device.uniqueID { return }
        let newInput: AVCaptureDeviceInput
        do { newInput = try AVCaptureDeviceInput(device: device) } catch {
            throw RecorderError.cannotUse(device.localizedName)
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else {
            if let input, session.canAddInput(input) { session.addInput(input) }
            throw RecorderError.cannotUse(device.localizedName)
        }
        session.addInput(newInput)
        input = newInput
    }

    private func switchInput(excluding uid: String) {
        let device = Self.pickDevice(preferredUID: preferredUID, excluding: uid)
        sessionQueue.async { // сессию настраиваем только из её очереди
            guard let device, (try? self.setInput(device)) != nil else {
                self.running = false
                DispatchQueue.main.async { self.onFailure?(RecorderError.noInput) }
                return
            }
        }
    }

    // MARK: - Звук

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard running else { return }
        var blockBuffer: CMBlockBuffer?
        var list = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let data = list.mBuffers.mData else { return }
        let count = Int(list.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return }
        let ptr = data.assumingMemoryBound(to: Float.self)
        if !gotFirstAudio { gotFirstAudio = true; onFirstAudio?() }

        var rms: Float = 0
        vDSP_rmsqv(ptr, 1, &rms, vDSP_Length(count))
        let db = 20 * log10(max(rms, 1e-7))
        onLevel?(max(0, min(1, (db + 55) / 45)))

        let chunk = UnsafeBufferPointer(start: ptr, count: count)
        lock.withLock { samples.append(contentsOf: chunk) }
    }
}
