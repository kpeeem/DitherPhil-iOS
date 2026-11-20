import SwiftUI
import UniformTypeIdentifiers

final class ShareController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?.flatMap { $0.attachments ?? [] } ?? []
        guard let provider = attachments.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        }), let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) || $0.conforms(to: .movie) }) else {
            extensionContext?.cancelRequest(withError: RenderError.invalidMedia)
            return
        }
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.center = view.center
        spinner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        view.addSubview(spinner)
        spinner.startAnimating()
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, error in
            let result = Result { () throws -> StudioFile in
                guard let url else { throw error ?? RenderError.invalidMedia }
                return try StudioFile.copy(url)
            }
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let file):
                    let editor = StudioView(initialFile: file) { [weak self] in
                        self?.extensionContext?.completeRequest(returningItems: nil)
                    }
                    let host = UIHostingController(rootView: editor)
                    self.addChild(host)
                    spinner.removeFromSuperview()
                    host.view.frame = self.view.bounds
                    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    self.view.addSubview(host.view)
                    host.didMove(toParent: self)
                case .failure(let failure): self.extensionContext?.cancelRequest(withError: failure)
                }
            }
        }
    }
}
