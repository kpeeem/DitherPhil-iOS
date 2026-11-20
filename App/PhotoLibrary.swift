import Photos

enum PhotoLibrary {
    static func save(_ file: StudioFile, video: Bool) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoError.denied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: video ? .video : .photo, fileURL: file.url, options: nil)
        }
    }
}

enum PhotoError: LocalizedError {
    case denied
    var errorDescription: String? { String(localized: "Allow adding photos in Settings to save this file.") }
}
