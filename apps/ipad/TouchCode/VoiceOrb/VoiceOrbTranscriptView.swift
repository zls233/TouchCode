import SwiftUI

/// Transcript pill above Orb, max 2-3 lines, subtle shadow (Plan §7).
struct VoiceOrbTranscriptView: View {
    var text: String
    var reduceTransparency: Bool = false

    var body: some View {
        Group {
            if text.isEmpty {
                Text("Listening…")
                    .foregroundStyle(.secondary)
            } else {
                Text(text)
                    .foregroundStyle(.primary)
            }
        }
        .font(.callout.weight(.medium))
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .frame(maxWidth: 300)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 18).fill(Color(.systemBackground))
            } else {
                RoundedRectangle(cornerRadius: 18).fill(.regularMaterial)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}
