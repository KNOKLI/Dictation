import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.undoManager) private var undoManager
    @State private var query = ""
    // Выделение, панель подробностей и подтверждение очистки — в AppState.historyUI:
    // ими управляют и кнопки панели инструментов главного окна.
    private var ui: HistoryUI { state.historyUI }
    private var selection: Set<DictationEntry.ID> {
        get { ui.selection }
        nonmutating set { ui.selection = newValue }
    }
    private var showInspector: Bool {
        get { ui.showInspector }
        nonmutating set { ui.showInspector = newValue }
    }
    @State var deleted: [DictationEntry] = []
    @State private var bannerTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let groups = state.history.groups(matching: query)
        let found = groups.reduce(0) { $0 + $1.entries.count }
        // Поиск и панель подробностей — внутри окна, а не в панели инструментов:
        // так переключатель разделов не сдвигается и не перестраивается (не лагает).
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchBar(found: found)
                listArea(groups: groups)
            }
            .frame(maxWidth: .infinity)
            if showInspector {
                Divider()
                EntryInspector(selection: selection, onDelete: { delete($0) })
                    .frame(width: 330)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: showInspector)
        .background {
            Button("Поиск") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
        .overlay(alignment: .bottom) { if !deleted.isEmpty { undoBanner } }
        .navigationTitle("История")
        .navigationSubtitle(query.trimmingCharacters(in: .whitespaces).isEmpty
                            ? "\(state.history.entries.count) \(RU.plural(state.history.entries.count, "запись", "записи", "записей"))"
                            : "Найдено: \(found)")
        .confirmationDialog("Удалить всю историю?", isPresented: Bindable(ui).confirmClear) {
            Button("Удалить", role: .destructive) { delete(Set(state.history.entries.map(\.id))) }
        } message: {
            Text("Общий счётчик символов сохранится. Сразу после удаления историю можно вернуть.")
        }
        .onChange(of: selection) { _, new in
            // выбрал другую запись — правку закрываем; двойной клик по той же — не мешаем
            if let e = state.editingEntryID, !new.contains(e) { state.editingEntryID = nil }
        }
    }

    @ViewBuilder
    private func listArea(groups: [DayGroup]) -> some View {
        Group {
            if state.history.entries.isEmpty {
                ContentUnavailableView("История пуста", systemImage: "clock",
                                       description: Text("Здесь появятся все надиктованные тексты"))
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(selection: Bindable(ui).selection) {
                    ForEach(groups) { group in
                        SwiftUI.Section {
                            ForEach(group.entries) { entry in
                                HistoryRow(entry: entry, query: query,
                                           selected: ui.selection == [entry.id],
                                           onEdit: { edit(entry.id) })
                                    .tag(entry.id)
                            }
                        } header: {
                            HStack {
                                Text(group.title)
                                Spacer()
                                Text(RU.chars(group.entries.reduce(0) { $0 + $1.characters }))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: DictationEntry.ID.self) { ids in
                    menu(for: ids)
                } primaryAction: { ids in
                    // двойной клик — править
                    guard let id = ids.first, ids.count == 1 else { return }
                    edit(id)
                }
                .onDeleteCommand { delete(selection) }
                .onCopyCommand {
                    [NSItemProvider(object: selectedText(selection) as NSString)]
                }
            }
        }
    }

    private func searchBar(found: Int) -> some View {
        let total = state.history.entries.count
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск в истории", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if searching {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: 360)
            .background(.primary.opacity(0.06), in: .capsule)
            Spacer()
            Text(searching ? "Найдено: \(found)" : "\(total) \(RU.plural(total, "запись", "записи", "записей"))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack(spacing: 6) {
                HistoryToolbarButtons()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .menuStyle(.button)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Меню

    @ViewBuilder
    private func menu(for ids: Set<DictationEntry.ID>) -> some View {
        if !ids.isEmpty {
            Button(ids.count > 1 ? "Копировать все (\(ids.count))" : "Копировать", systemImage: "doc.on.doc") {
                Paster.copy(selectedText(ids))
            }
            if ids.count == 1, let id = ids.first {
                Button("Изменить", systemImage: "pencil") {
                    selection = [id]
                    showInspector = true
                    state.editingEntryID = id
                }
            }
            Divider()
            Button(ids.count > 1 ? "Удалить (\(ids.count))" : "Удалить", systemImage: "trash", role: .destructive) {
                delete(ids)
            }
        }
    }

    private func edit(_ id: DictationEntry.ID) {
        selection = [id]
        showInspector = true
        state.editingEntryID = id
    }

    private func selectedText(_ ids: Set<DictationEntry.ID>) -> String {
        HistoryActions.text(of: ids, in: state.history)
    }

    // MARK: - Удаление с возвратом

    private func delete(_ ids: Set<DictationEntry.ID>) {
        guard !ids.isEmpty else { return }
        let removed = state.history.delete(ids)
        selection.subtract(ids)
        guard !removed.isEmpty else { return }
        let store = state.history
        undoManager?.registerUndo(withTarget: store) { s in
            MainActor.assumeIsolated { s.restore(removed) }
        }
        undoManager?.setActionName("Удаление")
        // Копим, а не заменяем: раньше второе удаление за 8 с затирало первое, а «Вернуть»
        // ещё и чистил ⌘Z — первые удалённые записи пропадали навсегда.
        deleted += removed
        bannerTask?.cancel()
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { withAnimation { deleted = [] } }
        }
    }

    func undoDelete() {
        state.history.restore(deleted)
        undoManager?.removeAllActions(withTarget: state.history)
        withAnimation { deleted = [] }
    }

    private var undoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            Text(deleted.count == 1 ? "Запись удалена" : "Удалено: \(deleted.count)")
            Button("Вернуть") { undoDelete() }
                .keyboardShortcut("z", modifiers: .command)
            .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Экспорт

}

/// Правая панель: полный текст выбранной записи, правка, копирование.
private struct EntryInspector: View {
    @Environment(AppState.self) private var state
    let selection: Set<DictationEntry.ID>
    let onDelete: (Set<DictationEntry.ID>) -> Void
    @State private var copied = false

    var body: some View {
        if selection.count == 1, let entry = state.history.entry(selection.first) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(HistoryStore.title(for: entry.date)), \(RU.time(entry.date))")
                            .font(.headline)
                        Text("\(RU.chars(entry.characters)) · \(RU.duration(entry.duration))")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if state.editingEntryID == entry.id {
                        EntryEditor(entryID: entry.id) { state.editingEntryID = nil }
                            .id(entry.id)
                    } else {
                        Text(entry.text)
                            .font(.system(size: 15))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Button {
                                Paster.copy(entry.text)
                                copied = true
                                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                            } label: {
                                Label(copied ? "Готово" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.glass)
                            Button("Изменить", systemImage: "pencil") { state.editingEntryID = entry.id }
                                .buttonStyle(.glass)
                            Spacer()
                            Button(role: .destructive) { onDelete([entry.id]) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Удалить запись")
                        }
                        if let original = entry.original {
                            DisclosureGroup("Исходный текст (до правки)") {
                                Text(original)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            }
                            .font(.callout)
                        }
                    }
                }
                .padding(18)
            }
        } else if selection.count > 1 {
            let list = state.history.entries.filter { selection.contains($0.id) }
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up").font(.largeTitle).foregroundStyle(.secondary)
                Text("Выбрано: \(list.count)").font(.headline)
                Text(RU.chars(list.reduce(0) { $0 + $1.characters })).foregroundStyle(.secondary)
                Button("Копировать все", systemImage: "doc.on.doc") {
                    Paster.copy(list.map(\.text).joined(separator: "\n\n"))
                }
                .buttonStyle(.glass)
                Button("Удалить", systemImage: "trash", role: .destructive) { onDelete(selection) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ContentUnavailableView("Выбери запись", systemImage: "text.cursor",
                                   description: Text("Здесь будет полный текст.\nДвойной клик по записи — изменить."))
        }
    }
}

/// 2026-11-24 (Камиль): Q1 «Только главное» — крупная строка: время серым, текст 17,
/// у выбранной записи справа «Копировать» и «Изменить» словами.
private struct HistoryRow: View {
    let entry: DictationEntry
    let query: String
    var selected = false
    var onEdit: () -> Void = {}
    @State private var copied = false

    var body: some View {
        HStack(spacing: 18) {
            Text(RU.time(entry.date))
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .leading)
            Text(highlighted)
                .font(.system(size: 17))
                .lineLimit(1)
            Spacer(minLength: 16)
            if selected {
                Button(copied ? "Скопировано" : "Копировать") {
                    Paster.copy(entry.text)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary) // строка выделена синим — синий текст был бы не виден
                Button("Изменить", action: onEdit)
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 40)
        .help(entry.text.count > 80 ? entry.text : "")
    }

    /// Найденное слово подсвечено.
    private var highlighted: AttributedString {
        var a = AttributedString(entry.text)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return a }
        var searchRange = entry.text.startIndex..<entry.text.endIndex
        while let r = entry.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            if let ar = Range(r, in: a) {
                a[ar].backgroundColor = .yellow.opacity(0.45)
                a[ar].inlinePresentationIntent = .stronglyEmphasized
            }
            searchRange = r.upperBound..<entry.text.endIndex
        }
        return a
    }
}

