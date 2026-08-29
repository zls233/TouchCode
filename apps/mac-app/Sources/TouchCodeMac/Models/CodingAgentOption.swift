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
    case codingAgents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .project: "Project"
        case .codingAgents: "Coding Agents"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "ipad.and.iphone"
        case .project: "folder"
        case .codingAgents: "terminal"
        }
    }
}

