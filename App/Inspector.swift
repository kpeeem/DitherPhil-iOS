import simd
import SwiftUI

enum InspectorSection: String, CaseIterable, Identifiable {
    case dither, color, output

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .dither: "Dither"
        case .color: "Color"
        case .output: "Output"
        }
    }
}

struct Inspector: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var editor: Editor
    @Binding var section: InspectorSection

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch section {
                    case .dither: dither
                    case .color: color
                    case .output: output
                    }
                }
                .padding(StudioStyle.gap)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.top)
            .id(section)
        }
        .foregroundStyle(StudioStyle.ink)
    }

    @ViewBuilder
    private var sectionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Editor section", selection: $section) {
                ForEach(InspectorSection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, StudioStyle.gap)
        } else {
            HStack(spacing: 0) {
                ForEach(InspectorSection.allCases) { item in
                    let selected = item == section
                    Button {
                        section = item
                    } label: {
                        Text(item.title)
                            .font(StudioStyle.font(14, relativeTo: .subheadline))
                            .foregroundStyle(selected ? StudioStyle.ink : StudioStyle.mute)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if selected {
                                    Rectangle().fill(StudioStyle.stroke).frame(height: StudioStyle.rule)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, StudioStyle.gap)
            .background(alignment: .bottom) { Rectangle().fill(StudioStyle.separator).frame(height: 1) }
        }
    }

    private var dither: some View {
        Group {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: StudioStyle.gap))
                : AnyLayout(HStackLayout(alignment: .top, spacing: StudioStyle.gap))
            layout {
                option("Algorithm", value: editor.settings.algorithm.name, identifier: "algorithm") {
                    Picker("Algorithm", selection: $editor.settings.algorithm) {
                        ForEach(Algorithm.allCases) { algorithm in
                            Text(algorithm.name).tag(algorithm)
                        }
                    }
                }
                option("Palette", value: editor.settings.palette.name, identifier: "palette",
                       swatches: editor.settings.colors) {
                    Picker("Palette", selection: $editor.settings.palette) {
                        ForEach(Palette.allCases) { palette in
                            Text(palette.name).tag(palette)
                        }
                    }
                }
            }
            .padding(.bottom, StudioStyle.gap / 2)

            StudioSlider("Cell size", value: $editor.settings.cell, in: 1...24, step: 1) {
                "\(Int($0)) px"
            }
            .accessibilityIdentifier("cell-size")

            if editor.settings.palette == .grayscale || editor.settings.palette == .rgb {
                StudioSlider("Levels", value: $editor.settings.levels, in: 2...16, step: 1) {
                    "\(Int($0))"
                }
            }
            if editor.settings.palette == .custom {
                ColorPicker("Shadows", selection: customColor($editor.settings.shadow), supportsOpacity: false)
                    .frame(minHeight: 44)
                ColorPicker("Highlights", selection: customColor($editor.settings.highlight), supportsOpacity: false)
                    .frame(minHeight: 44)
            }
            if editor.settings.algorithm != .threshold {
                StudioSlider("Strength", value: $editor.settings.strength, in: 0...1.5, step: 0.01, display: percent)
            }
            StudioSlider("Mix", value: $editor.settings.mix, in: 0...1, step: 0.01, display: percent)
        }
    }

    private func option<Content: View>(
        _ label: LocalizedStringKey,
        value: LocalizedStringKey,
        identifier: String,
        swatches: [SIMD3<Float>] = [],
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content().pickerStyle(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label)
                        .font(StudioStyle.font(12, relativeTo: .caption))
                        .foregroundStyle(StudioStyle.mute)
                    Spacer(minLength: 0)
                    if !dynamicTypeSize.isAccessibilitySize {
                        HStack(spacing: 1) {
                            ForEach(swatches.indices, id: \.self) { index in
                                let rgb = swatches[index]
                                Rectangle()
                                    .fill(Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 2))
                        .accessibilityHidden(true)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(StudioStyle.font(15, relativeTo: .subheadline))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                .foregroundStyle(StudioStyle.ink)
            }
            .padding(.horizontal, StudioStyle.gap)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(StudioStyle.paper, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
        .accessibilityIdentifier(identifier)
    }

    private var color: some View {
        Group {
            StudioSlider("Exposure", value: $editor.settings.exposure, in: -2...2, step: 0.05) {
                "\($0.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)))) EV"
            }
            StudioSlider("Contrast", value: $editor.settings.contrast, in: 0.5...2, step: 0.01, display: percent)
            StudioSlider("Saturation", value: $editor.settings.saturation, in: 0...2, step: 0.01, display: percent)
            StudioSlider("Warmth", value: $editor.settings.warmth, in: -1...1, step: 0.01, display: percent)
            Toggle("Invert", isOn: $editor.settings.invert).frame(minHeight: 44)
            Button("Reset color") { editor.settings.resetColor() }
                .frame(minHeight: 44)
        }
    }

    private var output: some View {
        Group {
            option("Resolution", value: editor.settings.resolution.name, identifier: "resolution") {
                resolution($editor.settings.resolution)
            }
            if let media = editor.media {
                let size = editor.settings.resolution.size(for: media.size, video: media.isVideo)
                LabeledContent("Dimensions") {
                    Text(dimensions(size))
                        .monospacedDigit()
                        .foregroundStyle(StudioStyle.mute)
                }
                .frame(minHeight: 44)
            }
            Button("Reset adjustments", role: .destructive) { editor.settings = EditSettings() }
                .frame(minHeight: 44)
        }
    }

    private func customColor(_ binding: Binding<SIMD3<Float>>) -> Binding<Color> {
        Binding {
            let rgb = binding.wrappedValue
            return Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
        } set: { color in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let components = UIColor(color).cgColor.converted(to: space, intent: .defaultIntent, options: nil)?.components,
                  components.count >= 3 else { return }
            binding.wrappedValue = simd_clamp(SIMD3(Float(components[0]), Float(components[1]), Float(components[2])),
                                               .zero, SIMD3(repeating: 1))
        }
    }
}

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var editor: Editor

    var body: some View {
        NavigationStack {
            Form {
                if let media = editor.media {
                    options(for: media)
                        .disabled(editor.exporting)
                        .onChange(of: editor.format) { _, _ in editor.exported = nil }
                        .onChange(of: editor.settings.resolution) { _, _ in editor.exported = nil }
                        .onChange(of: editor.quality) { _, _ in editor.exported = nil }
                }
            }
            .font(StudioStyle.font(15, relativeTo: .body))
            .scrollContentBackground(.hidden)
            .contentMargins(.top, StudioStyle.margin, for: .scrollContent)
            .background(StudioStyle.stone)
            .safeAreaInset(edge: .bottom, spacing: 0) { exportAction }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(editor.exporting)
                }
            }
        }
        .tint(StudioStyle.ink)
        .alert("Export", isPresented: Binding(
            get: { editor.error != nil },
            set: { if !$0 { editor.error = nil } }
        )) {
            Button("OK", role: .cancel) { editor.error = nil }
        } message: {
            Text(editor.error ?? "")
        }
    }

    private var exportAction: some View {
        VStack(spacing: StudioStyle.gap) {
            if editor.exporting {
                ProgressView(value: editor.progress) { Text("Rendering…") }
                    .accessibilityIdentifier("export-progress")
                Button("Cancel export", role: .cancel) { editor.cancelExport() }
                    .frame(minHeight: 44)
            } else if let file = editor.exported {
                ShareLink(item: file.url) { Label("Share or save", systemImage: "square.and.arrow.up") }
                    .buttonStyle(StudioPrimaryAction())
                    .accessibilityIdentifier("share-file")
            } else {
                Button { editor.export() } label: { Label("Render file", systemImage: "arrow.down.to.line") }
                    .buttonStyle(StudioPrimaryAction())
                    .accessibilityIdentifier("render-file")
            }
        }
        .padding(.horizontal, StudioStyle.margin)
        .padding(.vertical, StudioStyle.gap)
        .frame(maxWidth: .infinity)
        .background(StudioStyle.stone)
    }

    private func options(for media: StudioMedia) -> some View {
        let formats: [ExportFormat] = media.isVideo ? [.hevc, .h264] : [.png, .jpeg, .heic]
        let size = editor.settings.resolution.size(for: media.size, video: media.isVideo)
        return Section {
            Picker("Format", selection: $editor.format) {
                ForEach(formats) { format in
                    Text(verbatim: format.title).tag(format)
                }
            }
            .pickerStyle(.menu)
            resolution($editor.settings.resolution).pickerStyle(.menu)
            LabeledContent("Dimensions") {
                Text(dimensions(size))
                    .monospacedDigit()
                    .foregroundStyle(StudioStyle.mute)
            }
            if editor.format == .jpeg || editor.format == .heic {
                StudioSlider("Quality", value: $editor.quality, in: 0.5...1, step: 0.01, display: percent)
            }
        }
        .listRowBackground(StudioStyle.paper)
    }
}

