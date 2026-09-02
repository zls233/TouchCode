import Foundation

enum CodingAgentOption: String, CaseIterable, Identifiable {
    case codex
    case claudeCode = "claude-code"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }

    var isImplemented: Bool { self == .codex }
}

enum SidebarDestination: String, CaseIterable, Identifiable {
    case overview
    case project
    case codingAgent
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .project: "Project"
        case .codingAgent: "Coding Agent"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.connected.to.line.below"
        case .project: "folder"
        case .codingAgent: "terminal"
        case .diagnostics: "stethoscope"
        }
    }
}

