import AgentCore
import AppKit
import SwiftUI

/// Settings → Prompts: the system prompt's templates (SYSTEM_PROMPT.md), edited as the user's overrides in
/// `~/.kurtkode/prompts/`, each with a way back to kurtkode's default.
struct PromptSettings: View {
    @State private var names: [String] = []
    @State private var selection: String? = "intro"
    /// Unsaved text by template, so switching templates loses nothing.
    @State private var drafts: [String: String] = [:]
    @State private var confirmReset = false
    @State private var confirmResetAll = false
    @State private var askNewStyle = false
    @State private var newStyleName = ""
    @State private var failure: String?
    /// Bumped after every change on disk, to read the files again.
    @State private var generation = 0

    private var templates: PromptTemplates { PromptTemplates(overrides: [PromptTemplates.userFolder]) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(names, id: \.self) { name in
                        HStack {
                            Text(Self.label(name))
                            Spacer()
                            if drafts[name] != nil {
                                Text("unsaved").font(.caption).foregroundStyle(.orange)
                            } else if isEdited(name) {
                                Text(hasDefault(name) ? "edited" : "yours").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(name)
                    }
                }
                .frame(width: 190)
                Divider()
                if let name = selection, names.contains(name) {
                    editor(name)
                } else {
                    Text("Choose a template").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            HStack {
                Button("New Style…") { newStyleName = ""; askNewStyle = true }
                Button("Reset All to Default…") { confirmResetAll = true }
                    .disabled(!names.contains(where: { isEdited($0) && hasDefault($0) }))
                Button("Show in Finder") { showInFinder() }
                Spacer()
                Text("Applies to each session's next prompt. A project's .kurtkode/prompts/ overrides these there.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .onAppear(perform: reload)
        .alert("New prompt style", isPresented: $askNewStyle) {
            TextField("name (lowercase, digits, hyphens)", text: $newStyleName)
            Button("Create") { createStyle() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It starts as a copy of the detailed style. Choose it in Generation → System prompt.")
        }
        .alert("Couldn't save", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") {}
        } message: {
            Text(failure ?? "")
        }
        .confirmationDialog("Reset every template to kurtkode's default?", isPresented: $confirmResetAll) {
            Button("Reset All", role: .destructive) { resetAll() }
        } message: {
            Text("Your edits to the intro, the mode rules and the detailed and lean styles are removed. Styles of your own stay.")
        }
    }

    @ViewBuilder private func editor(_ name: String) -> some View {
        let current = currentText(name)
        let draft = drafts[name] ?? current
        let problem = Self.problem(draft)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.label(name)).font(.headline)
                Spacer()
                Text(status(name)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            TextEditor(text: Binding(get: { drafts[name] ?? current },
                                     set: { drafts[name] = $0 == current ? nil : $0 }))
                .font(.body.monospaced())
                .accessibilityLabel("Template text")
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            HStack {
                if hasDefault(name) {
                    Button("Reset to Default…") { confirmReset = true }.disabled(!isEdited(name))
                } else {
                    Button("Delete Style…") { confirmReset = true }
                }
                Spacer()
                Button("Revert") { drafts[name] = nil }.disabled(drafts[name] == nil)
                Button("Save") { save(name, draft) }
                    .keyboardShortcut("s")
                    .disabled(drafts[name] == nil || problem != nil)
            }
        }
        .padding(12)
        .id("\(name)-\(generation)")
        .confirmationDialog(hasDefault(name) ? "Reset \(Self.label(name)) to kurtkode's default?" : "Delete the style \(Self.label(name))?",
                            isPresented: $confirmReset) {
            Button(hasDefault(name) ? "Reset" : "Delete", role: .destructive) { reset(name) }
        } message: {
            Text("Removes \(PromptTemplates.userFolder.appending(path: name + ".md").path).")
        }
    }

    static func label(_ name: String) -> String {
        switch name {
        case "intro": return "Intro"
        case "mode": return "Mode rules"
        default: return name.hasPrefix("style-") ? "Style: " + name.dropFirst(6) : name
        }
    }

    static func problem(_ text: String) -> String? {
        do { _ = try PromptTemplate(text); return nil } catch { return "\(error)" }
    }

    private func hasDefault(_ name: String) -> Bool { templates.defaultText(name) != nil }

    private func isEdited(_ name: String) -> Bool {
        _ = generation
        return FileManager.default.fileExists(atPath: PromptTemplates.userFolder.appending(path: name + ".md").path)
    }

    private func currentText(_ name: String) -> String {
        _ = generation
        return templates.source(name)?.text ?? ""
    }

    private func status(_ name: String) -> String {
        guard isEdited(name) else { return "kurtkode's default" }
        return "~/.kurtkode/prompts/\(name).md"
    }

    private func reload() {
        names = PromptTemplates.shared + templates.styles.map { "style-" + $0 }
        if let s = selection, !names.contains(s) { selection = names.first }
        generation += 1
    }

    private func save(_ name: String, _ text: String) {
        do {
            try PromptTemplates.saveUserOverride(name, text: text)
            drafts[name] = nil
        } catch {
            failure = "\(error)"
        }
        reload()
    }

    private func reset(_ name: String) {
        do { try PromptTemplates.resetUserOverride(name) } catch { failure = "\(error)" }
        drafts[name] = nil
        reload()
    }

    private func resetAll() {
        for name in names where hasDefault(name) { reset(name) }
    }

    private func createStyle() {
        let name = newStyleName.trimmingCharacters(in: .whitespaces).lowercased()
        guard PromptTemplates.isValidName(name) else { failure = "“\(name)” isn't a usable name: use lowercase letters, digits and hyphens."; return }
        guard !names.contains("style-" + name) else { failure = "There is already a style named \(name)."; return }
        do {
            try PromptTemplates.saveUserOverride("style-" + name, text: templates.source("style-detailed")?.text ?? "{{intro}}\n\n{{mode_rules}}\n")
        } catch {
            failure = "\(error)"
        }
        reload()
        selection = "style-" + name
    }

    private func showInFinder() {
        let folder = PromptTemplates.userFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let name = selection, isEdited(name) {
            NSWorkspace.shared.activateFileViewerSelecting([folder.appending(path: name + ".md")])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }
}