struct StudioSlider: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var labelWidth = 104.0
    @ScaledMetric(relativeTo: .caption) private var valueWidth = 70.0
    let title: LocalizedStringResource
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: (Double) -> String

    init(_ title: LocalizedStringResource, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
         display: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.display = display
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: StudioStyle.gap) {
                    label.frame(width: labelWidth, alignment: .leading)
                    slider.frame(minWidth: 72, maxWidth: .infinity)
                    readout.frame(width: valueWidth, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: StudioStyle.gap) {
                        label.fixedSize()
                        Spacer(minLength: 0)
                        readout.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        label
                        readout
                    }
                }
                slider
            }
            .padding(.vertical, 6)
        }
    }

    private var label: some View {
        Text(title)
            .font(StudioStyle.font(14, relativeTo: .subheadline))
            .accessibilityHidden(true)
    }

    private var readout: some View {
        Text(display(value))
            .font(StudioStyle.font(12, relativeTo: .caption))
            .monospacedDigit()
            .foregroundStyle(StudioStyle.mute)
            .accessibilityHidden(true)
    }

    private var slider: some View {
        StudioRange(value: $value, range: range, step: step, title: title, display: display)
    }
}

@MainActor private func resolution(_ selection: Binding<OutputResolution>) -> some View {
    Picker("Resolution", selection: selection) {
        ForEach(OutputResolution.allCases) { option in
            Text(option.name).tag(option)
        }
    }
}

private func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0))) }

private struct StudioPrimaryAction: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StudioStyle.font(16, relativeTo: .body))
            .foregroundStyle(StudioStyle.paper)
            .padding(.horizontal, StudioStyle.gap)
            .padding(.vertical, StudioStyle.gap)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(StudioStyle.ink, in: .capsule)
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
