import SwiftUI

/// Свой словарь: слова и имена (подсказка модели), автозамены, голосовые команды.
/// 2026-11-24 (Камиль): R5.5 «Как „Настройки“» — слова и исправления одним списком, команды отдельной группой.
/// Прежний вид (Q1: две колонки) — `_backup-2026-11-24-R5.5/VocabularyView.swift`.
struct VocabularyView: View {
    @Environment(AppState.self) private var state
    @State private var adding = false
    @State private var first = ""
    @State private var second = ""
    @FocusState private var focus: Int?

    var body: some View {
        @Bindable var state = state
        let vocab = state.vocabulary
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(title: "Словарь", subtitle: "\(vocab.terms.count) \(RU.plural(vocab.terms.count, "слово", "слова", "слов")) · \(vocab.replacements.count) \(RU.plural(vocab.replacements.count, "исправление", "исправления", "исправлений"))")

                SettingsGroup(title: "Словарь") {
                    if vocab.terms.isEmpty && vocab.replacements.isEmpty && !adding {
                        SettingsRow {
                            Text("Пока пусто. Например: малярка, Азамат, Excel или «Майорки → малярки»")
                                .font(.system(size: 15)).foregroundStyle(.tertiary)
                            Spacer()
                        }
                    }
                    ForEach(vocab.terms, id: \.self) { term in
                        VocabRow(icon: "character.cursor.ibeam", kind: "слово") {
                            Text(term).font(.system(size: 17))
                        } onDelete: {
                            vocab.terms.removeAll { $0 == term }
                        }
                    }
                    ForEach(vocab.replacements) { r in
                        VocabRow(icon: "arrow.triangle.2.circlepath", kind: "исправление") {
                            HStack(spacing: 8) {
                                Text(r.from).foregroundStyle(.secondary)
                                Text("→").foregroundStyle(.tertiary)
                                Text(r.to)
                            }
                            .font(.system(size: 17))
                        } onDelete: {
                            vocab.replacements.removeAll { $0.id == r.id }
                        }
                    }
                    if adding {
                        SettingsRow {
                            Image(systemName: "plus").foregroundStyle(Color.accentColor).frame(width: 22)
                            TextField("Слово", text: $first, prompt: Text("Слово или имя"))
                                .textFieldStyle(.plain).font(.system(size: 16))
                                .focused($focus, equals: 1)
                                .onSubmit { second.isEmpty && !first.isEmpty ? add() : (focus = 2) }
                            Text("→").foregroundStyle(.tertiary)
                            TextField("Исправить на", text: $second, prompt: Text("исправить на (не обязательно)"))
                                .textFieldStyle(.plain).font(.system(size: 16))
                                .focused($focus, equals: 2)
                                .onSubmit { add() }
                        }
                        .onExitCommand { cancel() }
                    }
                    SettingsRow(last: true) {
                        Button {
                            if adding { add() } else { adding = true; focus = 1 }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus").frame(width: 22)
                                Text(adding ? "Добавить" : "Добавить слово или исправление").font(.system(size: 16))
                                Spacer()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        if adding {
                            Button("Отмена") { cancel() }
                                .buttonStyle(.plain).font(.system(size: 15)).foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsGroup(title: "Голосовые команды") {
                    SettingsRow(last: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.voiceCommands ? "Включены" : "Выключены").font(.system(size: 16))
                            Text("«новая строка», «запятая», «двоеточие» и другие")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        Spacer()
                        Toggle("Голосовые команды", isOn: $state.voiceCommands).toggleStyle(.switch).labelsHidden()
                    }
                    .help("Скажи: \(VoiceCommands.help)")
                }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 28)
            .frame(maxWidth: R55.column)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Словарь")
    }

    /// Второе поле пустое — новое слово; заполнено — исправление «первое → второе».
    private func add() {
        let a = first.trimmingCharacters(in: .whitespaces)
        let b = second.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty else { cancel(); return }
        if b.isEmpty {
            state.vocabulary.addTerm(a)
        } else {
            state.vocabulary.addReplacement(from: a, to: b)
        }
        first = ""
        second = ""
        focus = 1 // поле остаётся — можно сразу добавить следующее
    }

    private func cancel() {
        adding = false
        first = ""
        second = ""
    }
}

/// Строка словаря: значок, содержимое, тип справа; при наведении вместо типа — ✕
private struct VocabRow<C: View>: View {
    let icon: String
    let kind: String
    @ViewBuilder var content: C
    var onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        SettingsRow {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            content
            Spacer(minLength: 12)
            ZStack(alignment: .trailing) {
                Text(kind).font(.system(size: 13)).foregroundStyle(.tertiary).opacity(hover ? 0 : 1)
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Удалить")
                .opacity(hover ? 1 : 0)
            }
        }
        .contentShape(.rect)
        .onHover { hover = $0 }
    }
}