/// Общее состояние «Истории» — им пользуются и сам раздел, и кнопки панели главного окна.
@MainActor
@Observable
final class HistoryUI {
    var selection = Set<DictationEntry.ID>()
    var confirmClear = false
    var showInspector = false // 2026-11-24 (Камиль, Q1): открывается только при «Изменить»
}

/// Действия с историей, доступные из панели инструментов.
@MainActor
enum HistoryActions {
    static func text(of ids: Set<DictationEntry.ID>, in history: HistoryStore) -> String {
        history.entries.filter { ids.contains($0.id) }.map(\.text).joined(separator: "\n\n")
    }

    static func export(_ list: [DictationEntry], name: String, from history: HistoryStore) {
        guard !list.isEmpty else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.nameFieldStringValue = name + ".md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try history.markdown(list).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // раньше ошибка глоталась молча — казалось, что файл сохранён
            let alert = NSAlert()
            alert.messageText = "Не удалось сохранить файл"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

/// Кнопки «Истории» (в строке поиска): экспорт, очистка, панель подробностей.
struct HistoryToolbarButtons: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let ui = state.historyUI
        let history = state.history
        Menu {
            Button("Вся история…") { HistoryActions.export(history.entries, name: "Диктовки — вся история", from: history) }
            Button("За сегодня…") {
                HistoryActions.export(history.entries.filter { Calendar.current.isDateInToday($0.date) },
                                      name: "Диктовки — \(HistoryStore.key(.now))", from: history)
            }
            Button("Выделенные…") {
                HistoryActions.export(history.entries.filter { ui.selection.contains($0.id) },
                                      name: "Диктовки — выбранные", from: history)
            }
            .disabled(ui.selection.isEmpty)
            Divider()
            Button("Копировать выделенные") { Paster.copy(HistoryActions.text(of: ui.selection, in: history)) }
                .disabled(ui.selection.isEmpty)
        } label: {
            Label("Экспорт", systemImage: "square.and.arrow.up")
        }
        .help("Сохранить историю в файл .md (откроется в Obsidian и любом редакторе)")
        .disabled(history.entries.isEmpty)

        Button("Очистить историю", systemImage: "trash") { ui.confirmClear = true }
            .disabled(history.entries.isEmpty)

        Button("Подробности", systemImage: "sidebar.right") { ui.showInspector.toggle() }
            .help("Полный текст выбранной записи")
    }
}
