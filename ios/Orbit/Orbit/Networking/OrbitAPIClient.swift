import Foundation

protocol TodoAPIClientProtocol: Sendable {
    func listTodos() async throws -> [TodoDTO]
    func createTodo(_ payload: TodoCreateRequest) async throws -> TodoDTO
    func updateTodo(id: UUID, payload: TodoUpdateRequest) async throws -> TodoDTO
    func deleteTodo(id: UUID) async throws
}

protocol BillAPIClientProtocol: Sendable {
    func listBills() async throws -> [BillDTO]
    func createBill(_ payload: BillCreateRequest) async throws -> BillDTO
    func updateBill(id: UUID, payload: BillUpdateRequest) async throws -> BillDTO
    func deleteBill(id: UUID) async throws
}

protocol MemoryAPIClientProtocol: Sendable {
    func listMemory(includeArchived: Bool, kind: String?, tag: String?) async throws -> [MemoryDTO]
    func createMemory(_ payload: MemoryCreateRequest) async throws -> MemoryDTO
    func updateMemory(id: UUID, payload: MemoryUpdateRequest) async throws -> MemoryDTO
    func deleteMemory(id: UUID) async throws
}

protocol MoodAPIClientProtocol: Sendable {
    func listMoods(limit: Int?, fromDate: Date?, toDate: Date?) async throws -> [MoodDTO]
    func createMood(_ payload: MoodCreateRequest) async throws -> MoodDTO
    func updateMood(id: UUID, payload: MoodUpdateRequest) async throws -> MoodDTO
    func deleteMood(id: UUID) async throws
}

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

struct OrbitAPIClient: TodoAPIClientProtocol, BillAPIClientProtocol, MemoryAPIClientProtocol, MoodAPIClientProtocol, @unchecked Sendable {
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

    func listBills() async throws -> [BillDTO] {
        try await request(path: "/bills")
    }

    func createBill(_ payload: BillCreateRequest) async throws -> BillDTO {
        try await request(path: "/bills", method: "POST", body: payload)
    }

    func updateBill(id: UUID, payload: BillUpdateRequest) async throws -> BillDTO {
        try await request(path: "/bills/\(id.uuidString)", method: "PATCH", body: payload)
    }

    func deleteBill(id: UUID) async throws {
        let _: EmptyResponse = try await request(path: "/bills/\(id.uuidString)", method: "DELETE")
    }

    func listMemory(includeArchived: Bool = false, kind: String? = nil, tag: String? = nil) async throws -> [MemoryDTO] {
        var queryItems = [URLQueryItem(name: "include_archived", value: includeArchived ? "true" : "false")]
        if let kind, !kind.isEmpty {
            queryItems.append(URLQueryItem(name: "kind", value: kind))
        }
        if let tag, !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }
        let memoryItems: [MemoryDTO] = try await request(path: "/memory", queryItems: queryItems)
        return memoryItems
    }

    func createMemory(_ payload: MemoryCreateRequest) async throws -> MemoryDTO {
        try await request(path: "/memory", method: "POST", body: payload)
    }

    func updateMemory(id: UUID, payload: MemoryUpdateRequest) async throws -> MemoryDTO {
        try await request(path: "/memory/\(id.uuidString)", method: "PATCH", body: payload)
    }

    func deleteMemory(id: UUID) async throws {
        let _: EmptyResponse = try await request(path: "/memory/\(id.uuidString)", method: "DELETE")
    }

    func listMoods(limit: Int? = nil, fromDate: Date? = nil, toDate: Date? = nil) async throws -> [MoodDTO] {
        var queryItems: [URLQueryItem] = []
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let fromDate {
            queryItems.append(URLQueryItem(name: "from_date", value: Self.makeDateOnlyFormatter().string(from: fromDate)))
        }
        if let toDate {
            queryItems.append(URLQueryItem(name: "to_date", value: Self.makeDateOnlyFormatter().string(from: toDate)))
        }

        let moods: [MoodDTO] = try await request(path: "/moods", queryItems: queryItems)
        return moods
    }

    func createMood(_ payload: MoodCreateRequest) async throws -> MoodDTO {
        try await request(path: "/moods", method: "POST", body: payload)
    }

    func updateMood(id: UUID, payload: MoodUpdateRequest) async throws -> MoodDTO {
        try await request(path: "/moods/\(id.uuidString)", method: "PATCH", body: payload)
    }

    func deleteMood(id: UUID) async throws {
        let _: EmptyResponse = try await request(path: "/moods/\(id.uuidString)", method: "DELETE")
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method, queryItems: queryItems)
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

    private func makeRequest(path: String, method: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw OrbitAPIError.invalidURL
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OrbitAPIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let finalURL = components.url else {
            throw OrbitAPIError.invalidURL
        }

        var request = URLRequest(url: finalURL)
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
