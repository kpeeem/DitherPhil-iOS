import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import simd

enum RenderError: LocalizedError {
    case invalidMedia, renderingFailed, metalUnavailable, unsupportedExport

    var errorDescription: String? {
        switch self {
        case .invalidMedia: String(localized: "This file could not be opened.")
        case .renderingFailed: String(localized: "The media could not be rendered.")
        case .metalUnavailable: String(localized: "The dithering engine is unavailable.")
        case .unsupportedExport: String(localized: "This format is unavailable for the chosen media.")
        }
    }
}

final class DitherRenderer: Sendable {
    let context: CIContext
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let kernel: CIColorKernel

    init() throws {
        guard let location = Bundle.main.url(forResource: "Dither", withExtension: "metallib") else {
            throw RenderError.metalUnavailable
        }
        kernel = try CIColorKernel(functionName: "dither", fromMetalLibraryData: Data(contentsOf: location))
        let options: [CIContextOption: Any] = [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace,
            .cacheIntermediates: false,
            .name: "DitherPhil"
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    func render(
        _ source: CIImage,
        settings: EditSettings,
        sourceSize: CGSize,
        outputSize: CGSize,
        original: Bool = false
    ) throws -> CIImage {
        let output = CGRect(origin: .zero, size: outputSize)
        let input = resize(source, to: outputSize)
        guard !original else { return input }
        var adjusted = input
        if settings.exposure != 0 {
            adjusted = adjusted.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: settings.exposure])
        }
        if settings.contrast != 1 || settings.saturation != 1 {
            adjusted = adjusted.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: settings.contrast, kCIInputSaturationKey: settings.saturation
            ])
        }
        if settings.warmth != 0 {
            let offset = settings.warmth * 0.15
            adjusted = adjusted.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1 + offset, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 - offset, w: 0)
            ])
        }
        if settings.invert { adjusted = adjusted.applyingFilter("CIColorInvert") }
        guard settings.mix > 0 else { return adjusted.cropped(to: output) }

        let grid = CGSize(
            width: max(1, min(output.width, (sourceSize.width / settings.cell).rounded(.up))),
            height: max(1, min(output.height, (sourceSize.height / settings.cell).rounded(.up)))
        )
        let reduced = resize(adjusted.cropped(to: output), to: grid)
        let quantized: CIImage
        if settings.algorithm.diffusesError {
            quantized = try diffuse(reduced, settings: settings)
        } else {
            let colors = settings.colors
            let args = (0..<4).map { index -> CIVector in
                let color = colors.indices.contains(index) ? colors[index] : SIMD3<Float>.zero
                return CIVector(x: CGFloat(color.x), y: CGFloat(color.y), z: CGFloat(color.z), w: 1)
            }
            let mode = settings.palette == .rgb ? 1 : colors.isEmpty ? 0 : 2
            guard let image = kernel.apply(extent: reduced.extent, arguments: [
                reduced, Float(settings.algorithm.rawValue), Float(settings.strength),
                Float(colors.isEmpty ? Int(settings.levels) - 1 : colors.count - 1),
                Float(mode), args[0], args[1], args[2], args[3]
            ]) else { throw RenderError.renderingFailed }
            quantized = image
        }
        let pixelated = quantized.samplingNearest().transformed(by: CGAffineTransform(
            scaleX: output.width / grid.width, y: output.height / grid.height
        )).cropped(to: output)
        guard settings.mix < 1 else { return pixelated }
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = adjusted
        dissolve.targetImage = pixelated
        dissolve.time = Float(settings.mix)
        return (dissolve.outputImage ?? pixelated).cropped(to: output)
    }

    func resize(_ image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        let base = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let x = size.width / extent.width
        let y = size.height / extent.height
        let output = CGRect(origin: .zero, size: size)
        guard x != 1 || y != 1 else { return base.cropped(to: output) }
        return base.clampedToExtent().applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: y, kCIInputAspectRatioKey: x / y
        ]).cropped(to: output)
    }

    private func diffuse(_ image: CIImage, settings: EditSettings) throws -> CIImage {
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        let rowBytes = width * 4
        var bytes = Data(count: rowBytes * height)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: rowBytes,
                           bounds: image.extent, format: .RGBA8, colorSpace: colorSpace)
        }
        let colors = settings.colors
        let steps = Float((colors.isEmpty ? Int(settings.levels) : colors.count) - 1)
        let luma = SIMD3<Float>(0.2126, 0.7152, 0.0722)
        let stride = width + 4
        let strength = Float(settings.strength)
        let isRGB = settings.palette == .rgb
        let taps: [(x: Int, y: Int, weight: Float)]
        switch settings.algorithm {
        case .atkinson:
            taps = [(1, 0, 1/8), (2, 0, 1/8), (-1, 1, 1/8), (0, 1, 1/8), (1, 1, 1/8), (0, 2, 1/8)]
        case .floydSteinberg:
            taps = [(1, 0, 7/16), (-1, 1, 3/16), (0, 1, 5/16), (1, 1, 1/16)]
        default:
            taps = [(1, 0, 1/2), (-1, 1, 1/4), (0, 1, 1/4)]
        }

        // Core Image bitmaps start at the bottom. Diffuse from the visible top edge.
        try bytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let pixels = raw.bindMemory(to: UInt8.self)
            var errors = [SIMD3<Float>](repeating: .zero, count: 3 * stride)
            for row in 0..<height {
                if row.isMultiple(of: 32) { try Task.checkCancellation() }
                let pixelRow = (height - row - 1) * rowBytes
                let currentRow = (row % 3) * stride + 2
                let reversed = !row.isMultiple(of: 2)
                let direction = reversed ? -1 : 1
                for column in 0..<width {
                    let x = reversed ? width - column - 1 : column
                    let p = pixelRow + 4 * x
                    let alpha = Float(pixels[p + 3])
                    let incoming = errors[currentRow + x]
                    errors[currentRow + x] = .zero
                    guard alpha > 0 else { continue }

                    let source = SIMD3(Float(pixels[p]), Float(pixels[p + 1]), Float(pixels[p + 2])) / alpha
                    let input = isRGB ? source : SIMD3(repeating: simd_dot(source, luma))
                    let value = simd_clamp(input + incoming, .zero, SIMD3(repeating: 1))
                    let scaled = value * steps
                    let quantized = SIMD3(scaled.x.rounded(), scaled.y.rounded(), scaled.z.rounded()) / steps
                    let result = colors.isEmpty ? quantized : colors[Int((quantized.x * steps).rounded())]
                    let error = (value - quantized) * strength
                    for tap in taps {
                        let slot = ((row + tap.y) % 3) * stride + 2 + x + tap.x * direction
                        errors[slot] += error * tap.weight
                    }
                    let premultiplied = result * alpha
                    pixels[p] = UInt8(premultiplied.x.rounded())
                    pixels[p + 1] = UInt8(premultiplied.y.rounded())
                    pixels[p + 2] = UInt8(premultiplied.z.rounded())
                }
            }
        }
        return CIImage(bitmapData: bytes, bytesPerRow: rowBytes, size: image.extent.size,
                       format: .RGBA8, colorSpace: colorSpace)
    }
}
