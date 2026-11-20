import AVFoundation
import CoreImage
import ImageIO
import Testing
@testable import DitherPhil

struct MediaPipelineTests {
    @Test func orderedAndDiffusionMethodsProducePalettePixels() throws {
        let renderer = try DitherRenderer()
        let width = 64
        let height = 64
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        let input = CIImage(color: CIColor(red: 0.47, green: 0.47, blue: 0.47)).cropped(to: extent)
        var settings = EditSettings()
        settings.cell = 1
        settings.palette = .grayscale
        settings.levels = 2
        for algorithm in Algorithm.allCases {
            settings.algorithm = algorithm
            let result = try renderer.render(input, settings: settings, sourceSize: extent.size, outputSize: extent.size)
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            renderer.context.render(result, toBitmap: &bytes, rowBytes: width * 4, bounds: extent,
                                    format: .RGBA8, colorSpace: renderer.colorSpace)
            let values = Set(stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] })
            #expect(values == (algorithm == .threshold ? [0] : [0, 255]))
        }
    }

    @Test func pngRetainsRequestedDimensionsAndAlpha() async throws {
        let extent = CGRect(x: 0, y: 0, width: 800, height: 480)
        let input = CIImage(color: CIColor(red: 0.45, green: 0.3, blue: 0.25, alpha: 0.5)).cropped(to: extent)
        let media = StudioMedia(content: .image(input), size: extent.size, duration: 0)
        let pipeline = try MediaPipeline()
        var settings = EditSettings()
        settings.resolution = .small
        settings.algorithm = .atkinson
        let output = try await pipeline.export(media, settings: settings, format: .png, quality: 1) { _ in }
        let source = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 640)
        #expect(image.height == 384)
        #expect(image.alphaInfo == .last || image.alphaInfo == .premultipliedLast)
        let context = pipeline.renderer.context
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(CIImage(cgImage: image), toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 6, y: 6, width: 1, height: 1),
                       format: .RGBA8, colorSpace: pipeline.renderer.colorSpace)
        #expect((126...129).contains(pixel[3]))
    }

    @Test func photoImportAndLossyFormats() async throws {
        let pipeline = try MediaPipeline()
        let demo = try StudioMedia.sample()
        let original = try await pipeline.export(demo, settings: EditSettings(), format: .png, quality: 1) { _ in }
        let imported = try await StudioMedia.load(original)
        #expect(imported.size == demo.size)
        var settings = EditSettings()
        settings.resolution = .small
        for format in [ExportFormat.jpeg, .heic] {
            let file = try await pipeline.export(imported, settings: settings, format: format, quality: 0.95) { _ in }
            let source = try #require(CGImageSourceCreateWithURL(file.url as CFURL, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(decoded.width == 640 && decoded.height == 640)
        }
    }

    @Test func videoPreviewAndExportPreserveOrientationAndAudio() async throws {
        let fixture = try #require(Bundle(for: FixtureBundle.self).url(forResource: "Rotation", withExtension: "mp4"))
        let media = try await StudioMedia.load(StudioFile.copy(fixture))
        #expect(media.isVideo)
        #expect(media.size == CGSize(width: 480, height: 800))
        let pipeline = try MediaPipeline()
        let item = try await pipeline.previewVideo(media)
        #expect(item.videoComposition?.renderSize == CGSize(width: 480, height: 800))
        var settings = EditSettings()
        settings.resolution = .small
        for format in [ExportFormat.h264, .hevc] {
            let file = try await pipeline.export(media, settings: settings, format: format, quality: 1) { _ in }
            let rendered = try await StudioMedia.load(file)
            #expect(rendered.size == CGSize(width: 384, height: 640))
            #expect(abs(rendered.duration - media.duration) < 0.12)
            let asset = AVURLAsset(url: file.url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            #expect(tracks.count == 1)
            let generator = AVAssetImageGenerator(asset: asset)
            let frame = try await generator.image(at: .zero).image
            let ci = CIImage(cgImage: frame).cropped(to: CGRect(x: 50, y: 50, width: 100, height: 100))
            var bytes = [UInt8](repeating: 0, count: 100 * 100 * 4)
            pipeline.renderer.context.render(ci, toBitmap: &bytes, rowBytes: 400, bounds: ci.extent,
                                             format: .RGBA8, colorSpace: pipeline.renderer.colorSpace)
            let paperPixels = stride(from: 0, to: bytes.count, by: 4).filter {
                abs(Int(bytes[$0]) - Int(bytes[$0 + 1])) < 18 && abs(Int(bytes[$0 + 1]) - Int(bytes[$0 + 2])) < 18
            }.count
            #expect(paperPixels > 9_000)
        }
    }
}

private final class FixtureBundle: NSObject {}
