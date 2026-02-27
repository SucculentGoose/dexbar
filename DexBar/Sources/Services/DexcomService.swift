import Foundation

enum DexcomRegion: String, CaseIterable, Codable {
    case us = "US"
    case ous = "Outside US"
    case jp = "Japan"

    var baseURL: String {
        switch self {
        case .us: "https://share2.dexcom.com/ShareWebServices/Services"
        case .ous: "https://shareous1.dexcom.com/ShareWebServices/Services"
        case .jp: "https://shareous1.dexcom.jp/ShareWebServices/Services"
        }
    }
}

enum DexcomError: LocalizedError {
    case invalidCredentials
    case sessionExpired
    case noReadings
    case networkError(Error)
    case serverError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Invalid Dexcom credentials."
        case .sessionExpired: "Session expired. Please reconnect."
        case .noReadings: "No recent glucose readings available."
        case .networkError(let e): "Network error: \(e.localizedDescription)"
        case .serverError(let code): "Server error (HTTP \(code))."
        case .decodingError(let e): "Data error: \(e.localizedDescription)"
        }
    }
}

actor DexcomService {
    private let region: DexcomRegion
    private var sessionID: String?

    init(region: DexcomRegion) {
        self.region = region
    }

    // MARK: - Public API

    func authenticate(username: String, password: String) async throws {
        let accountID = try await fetchAccountID(username: username, password: password)
        let session = try await fetchSessionID(accountID: accountID, password: password)
        self.sessionID = session
    }

    func getLatestReadings(maxCount: Int = 2) async throws -> [GlucoseReading] {
        guard let session = sessionID else { throw DexcomError.sessionExpired }
        return try await fetchReadings(sessionID: session, maxCount: maxCount)
    }

    func clearSession() {
        sessionID = nil
    }

    // MARK: - Private helpers

    private func fetchAccountID(username: String, password: String) async throws -> String {
        var request = urlRequest(path: "/General/AuthenticatePublisherAccount")
        let body: [String: String] = [
            "accountName": username,
            "password": password,
            "applicationId": "d8665ade-9673-4e27-9ff6-92db4ce13d13",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        // Response is a JSON string (quoted UUID)
        guard let accountID = try? JSONDecoder().decode(String.self, from: data),
              !accountID.isEmpty,
              accountID != "00000000-0000-0000-0000-000000000000" else {
            throw DexcomError.invalidCredentials
        }
        return accountID
    }

    private func fetchSessionID(accountID: String, password: String) async throws -> String {
        var request = urlRequest(path: "/General/LoginPublisherAccountById")
        let body: [String: String] = [
            "accountId": accountID,
            "password": password,
            "applicationId": "d8665ade-9673-4e27-9ff6-92db4ce13d13",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        guard let sessionID = try? JSONDecoder().decode(String.self, from: data),
              !sessionID.isEmpty,
              sessionID != "00000000-0000-0000-0000-000000000000" else {
            throw DexcomError.invalidCredentials
        }
        return sessionID
    }

    private func fetchReadings(sessionID: String, maxCount: Int = 2) async throws -> [GlucoseReading] {
        var components = URLComponents(string: "\(region.baseURL)/Publisher/ReadPublisherLatestGlucoseValues")!
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionID),
            URLQueryItem(name: "minutes", value: "1440"),
            URLQueryItem(name: "maxCount", value: "\(maxCount)"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        let raw = try JSONDecoder().decode([DexcomRawReading].self, from: data)
        let readings = raw.compactMap { $0.toGlucoseReading() }
        guard !readings.isEmpty else { throw DexcomError.noReadings }
        return readings
    }

    private func urlRequest(path: String) -> URLRequest {
        let url = URL(string: "\(region.baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw DexcomError.networkError(error)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 500 {
            // Dexcom returns 500 for bad credentials
            throw DexcomError.invalidCredentials
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DexcomError.serverError(http.statusCode)
        }
    }
}
