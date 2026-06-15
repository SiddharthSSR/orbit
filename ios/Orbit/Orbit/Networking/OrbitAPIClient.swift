import Foundation

enum OrbitAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The backend URL is invalid."
        case .invalidResponse:
            "The backend returned an invalid response."
        case let .requestFailed(statusCode, message):
            message.isEmpty ? "Request failed with status \(statusCode)." : message
        }
    }
}

struct OrbitAPIClient {
    var baseURL: URL
    var session: URLSession

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:8000")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func listTodos() async throws -> [TodoDTO] {
        try await request(path: "/todos")
    }

    func createTodo(_ payload: TodoCreateRequest) async throws -> TodoDTO {
        try await request(path: "/todos", method: "POST", body: payload)
    }

    func updateTodo(id: UUID, payload: TodoUpdateRequest) async throws -> TodoDTO {
        try await request(path: "/todos/\(id.uuidString)", method: "PATCH", body: payload)
    }

    func deleteTodo(id: UUID) async throws {
        let _: EmptyResponse = try await request(path: "/todos/\(id.uuidString)", method: "DELETE")
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET"
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method)
        return try await send(request)
    }

    private func request<RequestBody: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: RequestBody
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: method)
        request.httpBody = try jsonEncoder.encode(body)
        return try await send(request)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw OrbitAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OrbitAPIError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw OrbitAPIError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        return try jsonDecoder.decode(Response.self, from: data)
    }

    private var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            for formatter in Self.dateDecodingFormatters() {
                if let date = formatter(value) {
                    return date
                }
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(value)"
            )
        }
        return decoder
    }

    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .formatted(Self.makeDateOnlyFormatter())
        return encoder
    }

    private static func dateDecodingFormatters() -> [(String) -> Date?] {
        [
            { Self.makeISODateTimeWithFractionalSecondsFormatter().date(from: $0) },
            { Self.makeISODateTimeFormatter().date(from: $0) },
            { Self.makeBackendDateTimeWithFractionalSecondsFormatter().date(from: $0) },
            { Self.makeBackendDateTimeFormatter().date(from: $0) },
            { Self.makeDateOnlyFormatter().date(from: $0) }
        ]
    }

    private static func makeISODateTimeWithFractionalSecondsFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeISODateTimeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func makeBackendDateTimeWithFractionalSecondsFormatter() -> DateFormatter {
        let formatter = makeBaseDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }

    private static func makeBackendDateTimeFormatter() -> DateFormatter {
        let formatter = makeBaseDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }

    private static func makeDateOnlyFormatter() -> DateFormatter {
        let formatter = makeBaseDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func makeBaseDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

private struct EmptyResponse: Decodable {}
