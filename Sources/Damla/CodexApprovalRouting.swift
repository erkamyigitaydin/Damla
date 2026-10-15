import Foundation

/// PermissionRequest precedes both Codex's automatic reviewer and its human prompt. Only a matching
/// turn_context can distinguish them. Read approval metadata, never decode message/tool payloads, and
/// retain none of the transcript. Unknown/changed formats fall back to Codex without an allow/deny.
enum CodexApprovalRouting {
    enum Reviewer: String { case user, automatic = "auto_review" }
    static let readLimit = 8 * 1024 * 1024
    static let headerLimit = 512 * 1024

    private struct Record: Decodable {
        struct Metadata: Decodable {
            var id: String?
            var turn_id: String?
            var approvals_reviewer: String?
        }
        var type: String
        var metadata: Metadata?
        private enum CodingKeys: String, CodingKey { case type, payload }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            type = try values.decode(String.self, forKey: .type)
            if type == "session_meta" || type == "turn_context" {
                metadata = try values.decode(Metadata.self, forKey: .payload)
            }
        }
    }

    static func reviewer(_ event: [String: Any]) -> Reviewer? {
        guard let session = event["session_id"] as? String, !session.isEmpty,
              let turn = event["turn_id"] as? String, !turn.isEmpty,
              let path = event["transcript_path"] as? String, path.hasPrefix("/"),
              URL(fileURLWithPath: path).pathExtension == "jsonl",
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        // Subagent hook payloads can carry the parent session_id plus the child's agent_id.
        let identity = event["agent_id"] as? String ?? session
        guard let header = try? handle.read(upToCount: headerLimit),
              let end = header.firstIndex(of: 10),
              let first = try? JSONDecoder().decode(Record.self, from: Data(header[..<end])),
              first.type == "session_meta", first.metadata?.id == identity,
              let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(readLimit) ? size - UInt64(readLimit) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let tail = try? handle.read(upToCount: readLimit) else { return nil }
        // If the tail starts mid-line, discard that partial record. Do not reconstruct or parse its content.
        let complete: Data
        if offset > 0 {
            guard let newline = tail.firstIndex(of: 10) else { return nil }
            complete = Data(tail.dropFirst(newline + 1))
        } else { complete = tail }
        return parse(complete, turn: turn)
    }

    static func parse(_ data: Data, turn: String) -> Reviewer? {
        let marker = Data("turn_context".utf8)
        for line in data.split(separator: 10).reversed() where line.range(of: marker) != nil {
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(line)) else { return nil }
            guard record.type == "turn_context" else { continue }
            // Never reuse a previous turn or an older policy for the same turn.
            guard record.metadata?.turn_id == turn, let value = record.metadata?.approvals_reviewer else { return nil }
            return Reviewer(rawValue: value)
        }
        return nil
    }
}
