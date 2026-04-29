using System.Text.Json;

record UsageData(double SessionPct, double WeeklyPct, DateTime? SessionResetAt, DateTime? WeeklyResetAt);

static class UsageService
{
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    public static async Task<UsageData> FetchAsync()
    {
        var token = ReadToken();
        using var req = new HttpRequestMessage(HttpMethod.Get, "https://api.anthropic.com/api/oauth/usage");
        req.Headers.Add("Authorization", $"Bearer {token}");
        req.Headers.Add("anthropic-beta", "oauth-2025-04-20");

        using var res = await Http.SendAsync(req);
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        var root = doc.RootElement;

        return new UsageData(
            SessionPct: GetDouble(root, "five_hour", "utilization"),
            WeeklyPct: GetDouble(root, "seven_day", "utilization"),
            SessionResetAt: GetDate(root, "five_hour", "resets_at"),
            WeeklyResetAt: GetDate(root, "seven_day", "resets_at")
        );
    }

    static string ReadToken()
    {
        var credPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude", ".credentials.json");

        if (!File.Exists(credPath))
            throw new Exception($"인증 파일을 찾을 수 없습니다: {credPath}");

        using var doc = JsonDocument.Parse(File.ReadAllText(credPath));
        return doc.RootElement
            .GetProperty("claudeAiOauth")
            .GetProperty("accessToken")
            .GetString() ?? throw new Exception("accessToken 파싱 실패");
    }

    static double GetDouble(JsonElement root, string slot, string field)
    {
        return root.TryGetProperty(slot, out var s) &&
               s.TryGetProperty(field, out var v) &&
               v.ValueKind == JsonValueKind.Number
            ? v.GetDouble() : 0;
    }

    static DateTime? GetDate(JsonElement root, string slot, string field)
    {
        return root.TryGetProperty(slot, out var s) &&
               s.TryGetProperty(field, out var v) &&
               v.ValueKind == JsonValueKind.String &&
               DateTime.TryParse(v.GetString(), out var dt)
            ? dt : null;
    }
}
