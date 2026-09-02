import SwiftUI

struct StatusRow: View {
    let model: StatusRowModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.icon)
                .font(.title3)
                .foregroundStyle(colorForSeverity)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.headline)
                Text(model.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            severityBadge
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.title): \(model.detail)")
        .accessibilityValue(model.severity.accessibilityLabel)
    }

    private var colorForSeverity: Color {
        switch model.severity {
        case .normal: return .secondary
        case .active: return .green
        case .waiting: return .orange
        case .warning: return .orange
        case .error: return .red
        case .unavailable: return .secondary
        }
    }

    private var severityBadge: some View {
        Group {
            switch model.severity {
            case .active:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .waiting:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .error:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
        .frame(width: 20)
    }
}
