import Combine
import Foundation
import Network

struct LocalAPIRequest {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data
}

struct LocalAPIResponse {
    let statusCode: Int
    let contentType: String
    let body: Data

    static func json(_ body: Data, statusCode: Int = 200) -> LocalAPIResponse {
        LocalAPIResponse(statusCode: statusCode, contentType: "application/json; charset=utf-8", body: body)
    }

    static func text(_ body: String, statusCode: Int = 200) -> LocalAPIResponse {
        LocalAPIResponse(statusCode: statusCode, contentType: "text/plain; charset=utf-8", body: Data(body.utf8))
    }

    static func jsonObject(_ object: Any, statusCode: Int = 200) -> LocalAPIResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return json(Data(#"{"error":"Could not encode response"}"#.utf8), statusCode: 500)
        }
        return json(data, statusCode: statusCode)
    }

    static func empty(statusCode: Int = 204) -> LocalAPIResponse {
        LocalAPIResponse(statusCode: statusCode, contentType: "text/plain; charset=utf-8", body: Data())
    }

    static func error(_ message: String, statusCode: Int) -> LocalAPIResponse {
        jsonObject(["error": message], statusCode: statusCode)
    }
}

final class LocalAPIServer: ObservableObject, @unchecked Sendable {
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Local API stopped"
    @Published private(set) var allowsLAN = false
    let port: UInt16

    private let queue = DispatchQueue(label: "com.metriday.local-api", qos: .utility)
    private var listener: NWListener?
    private var requestHandler: ((LocalAPIRequest) -> LocalAPIResponse)?

    init(port: UInt16 = 8765) {
        self.port = port
    }

    var endpoint: String {
        "\(baseEndpoint)/v1"
    }

    var baseEndpoint: String {
        "http://127.0.0.1:\(port)"
    }

    func start() {
        guard let requestHandler else {
            statusMessage = "Local API handler is unavailable"
            return
        }
        start(handler: requestHandler)
    }

    func start(handler: @escaping (LocalAPIRequest) -> LocalAPIResponse, allowLAN: Bool? = nil) {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: port) else {
            statusMessage = "Local API has an invalid port"
            return
        }

        requestHandler = handler
        if let allowLAN { allowsLAN = allowLAN }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(allowsLAN ? .any : .loopback), port: port)

        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.statusMessage = "Local API listening on \(self.endpoint)"
                    case .failed(let error):
                        self.isRunning = false
                        self.statusMessage = "Local API failed · \(error.localizedDescription)"
                        self.listener?.cancel()
                        self.listener = nil
                    case .cancelled:
                        self.isRunning = false
                        self.statusMessage = "Local API stopped"
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            requestHandler = nil
            statusMessage = "Local API failed · \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        statusMessage = "Local API stopped"
    }

    func setAllowsLAN(_ enabled: Bool) {
        guard allowsLAN != enabled else { return }
        allowsLAN = enabled
        guard listener != nil else { return }
        stop()
        start()
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state {
                connection.cancel()
            }
        }
        connection.start(queue: queue)
        receive(connection, buffered: Data())
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            var combined = buffered
            if let data { combined.append(data) }

            if let error {
                connection.cancel()
                self?.recordError(error)
                return
            }

            switch Self.parseRequest(from: combined) {
            case .incomplete:
                if isComplete {
                    connection.cancel()
                } else {
                    self?.receive(connection, buffered: combined)
                }
            case .invalid:
                self?.send(LocalAPIResponse.error("Invalid HTTP request", statusCode: 400), to: connection)
            case .request(let request):
                DispatchQueue.main.async { [weak self] in
                    let response = self?.requestHandler?(request)
                        ?? .error("Local API handler unavailable", statusCode: 503)
                    self?.send(response, to: connection)
                }
            }
        }
    }

    private func send(_ response: LocalAPIResponse, to connection: NWConnection) {
        let reason = Self.reasonPhrase(for: response.statusCode)
        let header = [
            "HTTP/1.1 \(response.statusCode) \(reason)",
            "Content-Type: \(response.contentType)",
            "Content-Length: \(response.body.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Headers: Content-Type",
            "Access-Control-Allow-Methods: GET,POST,PUT,PATCH,DELETE,OPTIONS",
            "",
            ""
        ].joined(separator: "\r\n")
        var data = Data(header.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func recordError(_ error: NWError) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Local API connection error · \(error)"
        }
    }

    private enum ParseResult {
        case incomplete
        case invalid
        case request(LocalAPIRequest)
    }

    private static func parseRequest(from data: Data) -> ParseResult {
        let separator = Data([13, 10, 13, 10])
        guard let headerRange = data.range(of: separator) else { return .incomplete }
        guard let header = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count == 3 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let bodyStart = headerRange.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard data.count >= bodyStart + contentLength else { return .incomplete }
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])
        let target = requestParts[1]
        let components = URLComponents(string: "http://127.0.0.1\(target)")
        let query = (components?.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value ?? ""
        }
        return .request(
            LocalAPIRequest(
                method: requestParts[0].uppercased(),
                path: components?.path ?? target,
                query: query,
                body: body
            )
        )
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Response"
        }
    }
}
