import Foundation
import Accelerate

enum OllamaError: LocalizedError, Equatable {
    case localOnly
    case notRunning
    case modelMissing(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .localOnly: "Somente modelos e servidor locais são permitidos."
        case .notRunning: "O Ollama não está em execução."
        case .modelMissing(let model): model.isEmpty ? "Modelo não instalado no Ollama." : "O modelo “\(model)” não está instalado no Ollama."
        case .server(let message): message.isEmpty ? "O Ollama retornou um erro." : "Erro do Ollama: \(message)"
        }
    }
}

struct OllamaMessage: Codable, Sendable, Equatable {
    var role: String
    var content: String
}

struct OllamaClient: Sendable {
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.baseURL = baseURL
    }

    // MARK: Public API

    func isRunning() async -> Bool {
        guard Self.isLocalEndpoint(baseURL) else { return false }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/version"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await Self.session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func models() async throws -> [String] {
        guard Self.isLocalEndpoint(baseURL) else { throw OllamaError.localOnly }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 10
        let data = try await send(request, model: nil)
        do {
            return try JSONDecoder().decode(TagsResponse.self, from: data).models.filter { $0.remote_host == nil && $0.remote_model == nil && Self.isLocalModel($0.name) }.map(\.name)
        } catch {
            throw OllamaError.server("Resposta inesperada ao listar modelos.")
        }
    }

    func embed(model: String, inputs: [String]) async throws -> [[Float]] {
        guard Self.isLocalModel(model) else { throw OllamaError.localOnly }
        var result: [[Float]] = []
        result.reserveCapacity(inputs.count)
        var start = 0
        while start < inputs.count {
            try Task.checkCancellation()
            let batch = Array(inputs[start..<min(start + Self.embedBatchSize, inputs.count)])
            let request = try post("api/embed", body: EmbedRequest(model: model, input: batch, truncate: true, keep_alive: Self.keepAlive), timeout: 300)
            let data = try await send(request, model: model)
            guard let decoded = try? JSONDecoder().decode(EmbedResponse.self, from: data),
                  decoded.embeddings.count == batch.count,
                  let dimension = decoded.embeddings.first?.count, dimension > 0,
                  decoded.embeddings.allSatisfy({ $0.count == dimension }) else {
                throw OllamaError.server("Resposta inesperada ao gerar embeddings.")
            }
            result += decoded.embeddings.map(Self.normalized)
            start += batch.count
        }
        return result
    }

    func chat(model: String, messages: [OllamaMessage], temperature: Double = 0.2, contextLength: Int = 8192) -> AsyncThrowingStream<String, Error> {
        let body = ChatRequest(model: model, messages: messages, stream: true,
                               options: .init(temperature: temperature, num_ctx: min(max(contextLength, 512), 8192), num_predict: 1024), keep_alive: Self.keepAlive)
        return stream(path: "api/chat", body: body, model: model, timeout: 600) { (line: ChatLine, continuation: AsyncThrowingStream<String, Error>.Continuation) in
            if let delta = line.message?.content, !delta.isEmpty { continuation.yield(delta) }
            return line.done == true
        }
    }

    func pull(model: String) -> AsyncThrowingStream<Double, Error> {
        let progress = PullProgress()
        return stream(path: "api/pull", body: PullRequest(model: model, stream: true), model: model, timeout: 600) { (line: PullLine, continuation: AsyncThrowingStream<Double, Error>.Continuation) in
            if line.status == "success" {
                continuation.yield(1)
                return true
            }
            if let value = progress.update(line) { continuation.yield(value) }
            return false
        }
    }

    static func hasModel(_ wanted: String, in installed: [String]) -> Bool {
        let wanted = wanted.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return false }
        let tagged = hasTag(wanted)
        return installed.contains { name in
            let name = name.lowercased()
            if name == wanted { return true }
            guard !tagged, hasTag(name), let colon = name.lastIndex(of: ":") else { return false }
            return name[..<colon] == wanted
        }
    }

    @discardableResult static func launchServer() -> Bool {
        let candidates = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if spawn(path, ["serve"]) { return true }
        }
        // `open` exits non-zero when the app is not installed.
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-a", "Ollama"]
        open.standardInput = FileHandle.nullDevice
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.nullDevice
        guard (try? open.run()) != nil else { return false }
        open.waitUntilExit()
        return open.terminationStatus == 0
    }

    // MARK: Internals

    private static let keepAlive = "2m"
    private static let embedBatchSize = 32

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForResource = 60 * 60 * 6
        return URLSession(configuration: configuration, delegate: LocalRedirectPolicy(), delegateQueue: nil)
    }()

    static func isLocalEndpoint(_ url: URL) -> Bool {
        url.scheme == "http" && ["127.0.0.1", "[::1]", "::1"].contains(url.host ?? "")
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }

    static func isLocalModel(_ name: String) -> Bool {
        !name.isEmpty && !name.lowercased().contains("cloud") && !name.contains("://")
    }

    private static func hasTag(_ name: String) -> Bool {
        // A tag is a colon after the last path separator ("host:5000/model" has none).
        let last = name.split(separator: "/", omittingEmptySubsequences: false).last ?? Substring(name)
        return last.contains(":")
    }

    private static func spawn(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return (try? process.run()) != nil
    }

    private static func normalized(_ vector: [Float]) -> [Float] {
        guard vector.allSatisfy(\.isFinite) else { return [Float](repeating: 0, count: vector.count) }
        let norm = vDSP.sumOfSquares(vector).squareRoot()
        guard norm > 0 else { return vector }
        return vDSP.divide(vector, norm)
    }

    private func post<Body: Encodable>(_ path: String, body: Body, timeout: TimeInterval) throws -> URLRequest {
        guard Self.isLocalEndpoint(baseURL) else { throw OllamaError.localOnly }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func send(_ request: URLRequest, model: String?) async throws -> Data {
        do {
            let (data, response) = try await Self.session.data(for: request)
            if let failure = Self.failure(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data, model: model) { throw failure }
            return data
        } catch {
            throw Self.mapped(error, model: model)
        }
    }

    /// One NDJSON object per line; `handle` returns true when the stream is complete.
    private func stream<Body: Encodable & Sendable, Line: Decodable & Sendable, Element: Sendable>(
        path: String, body: Body, model: String, timeout: TimeInterval,
        handle: @escaping @Sendable (Line, AsyncThrowingStream<Element, Error>.Continuation) -> Bool
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard Self.isLocalModel(model) else { throw OllamaError.localOnly }
                    let request = try post(path, body: body, timeout: timeout)
                    let (bytes, response) = try await Self.session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 65_536 { break }
                        }
                        throw Self.failure(status: status, body: data, model: model) ?? OllamaError.server("HTTP \(status)")
                    }
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                        if let failure = try? decoder.decode(ErrorLine.self, from: data) {
                            throw Self.failure(message: failure.error, status: 200, model: model)
                        }
                        guard let decoded = try? decoder.decode(Line.self, from: data) else { continue }
                        if handle(decoded, continuation) { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapped(error, model: model))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func failure(status: Int, body: Data, model: String?) -> OllamaError? {
        guard status != 200 else { return nil }
        let message = (try? JSONDecoder().decode(ErrorLine.self, from: body))?.error
            ?? String(data: body.prefix(300), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return failure(message: message.isEmpty ? "HTTP \(status)" : message, status: status, model: model)
    }

    private static func failure(message: String, status: Int, model: String?) -> OllamaError {
        let lowered = message.lowercased()
        let missing = status == 404
            || (lowered.contains("model") && lowered.contains("not found"))
            || lowered.contains("manifest: file does not exist")
        if missing, let model { return .modelMissing(model) }
        return .server(message)
    }

    private static func mapped(_ error: Error, model: String?) -> Error {
        if error is OllamaError || error is CancellationError { return error }
        guard let urlError = error as? URLError else { return OllamaError.server(error.localizedDescription) }
        switch urlError.code {
        case .cancelled:
            return CancellationError()
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
            return OllamaError.notRunning
        case .timedOut:
            return OllamaError.server("Tempo de resposta esgotado.")
        default:
            return OllamaError.server(urlError.localizedDescription)
        }
    }
}

