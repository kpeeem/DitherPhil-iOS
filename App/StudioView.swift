import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
                let height = geometry.size.height
                let panelHeight = min(height * (dynamicTypeSize.isAccessibilitySize ? 0.59 : 0.45), 354)
                VStack(spacing: 0) {
                    Rectangle().fill(StudioStyle.stroke).frame(height: StudioStyle.rule)
                    if let media = editor.media {
                        stage(media)
                            .padding(.horizontal, StudioStyle.margin)
                            .padding(.top, StudioStyle.gap)
                            .padding(.bottom, panelHeight + 10)
                    } else {
                        ContentUnavailableView("Choose a photo or video", systemImage: "photo.on.rectangle")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if editor.media != nil {
                        Inspector(editor: editor, section: $section)
                            .frame(maxWidth: 620)
                            .frame(height: max(148, panelHeight))
                            .background {
                                if reduceTransparency { StudioStyle.stone }
                                else { Rectangle().fill(.regularMaterial).background(StudioStyle.stone.opacity(0.78)) }
                            }
                            .clipShape(.rect(cornerRadius: StudioStyle.radius))
                            .overlay {
                                RoundedRectangle(cornerRadius: StudioStyle.radius)
                                    .strokeBorder(StudioStyle.ink.opacity(0.14))
                                    .allowsHitTesting(false)
                            }
                            .padding(.horizontal, StudioStyle.margin)
                            .padding(.bottom, 8)
                    }
                }
                .overlay {
                    if editor.loading {
                        ProgressView("Opening media…")
                            .padding(20)
                            .background(.regularMaterial, in: .rect(cornerRadius: StudioStyle.radius))
                    }
                }
            }
            .background(StudioStyle.paper.ignoresSafeArea())
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(verbatim: "DitherPhil")
                        .font(StudioStyle.title(22, relativeTo: .title2))
                        .foregroundStyle(StudioStyle.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Import", systemImage: "plus") { showsImport = true }
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
                .presentationDetents([.medium, .large])
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

    private func stage(_ media: StudioMedia) -> some View {
        VStack(alignment: .leading, spacing: StudioStyle.gap) {
            HStack {
                Text(editor.showsOriginal ? "Original" : "Preview")
                    .font(StudioStyle.title(15, relativeTo: .subheadline))
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(dimensions(editor.settings.resolution.size(for: media.size, video: media.isVideo)))
                        .font(StudioStyle.title(13, relativeTo: .caption))
                        .monospacedDigit()
                        .foregroundStyle(StudioStyle.mute)
                        .accessibilityLabel("Output dimensions")
                        .accessibilityValue(dimensions(editor.settings.resolution.size(for: media.size, video: media.isVideo)))
                }
            }
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
                            .interpolation(.none)
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
            HStack(spacing: StudioStyle.gap) {
                if media.isVideo { transport(media) }
                else { Spacer(minLength: 0) }
                Button {
                    editor.showsOriginal.toggle()
                } label: {
                    Image(systemName: editor.showsOriginal ? "circle.lefthalf.filled" : "circle.lefthalf.striped.horizontal")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Compare with original")
                .accessibilityValue(editor.showsOriginal ? Text("Original") : Text("Preview"))
                .accessibilityIdentifier("compare")
            }
        }
        .foregroundStyle(StudioStyle.ink)
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
