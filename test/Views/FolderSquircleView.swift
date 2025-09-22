import SwiftUI

struct FolderSquircleView: View {
    let name: String
    let count: Int
    var symbolName: String? = nil
    var color: Color? = nil
    var isSelected: Bool = false
    var isPrivate: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let accentColor = color ?? .accentColor

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbolName ?? "folder.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accentColor)
                
                Spacer()
                
                if isPrivate {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.purple)
                        .opacity(0.8)
                }
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .background(Circle().fill(.blue))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(count) \(count == 1 ? "note" : "notes")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(.ultraThinMaterial, in: shape)
        .overlay(
            shape.fill((isSelected ? Color.blue : accentColor).opacity(isSelected ? 0.15 : 0.08))
        )
        .overlay {
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.55),
                            accentColor.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
        .overlay {
            shape
                .strokeBorder(
                    LinearGradient(colors: [
                        .white.opacity(0.3),
                        .white.opacity(0.05)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.65
                )
                .blendMode(.overlay)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .contentShape(shape)
    }
}

#Preview {
    FolderSquircleView(name: "Reading", count: 12, symbolName: "book", color: .purple)
        .padding()
}
