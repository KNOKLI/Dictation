import SwiftUI

/// 2026-11-24 (Камиль): V7 «Герой и полки» — сверху «Всего надиктовано» с линией 14 дней,
/// ниже три карточки (неделя, лучший день, скорость) и полоса цифр.
/// Прежний R5.5 (строки как в «Настройках») — `_backup-2026-11-24-V7/StatsView.swift`.
struct StatsView: View {
    @Environment(AppState.self) private var state

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM, EEEE"
        return f
    }()

    private static let keyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f
    }()

    /// Примерно столько символов на странице А4 обычным шрифтом
    private static let pageChars = 1800
    /// Средняя скорость набора на клавиатуре, символов в минуту
    private static let typingSpeed = 200

    var body: some View {
        let history = state.history
        let archive = history.archive
        let week = history.lastDays(7)
        let weekTotal = week.reduce(0) { $0 + $1.characters }
        let days14 = history.lastDays(14).map(\.characters)
        let best = archive.daily.max(by: { $0.value < $1.value })
        let activeDays = archive.daily.values.filter { $0 > 0 }
        let average = activeDays.isEmpty ? 0 : activeDays.reduce(0, +) / activeDays.count
        let pages = Double(archive.totalCharacters) / Double(Self.pageChars)

        VStack(alignment: .leading, spacing: V7.gap) {
            HeroCard(symbol: "chart.line.uptrend.xyaxis", height: 240) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Всего надиктовано").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.accentColor)
                    Text(RU.number(archive.totalCharacters))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(RU.plural(archive.totalCharacters, "символ", "символа", "символов")) — примерно \(pagesText(pages))")
                        .font(.system(size: 15)).foregroundStyle(.secondary)
                }
                .fixedSize()
                VStack(alignment: .trailing, spacing: 6) {
                    TrendLine(values: days14).frame(maxHeight: .infinity)
                    Text("последние 14 дней").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                .padding(.leading, 24).padding(.trailing, 150)
            }

            HStack(spacing: V7.gap) {
                ShelfCard(title: "Эта неделя", icon: "calendar") {
                    Text(RU.number(weekTotal)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    WeekBars(days: week)
                }
                ShelfCard(title: "Лучший день", icon: "trophy") {
                    if let best, best.value > 0 {
                        Text(RU.number(best.value)).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(Self.keyParser.date(from: best.key).map { Self.dayMonth.string(from: $0) } ?? best.key)
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text("Топ-3 дня").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(Array(archive.daily.sorted { $0.value > $1.value }.prefix(3).enumerated()), id: \.offset) { i, d in
                            MeterRow(title: Self.keyParser.date(from: d.key).map { Self.shortDay.string(from: $0) } ?? d.key,
                                     value: RU.number(d.value), fraction: Double(d.value) / Double(best.value), strong: i == 0)
                        }
                        Spacer(minLength: 8)
                        if average > 0 {
                            Text("в \(ratio(Double(best.value) / Double(average))) больше среднего дня")
                                .font(.system(size: 13)).foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("Пока нет").font(.system(size: 18)).foregroundStyle(.secondary)
                    }
                }
                ShelfCard(title: "Скорость", icon: "gauge.with.dots.needle.67percent") {
                    Text(history.charsPerMinute > 0 ? RU.number(history.charsPerMinute) : "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("символов в минуту").font(.system(size: 14)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if history.charsPerMinute > 0 {
                        let top = Double(max(history.charsPerMinute, Self.typingSpeed))
                        MeterRow(title: "Диктовка", value: RU.number(history.charsPerMinute),
                                 fraction: Double(history.charsPerMinute) / top, strong: true)
                        MeterRow(title: "Печать", value: "≈ \(Self.typingSpeed)",
                                 fraction: Double(Self.typingSpeed) / top, strong: false)
                    }
                    Spacer(minLength: 8)
                    if history.charsPerMinute > Self.typingSpeed {
                        Text("быстрее, чем печатать, примерно в \(ratio(Double(history.charsPerMinute) / Double(Self.typingSpeed)))")
                            .font(.system(size: 13)).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 0) {
                strip(RU.number(archive.totalCount), RU.plural(archive.totalCount, "диктовка", "диктовки", "диктовок"))
                strip(RU.number(archive.totalWords), RU.plural(archive.totalWords, "слово", "слова", "слов"))
                strip(RU.duration(archive.totalDuration), "наговорено")
                strip(archive.totalCount > 0 ? RU.number(archive.totalCharacters / archive.totalCount) : "—", "символов в записи")
            }
            .frame(height: 96)
            .background(.background.secondary, in: .rect(cornerRadius: V7.radius, style: .continuous))
        }
        .padding(.horizontal, V7.pad).padding(.top, 8).padding(.bottom, V7.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Статистика")
    }

    private func strip(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }

    /// 2,6 → «2,6 раза», 3 → «3 раза»
    private func ratio(_ r: Double) -> String {
        let rounded = (r * 10).rounded() / 10
        let text = rounded.formatted(.number.precision(.fractionLength(rounded == rounded.rounded() ? 0 : 1)).locale(Locale(identifier: "ru_RU")))
        return "\(text) раза"
    }

    /// «12 страниц», «меньше страницы»
    private func pagesText(_ p: Double) -> String {
        if p < 1 { return "меньше страницы" }
        let n = Int(p.rounded())
        return "\(RU.number(n)) \(RU.plural(n, "страница", "страницы", "страниц"))"
    }
}

/// Неделя столбиками: число сверху, день недели снизу, сегодня — синим.
struct WeekBars: View {
    let days: [DayStat]
    @State private var hover: Int?

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEEEE"
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
                    VStack(spacing: 5) {
                        Text(d.characters > 0 ? short(d.characters) : "")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(hover == i ? .primary : .secondary)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(today ? AnyShapeStyle(Color.accentColor)
                                  : AnyShapeStyle(Color.accentColor.opacity(hover == i ? 0.55 : 0.35)))
                            .frame(width: 22, height: max(5, CGFloat(d.characters) / CGFloat(top) * max(10, g.size.height - 40)))
                        Text(today ? "сег." : Self.weekday.string(from: d.day).lowercased())
                            .font(.system(size: 12, weight: today ? .semibold : .regular))
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

    private func short(_ n: Int) -> String {
        n >= 1000 ? (Double(n) / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "ru_RU"))) + "к" : "\(n)"
    }
}

/// Строка-полоска: название, полоса доли, значение
struct MeterRow: View {
    let title: String
    let value: String
    let fraction: Double
    var strong = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13.5)).frame(width: 92, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(.primary.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule().fill(strong ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.4)))
                            .frame(width: max(8, g.size.width * min(1, fraction)))
                    }
            }
            .frame(height: 8)
            Text(value).font(.system(size: 13.5).monospacedDigit()).foregroundStyle(.secondary).frame(width: 62, alignment: .trailing)
        }
        .frame(height: 22)
    }
}
