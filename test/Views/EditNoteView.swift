//
//  EditNoteView.swift
//

import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct EditNoteView: View {
    @Binding var title: String
    @Binding var content: String
    @Binding var selectedRange: NSRange

    var body: some View {
        VStack(spacing: 0) {
            titleField
            Divider()
            contentEditor
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#if canImport(UIKit)
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(.keyboard, edges: .bottom)
#elseif canImport(AppKit)
        .background(Color(NSColor.windowBackgroundColor))
#endif
    }

    private var titleField: some View {
        TextField("Note Title", text: $title)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    private var contentEditor: some View {
#if canImport(UIKit)
        MarkdownTextEditor(
            text: $content,
            selectedRange: $selectedRange,
            formattingOptions: formattingOptions,
            onFormat: { option in
                applyFormatting(prefix: option.prefix, suffix: option.suffix)
            }
        )
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#else
        TextEditor(text: $content)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#endif
    }

    private func applyFormatting(prefix: String, suffix: String) {
        let current = content as NSString
        let clampedLocation = max(0, min(selectedRange.location, current.length))
        let clampedLength = max(0, min(selectedRange.length, current.length - clampedLocation))
        let safeRange = NSRange(location: clampedLocation, length: clampedLength)

        let updates: (newContent: String, newRange: NSRange)

        if safeRange.length == 0 {
            let insertion = prefix + suffix
            let updated = current.replacingCharacters(in: safeRange, with: insertion) as NSString
            let newLocation = safeRange.location + (prefix as NSString).length
            updates = (updated as String, NSRange(location: newLocation, length: 0))
        } else {
            let selectedText = current.substring(with: safeRange)
            let replacement = prefix + selectedText + suffix
            let updated = current.replacingCharacters(in: safeRange, with: replacement) as NSString
            let newLocation = safeRange.location + (prefix as NSString).length + (selectedText as NSString).length
            updates = (updated as String, NSRange(location: newLocation, length: 0))
        }

        DispatchQueue.main.async {
            content = updates.newContent
            selectedRange = updates.newRange
        }
    }
}

#if canImport(UIKit)
private extension EditNoteView {
    var formattingOptions: [FormattingOption] {
        [
            FormattingOption(symbol: "B", prefix: "**", suffix: "**", accessibilityLabel: "Bold"),
            FormattingOption(symbol: "I", prefix: "*", suffix: "*", accessibilityLabel: "Italic"),
            FormattingOption(symbol: "U", prefix: "++", suffix: "++", accessibilityLabel: "Underline")
        ]
    }
}

private struct FormattingOption: Identifiable, Equatable {
    var id: String { symbol }
    let symbol: String
    let prefix: String
    let suffix: String
    let accessibilityLabel: String
}

private struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let formattingOptions: [FormattingOption]
    let onFormat: (FormattingOption) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.text = text
        textView.selectedRange = selectedRange
        textView.adjustsFontForContentSizeCategory = true
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.keyboardDismissMode = .interactive
        textView.contentInset = .zero
        textView.scrollIndicatorInsets = .zero
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        context.coordinator.configureAccessory(for: textView,
                                               options: formattingOptions,
                                               action: onFormat)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        let clampedRange = selectedRange.clamped(to: uiView.text)
        if uiView.selectedRange != clampedRange {
            uiView.selectedRange = clampedRange
        }
        uiView.scrollRangeToVisible(clampedRange)
        context.coordinator.updateAccessory(options: formattingOptions)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: MarkdownTextEditor
        private var hostingController: UIHostingController<FormattingToolbar>?
        private var currentOptions: [FormattingOption] = []
        private var actionHandler: ((FormattingOption) -> Void)?

        init(parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func configureAccessory(for textView: UITextView,
                                options: [FormattingOption],
                                action: @escaping (FormattingOption) -> Void) {
            currentOptions = options
            actionHandler = action
            let toolbar = FormattingToolbar(options: options, action: action)
            let controller = UIHostingController(rootView: toolbar)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            controller.view.backgroundColor = .clear

            let inputView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
            inputView.translatesAutoresizingMaskIntoConstraints = false
            inputView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
            inputView.allowsSelfSizing = true
            inputView.backgroundColor = .clear
            inputView.addSubview(controller.view)

            NSLayoutConstraint.activate([
                controller.view.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
                controller.view.topAnchor.constraint(equalTo: inputView.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: inputView.bottomAnchor)
            ])

            hostingController = controller
            textView.inputAccessoryView = inputView
            textView.reloadInputViews()
        }

        func updateAccessory(options: [FormattingOption]) {
            actionHandler = parent.onFormat
            guard let hostingController else { return }
            currentOptions = options
            hostingController.rootView = FormattingToolbar(options: options,
                                                           action: actionHandler ?? parent.onFormat)
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
        }
    }
}

private struct FormattingToolbar: View {
    let options: [FormattingOption]
    let action: (FormattingOption) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(options) { option in
                Button {
                    action(option)
                } label: {
                    Text(option.symbol)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private extension NSRange {
    func clamped(to text: String) -> NSRange {
        let nsString = text as NSString
        let maxLocation = max(0, min(location, nsString.length))
        let maxLength = max(0, min(length, nsString.length - maxLocation))
        return NSRange(location: maxLocation, length: maxLength)
    }
}
#endif
