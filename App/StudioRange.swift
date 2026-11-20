import SwiftUI
import UIKit

struct StudioRange: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let title: LocalizedStringResource
    let display: (Double) -> String
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Control, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? max(72, uiView.intrinsicContentSize.width)
        return CGSize(width: width, height: 44)
    }

    func makeUIView(context: Context) -> Control {
        let control = Control()
        control.isContinuous = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.addTarget(context.coordinator, action: #selector(Coordinator.change(_:)), for: .valueChanged)
        control.addTarget(context.coordinator, action: #selector(Coordinator.begin), for: .touchDown)
        control.addTarget(context.coordinator, action: #selector(Coordinator.end(_:)), for: [
            .touchUpInside, .touchUpOutside, .touchCancel
        ])
        return control
    }

    func updateUIView(_ control: Control, context: Context) {
        let coordinator = context.coordinator
        coordinator.view = self
        if coordinator.appearance != colorScheme {
            let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
            let ink = UIColor(StudioStyle.ink).resolvedColor(with: traits)
            let mute = UIColor(StudioStyle.mute).resolvedColor(with: traits)
            let filled = Self.trackImage(color: ink)
            let empty = Self.trackImage(color: mute)
            let thumb = Self.dot(size: 18, color: ink)
            for state in [UIControl.State.normal, .highlighted, .disabled] {
                control.setMinimumTrackImage(filled, for: state)
                control.setMaximumTrackImage(empty, for: state)
                control.setThumbImage(thumb, for: state)
            }
            control.setThumbImage(Self.dot(size: 20, color: ink), for: .highlighted)
            coordinator.appearance = colorScheme
        }

        control.isEnabled = isEnabled
        control.alpha = isEnabled ? 1 : 0.5
        let length = range.upperBound - range.lowerBound
        let position = Float((value - range.lowerBound) / length)
        if abs(control.value - position) > 0.000_001 {
            control.setValue(position, animated: false)
        }
        control.increment = Float(step.map { $0 / length } ?? 0.05)
        var localizedTitle = title
        localizedTitle.locale = locale
        control.accessibilityLabel = String(localized: localizedTitle)
        control.accessibilityValue = display(value)
    }

    private static func dot(size: CGFloat, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { renderer in
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            renderer.cgContext.setFillColor(color.cgColor)
            renderer.cgContext.fillEllipse(in: bounds)
        }
    }

    private static func trackImage(color: UIColor) -> UIImage {
        dot(size: 7, color: color).resizableImage(
            withCapInsets: UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3),
            resizingMode: .stretch
        )
    }

    final class Control: UISlider {
        var increment: Float = 0.05

        override var accessibilityFrame: CGRect {
            get { UIAccessibility.convertToScreenCoordinates(bounds, in: self) }
            set { super.accessibilityFrame = newValue }
        }

        override func trackRect(forBounds bounds: CGRect) -> CGRect {
            let track = super.trackRect(forBounds: bounds)
            return CGRect(x: track.minX, y: bounds.midY - 3.5, width: track.width, height: 7)
        }

        override func accessibilityIncrement() { adjust(by: increment) }
        override func accessibilityDecrement() { adjust(by: -increment) }

        private func adjust(by offset: Float) {
            setValue(min(1, max(0, value + offset)), animated: false)
            sendActions(for: .valueChanged)
        }
    }

    @MainActor final class Coordinator: NSObject {
        var view: StudioRange
        var appearance: ColorScheme?

        init(_ view: StudioRange) { self.view = view }

        @objc func begin() { view.onEditingChanged(true) }
        @objc func end(_ control: UISlider) {
            let length = view.range.upperBound - view.range.lowerBound
            control.setValue(Float((view.value - view.range.lowerBound) / length), animated: false)
            view.onEditingChanged(false)
        }

        @objc func change(_ control: UISlider) {
            let lower = view.range.lowerBound
            let span = view.range.upperBound - lower
            let distance = Double(control.value) * span
            let quantized = view.step.map { (distance / $0).rounded() * $0 } ?? distance
            let value = min(view.range.upperBound, max(lower, lower + quantized))
            control.accessibilityValue = view.display(value)
            if view.value != value { view.value = value }
        }
    }
}
