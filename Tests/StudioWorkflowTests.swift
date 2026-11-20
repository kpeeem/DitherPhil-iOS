import AVFoundation
import AppIntents
import CoreImage
import Photos
import Testing
@testable import DitherPhil

@MainActor struct StudioWorkflowTests {
    @Test func presetRoundTripAndUpdate() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = PresetLibrary(defaults: defaults)
        var settings = EditSettings()
        settings.palette = .custom
        settings.shadow = rgbHex(0x223355)
        settings.resolution = .small
        try library.save(name: " Night ", settings: settings)
        let id = try #require(library.presets.first?.id)
        settings.mix = 0.3
        try library.save(name: "night", settings: settings)
        let restored = PresetLibrary(defaults: defaults)
        #expect(restored.presets.count == 1)
        #expect(restored.presets.first?.id == id)
        #expect(restored.presets.first?.settings == settings)
        try restored.remove(at: IndexSet(integer: 0))
        #expect(PresetLibrary(defaults: defaults).presets.isEmpty)
    }

    @Test func shortcutReturnsAPlayableVideoAndPhotosAcceptsIt() async throws {
        let name = try #require(Bundle(for: WorkflowBundle.self).url(forResource: "Rotation", withExtension: "mp4"))
        let intent = RenderDitherIntent()
        intent.input = IntentFile(fileURL: name)
        let result = try await intent.perform()
        let file = try #require(result.value)
        let output = try StudioFile(extension: "mp4", name: "Rendered")
        try file.data.write(to: output.url)
        let media = try await StudioMedia.load(output)
        #expect(media.isVideo && media.duration > 0)
        try await PhotoLibrary.save(output, video: true)
    }

    @Test func playLoopsAndAcceptsEdits() async throws {
        let url = try #require(Bundle(for: WorkflowBundle.self).url(forResource: "Rotation", withExtension: "mp4"))
        let editor = Editor()
        editor.start(with: try StudioFile.copy(url))
        for _ in 0..<120 where editor.media == nil { try await Task.sleep(for: .milliseconds(50)) }
        let media = try #require(editor.media)
        let item = try #require(editor.player.currentItem)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        editor.player.isMuted = true
        editor.setPlayback(true)
        defer { editor.setPlayback(false); item.remove(output) }
        var previous = 0.0
        var looped = false
        var monochrome = false
        var colored = false
        for _ in 0..<250 {
            try await Task.sleep(for: .milliseconds(40))
            let time = editor.player.currentTime()
            let seconds = time.seconds
            if previous - seconds > media.duration * 0.4 { looped = true }
            previous = seconds
            if output.hasNewPixelBuffer(forItemTime: time),
               let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                let hasColor = Self.hasColor(buffer)
                if !monochrome && !hasColor {
                    monochrome = true
                    editor.settings.mix = 0
                    await editor.updatePreview()
                } else if monochrome && hasColor { colored = true }
            }
            if looped && colored { break }
        }
        #expect(looped)
        #expect(monochrome && colored)
        #expect(editor.wantsPlayback && editor.player.currentItem === item)
    }

    private static func hasColor(_ buffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let bytes = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return false }
        for y in stride(from: 0, to: CVPixelBufferGetHeight(buffer), by: 12) {
            for x in stride(from: 0, to: CVPixelBufferGetWidth(buffer), by: 12) {
                let i = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                if abs(Int(bytes[i]) - Int(bytes[i + 2])) > 50 { return true }
            }
        }
        return false
    }
}

private final class WorkflowBundle: NSObject {}
