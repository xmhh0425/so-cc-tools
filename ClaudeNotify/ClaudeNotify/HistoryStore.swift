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
        // Capture a snapshot while still on the calling thread (main),
        // so the Task reads a consistent copy instead of racing with future mutations.
        let snapshot = records
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveSnapshot(snapshot)
        }
    }

    func clearAll() {
        // Cancel any pending debounced save, otherwise a stale snapshot
        // scheduled by a recent add() would write the cleared records back.
        saveTask?.cancel()
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

    /// Save a pre-captured snapshot — safe to call from any thread.
    private func saveSnapshot(_ snapshot: [NotificationRecord]) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error)")
        }
    }
}
