import Foundation
import Observation

/// Свой словарь: слова/имена/термины (подсказка для Whisper) и автозамены после распознавания.
@MainActor
@Observable
final class Vocabulary {
    private struct Stored: Codable {
        var terms: [String] = []
        var replacements: [Replacement] = []
    }

    var terms: [String] = [] { didSet { save() } }
    var replacements: [Replacement] = [] { didSet { save() } }

    @ObservationIgnored private let url = AppPaths.support.appendingPathComponent("vocabulary.json")
    @ObservationIgnored private var loading = false

    init() {
        loading = true
        if let data = try? Data(contentsOf: url) {
            if let s = try? JSONDecoder().decode(Stored.self, from: data) {
                terms = s.terms
                replacements = s.replacements
            } else {
                // Файл не читается — откладываем в сторону, иначе первая правка словаря затрёт его пустым.
                let stamp = Int(Date.now.timeIntervalSince1970)
                let backup = url.deletingLastPathComponent().appendingPathComponent("vocabulary.broken-\(stamp).json")
                try? FileManager.default.copyItem(at: url, to: backup)
            }
        }
        loading = false
    }

    func addTerm(_ raw: String) {
        // можно вставить сразу несколько через запятую
        for part in raw.split(separator: ",") {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !terms.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { continue }
            terms.append(t)
        }
    }

    func addReplacement(from: String, to: String) {
        let f = from.trimmingCharacters(in: .whitespaces), t = to.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty, f.caseInsensitiveCompare(t) != .orderedSame else { return }
        if let i = replacements.firstIndex(where: { $0.from.caseInsensitiveCompare(f) == .orderedSame }) {
            replacements[i].to = t
        } else {
            replacements.append(Replacement(from: f, to: t))
        }
        // правильное слово полезно и как подсказка модели
        if t.count >= 4 { addTerm(t) }
    }

    func hasReplacement(from: String) -> Bool {
        replacements.contains { $0.from.caseInsensitiveCompare(from) == .orderedSame }
    }

    /// Хвост подсказки для Whisper. Подсказка ограничена ~224 токенами — берём не больше ~500 символов.
    var promptTerms: String {
        var out: [String] = []
        var length = 0
        for t in terms {
            if length + t.count > 500 { break }
            out.append(t)
            length += t.count + 2
        }
        return out.joined(separator: ", ")
    }

    private func save() {
        guard !loading else { return }
        let s = Stored(terms: terms, replacements: replacements)
        let url = url
        // Своя последовательная очередь: раньше записи шли параллельно, и старая версия могла
        // записаться последней — свежая правка (например, слово из автозамены) терялась.
        saveQueue.async {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            if let data = try? enc.encode(s) { try? data.write(to: url, options: .atomic) }
        }
    }

    @ObservationIgnored private let saveQueue = DispatchQueue(label: "dictation.vocabulary.save", qos: .utility)

    /// Дождаться записи на диск (при выходе из приложения).
    func flush() { saveQueue.sync {} }
}
