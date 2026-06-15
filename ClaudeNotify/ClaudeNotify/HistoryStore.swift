import Foundation
import os.log

/// Persists notification history as a JSON file.
@Observable
final class HistoryStore {
    private(set) var records: [NotificationRecord] = []
    private let logger = Logger(subsystem: "com.claude-notify", category: "History")

    private let fileURL: URL
    private let maxRecords = 200
    private var saveTask: Task<Void, Never>?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("ClaudeNotify", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("history.json")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        load()
    }

    func add(event: HookEvent, message: String, project: String?) {
        let record = NotificationRecord(event: event, message: message, project: project)
        records.insert(record, at: 0)

        // Trim to max
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }

        // Debounced save
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    // MARK: - Private

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([NotificationRecord].self, from: data)
        } catch {
            logger.error("Failed to load history: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error)")
        }
    }
}
