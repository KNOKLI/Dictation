import SwiftUI

/// Правка текста записи. После сохранения предлагает запомнить исправления как автозамены.
struct EntryEditor: View {
    @Environment(AppState.self) private var state
    let entryID: DictationEntry.ID
    var onDone: () -> Void = {}

    @State private var draft = ""
    @State private var original = ""
    @State private var suggestions: [Suggestion] = []
    @State private var saved = false

    struct Suggestion: Identifiable {
        let id = UUID()
        let from: String
        let to: String
        var remembered = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if saved && !suggestions.isEmpty {
                suggestionsBox
            } else {
                TextEditor(text: $draft)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 120)
                    .background(.background, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                HStack {
                    Button("Отмена", action: onDone)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Сохранить", action: save)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft == original)
                }
                Text("⌘Return — сохранить")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            original = state.history.entry(entryID)?.text ?? ""
            draft = original
        }
    }

    private var suggestionsBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Сохранено. Запомнить исправления?", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("Тогда в следующий раз они исправятся сами.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach($suggestions) { $s in
                HStack(spacing: 8) {
                    Text(s.from).foregroundStyle(.secondary).strikethrough()
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                    Text(s.to).fontWeight(.medium)
                    Spacer()
                    if s.remembered {
                        Label("Запомнено", systemImage: "checkmark").labelStyle(.titleAndIcon)
                            .font(.callout).foregroundStyle(.green)
                    } else {
                        Button("Запомнить") {
                            state.vocabulary.addReplacement(from: s.from, to: s.to)
                            s.remembered = true
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Spacer()
                Button("Готово", action: onDone)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 12))
    }

    private func save() {
        let before = state.history.entry(entryID)?.text ?? original
        state.history.update(entryID, text: draft)
        let after = state.history.entry(entryID)?.text ?? draft
        suggestions = WordDiff.pairs(old: before, new: after)
            .filter { !state.vocabulary.hasReplacement(from: $0.from) }
            .map { Suggestion(from: $0.from, to: $0.to) }
        saved = true
        if suggestions.isEmpty { onDone() }
    }
}
