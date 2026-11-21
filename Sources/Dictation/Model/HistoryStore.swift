import Foundation
import Observation

struct DictationEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var duration: TimeInterval
    /// Текст до ручной правки (nil — не правили). Старые записи без поля читаются как nil.
    var original: String?

    var isEdited: Bool { original != nil }
    var characters: Int { text.count }
    var words: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
}

/// Всё, что хранится на диске. Общие счётчики живут отдельно от истории —
/// если почистить историю, «всего надиктовано» не обнулится.
struct Archive: Codable {
    var entries: [DictationEntry] = []
    var totalCharacters = 0
    var totalWords = 0
    var totalDuration: TimeInterval = 0
    var totalCount = 0
    var daily: [String: Int] = [:] // "2026-11-15": символы
}

struct DayGroup: Identifiable {
    let id: String
    let title: String
    let entries: [DictationEntry]
}

struct DayStat: Identifiable {
    var id: Date { day }
    let day: Date
    let characters: Int
}

@MainActor
@Observable
final class HistoryStore {
    private(set) var archive = Archive()
    @ObservationIgnored private let url = AppPaths.support.appendingPathComponent("history.json")

    var entries: [DictationEntry] { archive.entries }
    var todayCharacters: Int { archive.daily[Self.key(.now)] ?? 0 }
    var charsPerMinute: Int {
        archive.totalDuration > 5 ? Int(Double(archive.totalCharacters) / (archive.totalDuration / 60)) : 0
    }

    init() { load() }

    @discardableResult
    func add(text: String, duration: TimeInterval) -> DictationEntry {
        let e = DictationEntry(date: .now, text: text, duration: duration)
        archive.entries.insert(e, at: 0)
        archive.totalCharacters += e.characters
        archive.totalWords += e.words
        archive.totalDuration += duration
        archive.totalCount += 1
        archive.daily[Self.key(e.date), default: 0] += e.characters
        save()
        return e
    }

    func entry(_ id: DictationEntry.ID?) -> DictationEntry? {
        guard let id else { return nil }
        return archive.entries.first { $0.id == id }
    }

    /// Последние записи — для меню «Недавние».
    func recent(_ n: Int) -> [DictationEntry] { Array(archive.entries.prefix(n)) }

    /// Ручная правка текста. Счётчик «надиктовано» не меняется — он про то, что сказано голосом.
    func update(_ id: DictationEntry.ID, text: String) {
        guard let i = archive.entries.firstIndex(where: { $0.id == id }) else { return }
        let new = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != archive.entries[i].text else { return }
        if archive.entries[i].original == nil { archive.entries[i].original = archive.entries[i].text }
        archive.entries[i].text = new
        save()
    }

    /// Удаляет и возвращает удалённое — чтобы можно было вернуть (⌘Z / «Вернуть»).
    @discardableResult
    func delete(_ ids: Set<DictationEntry.ID>) -> [DictationEntry] {
        let removed = archive.entries.filter { ids.contains($0.id) }
        archive.entries.removeAll { ids.contains($0.id) }
        save()
        return removed
    }

    func restore(_ removed: [DictationEntry]) {
        let existing = Set(archive.entries.map(\.id))
        archive.entries.append(contentsOf: removed.filter { !existing.contains($0.id) })
        archive.entries.sort { $0.date > $1.date }
        save()
    }

    /// Markdown для экспорта: по дням, со временем.
    func markdown(_ list: [DictationEntry]) -> String {
        var out = "# Диктовки\n"
        var currentDay = ""
        for e in list.sorted(by: { $0.date < $1.date }) {
            let day = Self.key(e.date)
            if day != currentDay {
                currentDay = day
                out += "\n## \(Self.title(for: e.date)) (\(day))\n\n"
            }
            out += "- **\(RU.time(e.date))** — \(e.text.replacingOccurrences(of: "\n", with: "  \n  "))\n"
        }
        return out
    }

    func clear() {
        archive.entries.removeAll()
        save()
    }

    func lastDays(_ n: Int) -> [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<n).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayStat(day: d, characters: archive.daily[Self.key(d)] ?? 0)
        }
    }

    func groups(matching query: String) -> [DayGroup] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? entries : entries.filter { $0.text.localizedCaseInsensitiveContains(q) }
        var order: [String] = []
        var map: [String: [DictationEntry]] = [:]
        for e in list {
            let k = Self.key(e.date)
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(e)
        }
        return order.map { k in DayGroup(id: k, title: Self.title(for: map[k]![0].date), entries: map[k]!) }
    }

    // MARK: - Диск

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            archive = try dec.decode(Archive.self, from: data)
        } catch {
            // Файл не читается — откладываем его в сторону, иначе первая же новая диктовка
            // перезапишет его пустой историей и все записи со счётчиками пропадут.
            let stamp = Int(Date.now.timeIntervalSince1970)
            let backup = url.deletingLastPathComponent().appendingPathComponent("history.broken-\(stamp).json")
            try? FileManager.default.copyItem(at: url, to: backup)
        }
    }

    /// Пишем в фоне по очереди — интерфейс не ждёт диск, порядок записей сохраняется.
    @ObservationIgnored private let saveQueue = DispatchQueue(label: "dictation.history.save", qos: .utility)

    private func save() {
        let snapshot = archive
        let url = url
        saveQueue.async {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            if let data = try? enc.encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    /// Дождаться записи на диск (при выходе из приложения).
    func flush() { saveQueue.sync {} }

    // MARK: - Даты

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ d: Date) -> String { keyFormatter.string(from: d) }

    static func title(for d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Сегодня" }
        if cal.isDateInYesterday(d) { return "Вчера" }
        let f = cal.isDate(d, equalTo: .now, toGranularity: .year) ? thisYear : otherYear
        return f.string(from: d).capitalizedFirst
    }

    private static let thisYear = ruFormatter("d MMMM, EEEE")
    private static let otherYear = ruFormatter("d MMMM yyyy")

    private static func ruFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = format
        return f
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
