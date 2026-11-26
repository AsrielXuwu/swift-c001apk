import Foundation

public struct AppReleaseInfo: Sendable, Equatable {
    public let tagName: String
    public let name: String
    public let body: String
    public let htmlURL: URL
}

public enum UpdateChecker: Sendable {
    public static let releasesAPI = URL(string: "https://api.github.com/repos/TG-Twilight/c001apk/releases/latest")!

    public static func fetchLatestRelease() async throws -> AppReleaseInfo? {
        var request = URLRequest(url: releasesAPI)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let urlString = object["html_url"] as? String,
              let url = URL(string: urlString) else {
            return nil
        }
        return AppReleaseInfo(
            tagName: tag,
            name: (object["name"] as? String) ?? tag,
            body: (object["body"] as? String) ?? "",
            htmlURL: url
        )
    }
}
