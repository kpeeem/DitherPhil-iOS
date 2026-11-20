import CoreGraphics
import SwiftUI

enum Algorithm: Int, CaseIterable, Identifiable, Codable, Sendable {
    case threshold, bayer2, bayer4, bayer8, stipple, atkinson, floydSteinberg, sierraLite

    var id: Self { self }

    var name: LocalizedStringKey {
        switch self {
        case .threshold: "Threshold"
        case .bayer2: "Bayer 2 × 2"
        case .bayer4: "Bayer 4 × 4"
        case .bayer8: "Bayer 8 × 8"
        case .stipple: "Stipple"
        case .atkinson: "Atkinson"
        case .floydSteinberg: "Floyd–Steinberg"
        case .sierraLite: "Sierra Lite"
        }
    }

    var diffusesError: Bool { rawValue >= Self.atkinson.rawValue }
}

enum Palette: Int, CaseIterable, Identifiable, Codable, Sendable {
    case grayscale, rgb, paper, handheld, amber, custom

    var id: Self { self }

    var name: LocalizedStringKey {
        switch self {
        case .grayscale: "Grayscale"
        case .rgb: "Source colors"
        case .paper: "Paper"
        case .handheld: "Handheld"
        case .amber: "Amber"
        case .custom: "Custom"
        }
    }

    var colors: [SIMD3<Float>] {
        switch self {
        case .grayscale, .rgb: []
        case .paper: [rgbHex(0x171817), rgbHex(0xE8E6E0)]
        case .handheld: [rgbHex(0x131B18), rgbHex(0x425747), rgbHex(0x849477), rgbHex(0xDFE6B4)]
        case .amber: [rgbHex(0x221610), rgbHex(0x73421D), rgbHex(0xC48343), rgbHex(0xFFD699)]
        case .custom: []
        }
    }
}

func rgbHex(_ hex: UInt32) -> SIMD3<Float> {
    SIMD3(Float((hex >> 16) & 255), Float((hex >> 8) & 255), Float(hex & 255)) / 255
}

struct EditSettings: Equatable, Codable, Sendable {
    var algorithm: Algorithm = .bayer4
    var palette: Palette = .paper
    var cell = 4.0
    var levels = 4.0
    var strength = 0.9
    var mix = 1.0
    var exposure = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var warmth = 0.0
    var invert = false
    var shadow = rgbHex(0x171817)
    var highlight = rgbHex(0xE8E6E0)
    var resolution: OutputResolution = .original

    var colors: [SIMD3<Float>] { palette == .custom ? [shadow, highlight] : palette.colors }

    mutating func resetColor() {
        exposure = 0
        contrast = 1
        saturation = 1
        warmth = 0
        invert = false
    }
}

enum OutputResolution: Int, CaseIterable, Identifiable, Codable, Sendable {
    case original = 0
    case ultraHD = 3840
    case fullHD = 1920
    case hd = 1280
    case small = 640

    var id: Self { self }

    var name: LocalizedStringKey {
        switch self {
        case .original: "Original"
        case .ultraHD: "4K · 3840 px"
        case .fullHD: "1920 px"
        case .hd: "1280 px"
        case .small: "640 px"
        }
    }

    func size(for source: CGSize, video: Bool) -> CGSize {
        let limit = rawValue == 0 ? max(source.width, source.height) : CGFloat(rawValue)
        let scale = min(1, limit / max(1, source.width, source.height))
        let alignment = video ? 2.0 : 1.0
        return CGSize(
            width: max(alignment, (source.width * scale / alignment).rounded(.down) * alignment),
            height: max(alignment, (source.height * scale / alignment).rounded(.down) * alignment)
        )
    }
}

enum ExportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case png, jpeg, heic, hevc, h264

    var id: Self { self }

    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .hevc: "HEVC"
        case .h264: "H.264"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .hevc, .h264: "mp4"
        }
    }
}
