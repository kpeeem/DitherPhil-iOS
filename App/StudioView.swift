import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editor = Editor()
    @State private var section: InspectorSection = .dither
    @State private var showsImport = false
    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var showsExport = false
    @State private var picker: PhotosPickerItem?
    @State private var scrubbing = false
    @State private var resumeAfterScrub = false
    @State private var position = 0.0

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Rectangle().fill(StudioStyle.stroke).frame(height: StudioStyle.rule)
                    if let media = editor.media {
                        workspace(media, size: geometry.size)
                            .padding(StudioStyle.margin)
                    } else {
                        ContentUnavailableView("Choose a photo or video", systemImage: "photo.on.rectangle")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if editor.loading {
                        ProgressView("Opening media…")
                            .padding(20)
                            .background(StudioStyle.stone, in: .rect(cornerRadius: StudioStyle.radius))
                    }
                }
            }
            .background(StudioStyle.paper.ignoresSafeArea())
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(verbatim: "DitherPhil")
                        .font(StudioStyle.font(22, relativeTo: .title2))
                        .foregroundStyle(StudioStyle.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Import", systemImage: "photo.badge.plus") { showsImport = true }
                        .accessibilityIdentifier("import")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export", systemImage: "square.and.arrow.up") { showsExport = true }
                        .accessibilityIdentifier("export")
                        .disabled(editor.media == nil || editor.loading || editor.exporting)
                }
            }
        }
        .tint(StudioStyle.ink)
        .task { editor.start() }
        .task(id: editor.previewRequest) { await editor.updatePreview() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { editor.player.pause() }
        }
        .onChange(of: editor.settings) { _, _ in editor.showsOriginal = false }
        .confirmationDialog("Open media", isPresented: $showsImport, titleVisibility: .visible) {
            Button("Photo Library") { showsPhotos = true }
            Button("Files") { showsFiles = true }
            Button("Studio sample") { editor.loadSample() }
        }
        .photosPicker(isPresented: $showsPhotos, selection: $picker,
                      matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)
        .onChange(of: picker) { _, item in
            if let item { editor.importPhotoLibrary(item); picker = nil }
        }
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.image, .movie]) { result in
            switch result {
            case .success(let file): editor.importFile(file)
            case .failure(let error): editor.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $showsExport, onDismiss: { editor.exported = nil }) {
            ExportSheet(editor: editor)
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.fraction(0.54), .large])
                .interactiveDismissDisabled(editor.exporting)
        }
        .alert("DitherPhil", isPresented: Binding(
            get: { editor.error != nil },
            set: { if !$0 { editor.error = nil } }
        )) {
            Button("OK", role: .cancel) { editor.error = nil }
        } message: {
            Text(editor.error ?? "")
        }
    }

    private func workspace(_ media: StudioMedia, size: CGSize) -> some View {
        let availableHeight = size.height - 2 * StudioStyle.margin - StudioStyle.rule
        let wide = size.width >= 720 || (size.width > size.height && size.width >= 580)
        let inspector = Inspector(editor: editor, section: $section)
            .background(StudioStyle.stone, in: .rect(cornerRadius: StudioStyle.radius))
            .clipShape(.rect(cornerRadius: StudioStyle.radius))

        return Group {
            if wide {
                let paneWidth = min(420, (size.width - 2 * StudioStyle.margin) * 0.44)
                HStack(alignment: .top, spacing: StudioStyle.margin) {
                    stage(media)
                    inspector.frame(width: paneWidth)
                }
            } else {
                let panelHeight = dynamicTypeSize.isAccessibilitySize
                    ? min(355, availableHeight * 0.54)
                    : min(264, availableHeight * 0.45)
                stage(media)
                    .padding(.bottom, panelHeight + StudioStyle.gap)
                    .overlay(alignment: .bottom) {
                        inspector.frame(height: panelHeight)
                    }
            }
        }
    }

    private func stage(_ media: StudioMedia) -> some View {
        VStack(alignment: .leading, spacing: StudioStyle.gap) {
            GeometryReader { area in
                let aspect = media.size.width / media.size.height
                let width = min(area.size.width, area.size.height * aspect)
                let height = min(area.size.height, area.size.width / aspect)
                ZStack {
                    StudioStyle.stone
                    if media.isVideo {
                        PlayerSurface(player: editor.player)
                    } else if let image = editor.preview {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: max(0, width), height: max(0, height))
                .clipShape(.rect(cornerRadius: StudioStyle.radius))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            }
            if media.isVideo { transport(media) }
            stageHeader(media)
        }
        .foregroundStyle(StudioStyle.ink)
    }

    private func stageHeader(_ media: StudioMedia) -> some View {
        let size = editor.showsOriginal ? media.size : editor.settings.resolution.size(for: media.size, video: media.isVideo)
        return HStack(spacing: StudioStyle.gap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(editor.showsOriginal ? "Original" : "Preview")
                    .font(StudioStyle.font(15, relativeTo: .subheadline))
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityValue(dynamicTypeSize.isAccessibilitySize ? dimensions(size) : "")
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("\(dimensions(size)) px")
                        .font(StudioStyle.font(12, relativeTo: .caption))
                        .monospacedDigit()
                        .foregroundStyle(StudioStyle.mute)
                        .accessibilityLabel(editor.showsOriginal ? "Source dimensions" : "Output dimensions")
                        .accessibilityValue(dimensions(size))
                        .accessibilityIdentifier("preview-dimensions")
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            Button {
                editor.showsOriginal.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.filled")
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(editor.showsOriginal ? "Show edit" : "Show original")
                            .font(StudioStyle.font(14, relativeTo: .subheadline))
                    }
                }
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : 4)
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Compare with original")
            .accessibilityValue(editor.showsOriginal ? Text("Original") : Text("Preview"))
            .accessibilityIdentifier("compare")
        }
    }

    private func transport(_ media: StudioMedia) -> some View {
        HStack(spacing: StudioStyle.gap) {
            Button {
                editor.togglePlayback()
            } label: {
                Image(systemName: editor.playing ? "pause.fill" : "play.fill")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(editor.playing ? "Pause" : "Play")
            .accessibilityIdentifier("playback")

            Slider(value: Binding(get: { scrubbing ? position : min(editor.time, media.duration) },
                                  set: { position = $0; if !scrubbing { editor.seek($0) } }),
                   in: 0...media.duration) {
                Text("Playback position")
            } onEditingChanged: { editing in
                if editing {
                    position = editor.time
                    resumeAfterScrub = editor.playing
                    editor.player.pause()
                } else {
                    editor.seek(position)
                    if resumeAfterScrub { editor.player.play() }
                }
                scrubbing = editing
            }
            .frame(minHeight: 44)
            if !dynamicTypeSize.isAccessibilitySize {
                Text(Duration.seconds(scrubbing ? position : editor.time).formatted(.time(pattern: .minuteSecond)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(StudioStyle.mute)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ view: Surface, context: Context) { view.layerPlayer.player = player }

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var layerPlayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

func dimensions(_ size: CGSize) -> String {
    "\(Int(size.width)) × \(Int(size.height))"
}

#Preview {
    StudioView()
}
