import AVFoundation
import CoreImage
import CoreTransferable
import ImageIO
import Synchronization
import UniformTypeIdentifiers
import UIKit

final class StudioFile: Sendable {
    let url: URL
    private let folder: URL

    init(extension fileExtension: String, name: String) throws {
        folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        url = folder.appending(path: name, directoryHint: .notDirectory).appendingPathExtension(fileExtension)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static func copy(_ url: URL) throws -> StudioFile {
        let file = try StudioFile(extension: url.pathExtension, name: "Source")
        try FileManager.default.copyItem(at: url, to: file.url)
        return file
    }

    deinit { try? FileManager.default.removeItem(at: folder) }
}

struct ImportedFile: Transferable {
    let file: StudioFile

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            Self(file: try StudioFile.copy(received.file))
        }
        FileRepresentation(importedContentType: .image) { received in
            Self(file: try StudioFile.copy(received.file))
        }
    }
}

struct StudioMedia: Identifiable, Sendable {
    enum Content: Sendable {
        case image(CIImage)
        case photo(StudioFile)
        case video(StudioFile)
    }

    let id = UUID()
    let content: Content
    let size: CGSize
    let duration: Double

    var isVideo: Bool {
        if case .video = content { return true }
        return false
    }

    static func sample() throws -> StudioMedia {
        guard let image = CIImage(image: UIImage(resource: .studioSample)) else { throw RenderError.invalidMedia }
        return StudioMedia(content: .image(image), size: image.extent.size, duration: 0)
    }

    static func load(_ file: StudioFile) async throws -> StudioMedia {
        if let source = CGImageSourceCreateWithURL(file.url as CFURL, nil),
           let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = metadata[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = metadata[kCGImagePropertyPixelHeight] as? CGFloat {
            let orientation = (metadata[kCGImagePropertyOrientation] as? Int) ?? 1
            let size = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
            guard size.width > 0, size.height > 0 else { throw RenderError.invalidMedia }
            return StudioMedia(content: .photo(file), size: size, duration: 0)
        }
        let asset = AVURLAsset(url: file.url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RenderError.invalidMedia
        }
        async let duration = asset.load(.duration)
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let rectangle = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let seconds = try await duration.seconds
        guard rectangle.width > 0, rectangle.height > 0, seconds.isFinite, seconds > 0 else {
            throw RenderError.invalidMedia
        }
        return StudioMedia(content: .video(file), size: rectangle.size, duration: seconds)
    }

    func image(maxDimension: Int) throws -> CIImage {
        switch content {
        case .image(let image): return image
        case .photo(let file):
            let decoding = [kCGImageSourceShouldCache: false] as CFDictionary
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(file.url as CFURL, decoding),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                throw RenderError.invalidMedia
            }
            return CIImage(cgImage: image)
        case .video: throw RenderError.invalidMedia
        }
    }
}

struct VideoEdits: Sendable {
    var settings: EditSettings
    var original: Bool
}

final class MediaPipeline: Sendable {
    let renderer: DitherRenderer
    private let videoEdits = Mutex(VideoEdits(settings: EditSettings(), original: false))

    init() throws { renderer = try DitherRenderer() }

    func updateVideo(_ edits: VideoEdits) {
        videoEdits.withLock { $0 = edits }
    }

    func previewVideo(_ media: StudioMedia) async throws -> AVPlayerItem {
        guard case .video(let file) = media.content else { throw RenderError.invalidMedia }
        let asset = AVURLAsset(url: file.url)
        let composition = try await videoComposition(asset: asset, preview: true, trackSize: media.size) {
            self.videoEdits.withLock { $0 }
        }
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = composition
        item.seekingWaitsForVideoCompositionRendering = true
        return item
    }

    func previewPhoto(_ media: StudioMedia, _ edits: VideoEdits, source: CIImage) throws -> CGImage {
        let size = OutputResolution.hd.size(for: media.size, video: false)
        let result = try renderer.render(source, settings: edits.settings,
                                         sourceSize: edits.settings.resolution.size(for: media.size, video: false),
                                         outputSize: size, original: edits.original)
        guard let image = renderer.context.createCGImage(result, from: result.extent,
                                                        format: .RGBA8, colorSpace: renderer.colorSpace) else {
            throw RenderError.renderingFailed
        }
        return image
    }

    @concurrent func export(
        _ media: StudioMedia,
        settings: EditSettings,
        format: ExportFormat,
        quality: Double,
        progress: @Sendable @escaping (Double) async -> Void
    ) async throws -> StudioFile {
        let file = try StudioFile(extension: format.fileExtension, name: "DitherPhil")
        try Task.checkCancellation()
        switch media.content {
        case .video(let input):
            let asset = AVURLAsset(url: input.url)
            let preset = format == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
            guard let session = AVAssetExportSession(asset: asset, presetName: preset),
                  session.supportedFileTypes.contains(.mp4) else { throw RenderError.unsupportedExport }
            session.videoComposition = try await videoComposition(asset: asset, preview: false, trackSize: media.size) {
                VideoEdits(settings: settings, original: false)
            }
            session.metadata = []
            let states = session.states(updateInterval: 0.15)
            let updates = Task {
                for await state in states {
                    if case .exporting(let value) = state { await progress(value.fractionCompleted) }
                }
            }
            defer { updates.cancel() }
            try await session.export(to: file.url, as: .mp4)
        case .photo, .image:
            let size = settings.resolution.size(for: media.size, video: false)
            let source = try media.image(maxDimension: Int(max(size.width, size.height)))
            let image = try renderer.render(source, settings: settings, sourceSize: size, outputSize: size)
            let context = renderer.context
            let space = renderer.colorSpace
            let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
            switch format {
            case .png:
                try context.writePNGRepresentation(of: image, to: file.url, format: .RGBA8, colorSpace: space)
            case .jpeg, .heic:
                let flat = image.composited(over: CIImage(color: .white).cropped(to: image.extent))
                if format == .jpeg {
                    try context.writeJPEGRepresentation(of: flat, to: file.url, colorSpace: space, options: options)
                } else {
                    try context.writeHEIFRepresentation(of: flat, to: file.url, format: .RGBA8, colorSpace: space, options: options)
                }
            case .h264, .hevc: throw RenderError.unsupportedExport
            }
        }
        try Task.checkCancellation()
        await progress(1)
        return file
    }

    private func videoComposition(
        asset: AVURLAsset,
        preview: Bool,
        trackSize: CGSize,
        edits: @escaping @Sendable () -> VideoEdits
    ) async throws -> AVVideoComposition {
        let renderSize = preview
            ? OutputResolution.hd.size(for: trackSize, video: true)
            : edits().settings.resolution.size(for: trackSize, video: true)
        let generated = try await AVVideoComposition(applyingFiltersTo: asset) { frame in
            let state = edits()
            let sourceSize = state.settings.resolution.size(for: trackSize, video: true)
            let image = try self.renderer.render(frame.sourceImage, settings: state.settings,
                                                 sourceSize: sourceSize, outputSize: frame.renderSize,
                                                 original: state.original)
            return AVCIImageFilteringResult(resultImage: image, ciContext: self.renderer.context)
        }
        guard let composition = generated.mutableCopy() as? AVMutableVideoComposition else {
            throw RenderError.renderingFailed
        }
        composition.renderSize = renderSize
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        if preview {
            composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
            composition.frameDuration = CMTime(value: 1, timescale: 30)
        }
        return composition
    }
}
