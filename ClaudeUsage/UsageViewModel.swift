import Foundation
import Security

struct UsageData {
    var sessionPct: Double
    var sessionResetAt: Date?
    var weeklyPct: Double
    var weeklyResetAt: Date?
}

@MainActor
class UsageViewModel: ObservableObject {
    @Published var data: UsageData?
    @Published var errorMsg: String?
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    var onTitleChange: ((String) -> Void)?

    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: TimeInterval = 60

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            await doFetch()
            try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
            if !Task.isCancelled { refresh() }
        }
    }

    private func doFetch() async {
        isLoading = true
        errorMsg = nil

        do {
            let raw = try await fetchUsageAPI()
            data = parse(raw)
            lastUpdated = Date()
            onTitleChange?(menuTitle())
        } catch {
            errorMsg = error.localizedDescription
            onTitleChange?("⚠ --")
        }
        isLoading = false
    }

    private func menuTitle() -> String {
        guard let d = data else { return "☁ --" }
        let dominant = max(d.sessionPct, d.weeklyPct)
        let icon = dominant >= 80 ? "🔴" : dominant >= 50 ? "🟡" : "🟢"
        return "\(icon) \(String(format: "%3d%%", Int(dominant)))"
    }
}

private func readToken() throws -> String {
    let query: [String: Any] = [
        kSecClass as String:            kSecClassGenericPassword,
        kSecAttrService as String:      "Claude Code-credentials",
        kSecReturnData as String:       true,
        kSecMatchLimit as String:       kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String
    else {
        throw URLError(.userAuthenticationRequired)
    }
    return token
}

private struct RawUsage: Decodable {
    struct Slot: Decodable {
        let utilization: Double?
        let resets_at: String?
    }
    let five_hour: Slot?
    let seven_day: Slot?
}

private func fetchUsageAPI() async throws -> RawUsage {
    let token = try readToken()
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    req.timeoutInterval = 15

    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(RawUsage.self, from: data)
}

private func parse(_ raw: RawUsage) -> UsageData {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    func toDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s)
    }

    return UsageData(
        sessionPct:    raw.five_hour?.utilization ?? 0,
        sessionResetAt: toDate(raw.five_hour?.resets_at),
        weeklyPct:     raw.seven_day?.utilization ?? 0,
        weeklyResetAt: toDate(raw.seven_day?.resets_at)
    )
}
