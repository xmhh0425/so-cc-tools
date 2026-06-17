import Foundation
import os.log

/// kqueue-based file watcher for ~/.claude/settings.json.
/// Re-establishes on delete/rename (CC Switch atomic write pattern).
final class SettingsWatcher {
    private let logger = Logger(subsystem: "com.claude-notify", category: "SettingsWatcher")
    private let fileURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.claude-notify.settings-watch")
    private var debounceWork: DispatchWorkItem?
    private var retryWork: DispatchWorkItem?
    private var retryCount = 0
    private let maxRetries = 30

    /// Suppress flag: set before app writes, cleared after.
    private var isSelfWriting = false

    /// Callback fired on main queue when settings.json changes externally, after debounce.
    var onChange: (() -> Void)?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func start() {
        queue.async { [weak self] in self?.establish() }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.retryWork?.cancel()
            self.retryWork = nil
            self.debounceWork?.cancel()
            self.debounceWork = nil
            self.source?.cancel()
            self.source = nil
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
    }

    /// Call before the app writes settings.json.
    /// Sets the flag on `queue` so all `isSelfWriting` access stays serialized
    /// on the same queue as the file-event handler (no cross-thread race).
    /// The serial queue guarantees this runs before the write's fs event,
    /// which the kernel only delivers after the write completes.
    func beginSelfWrite() {
        queue.async { [weak self] in
            self?.isSelfWriting = true
        }
    }

    /// Call after the app finishes writing.
    func endSelfWrite() {
        // Brief grace period for the atomic rename to complete
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isSelfWriting = false
        }
    }

    // MARK: - Private

    private func establish() {
        // Close any existing fd
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        source?.cancel()
        source = nil

        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else {
            // File may not exist yet — retry
            if retryCount < maxRetries {
                retryCount += 1
                logger.info("File not found, retrying (\(self.retryCount)/\(self.maxRetries))...")
                retryWork?.cancel()
                retryWork = DispatchWorkItem { [weak self] in self?.establish() }
                queue.asyncAfter(deadline: .now() + 1.0, execute: retryWork!)
            } else {
                logger.error("Gave up waiting for \(self.fileURL.path)")
            }
            return
        }

        retryCount = 0
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )

        src.setEventHandler { [weak self] in
            self?.handleFileEvent(flags: src.data)
        }

        src.setCancelHandler { [fd] in
            close(fd)
        }

        source = src
        src.resume()
        logger.info("Watching \(self.fileURL.path)")
    }

    private func handleFileEvent(flags: DispatchSource.FileSystemEvent) {
        if isSelfWriting {
            logger.debug("Ignoring self-write")
            return
        }

        if flags.contains(.delete) || flags.contains(.rename) {
            // Inode replaced (atomic write). Re-establish on the new inode.
            logger.info("File replaced (delete/rename), re-establishing...")
            retryCount = 0
            queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.establish()
                self?.scheduleCallback()
            }
        } else {
            scheduleCallback()
        }
    }

    private func scheduleCallback() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isSelfWriting else { return }
            DispatchQueue.main.async {
                self.onChange?()
            }
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)  // 500ms debounce
    }

    deinit {
        // Cancel source first — its cancel handler will close the fd.
        // Do NOT close fd here to avoid double-close: if we close first,
        // the OS may reuse the fd number, and the cancel handler would
        // then close an unrelated file descriptor.
        source?.cancel()
    }
}
