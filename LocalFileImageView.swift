//
//  LocalFileImageView.swift
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct LocalFileImageView: View {
    let fileURL: URL
    @State private var image: Image? = nil

    var body: some View {
        ZStack {
            if let image = image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .overlay { ProgressView().scaleEffect(0.8) }
                    .task { await loadImage() }
            }
        }
    }

    @MainActor
    private func setImage(_ new: Image?) {
        self.image = new
    }

    private func loadImageSync() -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(contentsOfFile: fileURL.path) {
            return Image(uiImage: ui)
        }
        #elseif canImport(AppKit)
        if let ns = NSImage(contentsOf: fileURL) {
            return Image(nsImage: ns)
        }
        #endif
        return nil
    }

    private func loadImage() async {
        // Load off the main thread
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = loadImageSync()
                DispatchQueue.main.async {
                    setImage(img)
                    continuation.resume()
                }
            }
        }
    }
}