import Foundation
import CWhisper

/// Обёртка над whisper.cpp. Вся работа — на своей очереди, чтобы не тормозить интерфейс.
final class WhisperEngine: @unchecked Sendable {
    private var ctx: UnsafeMutableRawPointer?
    private let queue = DispatchQueue(label: "dictation.whisper", qos: .userInitiated)

    func load(path: String) async -> Bool {
        await withCheckedContinuation { cont in
            queue.async {
                if self.ctx == nil { self.ctx = dw_init(path) }
                cont.resume(returning: self.ctx != nil)
            }
        }
    }

    func transcribe(_ samples: [Float], language: String, prompt: String?) async -> String? {
        await withCheckedContinuation { cont in
            queue.async {
                guard let ctx = self.ctx else { return cont.resume(returning: nil) }
                // whisper не любит совсем короткие куски — добиваем тишиной до 1.1 с
                var pcm = samples
                if pcm.count < 17_600 { pcm += [Float](repeating: 0, count: 17_600 - pcm.count) }
                let threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
                let result: String? = pcm.withUnsafeBufferPointer { buf in
                    guard let raw = dw_transcribe(ctx, buf.baseAddress, Int32(buf.count),
                                                  language, prompt ?? "", threads) else { return nil }
                    defer { dw_free_string(raw) }
                    return String(cString: raw)
                }
                cont.resume(returning: result)
            }
        }
    }

    /// Выгружает модель (обязательно перед выходом — иначе Metal падает при завершении).
    func unload() {
        queue.sync {
            if let ctx { dw_free(ctx) }
            ctx = nil
        }
    }

    deinit { if let ctx { dw_free(ctx) } }
}

enum ModelInfo {
    static let displayName = "Whisper Large v3 Turbo"
    /// Сжатая (q5_0) версия: то же качество на русском, памяти в 2,4 раза меньше (0,8 ГБ против 1,9 ГБ).
    static let fileName = "ggml-large-v3-turbo-q5_0.bin"
    /// Полная версия — запасной вариант, если сжатой нет.
    static let fallbackName = "ggml-large-v3-turbo.bin"
    static let downloadURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!

    static var directory: URL {
        AppPaths.support.appendingPathComponent("Models", isDirectory: true)
    }
    /// Куда качать.
    static var downloadPath: URL { directory.appendingPathComponent(fileName) }
    /// Что загружать: сжатую, если есть, иначе полную.
    static var path: URL {
        let main = directory.appendingPathComponent(fileName)
        let fallback = directory.appendingPathComponent(fallbackName)
        if !FileManager.default.fileExists(atPath: main.path),
           FileManager.default.fileExists(atPath: fallback.path) { return fallback }
        return main
    }
    static var exists: Bool { FileManager.default.fileExists(atPath: path.path) }

    static var sizeDescription: String {
        let size = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int64) ?? 0
        return size > 0 ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file) : "—"
    }
}

enum AppPaths {
    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dictation", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Докачка модели, если её нет (например, после переустановки).
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    private var session: URLSession?
    var onProgress: ((Double) -> Void)?
    var onFinish: ((Error?) -> Void)?

    func start() {
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session = s
        s.downloadTask(with: ModelInfo.downloadURL).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    private var saveError: Error?

    struct BadDownload: LocalizedError {
        var errorDescription: String? { "сервер вернул не модель — попробуй ещё раз позже" }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Не кладём на место модели страницу с ошибкой или обрывок файла
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? 0
        guard status == 200, size > 100_000_000 else { saveError = BadDownload(); return }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: ModelInfo.directory, withIntermediateDirectories: true)
            let tmp = ModelInfo.downloadPath.appendingPathExtension("part")
            try? fm.removeItem(at: tmp)
            try fm.moveItem(at: location, to: tmp)
            try? fm.removeItem(at: ModelInfo.downloadPath)
            try fm.moveItem(at: tmp, to: ModelInfo.downloadPath)
        } catch {
            saveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onFinish?(error ?? saveError)
        session.finishTasksAndInvalidate()
    }
}
