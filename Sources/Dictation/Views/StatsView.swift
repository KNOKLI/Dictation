import SwiftUI

/// 2026-11-24 (Камиль): R5.5 «Как „Настройки“» — цифры строками «название … значение» и график недели.
/// Прежний вид (Q1: три числа и график 14 дней) — `_backup-2026-11-24-R5.5/StatsView.swift`.
struct StatsView: View {
    @Environment(AppState.self) private var state

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f
    }()

    private static let keyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        let history = state.history
        let archive = history.archive
        let week = history.lastDays(7)
        let weekTotal = week.reduce(0) { $0 + $1.characters }
        let rows: [(String, String)] = [
            ("Сегодня", RU.number(history.todayCharacters)),
            ("Неделя", RU.number(weekTotal)),
            ("Всего", RU.number(archive.totalCharacters)),
            ("Лучший день", bestDay(archive.daily)),
            ("Скорость", history.charsPerMinute > 0 ? "\(RU.number(history.charsPerMinute)) в минуту" : "—"),
        ]
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(title: "Статистика", subtitle: RU.chars(archive.totalCharacters))
                SettingsGroup(title: "Символы") {
                    ForEach(rows.indices, id: \.self) { k in
                        SettingsRow(last: k == rows.count - 1) {
                            Text(rows[k].0).font(.system(size: 16))
                            Spacer()
                            Text(rows[k].1).font(.system(size: 16).monospacedDigit()).foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                    }
                }
                SettingsGroup(title: "Эта неделя", trailing: RU.chars(weekTotal)) {
                    WeekBars(days: week).frame(height: 180).padding(16)
                }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 28)
            .frame(maxWidth: R55.column)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Статистика")
    }

    /// «6 820 · 17 ноября» — день с наибольшим числом символов
    private func bestDay(_ daily: [String: Int]) -> String {
        guard let best = daily.max(by: { $0.value < $1.value }), best.value > 0 else { return "—" }
        let day = Self.keyParser.date(from: best.key).map { Self.dayMonth.string(from: $0) } ?? best.key
        return "\(RU.number(best.value)) · \(day)"
    }
}

/// Неделя столбиками: число сверху, день недели снизу, сегодня — синим.
private struct WeekBars: View {
    let days: [DayStat]
    @State private var hover: Int?

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEEEE" // пн, вт…
        return f
    }()

    private static let longDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM, EEEE"
        return f
    }()

    var body: some View {
        let top = max(1, days.map(\.characters).max() ?? 1)
        GeometryReader { g in
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(days.indices, id: \.self) { i in
                    let d = days[i]
                    let today = i == days.count - 1
                    VStack(spacing: 6) {
                        Text(d.characters > 0 ? short(d.characters) : "")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(hover == i ? .primary : .secondary)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(today ? AnyShapeStyle(Color.accentColor)
                                  : AnyShapeStyle(Color.accentColor.opacity(hover == i ? 0.55 : 0.35)))
                            .frame(width: 34, height: max(6, CGFloat(d.characters) / CGFloat(top) * (g.size.height - 44)))
                        Text(today ? "сег." : Self.weekday.string(from: d.day).lowercased())
                            .font(.system(size: 13, weight: today ? .semibold : .regular))
                            .foregroundStyle(today ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .contentShape(.rect)
                    .onHover { hover = $0 ? i : (hover == i ? nil : hover) }
                    .help("\(Self.longDay.string(from: d.day)): \(RU.chars(d.characters))")
                }
            }
        }
    }

    /// 6820 → «6,8к», 120 → «120»
    private func short(_ n: Int) -> String {
        n >= 1000 ? (Double(n) / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "ru_RU"))) + "к" : "\(n)"
    }
}
