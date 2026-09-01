import SwiftUI

/// Satellite buttons Cancel/Submit. Selection enlarges to 1.12-1.18 and glows (Plan §6).
struct VoiceOrbActionButton: View {
    enum Kind { case cancel, submit }
    let kind: Kind
    var highlighted: Bool
    var reduceMotion: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: kind == .cancel ? "xmark" : "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(highlighted ? .white : (kind == .cancel ? .primary : .white))
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(kind == .cancel
                              ? (highlighted ? Color.primary.opacity(0.85) : Color.white.opacity(0.62))
                              : (highlighted ? Color.blue : Color.blue.opacity(0.88)))
                        .shadow(color: highlighted && kind == .submit ? .blue.opacity(0.45) : .black.opacity(0.12),
                                radius: highlighted ? 10 : 6, y: highlighted ? 4 : 3)
                }
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: kind == .cancel ? 0.5 : 0))
                .scaleEffect(highlighted ? (kind == .submit ? 1.16 : 1.12) : 1)
                .opacity(kind == .cancel && !highlighted ? 0.85 : 1)
                .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.72), value: highlighted)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(kind == .cancel ? "Cancel voice" : "Submit voice")
    }
}
