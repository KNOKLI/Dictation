import SwiftUI
import Charts

struct StatsView: View {
    @Environment(AppState.self) private var state
    @State private var selectedDay: String?
    @State private var width: CGFloat = 900

    private static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d"
        return f
    }()

    private static let longDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM, EEEE"
        return f
    }()

    /// Подпись под столбиком — число месяца (14 дней подряд не повторяются).
    private func label(_ d: DayStat) -> String { Self.dayNumber.string(from: d.day) }

    var body: some View {
        let a = state.history.archive
        let days = state.history.lastDays(14)
        let todayLabel = Self.dayNumber.string(from: .now)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Ровно на всю ширину: 6 карточек в ряд на широком окне, 3 — на узком (без пустых колонок справа)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: width >= 1050 ? 6 : 3),
                          spacing: 16) {
                    StatCard(title: "Всего символов", value: RU.number(a.totalCharacters),
                             icon: "character.cursor.ibeam", tint: .blue)
                    StatCard(title: "Сегодня", value: RU.number(state.history.todayCharacters),
                             icon: "sun.max.fill", tint: .orange)
                    StatCard(title: "Слов", value: RU.number(a.totalWords),
                             icon: "text.word.spacing", tint: .purple)
                    StatCard(title: "Диктовок", value: RU.number(a.totalCount),
                             icon: "waveform", tint: .pink)
                    StatCard(title: "Время диктовки", value: RU.duration(a.totalDuration),
                             icon: "clock.fill", tint: .green)
                    StatCard(title: "Символов в минуту", value: RU.number(state.history.charsPerMinute),
                             icon: "gauge.with.dots.needle.67percent", tint: .teal)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Последние 14 дней").font(.headline)
                        Spacer()
                        Text("всего \(RU.chars(days.reduce(0) { $0 + $1.characters }))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Chart(days) { d in
                        let isToday = Calendar.current.isDateInToday(d.day)
                        let isSelected = selectedDay == label(d)
                        BarMark(x: .value("День", label(d)), y: .value("Символы", d.characters))
                            .foregroundStyle(isToday || isSelected
                                             ? AnyShapeStyle(Color.accentColor.gradient)
                                             : AnyShapeStyle(Color.accentColor.opacity(0.4).gradient))
                            .clipShape(.rect(cornerRadius: 5))
                            .annotation(position: .top, spacing: 4,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                if isSelected {
                                    VStack(spacing: 1) {
                                        Text(RU.chars(d.characters)).font(.caption.weight(.semibold))
                                        Text(isToday ? "сегодня" : Self.longDay.string(from: d.day))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(.background, in: .rect(cornerRadius: 8))
                                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                                }
                            }
                    }
                    .chartOverlay { proxy in
                        // наведение мышью — подсказка с числом за день
                        GeometryReader { geo in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        guard let plot = proxy.plotFrame else { return }
                                        let x = location.x - geo[plot].origin.x
                                        selectedDay = proxy.value(atX: x, as: String.self)
                                    case .ended:
                                        selectedDay = nil
                                    }
                                }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let s = value.as(String.self) {
                                    Text(s == todayLabel ? "Сегодня" : s)
                                        .fontWeight(s == todayLabel ? .semibold : .regular)
                                        .foregroundStyle(s == todayLabel ? Color.accentColor : Color.secondary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let n = value.as(Int.self) { Text(RU.number(n)) }
                            }
                        }
                    }
                    .frame(height: 240)
                    Text("Наведи на столбик — покажу число за день.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(22)
                .background(.background.secondary, in: .rect(cornerRadius: 22))
            }
            .padding(28)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle("Статистика")
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
