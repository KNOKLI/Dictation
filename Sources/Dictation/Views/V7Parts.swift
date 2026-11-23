import SwiftUI

/// 2026-11-24 (Камиль): дизайн V7 «Герой и полки» для всех разделов — сверху крупная синяя карточка
/// с главным, ниже полки карточек. Галерея — `../Dictation_Дизайны/` (`FullGallery2`, `fV7`).

enum V7 {
    static let pad: CGFloat = 28       // отступ от краёв окна
    static let gap: CGFloat = 16       // между карточками
    static let radius: CGFloat = 18
}

/// «Герой» раздела: синяя карточка с крупным водяным знаком-символом справа
struct HeroCard<Content: View>: View {
    let symbol: String
    var height: CGFloat = 220
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32).padding(.vertical, 24)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(alignment: .trailing) {
            Image(systemName: symbol)
                .font(.system(size: height * 0.95, weight: .thin))
                .foregroundStyle(Color.accentColor.opacity(0.13))
                .offset(x: 14, y: height * 0.12)
                .allowsHitTesting(false)
        }
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.24), Color.accentColor.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 24, style: .continuous))
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

/// Заголовок полки: «Недавние», «Сегодня»…
struct ShelfTitle<Trailing: View>: View {
    let title: String
    var count = ""
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 22, weight: .bold))
                if !count.isEmpty { Text(count).font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit() }
            }
            Spacer(minLength: 10)
            trailing
        }
    }
}

extension ShelfTitle where Trailing == EmptyView {
    init(title: String, count: String = "") {
        self.init(title: title, count: count) { EmptyView() }
    }
}

/// Мягкая карточка полки со значком и заголовком
struct ShelfCard<Content: View>: View {
    var title = ""
    var icon = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.accentColor)
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: .rect(cornerRadius: V7.radius, style: .continuous))
    }
}

/// Плитка: значок в синем квадрате, крупное число, подпись
struct StatTile<Middle: View>: View {
    let icon: String
    let value: String
    let label: String
    var note = ""
    var highlight = false
    @ViewBuilder var middle: Middle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(highlight ? Color.white : Color.accentColor)
                .frame(width: 34, height: 34)
                .background(highlight ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.15)),
                            in: .rect(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 6)
            middle
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 14)).foregroundStyle(.secondary)
            if !note.isEmpty { Text(note).font(.system(size: 12.5)).foregroundStyle(.tertiary) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: .rect(cornerRadius: V7.radius, style: .continuous))
    }
}

/// Карточка записи: время, размер, текст в 3 строки. Нажатие — скопировать.
struct EntryCard: View {
    let entry: DictationEntry
    @State private var copied = false
    @State private var hover = false

    var body: some View {
        Button {
            Paster.copy(entry.text)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(HistoryStore.title(for: entry.date)), \(RU.time(entry.date))")
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text(copied ? "Скопировано" : (hover ? "Копировать" : RU.chars(entry.characters)))
                        .font(.system(size: 12))
                        .foregroundStyle(copied || hover ? Color.accentColor : Color.secondary.opacity(0.7))
                }
                Text(entry.text)
                    .font(.system(size: 16))
                    .lineLimit(3)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.background.secondary, in: .rect(cornerRadius: V7.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: V7.radius, style: .continuous)
                .strokeBorder(hover ? Color.accentColor.opacity(0.5) : .white.opacity(0.05)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(entry.text)
    }
}

/// Линия-тренд по дням с заливкой (для «героя» статистики)
struct TrendLine: View {
    let values: [Int]

    var body: some View {
        GeometryReader { g in
            let top = CGFloat(max(1, values.max() ?? 1))
            let n = max(1, values.count - 1)
            let pts = values.indices.map { i in
                CGPoint(x: g.size.width * CGFloat(i) / CGFloat(n),
                        y: g.size.height - CGFloat(values[i]) / top * (g.size.height - 8) - 4)
            }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: g.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: g.size.width, y: g.size.height))
                }
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in p.addLines(pts) }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(Color.accentColor).frame(width: 9, height: 9).position(last)
                }
            }
        }
    }
}

/// Капсула-«таблетка»: слово, команда; при наведении — ✕ (если можно удалить)
struct Chip: View {
    let text: String
    var onDelete: (() -> Void)?
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 14))
            if let onDelete, hover {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Удалить")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.primary.opacity(0.08), in: .capsule)
        .onHover { hover = $0 }
    }
}

/// Раскладка «таблеток» в строку с переносом
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += z.width + spacing
            rowH = max(rowH, z.height)
        }
        return CGSize(width: w, height: y + rowH)
    }

    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, rowH: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x + z.width > b.maxX, x > b.minX { x = b.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += z.width + spacing
            rowH = max(rowH, z.height)
        }
    }
}

extension StatTile where Middle == EmptyView {
    init(icon: String, value: String, label: String, note: String = "", highlight: Bool = false) {
        self.init(icon: icon, value: value, label: label, note: note, highlight: highlight) { EmptyView() }
    }
}
