//
//  ShareViewController.swift
//  ShareExtension
//
//  Minimal share sheet that surfaces the first shared URL/text and lets the
//  user post it straight into the Notes app.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroupID = "group.com.br3dev.test"
    private var hasLoadedInitialContent = false
    private var availableFolders: [ShareFolder] = [] {
        didSet { configureFolderButtonMenu() }
    }
    private var selectedFolder: ShareFolder? {
        didSet {
            updateFolderButtonTitle()
            updateSaveButtonSubtitle()
        }
    }
    private var capturedPageTitle: String?
    private var capturedURLString: String?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.text = "Add to Notes"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let hintLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = "We captured the first link or text from what you're sharing. Tap Save to add it to Notes."
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let textView: UITextView = {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.layer.cornerRadius = 12
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor.secondarySystemFill.cgColor
        tv.backgroundColor = UIColor.secondarySystemBackground
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let folderButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "Choose Folder"
        config.image = UIImage(systemName: "folder")
        config.imagePadding = 6
        config.cornerStyle = .large

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsMenuAsPrimaryAction = false
        return button
    }()

    private let saveButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Save to Notes"
        config.image = UIImage(systemName: "square.and.arrow.down")
        config.imagePadding = 6
        config.cornerStyle = .large
        config.baseBackgroundColor = .systemBlue

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 0, height: 320)

        saveButton.addTarget(self, action: #selector(handleSave), for: .touchUpInside)
        folderButton.addTarget(self, action: #selector(presentFolderPicker), for: .touchUpInside)
        textView.delegate = self

        layoutContent()
        updateSaveButtonSubtitle()
        loadAvailableFolders()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadInitialContentIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadInitialContentIfNeeded()
    }

    override func beginRequest(with context: NSExtensionContext) {
        super.beginRequest(with: context)
        loadAvailableFolders()
        loadInitialContentIfNeeded()
    }

    private func layoutContent() {
        view.addSubview(titleLabel)
        view.addSubview(hintLabel)
        view.addSubview(textView)
        view.addSubview(folderButton)
        view.addSubview(saveButton)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            textView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            textView.heightAnchor.constraint(equalToConstant: 140),

            folderButton.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 16),
            folderButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            folderButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            saveButton.topAnchor.constraint(equalTo: folderButton.bottomAnchor, constant: 20),
            saveButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            saveButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            activityIndicator.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: -16)
        ])
    }
}

// MARK: - Actions

private extension ShareViewController {
    @objc func handleSave() {
        let trimmed = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presentAlert(title: "Nothing to Save", message: "Enter a link or text before saving.")
            return
        }

        saveButton.isEnabled = false
        activityIndicator.startAnimating()

        let isURL = isLikelyURL(trimmed)
        let didSave = saveSharedContent(trimmed,
                                        isURL: isURL,
                                        folderID: selectedFolder?.id,
                                        pageTitle: capturedPageTitle,
                                        sourceURL: capturedURLString ?? (isURL ? trimmed : nil))

        guard didSave else {
            activityIndicator.stopAnimating()
            saveButton.isEnabled = true
            presentAlert(title: "Unable to Save", message: "We couldn't access shared storage. Please try again after opening the app once.")
            return
        }

        let urlToOpen = URL(string: "notesapp://process-shared-content")

        extensionContext?.completeRequest(returningItems: [], completionHandler: { _ in
            if let url = urlToOpen {
                DispatchQueue.main.async {
                    self.extensionContext?.open(url, completionHandler: nil)
                }
            }
        })
    }

    func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Content Loading

private extension ShareViewController {
    func loadInitialContentIfNeeded() {
        guard !hasLoadedInitialContent else { return }
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        hasLoadedInitialContent = true

        let propertyListIdentifier: String
        if #available(iOS 14.0, *) {
            propertyListIdentifier = UTType.propertyList.identifier
        } else {
            propertyListIdentifier = "com.apple.property-list"
        }

        for item in items {
            guard let attachments = item.attachments else { continue }

            if load(from: attachments, matching: UTType.url.identifier, handler: handleLoadedURLItem(_:)) { return }
            if load(from: attachments, matching: UTType.plainText.identifier, handler: handleLoadedPlainTextItem(_:)) { return }
            if load(from: attachments, matching: propertyListIdentifier, handler: handleLoadedPropertyListItem(_:)) { return }
        }
    }

    @discardableResult
    func load(from providers: [NSItemProvider], matching typeIdentifier: String, handler: @escaping (NSSecureCoding?) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(typeIdentifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            handler(item as? NSSecureCoding)
        }
        return true
    }

    func handleLoadedURLItem(_ item: NSSecureCoding?) {
        guard let text = extractURLString(from: item) else { return }
        capturedURLString = text
        updateTextViewIfNeeded(with: text)
    }

    func handleLoadedPlainTextItem(_ item: NSSecureCoding?) {
        guard let text = item as? String else { return }
        if isLikelyURL(text) {
            capturedURLString = sanitizeURLString(text) ?? text
        }
        updateTextViewIfNeeded(with: text)
    }

    func handleLoadedPropertyListItem(_ item: NSSecureCoding?) {
        guard let dictionary = item as? [String: Any] else { return }

        if let jsResults = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
            if let urlString = jsResults["URL"] as? String ?? jsResults["url"] as? String,
               let sanitized = sanitizeURLString(urlString) {
                capturedURLString = sanitized
                updateTextViewIfNeeded(with: sanitized)
            }
            if let title = jsResults["title"] as? String {
                capturedPageTitle = title
                if (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    updateTextViewIfNeeded(with: title)
                }
            }
        }

        if let urlString = dictionary["URL"] as? String ?? dictionary["url"] as? String,
           let sanitized = sanitizeURLString(urlString) {
            capturedURLString = sanitized
            updateTextViewIfNeeded(with: sanitized)
        }

        if let title = dictionary["title"] as? String {
            capturedPageTitle = title
            if (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateTextViewIfNeeded(with: title)
            }
        }
    }

    func updateTextViewIfNeeded(with text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.textView.text = trimmed
            }
        }
    }
}

