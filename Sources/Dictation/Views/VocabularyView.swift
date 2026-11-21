import SwiftUI

/// Свой словарь: слова и имена (подсказка модели), автозамены, голосовые команды.
struct VocabularyView: View {
    @Environment(AppState.self) private var state
    @State private var newTerm = ""
    @State private var from = ""
    @State private var to = ""

    var body: some View {
        @Bindable var state = state
        let vocab = state.vocabulary
        Form {
            SwiftUI.Section {
                HStack {
                    TextField("Слово", text: $newTerm, prompt: Text("Слово, имя или термин — например, малярка"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTerm)
                    Button("Добавить", action: addTerm)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if vocab.terms.isEmpty {
                    Text("Пока пусто. Например: малярка, штукатурка, Азамат, Excel")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)],
                              alignment: .leading, spacing: 8) {
                        ForEach(vocab.terms, id: \.self) { term in
                            HStack(spacing: 4) {
                                Text(term).lineLimit(1)
                                Button {
                                    vocab.terms.removeAll { $0 == term }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Убрать")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: .capsule)
                        }
                    }
                }
            } header: {
                Text("Слова и имена")
            } footer: {
                Text("Подсказывают модели, как писать редкие слова: имена, профессиональные термины, названия, английские слова. Можно вставить сразу несколько через запятую.")
            }

            SwiftUI.Section {
                HStack(spacing: 8) {
                    TextField("Как распознаёт", text: $from, prompt: Text("Как распознаёт"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    TextField("Как должно быть", text: $to, prompt: Text("Как должно быть"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addReplacement)
                    Button("Добавить", action: addReplacement)
                        .disabled(from.trimmingCharacters(in: .whitespaces).isEmpty
                                  || to.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if vocab.replacements.isEmpty {
                    Text("Пока пусто. Например: Майорки → малярки")
                        .foregroundStyle(.secondary)
                }
                ForEach(vocab.replacements) { r in
                    HStack(spacing: 8) {
                        Text(r.from).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                        Text(r.to).fontWeight(.medium)
                        Spacer()
                        Button {
                            vocab.replacements.removeAll { $0.id == r.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Удалить автозамену")
                    }
                }
            } header: {
                Text("Автозамены")
            } footer: {
                Text("Срабатывают после распознавания: целое слово или фраза, без учёта регистра. Проще всего — исправить запись в «Истории», приложение само предложит запомнить исправление.")
            }

            SwiftUI.Section {
                Toggle("Голосовые команды", isOn: $state.voiceCommands)
            } footer: {
                Text("Скажи: \(VoiceCommands.help).")
            }
        }
        .formStyle(.grouped)
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
