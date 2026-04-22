import Foundation

enum EventStatus: String, Codable {
    case success, error, waiting, info
}

struct Event: Codable, Identifiable {
    let id: UUID
    let agent: String
    let project: String
    let status: EventStatus
    let title: String
    let summary: String?
    let durationMs: Int?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        agent: String,
        project: String,
        status: EventStatus,
        title: String,
        summary: String? = nil,
        durationMs: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.agent = agent
        self.project = project
        self.status = status
        self.title = title
        self.summary = summary
        self.durationMs = durationMs
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.agent = try c.decode(String.self, forKey: .agent)
        self.project = try c.decode(String.self, forKey: .project)
        self.status = try c.decode(EventStatus.self, forKey: .status)
        self.title = try c.decode(String.self, forKey: .title)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        self.timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }
}

extension Event {
    /// Canonical sample `Event` used by the Settings Sandbox. Centralised
    /// here so the Sandbox preview (`SettingsSandboxRail.previewEvent`)
    /// and the actual notification dispatched by the Sandbox's Trigger
    /// button (`AppDelegate.triggerTestNotification`) stay in lockstep —
    /// same title, same summary, same duration. Previously they drifted
    /// apart (preview showed duration, trigger didn't) and users saw a
    /// different pill from what they had been previewing.
    static func preview(
        status: EventStatus,
        project: String = "tockk · preview"
    ) -> Event {
        let (title, summary, durationMs): (String, String?, Int?) = {
            switch status {
            case .success: return ("빌드 완료", "56 tests · 0 failed", 3_200)
            case .error:   return ("테스트 실패", "2 failed of 56", 12_000)
            case .waiting: return ("권한 요청", "write to ~/.zshrc?", nil)
            case .info:    return ("작업 중", "refactoring · 32s elapsed", 32_000)
            }
        }()
        return Event(
            agent: "tockk",
            project: project,
            status: status,
            title: title,
            summary: summary,
            durationMs: durationMs
        )
    }
}

extension JSONDecoder {
    static let tockkDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
