import SwiftUI

/// Свой словарь: слова и имена (подсказка модели), автозамены, голосовые команды.
struct VocabularyView: View {
    @Environment(AppState.self) private var state
    @State private var newTerm = ""
    @State private var from = ""
    @State private var to = ""

    // 2026-11-24 (Камиль): Q1 «Только главное» — две колонки крупным текстом, без рамок.
    // Прежний вид (форма) — `_backup-2026-11-24-Q1/VocabularyView.swift`.
    @State private var addingTerm = false
    @State private var addingSwap = false
    @FocusState private var focus: Int?

    var body: some View {
        @Bindable var state = state
        let vocab = state.vocabulary
        ScrollView {
            HStack(alignment: .top, spacing: 60) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Слова").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    if vocab.terms.isEmpty && !addingTerm {
                        Text("Пока пусто. Например: малярка, Азамат, Excel").font(.system(size: 16)).foregroundStyle(.tertiary)
                    }
                    ForEach(vocab.terms, id: \.self) { term in
                        QuietItem {
                            Text(term).font(.system(size: 18))
                        } onDelete: {
                            vocab.terms.removeAll { $0 == term }
                        }
                    }
                    if addingTerm {
                        TextField("Слово", text: $newTerm, prompt: Text("Слово или имя — Return, чтобы добавить"))
                            .textFieldStyle(.plain).font(.system(size: 18))
                            .focused($focus, equals: 1)
                            .onSubmit { addTerm(); addingTerm = !newTerm.isEmpty }
                            .onExitCommand { addingTerm = false; newTerm = "" }
                    }
                    Button("+ Добавить слово") { addingTerm = true; focus = 1 }
                        .buttonStyle(.plain).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.accentColor)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Исправления").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    if vocab.replacements.isEmpty && !addingSwap {
                        Text("Пока пусто. Например: Майорки → малярки").font(.system(size: 16)).foregroundStyle(.tertiary)
                    }
                    ForEach(vocab.replacements) { r in
                        QuietItem {
                            HStack(spacing: 10) {
                                Text(r.from).foregroundStyle(.tertiary)
                                Text("→").foregroundStyle(.tertiary)
                                Text(r.to)
                            }
                            .font(.system(size: 18))
                        } onDelete: {
                            vocab.replacements.removeAll { $0.id == r.id }
                        }
                    }
                    if addingSwap {
                        HStack(spacing: 10) {
                            TextField("Как распознаёт", text: $from, prompt: Text("Как распознаёт"))
                                .textFieldStyle(.plain).focused($focus, equals: 2)
                                .onSubmit { focus = 3 }
                            Text("→").foregroundStyle(.tertiary)
                            TextField("Как должно быть", text: $to, prompt: Text("Как должно быть"))
                                .textFieldStyle(.plain).focused($focus, equals: 3)
                                .onSubmit { addReplacement(); addingSwap = false }
                        }
                        .font(.system(size: 18))
                        .onExitCommand { addingSwap = false; from = ""; to = "" }
                    }
                    Button("+ Добавить исправление") { addingSwap = true; focus = 2 }
                        .buttonStyle(.plain).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.accentColor)
                        .padding(.top, 4)

                    HStack {
                        Text("Голосовые команды").font(.system(size: 17))
                        Spacer()
                        Toggle("Голосовые команды", isOn: $state.voiceCommands).toggleStyle(.switch).labelsHidden()
                    }
                    .padding(.top, 30)
                    .help("Скажи: \(VoiceCommands.help)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 44).padding(.vertical, 28)
        }
        .navigationTitle("Словарь")
        .navigationSubtitle("\(vocab.terms.count) \(RU.plural(vocab.terms.count, "слово", "слова", "слов")) · \(vocab.replacements.count) \(RU.plural(vocab.replacements.count, "автозамена", "автозамены", "автозамен"))")
    }

    private func addTerm() {
        state.vocabulary.addTerm(newTerm)
        newTerm = ""
    }

    private func addReplacement() {
        state.vocabulary.addReplacement(from: from, to: to)
        from = ""
        to = ""
    }
}

/// Строка словаря: при наведении справа появляется ✕
private struct QuietItem<C: View>: View {
    @ViewBuilder var content: C
    var onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack {
            content
            Spacer(minLength: 12)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Удалить")
            .opacity(hover ? 1 : 0)
        }
        .contentShape(.rect)
        .onHover { hover = $0 }
    }
}
