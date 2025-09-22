//
//  FolderSquircleView.swift
//

import SwiftUI

struct FolderSquircleView: View {
    let name: String
    let count: Int
    let symbolName: String
    let color: Color?
    
    private var displayColor: Color {
        color ?? .blue
    }
    
    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 16)
                .fill(displayColor.opacity(0.2))
                .frame(height: 60)
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: symbolName)
                            .font(.title2)
                            .foregroundColor(displayColor)
                        
                        Text("\(count)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(displayColor)
                    }
                }
            
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    HStack {
        FolderSquircleView(name: "Notes", count: 12, symbolName: "tray.full", color: .blue)
        FolderSquircleView(name: "Links", count: 5, symbolName: "link", color: .green)
    }
    .padding()
}