import Foundation

/// Голосовые команды: «новая строка», «двоеточие», «открыть скобку»…
/// Whisper сам ставит запятые и точки вокруг команды — их убираем.
enum VoiceCommands {
    /// eatAfter — какие знаки Whisper после команды выбрасывать.
    private struct Rule { let phrases: [String]; let output: String; var eatAfter = ",.;:!?…" }

    private static let rules: [Rule] = [
        Rule(phrases: ["новый абзац", "с нового абзаца"], output: "\n\n"),
        Rule(phrases: ["новая строка", "с новой строки", "новую строку"], output: "\n"),
        Rule(phrases: ["точка с запятой"], output: ";"),
        Rule(phrases: ["двоеточие"], output: ":"),
        Rule(phrases: ["восклицательный знак"], output: "!"),
        Rule(phrases: ["вопросительный знак"], output: "?"),
        Rule(phrases: ["многоточие"], output: "…"),
        Rule(phrases: ["запятая"], output: ","),
        Rule(phrases: ["открыть скобку", "открой скобку", "скобка открывается"], output: " (", eatAfter: ",."),
        Rule(phrases: ["закрыть скобку", "закрой скобку", "скобка закрывается"], output: ")", eatAfter: ","),
    ]

    static let help = "«новая строка», «новый абзац», «запятая», «двоеточие», «точка с запятой», «вопросительный знак», «восклицательный знак», «многоточие», «открыть / закрыть скобку»"

    static func apply(_ text: String) -> String {
        var t = text
        for rule in rules {
            for phrase in rule.phrases {
                // знаки препинания, которые Whisper поставил вокруг команды, съедаем
                // перед командой съедаем только запятую (точку конца предложения оставляем)
                let after = NSRegularExpression.escapedPattern(for: rule.eatAfter)
                let pattern = #"[ \t]*,?[ \t]*(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: phrase)
                    + #"(?![\p{L}\p{N}])[ \t]*["# + after + "]*"
                t = t.replacingOccurrences(of: pattern, with: rule.output.replacingOccurrences(of: "\\", with: "\\\\"),
                                           options: [.regularExpression, .caseInsensitive])
            }
        }
        return tidy(t)
    }

    /// Пробелы вокруг знаков, переносов и заглавные буквы после них.
    static func tidy(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: #"[ \t]+([,.;:!?…)])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"([,;:!?…)])(?=[\p{L}\p{N}(«"])"#, with: "$1 ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\(\s+"#, with: "(", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // заглавная после переноса строки и после ! ? …
        t = capitalize(after: #"(\n|[!?…]\s)(\p{Ll})"#, in: t)
        return t.capitalizedFirst
    }

    private static func capitalize(after pattern: String, in text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = NSMutableString(string: text)
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let r = m.range(at: 2)
            ns.replaceCharacters(in: r, with: ns.substring(with: r).uppercased())
        }
        return ns as String
    }
}

struct Replacement: Codable, Identifiable, Hashable {
    var id = UUID()
    var from: String
    var to: String
}

/// Автозамены «Майорка → малярка»: целое слово/фраза, без учёта регистра, заглавная буква сохраняется.
enum Replacer {
    static func apply(_ text: String, rules: [Replacement]) -> String {
        var t = text
        for rule in rules {
            let from = rule.from.trimmingCharacters(in: .whitespaces)
            guard !from.isEmpty else { continue }
            let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: from) + #"(?![\p{L}\p{N}])"#
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = NSMutableString(string: t)
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
                let found = ns.substring(with: m.range)
                var to = rule.to
                // заглавную ставим только в начале предложения (Whisper любит писать ошибку с большой буквы)
                let before = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
                let sentenceStart = before.isEmpty || before.hasSuffix(".") || before.hasSuffix("!")
                    || before.hasSuffix("?") || before.hasSuffix("…") || before.hasSuffix("\n")
                if sentenceStart, let f = found.first, f.isUppercase { to = to.capitalizedFirst }
                ns.replaceCharacters(in: m.range, with: to)
            }
            t = ns as String
        }
        return t
    }
}

/// Что поменялось при ручной правке — чтобы предложить запомнить как автозамену.
enum WordDiff {
    static func pairs(old: String, new: String) -> [(from: String, to: String)] {
        let a = words(old), b = words(new)
        guard !a.isEmpty, !b.isEmpty, a.count < 400, b.count < 400 else { return [] }
        // наибольшая общая подпоследовательность по словам (без регистра)
        let al = a.map { $0.lowercased() }, bl = b.map { $0.lowercased() }
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                dp[i][j] = al[i] == bl[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var result: [(String, String)] = []
        var i = 0, j = 0
        var gapA: [String] = [], gapB: [String] = []
        func flush() {
            if !gapA.isEmpty, !gapB.isEmpty, gapA.count <= 3, gapB.count <= 3 {
                result.append((gapA.joined(separator: " "), gapB.joined(separator: " ")))
            }
            gapA = []; gapB = []
        }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, al[i] == bl[j] { flush(); i += 1; j += 1 }
            else if j < b.count, (i == a.count || dp[i][j + 1] >= dp[i + 1][j]) { gapB.append(b[j]); j += 1 }
            else { gapA.append(a[i]); i += 1 }
        }
        flush()
        // одинаковые пары не повторяем
        var seen = Set<String>()
        return result.filter { seen.insert($0.0.lowercased() + "→" + $0.1.lowercased()).inserted }
    }

    private static func words(_ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"[\p{L}\p{N}][\p{L}\p{N}\-]*"#) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
}
