import Observation
import SwiftUI

struct StudioPreset: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let settings: EditSettings
}

@MainActor @Observable
final class PresetLibrary {
    private(set) var presets: [StudioPreset]
    private let defaults: UserDefaults
    private static let key = "studio.presets.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([StudioPreset].self, from: $0) } ?? []
    }

    func save(name: String, settings: EditSettings) throws {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var next = presets
        if let index = next.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
            next[index] = StudioPreset(id: next[index].id, name: title, settings: settings)
        } else {
            next.append(StudioPreset(id: UUID(), name: title, settings: settings))
        }
        try persist(next)
    }

    func remove(at indices: IndexSet) throws {
        var next = presets
        next.remove(atOffsets: indices)
        try persist(next)
    }

    private func persist(_ next: [StudioPreset]) throws {
        defaults.set(try JSONEncoder().encode(next), forKey: Self.key)
        presets = next
    }
}

struct StudioLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var library = PresetLibrary()
    @State private var name = ""
    @State private var error: String?
    @AppStorage("studio.appearance") private var appearance = "dark"
    @AppStorage("studio.language") private var language = "system"
    @Bindable var editor: Editor

    var body: some View {
        NavigationStack {
            Form {
                Section("Save preset") {
                    TextField("Preset name", text: $name)
                    Button(library.presets.contains { $0.name.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame } ? "Update preset" : "Save preset") {
                        do {
                            try library.save(name: name, settings: editor.settings)
                            name = ""
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !library.presets.isEmpty {
                    Section("My presets") {
                        ForEach(library.presets) { preset in
                            Button(preset.name) { editor.settings = preset.settings; dismiss() }
                        }
                        .onDelete { indices in
                            do { try library.remove(at: indices) } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                Section {
                    Picker("Appearance", selection: $appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("System").tag("system")
                    }
                    Picker("Language", selection: $language) {
                        Text("System").tag("system")
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "Русский").tag("ru")
                        Text(verbatim: "日本語").tag("ja")
                    }
                    .accessibilityIdentifier("studio-language")
                }
            }
            .navigationTitle("Presets & settings")
            .toolbar { Button("Done") { dismiss() } }
            .alert("DitherPhil", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
