import SwiftUI

/// 2026-11-24 (Камиль): вариант R5.5 «Как „Настройки“» для Истории, Словаря и Статистики —
/// крупный заголовок раздела, одна колонка по центру, всё строками «название … значение».
/// Галерея — `../Dictation_Дизайны/` (`R5Gallery`, `r55`).

/// Ширина колонки по центру окна
enum R55 {
    static let column: CGFloat = 680
}

/// Крупный заголовок раздела: имя слева, подпись рядом, справа — своё содержимое
struct SectionTitle<Trailing: View>: View {
    let title: String
    var subtitle = ""
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.system(size: 30, weight: .bold))
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(title: String, subtitle: String = "") {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Группа как в «Настройках»: серый заголовок и скруглённый блок со строками
struct SettingsGroup<Content: View>: View {
    let title: String
    var trailing = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(trailing).font(.system(size: 13)).foregroundStyle(.tertiary).monospacedDigit()
            }
            .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 0) { content }
                .background(.background.secondary, in: .rect(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Строка группы; разделитель снизу, кроме последней
struct SettingsRow<Content: View>: View {
    var last = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) { content }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            if !last { Divider().padding(.leading, 16) }
        }
    }
}
