import SwiftUI
import Charts

/// 2026-11-24 (Камиль): Q1 «Только главное» — три больших числа и тонкий график 14 дней.
/// Прежний вид (6 карточек + Charts) — `_backup-2026-11-24-Q1/StatsView.swift`.
struct StatsView: View {
    @Environment(AppState.self) private var state
    @State private var hoverDay: Int?

    private static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d"
        return f
    }()

    private static let longDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f
    }()

    var body: some View {
        let days = state.history.lastDays(14)
        let week = days.suffix(7).reduce(0) { $0 + $1.characters }
        let top = max(1, days.map(\.characters).max() ?? 1)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 50) {
                number(RU.number(state.history.todayCharacters), "Сегодня")
                number(RU.number(week), "Неделя")
                number(RU.number(state.history.archive.totalCharacters), "Всего")
                Spacer()
            }
            Spacer().frame(height: 36)
            GeometryReader { g in
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        let today = i == days.count - 1
                        VStack(spacing: 8) {
                            if hoverDay == i {
                                Text(RU.number(d.characters)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                    .fixedSize()
                            }
                            Capsule()
                                .fill(today ? AnyShapeStyle(Color.accentColor)
                                      : AnyShapeStyle(.primary.opacity(hoverDay == i ? 0.45 : 0.22)))
                                .frame(width: 8, height: max(4, CGFloat(d.characters) / CGFloat(top) * (g.size.height - 50)))
                            Text(today ? "сег." : Self.dayNumber.string(from: d.day))
                                .font(.system(size: 12, weight: today ? .semibold : .regular))
                                .foregroundStyle(today ? .primary : .tertiary)
                                .frame(height: 14)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .contentShape(.rect)
                        .onHover { hoverDay = $0 ? i : (hoverDay == i ? nil : hoverDay) }
                        .help("\(Self.longDay.string(from: d.day)): \(RU.chars(d.characters))")
                    }
                }
            }
        }
        .padding(.horizontal, 44).padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Статистика")
    }

    private func number(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
            Text(title).font(.system(size: 15)).foregroundStyle(.secondary)
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint.gradient)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 20))
    }
}
