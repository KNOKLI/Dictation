import SwiftUI
import AppKit

enum Section: String, CaseIterable, Identifiable {
    case dictation, history, vocabulary, stats
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: "Диктовка"
        case .history: "История"
        case .vocabulary: "Словарь"
        case .stats: "Статистика"
        }
    }

    var icon: String {
        switch self {
        case .dictation: "mic"
        case .history: "clock.arrow.circlepath"
        case .vocabulary: "character.book.closed"
        case .stats: "chart.bar.xaxis"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .dictation: "1"
        case .history: "2"
        case .vocabulary: "3"
        case .stats: "4"
        }
    }
}

/// Дизайн «Фокус» (выбран Камилем 2026-11-20): без боковой панели,
/// разделы — стеклянный переключатель по центру панели инструментов.
struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var section: Section = .dictation

    var body: some View {
        PageContainer(section: section, state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                // 2026-11-24 (Камиль): Q1 «Только главное» — разделы простыми словами
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 28) {
                        ForEach(Section.allCases) { s in
                            Button { section = s } label: {
                                Text(s.title)
                                    .font(.system(size: 15, weight: s == section ? .semibold : .regular))
                                    .foregroundStyle(s == section ? .primary : .tertiary)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                // Панель одинаковая во всех разделах — macOS не перекладывает её при переключении
                ToolbarItem(placement: .primaryAction) {
                    MicrophoneToolbarMenu()
                }
            }
            .toolbar(removing: .title)
            .background {
                // ⌘1–⌘4 — переключение разделов
                ForEach(Section.allCases) { s in
                    Button(s.title) { section = s }
                        .keyboardShortcut(s.shortcut, modifiers: .command)
                        .hidden()
                }
            }
            .sheet(isPresented: Bindable(state).showWelcome) {
                OnboardingView()
                    .environment(state)
                    .interactiveDismissDisabled()
            }
    }
}

/// Разделы как вкладки AppKit (по образцу NSTabView): у каждого раздела свой NSHostingView,
/// созданный один раз. Переключение — только `isHidden`, без пересборки и без переноса
/// таблиц в окне. Раньше раздел строился заново при каждом переключении — отсюда подлагивание.
/// Скрытый раздел не получает ни кликов, ни горячих клавиш (так устроен AppKit).
private struct PageContainer: NSViewRepresentable {
    let section: Section
    let state: AppState

    final class Coordinator {
        var hosts: [Section: NSView] = [:]
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let root = NSView()
        for s in Section.allCases {
            let host = NSHostingView(rootView: AnyView(page(s).environment(state)))
            host.sizingOptions = [] // размер задаёт окно, а не содержимое
            host.frame = root.bounds
            host.autoresizingMask = [.width, .height]
            host.isHidden = s != section
            root.addSubview(host)
            context.coordinator.hosts[s] = host
        }
        return root
    }

    /// Контейнер всегда размером с отведённое место. Без этого SwiftUI при каждом обновлении
    /// (во время записи — много раз в секунду) спрашивал у AppKit «удобный размер» и тот
    /// прогонял автораскладку по всем четырём разделам — отсюда подлагивание при диктовке.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 780, height: proposal.height ?? 560)
    }

    func updateNSView(_ root: NSView, context: Context) {
        for (s, host) in context.coordinator.hosts where host.isHidden != (s != section) {
            host.isHidden = s != section
        }
    }

    @ViewBuilder
    private func page(_ s: Section) -> some View {
        switch s {
        case .dictation: DictationView()
        case .history: HistoryView()
        case .vocabulary: VocabularyView()
        case .stats: StatsView()
        }
    }
}
