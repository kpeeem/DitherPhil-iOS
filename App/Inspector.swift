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
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    sectionPicker.pickerStyle(.menu)
                } else {
                    sectionPicker.pickerStyle(.segmented)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    switch section {
                    case .dither: dither
                    case .color: color
                    case .output: output
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.top)
            .id(section)
        }
        .padding(.top, 6)
        .foregroundStyle(StudioStyle.ink)
    }

    private var sectionPicker: some View {
        Picker("Editor section", selection: $section) {
            ForEach(InspectorSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
    }

    private var dither: some View {
        Group {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .top, spacing: StudioStyle.gap))
            layout {
                option("Algorithm", value: editor.settings.algorithm.name, identifier: "algorithm") {
                    Picker("Algorithm", selection: $editor.settings.algorithm) {
                        ForEach(Algorithm.allCases) { algorithm in
                            Text(algorithm.name).tag(algorithm)
                        }
                    }
                }
                option("Palette", value: editor.settings.palette.name, identifier: "palette") {
                    Picker("Palette", selection: $editor.settings.palette) {
                        ForEach(Palette.allCases) { palette in
                            Text(palette.name).tag(palette)
                        }
                    }
                }
            }

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
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(StudioStyle.mute)
                .accessibilityHidden(true)
            Menu {
                content().pickerStyle(.inline)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value))
            .accessibilityIdentifier(identifier)
        }
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
            resolution($editor.settings.resolution)
            if let media = editor.media {
                LabeledContent("Dimensions", value: dimensions(editor.settings.resolution.size(for: media.size, video: media.isVideo)))
                    .monospacedDigit()
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
                Section {
                    if editor.exporting {
                        ProgressView(value: editor.progress) { Text("Rendering…") }
                            .accessibilityIdentifier("export-progress")
                        Button("Cancel export", role: .cancel) { editor.cancelExport() }
                    } else if let file = editor.exported {
                        ShareLink(item: file.url) { Label("Share or save", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("share-file")
                    } else {
                        Button { editor.export() } label: {
                            Label("Render file", systemImage: "arrow.down.to.line")
                        }
                        .accessibilityIdentifier("render-file")
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(editor.exporting)
                }
            }
        }
        .alert("Export", isPresented: Binding(
            get: { editor.error != nil },
            set: { if !$0 { editor.error = nil } }
        )) {
            Button("OK", role: .cancel) { editor.error = nil }
        } message: {
            Text(editor.error ?? "")
        }
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
            resolution($editor.settings.resolution)
            LabeledContent("Dimensions", value: dimensions(size))
                .monospacedDigit()
            if editor.format == .jpeg || editor.format == .heic {
                StudioSlider("Quality", value: $editor.quality, in: 0.5...1, step: 0.01, display: percent)
            }
        }
    }
}

struct StudioSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: (Double) -> String

    init(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
         display: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.display = display
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabeledContent { Text(display(value)).monospacedDigit().foregroundStyle(StudioStyle.mute) } label: { Text(title) }
                .font(.subheadline)
                .accessibilityHidden(true)
            Slider(value: $value, in: range, step: step) { Text(title) }
                .frame(minHeight: 44)
                .accessibilityValue(display(value))
        }
    }
}

@MainActor private func resolution(_ selection: Binding<OutputResolution>) -> some View {
    Picker("Resolution", selection: selection) {
        ForEach(OutputResolution.allCases) { option in
            Text(option.name).tag(option)
        }
    }
    .studioPicker()
}

private func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0))) }

private extension View {
    func studioPicker() -> some View {
        pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}
