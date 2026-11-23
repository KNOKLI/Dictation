import SwiftUI

/// Свой словарь: слова и имена (подсказка модели), автозамены, голосовые команды.
/// 2026-11-24 (Камиль): V7 «Герой и полки» — сверху синяя карточка с объяснением и счётчиками,
/// ниже три карточки (слова «таблетками», исправления, голосовые команды) и полоса «как это работает».
/// Прежний R5.5 — `_backup-2026-11-24-V7/VocabularyView.swift`.
struct VocabularyView: View {
    @Environment(AppState.self) private var state
    @State private var addingTerm = false
    @State private var addingSwap = false
    @State private var newTerm = ""
    @State private var from = ""
    @State private var to = ""
    @FocusState private var focus: Int?

    /// «новая строка», «запятая»… — из подсказки голосовых команд
    private static let commands: [String] = VoiceCommands.help
        .components(separatedBy: ", ")
        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "«» ")) }

    var body: some View {
        @Bindable var state = state
        let vocab = state.vocabulary
        VStack(alignment: .leading, spacing: V7.gap) {
            HeroCard(symbol: "character.book.closed", height: 200) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Словарь учит Dictation твоим словам").font(.system(size: 30, weight: .bold))
                    Text("Имена и термины пишутся правильно. Ошибки исправляются сами.")
                        .font(.system(size: 15.5)).foregroundStyle(.secondary)
                    HStack(spacing: 30) {
                        count(vocab.terms.count, RU.plural(vocab.terms.count, "слово", "слова", "слов"))
                        count(vocab.replacements.count, RU.plural(vocab.replacements.count, "исправление", "исправления", "исправлений"))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(state.voiceCommands ? "вкл." : "выкл.").font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("голосовые команды").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }
            }

            HStack(spacing: V7.gap) {
                ShelfCard(title: "Мои слова", icon: "character.cursor.ibeam") {
                    ScrollView {
                        ChipFlow {
                            ForEach(vocab.terms, id: \.self) { term in
                                Chip(text: term) { vocab.terms.removeAll { $0 == term } }
                            }
                            if !addingTerm {
                                Button { addingTerm = true; focus = 1 } label: {
                                    Text("+ Добавить").font(.system(size: 14, weight: .medium))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.14), in: .capsule)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.accentColor)
                            }
                        }
                        if addingTerm {
                            HStack(spacing: 8) {
                                TextField("Слово", text: $newTerm, prompt: Text("Слово или имя — Return"))
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focus, equals: 1)
                                    .onSubmit { addTerm() }
                                    .onExitCommand { addingTerm = false; newTerm = "" }
                                Button("Готово") { addTerm(); addingTerm = false }
                                    .buttonStyle(.glass)
                            }
                            .padding(.top, 10)
                        }
                        if vocab.terms.isEmpty && !addingTerm {
                            Text("Например: малярка, Азамат, Excel").font(.system(size: 13)).foregroundStyle(.tertiary).padding(.top, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .scrollIndicators(.never)
                }

                ShelfCard(title: "Исправления", icon: "arrow.triangle.2.circlepath") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(vocab.replacements) { r in
                                SwapRow(from: r.from, to: r.to) { vocab.replacements.removeAll { $0.id == r.id } }
                            }
                            if vocab.replacements.isEmpty && !addingSwap {
                                Text("Например: Майорки → малярки").font(.system(size: 13)).foregroundStyle(.tertiary)
                            }
                            if addingSwap {
                                HStack(spacing: 8) {
                                    TextField("Как распознаёт", text: $from, prompt: Text("Как распознаёт"))
                                        .textFieldStyle(.roundedBorder).focused($focus, equals: 2)
                                        .onSubmit { focus = 3 }
                                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                                    TextField("Как должно быть", text: $to, prompt: Text("Как должно быть"))
                                        .textFieldStyle(.roundedBorder).focused($focus, equals: 3)
                                        .onSubmit { addSwap() }
                                }
                                .onExitCommand { cancelSwap() }
                                HStack {
                                    Button("Добавить") { addSwap() }.buttonStyle(.glassProminent)
                                    Button("Отмена") { cancelSwap() }.buttonStyle(.glass)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.never)
                    if !addingSwap {
                        Button("+ Добавить исправление") { addingSwap = true; focus = 2 }
                            .buttonStyle(.plain)
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                ShelfCard(title: "Голосовые команды", icon: "text.bubble") {
                    HStack {
                        Text(state.voiceCommands ? "Включены" : "Выключены").font(.system(size: 15))
                        Spacer()
                        Toggle("Голосовые команды", isOn: $state.voiceCommands).toggleStyle(.switch).labelsHidden()
                    }
                    ScrollView {
                        ChipFlow { ForEach(Self.commands, id: \.self) { Chip(text: $0) } }
                    }
                    .scrollIndicators(.never)
                    .opacity(state.voiceCommands ? 1 : 0.45)
                    .help("Скажи: \(VoiceCommands.help)")
                }
            }
            .frame(minHeight: 200, maxHeight: 330)

            HStack(spacing: V7.gap) {
                info("character.cursor.ibeam", "Слова",
                     "Имена, термины и названия, которые часто говоришь. Модель будет их узнавать и писать правильно.",
                     "Например: Азамат, Excel, котлован")
                info("arrow.triangle.2.circlepath", "Исправления",
                     "Если модель упорно пишет не то слово — оно само заменится на нужное после распознавания.",
                     "Например: Майорки → малярки")
                info("pencil", "Правка в Истории",
                     "Исправил ошибку в записи — я предложу запомнить исправление, чтобы больше её не было.",
                     "Двойной клик по записи — изменить")
            }
            .frame(minHeight: 150, maxHeight: .infinity)
        }
        .padding(.horizontal, V7.pad).padding(.top, 8).padding(.bottom, V7.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Словарь")
    }

    private func count(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(RU.number(n)).font(.system(size: 30, weight: .bold, design: .rounded)).contentTransition(.numericText())
            Text(label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private func info(_ icon: String, _ title: String, _ sub: String, _ example: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 0)
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(sub).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(example).font(.system(size: 13)).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: .rect(cornerRadius: V7.radius, style: .continuous))
    }

    private func addTerm() {
        state.vocabulary.addTerm(newTerm)
        newTerm = ""
        focus = 1
    }

    private func addSwap() {
        guard !from.trimmingCharacters(in: .whitespaces).isEmpty,
              !to.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state.vocabulary.addReplacement(from: from, to: to)
        cancelSwap()
    }

    private func cancelSwap() {
        addingSwap = false
        from = ""
        to = ""
    }
}

/// Исправление: «было» зачёркнуто → «стало», при наведении ✕
private struct SwapRow: View {
    let from: String
    let to: String
    var onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Text(from).foregroundStyle(.secondary).strikethrough(color: .secondary)
            Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(.tertiary)
            Text(to)
            Spacer(minLength: 8)
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Удалить")
            .opacity(hover ? 1 : 0)
        }
        .font(.system(size: 17))
        .contentShape(.rect)
        .onHover { hover = $0 }
    }
}
