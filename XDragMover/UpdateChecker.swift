import Foundation

/// Compares plain `major.minor.patch` version strings, as used by
/// `VERSION.md`/`scripts/bump_version.sh` (no pre-release/build-metadata
/// suffixes) and by GitHub's `vX.Y.Z` release tags.
enum SemanticVersion {

    /// True if `candidate` (e.g. "v3.2.0" or "3.2.0") is a strictly newer
    /// version than `current`. Compares each component numerically (not
    /// lexicographically, so "3.1.10" > "3.1.9"); a missing trailing
    /// component is treated as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = components(of: candidate)
        let currentParts = components(of: current)
        let count = max(candidateParts.count, currentParts.count)
        for i in 0..<count {
            let c = i < candidateParts.count ? candidateParts[i] : 0
            let x = i < currentParts.count ? currentParts[i] : 0
            if c != x {
                return c > x
            }
        }
        return false
    }

    private static func components(of version: String) -> [Int] {
        var trimmed = version
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        return trimmed.split(separator: ".").compactMap { Int($0) }
    }
}

/// Abstraction over "fetch the latest published version", so
/// `UpdateCheckScheduler` can be unit tested without a real network call —
/// mirrors this codebase's existing protocol-plus-fake split (e.g.
/// `WindowListProviding`, `AXWindowLocating`).
protocol UpdateChecking {
    func fetchLatestVersion(completion: @escaping (Result<String, Error>) -> Void)
}

/// Queries the public release repo's GitHub Releases API for the latest
/// tag. `ralfhartmann/xdragmover-release` is already the public home for
/// signed builds regardless of whether the main development repo is
/// private — see `LICENSING.md`. No authentication needed: this is a
/// public repo, and the unauthenticated GitHub API rate limit is generous
/// enough for a once-daily check.
final class GitHubReleaseUpdateChecker: UpdateChecking {
    private static let releaseAPIURL = URL(
        string: "https://api.github.com/repos/ralfhartmann/xdragmover-release/releases/latest"
    )!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatestVersion(completion: @escaping (Result<String, Error>) -> Void) {
        let task = session.dataTask(with: Self.releaseAPIURL) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            completion(Result { try Self.parseTagName(from: data) })
        }
        task.resume()
    }

    /// Pulled out as its own pure function (rather than inlined in the
    /// `dataTask` closure) so JSON parsing is unit-testable against a
    /// canned response, without needing a live network stub.
    static func parseTagName(from data: Data) throws -> String {
        struct Release: Decodable {
            let tagName: String
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Release.self, from: data).tagName
    }
}
