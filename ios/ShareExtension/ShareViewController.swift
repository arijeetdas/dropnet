import UIKit
import UniformTypeIdentifiers

/// iOS Share Sheet target ("Share" / "Send" from other apps into DropNet).
///
/// Runs as a separate process from the main app in its own sandbox, so
/// handing files off means writing into the shared App Group container
/// (never the main app's own storage) and reading them back on the main
/// app's side. No copy of a shared file is kept anywhere else, and nothing
/// here is written to a user-visible location.
class ShareViewController: UIViewController {
  private static let appGroupId = "group.com.dropnet.shared"
  private static let sharedDefaultsKey = "pendingShareExtensionItems"

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    handleShare()
  }

  private func handleShare() {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
      finish()
      return
    }

    let providers = items.flatMap { $0.attachments ?? [] }
    guard !providers.isEmpty else {
      finish()
      return
    }

    let group = DispatchGroup()
    var filePaths: [String] = []
    var texts: [String] = []
    let lock = NSLock()

    for provider in providers {
      group.enter()
      loadItem(from: provider) { path, text in
        lock.lock()
        if let path {
          filePaths.append(path)
        }
        if let text {
          texts.append(text)
        }
        lock.unlock()
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      self?.storeAndSignal(filePaths: filePaths, texts: texts)
      self?.finish()
    }
  }

  /// Tries, in order, a real file URL (copied into the App Group container),
  /// then plain text/a URL string. Every content type the Share Sheet can
  /// hand over is one of these two shapes underneath.
  private func loadItem(
    from provider: NSItemProvider,
    completion: @escaping (String?, String?) -> Void
  ) {
    let fileTypes: [String] = [
      UTType.fileURL.identifier,
      UTType.url.identifier,
      UTType.item.identifier,
    ]

    func tryNext(_ index: Int) {
      guard index < fileTypes.count else {
        completion(nil, nil)
        return
      }
      let typeId = fileTypes[index]
      guard provider.hasItemConformingToTypeIdentifier(typeId) else {
        tryNext(index + 1)
        return
      }
      provider.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] value, _ in
        if let url = value as? URL {
          if url.isFileURL {
            let copied = self?.copyIntoAppGroup(url)
            completion(copied, nil)
          } else {
            completion(nil, url.absoluteString)
          }
          return
        }
        if let text = value as? String {
          completion(nil, text)
          return
        }
        if let data = value as? Data, let text = String(data: data, encoding: .utf8) {
          completion(nil, text)
          return
        }
        tryNext(index + 1)
      }
    }

    tryNext(0)
  }

  private func copyIntoAppGroup(_ sourceUrl: URL) -> String? {
    guard
      let containerUrl = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Self.appGroupId
      )
    else {
      return nil
    }

    let inboxUrl = containerUrl.appendingPathComponent("share_inbox", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: inboxUrl, withIntermediateDirectories: true)

      let accessed = sourceUrl.startAccessingSecurityScopedResource()
      defer {
        if accessed {
          sourceUrl.stopAccessingSecurityScopedResource()
        }
      }

      var destination = inboxUrl.appendingPathComponent(sourceUrl.lastPathComponent)
      if FileManager.default.fileExists(atPath: destination.path) {
        let ext = destination.pathExtension
        let stem = destination.deletingPathExtension().lastPathComponent
        let unique = "\(stem)_\(Int(Date().timeIntervalSince1970 * 1000))"
        destination = inboxUrl.appendingPathComponent(ext.isEmpty ? unique : "\(unique).\(ext)")
      }

      try FileManager.default.copyItem(at: sourceUrl, to: destination)
      return destination.path
    } catch {
      return nil
    }
  }

  private func storeAndSignal(filePaths: [String], texts: [String]) {
    guard !filePaths.isEmpty || !texts.isEmpty else {
      return
    }
    guard let defaults = UserDefaults(suiteName: Self.appGroupId) else {
      return
    }

    var existing = defaults.dictionary(forKey: Self.sharedDefaultsKey) ?? [:]
    var existingFiles = existing["files"] as? [String] ?? []
    var existingTexts = existing["texts"] as? [String] ?? []
    for path in filePaths where !existingFiles.contains(path) {
      existingFiles.append(path)
    }
    for text in texts where !existingTexts.contains(text) {
      existingTexts.append(text)
    }
    existing["files"] = existingFiles
    existing["texts"] = existingTexts
    defaults.set(existing, forKey: Self.sharedDefaultsKey)
  }

  private func finish() {
    // Hands off to the host app immediately (rather than waiting for the
    // user to switch to it manually) via a private URL scheme, using the
    // extension-context API meant for exactly this — UIApplication.shared
    // isn't available inside an app extension at all. DropNet's scene
    // delegate reads the App Group data as soon as it opens.
    let url = URL(string: "dropnet://share-extension-import")!
    extensionContext?.open(url) { [weak self] _ in
      self?.extensionContext?.completeRequest(returningItems: nil)
    }
  }
}
