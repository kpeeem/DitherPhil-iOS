import CoreText
import SwiftUI

enum StudioStyle {
    static let radius: CGFloat = 18
    static let margin: CGFloat = 20
    static let gap: CGFloat = 10
    static let rule: CGFloat = 3

    static let paper = adaptive(0xFFFFFF, 0x18191A)
    static let stone = adaptive(0xE8E6E0, 0x232427)
    static let ink = adaptive(0x000000, 0xE8E6E0)
    static let mute = adaptive(0x676661, 0x999893)
    static let stroke = adaptive(0x020202, 0xE8E6E0)
    static let separator = ink.opacity(0.18)

    static let registeredFont: String = {
        if let url = Bundle.main.url(forResource: "KpemSans", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return "Iosevka-Aile"
    }()

    static func font(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(registeredFont, size: size, relativeTo: style)
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = rgbHex(traits.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: CGFloat(value.x), green: CGFloat(value.y), blue: CGFloat(value.z), alpha: 1)
        })
    }
}
