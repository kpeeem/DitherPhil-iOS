import AppIntents
import UniformTypeIdentifiers

struct PresetNames: DynamicOptionsProvider {
    @MainActor func results() async throws -> [String] { PresetLibrary().presets.map(\.name) }
}

struct RenderDitherIntent: AppIntent {
    static let title: LocalizedStringResource = "Dither media"
    static let description = IntentDescription("Render a photo or video and return the processed file.")
    @Parameter(title: "Media", supportedContentTypes: [.image, .movie]) var input: IntentFile
    @Parameter(title: "Preset", optionsProvider: PresetNames()) var preset: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Dither \(\.$input)") { \.$preset }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let settings = try await resolvedSettings()
        let file = try StudioFile(extension: (input.filename as NSString).pathExtension, name: "Source")
        if let url = input.fileURL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: url, to: file.url)
        } else { try input.data.write(to: file.url) }
        let media = try await StudioMedia.load(file)
        let output = try await MediaPipeline().export(media, settings: settings, format: media.isVideo ? .hevc : .png, quality: 1) { _ in }
        let data = try Data(contentsOf: output.url, options: .alwaysMapped)
        return .result(value: IntentFile(data: data, filename: output.url.lastPathComponent, type: media.isVideo ? .mpeg4Movie : .png))
    }

    @MainActor private func resolvedSettings() throws -> EditSettings {
        guard let preset else { return EditSettings() }
        guard let saved = PresetLibrary().presets.first(where: { $0.name == preset }) else {
            throw $preset.needsValueError("Choose an existing preset.")
        }
        return saved.settings
    }
}

struct StudioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RenderDitherIntent(), phrases: ["Dither media with \(.applicationName)"],
                    shortTitle: "Dither media", systemImageName: "circle.lefthalf.filled")
    }
}
