import Foundation
import Darwin

struct OperationLogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let operation: String

    init(id: UUID = UUID(), timestamp: Date, operation: String) {
        self.id = id
        self.timestamp = timestamp
        self.operation = operation
    }

    var displayTime: String {
        OperationLogEntry.displayFormatter.string(from: timestamp)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

enum OperationLogReader {
    static func entries(from url: URL) -> [OperationLogEntry] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).compactMap { parse(line: String($0)) }
    }

    static func parse(line: String) -> OperationLogEntry? {
        guard let data = line.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestampText = payload["timestamp"] as? String,
              let timestamp = parseTimestamp(timestampText) else {
            return nil
        }
        let message = (payload["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let event = (payload["event"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let operation = message.isEmpty ? friendlyEvent(event) : message
        guard !operation.isEmpty else { return nil }
        return OperationLogEntry(timestamp: timestamp, operation: operation)
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        if let date = ISO8601DateFormatter.operationLog.date(from: text) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func friendlyEvent(_ event: String) -> String {
        switch event {
        case "app.started": return "应用启动"
        case "operation.started": return "开始执行操作"
        case "backend.command.started": return "开始执行后台操作"
        case "backend.command.completed": return "后台操作完成"
        case "backend.command.failed": return "后台操作失败"
        case "file.write": return "保存文件"
        default: return event.replacingOccurrences(of: ".", with: " ")
        }
    }
}

final class OperationLogWriter {
    static let shared = OperationLogWriter()

    private let lock = NSLock()
    private let sessionID = UUID().uuidString
    private var enabled = true

    private var logURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/pp-flowhub/data/operation-log.jsonl")
    }

    func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        lock.unlock()
    }

    func isEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    func record(
        _ event: String,
        message: String,
        actor: String = "app",
        component: String = "swiftui",
        details: [String: Any] = [:],
        operationID: String? = nil,
        force: Bool = false
    ) {
        lock.lock()
        let shouldWrite = enabled || force
        lock.unlock()
        guard shouldWrite else { return }

        var payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter.operationLog.string(from: Date()),
            "event": event,
            "actor": actor,
            "component": component,
            "message": Self.redact(message),
            "session_id": sessionID,
            "operation_id": operationID ?? "",
            "details": Self.redact(details),
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
            }
            var line = data
            line.append(0x0A)
            let descriptor = Darwin.open(logURL.path, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { return }
            defer { Darwin.close(descriptor) }
            line.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                _ = Darwin.write(descriptor, baseAddress, bytes.count)
            }
            _ = Darwin.fsync(descriptor)
        } catch {
            // Audit logging must never break the user's business operation.
        }
        payload.removeAll()
    }

    func environment(operationID: String? = nil) -> [String: String] {
        [
            "WORKFLOW_OPERATION_LOG": logURL.path,
            "WORKFLOW_OPERATION_LOG_ENABLED": isEnabled() ? "1" : "0",
            "WORKFLOW_OPERATION_SESSION_ID": sessionID,
            "WORKFLOW_OPERATION_ID": operationID ?? "",
        ]
    }

    private static func sensitiveKey(_ key: String) -> Bool {
        let normalized = key.replacingOccurrences(of: "-", with: "_").lowercased()
        return ["password", "passwd", "secret", "token", "api_key", "apikey", "authorization", "cookie", "keychain", "credential", "username", "user_name", "remarks", "query", "input_value"]
            .contains { normalized.contains($0) }
    }

    private static func redact(_ value: Any, key: String? = nil) -> Any {
        if let key, sensitiveKey(key) { return "[REDACTED]" }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = redact(item.value, key: item.key)
            }
        }
        if let array = value as? [Any] { return array.map { redact($0) } }
        if let string = value as? String {
            return string.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        if value is NSNull || value is String || value is NSNumber { return value }
        return String(describing: value)
    }
}

private extension ISO8601DateFormatter {
    static let operationLog: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
