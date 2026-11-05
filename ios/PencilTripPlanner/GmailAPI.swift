import Foundation

// MARK: - Gmail REST (URLSession, no SDK)

enum GmailAPIError: Error, LocalizedError {
    case transport(Error)
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .transport(let e):
            return "Network error: \(e.localizedDescription)"
        case .http(let code, let body):
            return "Gmail API error \(code): \(body.prefix(200))"
        case .decoding(let d):
            return "Couldn't parse Gmail response: \(d)"
        }
    }
}

struct GmailMessageMeta: Identifiable, Hashable {
    let id: String
    let threadId: String
    let from: String
    let subject: String
    let date: Date?
    let snippet: String
}

struct GmailMessageBody {
    let id: String
    let subject: String
    let from: String
    let date: Date?
    let plainText: String
}

private struct MessageListResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let threadId: String
    }
    let messages: [Item]?
}

private struct MetadataResponse: Decodable {
    let id: String
    let threadId: String
    let snippet: String?
    struct Payload: Decodable {
        struct Header: Decodable {
            let name: String
            let value: String
        }
        let headers: [Header]?
    }
    let payload: Payload?
}

private struct FullMessageResponse: Decodable {
    let id: String
    let snippet: String?
    struct Payload: Decodable {
        let mimeType: String?
        struct Header: Decodable {
            let name: String
            let value: String
        }
        let headers: [Header]?
        struct Body: Decodable {
            let data: String?
        }
        let body: Body?
        let parts: [Payload]?
    }
    let payload: Payload?
}

private struct ProfileResponse: Decodable {
    let emailAddress: String?
}

enum GmailAPI {
    static let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    // MARK: - Search booking confirmations (last 180 days)

    static func searchConfirmations(token: String, maxResults: Int = 25) async throws -> [GmailMessageMeta] {
        var comps = URLComponents(string: base + "/messages")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: "newer_than:180d (subject:(confirmation OR itinerary OR e-ticket OR booking OR reservation))"),
            URLQueryItem(name: "maxResults", value: "\(maxResults)"),
        ]
        let list: MessageListResponse = try await get(url: comps.url!, token: token)
        let items = list.messages ?? []
        // Fetch headers concurrently; tolerate individual failures.
        return try await withThrowingTaskGroup(of: GmailMessageMeta?.self) { group in
            for item in items {
                group.addTask { try? await fetchMetadata(id: item.id, token: token) }
            }
            var out: [GmailMessageMeta] = []
            for try await meta in group {
                if let meta = meta { out.append(meta) }
            }
            return out.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
    }

    private static func fetchMetadata(id: String, token: String) async throws -> GmailMessageMeta {
        var comps = URLComponents(string: base + "/messages/\(id)")!
        comps.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date"),
        ]
        let r: MetadataResponse = try await get(url: comps.url!, token: token)
        let headers = Dictionary(
            uniqueKeysWithValues: (r.payload?.headers ?? []).map { ($0.name.lowercased(), $0.value) }
        )
        return GmailMessageMeta(
            id: r.id,
            threadId: r.threadId,
            from: headers["from"] ?? "",
            subject: headers["subject"] ?? "",
            date: headers["date"].flatMap(parseEmailDate),
            snippet: r.snippet ?? ""
        )
    }

    // MARK: - Full message body (prefer text/plain, fallback to stripped HTML)

    static func getMessageBody(id: String, token: String) async throws -> GmailMessageBody {
        var comps = URLComponents(string: base + "/messages/\(id)")!
        comps.queryItems = [URLQueryItem(name: "format", value: "full")]
        let r: FullMessageResponse = try await get(url: comps.url!, token: token)
        var plain = ""
        var html = ""
        if let payload = r.payload {
            collectText(from: payload, plain: &plain, html: &html)
        }
        let headers = Dictionary(
            uniqueKeysWithValues: (r.payload?.headers ?? []).map { ($0.name.lowercased(), $0.value) }
        )
        var text = plain
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = html.isEmpty ? (r.snippet ?? "") : stripHTML(html)
        }
        return GmailMessageBody(
            id: r.id,
            subject: headers["subject"] ?? "",
            from: headers["from"] ?? "",
            date: headers["date"].flatMap(parseEmailDate),
            plainText: text
        )
    }

    private static func collectText(from payload: FullMessageResponse.Payload, plain: inout String, html: inout String) {
        if let data = payload.body?.data, !data.isEmpty {
            if payload.mimeType == "text/plain", plain.isEmpty {
                plain = decodeBase64URL(data) ?? ""
            } else if payload.mimeType == "text/html", html.isEmpty {
                html = decodeBase64URL(data) ?? ""
            }
        }
        for part in payload.parts ?? {
            collectText(from: part, plain: &plain, html: &html)
            if !plain.isEmpty && !html.isEmpty { return }
        }
    }

    // MARK: - Profile

    static func fetchProfileEmail(token: String) async throws -> String {
        let r: ProfileResponse = try await get(url: URL(string: base + "/profile")!, token: token)
        return r.emailAddress ?? ""
    }

    // MARK: - HTTP plumbing

    private static func get<T: Decodable>(url: URL, token: String) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw GmailAPIError.transport(error)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw GmailAPIError.decoding("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GmailAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GmailAPIError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Gmail uses unpadded base64url.
    static func decodeBase64URL(_ s: String) -> String? {
        var t = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = t.count % 4
        if rem > 0 { t += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: t) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func stripHTML(_ s: String) -> String {
        var t = s.replacingOccurrences(
            of: "(?s)<(script|style)[^>]*>.*?</\\1>",
            with: " ",
            options: .regularExpression
        )
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        ]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseEmailDate(_ s: String) -> Date? {
        var t = s.replacingOccurrences(of: "\\s*\\([^\\)]*\\)\\s*$", with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm Z",
            "d MMM yyyy HH:mm:ss Z",
        ] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        return nil
    }
}