// MARK: - Helpers

private extension ShareViewController {
    func loadAvailableFolders() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else { return }
        let rawFolders = sharedDefaults.array(forKey: "availableFolders") as? [[String: Any]] ?? []

        let folders = rawFolders.compactMap { item -> ShareFolder? in
            guard let name = item["name"] as? String else { return nil }
            let id = (item["id"] as? String).flatMap(UUID.init)
            let isPrivate = item["isPrivate"] as? Bool ?? false
            return ShareFolder(id: id, name: name, isPrivate: isPrivate)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let defaultOption = ShareFolder(id: nil, name: "No Folder", isPrivate: false)
            self.availableFolders = [defaultOption] + folders
            if let current = self.selectedFolder,
               self.availableFolders.contains(current) {
                self.selectedFolder = current
            } else {
                self.selectedFolder = self.availableFolders.first
            }
        }
    }

    func configureFolderButtonMenu() {
        guard !availableFolders.isEmpty else {
            folderButton.configuration?.subtitle = ""
            folderButton.isEnabled = false
            return
        }

        folderButton.isEnabled = true
    }

    func updateFolderButtonTitle() {
        folderButton.configurationUpdateHandler = nil
        guard let selection = selectedFolder else {
            folderButton.configuration?.title = "Choose Folder"
            folderButton.configuration?.subtitle = nil
            folderButton.configuration?.image = UIImage(systemName: "folder")
            return
        }

        folderButton.configurationUpdateHandler = { button in
            guard var config = button.configuration else { return }
            config.title = selection.name
            config.subtitle = selection.id == nil ? "Will appear in All Notes" : nil
            config.image = UIImage(systemName: selection.id == nil ? "tray" : "folder")
            button.configuration = config
        }
        folderButton.setNeedsUpdateConfiguration()
    }

    func updateSaveButtonSubtitle() {
        guard var config = saveButton.configuration else { return }
        if let selection = selectedFolder, let id = selection.id {
            config.subtitle = "Saving to \(selection.name)"
            config.image = UIImage(systemName: "square.and.arrow.down.on.square")
        } else {
            config.subtitle = "Saving to All Notes"
            config.image = UIImage(systemName: "square.and.arrow.down")
        }
        saveButton.configuration = config
    }

    @objc func presentFolderPicker() {
        guard !availableFolders.isEmpty else { return }
        let alert = UIAlertController(title: "Save To Folder", message: nil, preferredStyle: .actionSheet)

        for folder in availableFolders {
            var title = folder.name
            if folder.isPrivate { title += " (Private)" }
            if folder == selectedFolder { title = "✓ " + title }
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.selectedFolder = folder
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = folderButton
            popover.sourceRect = folderButton.bounds
        }

        present(alert, animated: true)
    }

    func saveSharedContent(_ content: String,
                           isURL: Bool,
                           folderID: UUID?,
                           pageTitle: String?,
                           sourceURL: String?) -> Bool {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID) else { return false }

        var shareData: [String: Any] = [
            "content": content,
            "isURL": isURL,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let folderID = folderID {
            shareData["folderID"] = folderID.uuidString
        }
        if let title = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            shareData["pageTitle"] = title
        }
        if let urlString = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty {
            shareData["sourceURL"] = urlString
        }

        var pendingShares = sharedDefaults.array(forKey: "pendingShares") as? [[String: Any]] ?? []
        pendingShares.append(shareData)
        sharedDefaults.set(pendingShares, forKey: "pendingShares")
        sharedDefaults.synchronize()
        return true
    }

    func extractURLString(from item: NSSecureCoding?) -> String? {
        if let url = item as? URL {
            return url.absoluteString
        }
        if let string = item as? String,
           let sanitized = sanitizeURLString(string) {
            return sanitized
        }
        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8),
           let sanitized = sanitizeURLString(string) {
            return sanitized
        }
        return nil
    }

    func sanitizeURLString(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url.absoluteString
    }

    func isLikelyURL(_ text: String) -> Bool {
        if URL(string: text)?.scheme != nil { return true }
        return text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://")
    }
}

extension ShareViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let trimmed = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sanitized = sanitizeURLString(trimmed) {
            capturedURLString = sanitized
        } else {
            capturedURLString = nil
        }
        if trimmed.isEmpty {
            capturedPageTitle = nil
        }
    }
}

private struct ShareFolder: Hashable {
    let id: UUID?
    let name: String
    let isPrivate: Bool
}
