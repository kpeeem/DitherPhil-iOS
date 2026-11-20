import AVFoundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private actor PhotoPreview {
    private var cached: (id: UUID, image: CIImage)?

    func draw(_ media: StudioMedia, edits: VideoEdits, pipeline: MediaPipeline) throws -> CGImage {
        let image: CIImage
        if let cached, cached.id == media.id {
            image = cached.image
        } else {
            image = try media.image(maxDimension: 1280)
            cached = (media.id, image)
        }
        try Task.checkCancellation()
        return try pipeline.previewPhoto(media, edits, source: image)
    }

    func clear() { cached = nil }
}

@MainActor
@Observable
final class Editor {
    var settings = EditSettings()
    var showsOriginal = false
    var format: ExportFormat = .png
    var quality = 0.95
    var error: String?
    var exported: StudioFile?
    private(set) var media: StudioMedia?
    private(set) var preview: CGImage?
    private(set) var loading = false
    private(set) var exporting = false
    private(set) var progress = 0.0
    private(set) var time = 0.0
    private(set) var wantsPlayback = false

    let player = AVPlayer()
    @ObservationIgnored private let renderer = PhotoPreview()
    @ObservationIgnored private var pipeline: MediaPipeline?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    var previewRequest: PreviewRequest {
        PreviewRequest(media: media?.id, settings: settings, original: showsOriginal)
    }

    struct PreviewRequest: Equatable {
        var media: UUID?
        var settings: EditSettings
        var original: Bool
    }

    isolated deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        importTask?.cancel()
        exportTask?.cancel()
    }

    func start(with initialFile: StudioFile? = nil) {
        guard pipeline == nil else { return }
        do {
            pipeline = try MediaPipeline()
            player.actionAtItemEnd = .none
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(value: 1, timescale: 5), queue: .main
            ) { [weak self] time in
                MainActor.assumeIsolated { self?.time = time.seconds.isFinite ? time.seconds : 0 }
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
            ) { [weak self] notification in
                let item = notification.object as? AVPlayerItem
                MainActor.assumeIsolated {
                    guard let self, item === self.player.currentItem else { return }
                    guard self.wantsPlayback, let item else { return }
                    Task { @MainActor in
                        let rewound = await self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                        if rewound, self.wantsPlayback, self.player.currentItem === item { self.player.play() }
                    }
                }
            }
            if let initialFile { beginImport { try await StudioMedia.load(initialFile) } }
            else { loadSample() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadSample() {
        beginImport { try .sample() }
    }

    func importPhotoLibrary(_ item: PhotosPickerItem) {
        beginImport {
            guard let imported = try await item.loadTransferable(type: ImportedFile.self) else {
                throw RenderError.invalidMedia
            }
            return try await StudioMedia.load(imported.file)
        }
    }

    func importFile(_ url: URL) {
        beginImport {
            let file = try await Task.detached(priority: .userInitiated) {
                let canAccess = url.startAccessingSecurityScopedResource()
                defer { if canAccess { url.stopAccessingSecurityScopedResource() } }
                return try StudioFile.copy(url)
            }.value
            return try await StudioMedia.load(file)
        }
    }

    private func beginImport(_ load: @escaping @MainActor () async throws -> StudioMedia) {
        guard let pipeline else { return }
        importTask?.cancel()
        setPlayback(false)
        loading = true
        importTask = Task {
            defer { if !Task.isCancelled { loading = false; importTask = nil } }
            do {
                let media = try await load()
                let playerItem = try await (media.isVideo ? pipeline.previewVideo(media) : nil)
                await renderer.clear()
                try Task.checkCancellation()
                player.replaceCurrentItem(with: playerItem)
                self.media = media
                preview = nil
                time = 0
                showsOriginal = false
                format = media.isVideo ? .hevc : .png
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    func updatePreview() async {
        guard let pipeline, let media else { return }
        let edits = VideoEdits(settings: settings, original: showsOriginal)
        pipeline.updateVideo(edits)
        do {
            if media.isVideo {
                guard !wantsPlayback else { return }
                try await Task.sleep(for: .milliseconds(48))
                await player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                try await Task.sleep(for: .milliseconds(30))
                let image = try await renderer.draw(media, edits: edits, pipeline: pipeline)
                try Task.checkCancellation()
                preview = image
            }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func seek(_ seconds: Double) {
        time = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayback() {
        setPlayback(!wantsPlayback)
    }

    func setPlayback(_ enabled: Bool) {
        wantsPlayback = enabled
        if enabled { player.play() } else { player.pause() }
    }

    func export() {
        guard let pipeline, let media, exportTask == nil else { return }
        let settings = settings
        let format = format
        let quality = quality
        setPlayback(false)
        progress = 0
        exporting = true
        exported = nil
        let report: @Sendable (Double) async -> Void = { [weak self] value in
            await self?.reportProgress(value)
        }
        exportTask = Task {
            defer { exporting = false; exportTask = nil }
            do {
                let output = try await pipeline.export(media, settings: settings, format: format,
                                                       quality: quality, progress: report)
                try Task.checkCancellation()
                exported = output
            } catch is CancellationError {
            } catch let failure {
                if !Task.isCancelled { self.error = failure.localizedDescription }
            }
        }
    }

    private func reportProgress(_ value: Double) { progress = max(progress, value) }

    func cancelExport() { exportTask?.cancel() }
}