// MARK: Wire formats

private struct TagsResponse: Decodable {
    struct Model: Decodable { let name: String; let remote_model: String?; let remote_host: String? }
    let models: [Model]
}

private struct EmbedRequest: Encodable, Sendable {
    let model: String
    let input: [String]
    let truncate: Bool
    let keep_alive: String
}

private struct EmbedResponse: Decodable {
    let embeddings: [[Float]]
}

private struct ChatRequest: Encodable, Sendable {
    struct Options: Encodable, Sendable {
        let temperature: Double
        let num_ctx: Int
        let num_predict: Int
    }
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let options: Options
    let keep_alive: String
}

private struct ChatLine: Decodable {
    struct Message: Decodable { let content: String? }
    let message: Message?
    let done: Bool?
}

private struct PullRequest: Encodable, Sendable {
    let model: String
    let stream: Bool
}

private struct PullLine: Decodable {
    let status: String?
    let digest: String?
    let total: Double?
    let completed: Double?
}

private struct ErrorLine: Decodable {
    let error: String
}

/// Aggregates per-layer byte counts into a monotonic 0...1 fraction. Only touched from the single task that reads the pull stream.
private final class PullProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var layers: [String: (total: Double, completed: Double)] = [:]
    private var last = -1.0

    func update(_ line: PullLine) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let digest = line.digest, let total = line.total, total > 0 else { return last < 0 ? emit(0) : nil }
        layers[digest] = (total, min(max(line.completed ?? 0, 0), total))
        let all = layers.values.reduce(0) { $0 + $1.total }
        let done = layers.values.reduce(0) { $0 + $1.completed }
        // Layers are announced one at a time, so cap below 1 until "success".
        return emit(min(done / all, 0.99))
    }

    private func emit(_ value: Double) -> Double? {
        guard value > last else { return nil }
        last = value
        return value
    }
}

/// A local server must never redirect a document request to another host.
private final class LocalRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
