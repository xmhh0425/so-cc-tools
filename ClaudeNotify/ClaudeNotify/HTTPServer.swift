import Foundation
import Network
import os.log

/// Reference-type data wrapper for use in closure-based receive loops.
private final class DataBuffer {
    var data = Data()
}

/// TCP HTTP server using Network.framework.
/// Listens on localhost only for Claude Code hook payloads.
@Observable
final class HTTPServer {
    private(set) var isRunning = false
    private(set) var lastError: String?

    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    private let connectionQueue = DispatchQueue(label: "com.claude-notify.connections")
    private let port: UInt16
    private let logger = Logger(subsystem: "com.claude-notify", category: "HTTPServer")

    /// Callback when a hook event is received.
    var onHookReceived: ((HookEvent, HookPayload) -> Void)?

    init(port: UInt16) {
        self.port = port
    }

    func start() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener?.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    DispatchQueue.main.async {
                        self.isRunning = true
                        self.lastError = nil
                    }
                    self.logger.info("Server listening on 127.0.0.1:\(self.port)")
                case .failed(let error):
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.lastError = "Server failed: \(error.localizedDescription)"
                    }
                    self.logger.error("Server failed: \(error)")
                case .cancelled:
                    DispatchQueue.main.async {
                        self.isRunning = false
                    }
                default:
                    break
                }
            }

            let queue = DispatchQueue(label: "com.claude-notify.server", qos: .userInitiated)
            listener?.start(queue: queue)
        } catch {
            lastError = "Failed to start server: \(error.localizedDescription)"
            logger.error("Failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        logger.info("Server stopped")
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connectionQueue.sync { activeConnections[id] = connection }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connectionQueue.sync { self?.activeConnections.removeValue(forKey: id) }
            default:
                break
            }
        }

        connection.start(queue: DispatchQueue(label: "com.claude-notify.conn.\(id)", qos: .userInitiated))

        // Use a reference-type wrapper so the closure can mutate the accumulated data
        let buffer = DataBuffer()
        readLoop(connection: connection, buffer: buffer)
    }

    private func readLoop(connection: NWConnection, buffer: DataBuffer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data {
                buffer.data.append(data)
            }

            if let error {
                self.logger.error("Receive error: \(error)")
                connection.cancel()
                self.connectionQueue.sync {
                    self.activeConnections.removeValue(forKey: ObjectIdentifier(connection))
                }
                return
            }

            // Try to parse a complete HTTP request
            if let request = HTTPParser.parseComplete(from: buffer.data) {
                self.handleRequest(request, connection: connection)
                return
            }

            if isComplete {
                // Connection closed before we got a complete request
                connection.cancel()
                self.connectionQueue.sync {
                    self.activeConnections.removeValue(forKey: ObjectIdentifier(connection))
                }
                return
            }

            // Need more data
            self.readLoop(connection: connection, buffer: buffer)
        }
    }

    private func handleRequest(_ request: HTTPRequest, connection: NWConnection) {
        // Only accept POST to our hook endpoints
        guard request.method == "POST" else {
            sendResponse(statusCode: 405, connection: connection)
            return
        }

        var event: HookEvent?
        switch request.path {
        case "/hook/stop":
            event = .stop
        case "/hook/notification":
            event = .notification
        case "/hook/stopfailure":
            event = .stopFailure
        default:
            sendResponse(statusCode: 404, connection: connection)
            return
        }

        // Parse JSON body
        guard let body = request.body,
              let payload = try? JSONDecoder().decode(HookPayload.self, from: body) else {
            sendResponse(statusCode: 400, connection: connection)
            return
        }

        // Dispatch to main actor
        if let event {
            logger.info("Received \(event.rawValue) hook")
            DispatchQueue.main.async { [weak self] in
                self?.onHookReceived?(event, payload)
            }
        }

        sendResponse(statusCode: 200, connection: connection)
    }

    private func sendResponse(statusCode: Int, connection: NWConnection) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        default: statusText = "Error"
        }

        let response = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            self?.connectionQueue.sync {
                self?.activeConnections.removeValue(forKey: ObjectIdentifier(connection))
            }
        })
    }
}
