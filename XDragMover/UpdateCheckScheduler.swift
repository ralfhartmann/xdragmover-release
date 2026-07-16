import Foundation

/// Outcome of a single update check — unlike the scheduled/automatic path
/// (which only ever *acts* on `.updateAvailable`, via `onUpdateAvailable`),
/// a user-initiated check (US-22: the menu bar item's "Check for
/// Updates…" and Settings' "Check Now" button) needs to report back
/// regardless of outcome, the same way any standard "check for updates
/// now" button does.
enum UpdateCheckResult {
    case upToDate
    case updateAvailable(String)
    case failed(Error)
}

/// Owns the "check 5 minutes after launch, then once a day" schedule for
/// `AppSettings.checkForUpdatesEnabled`. Deliberately thin — mirrors this
/// codebase's EventTap-vs-Controller split: the actual network fetch and
/// version comparison live in `UpdateChecker.swift` and are unit tested
/// directly via a fake `UpdateChecking`; this class just owns `Timer`s and
/// is exercised in tests through `performCheck()` rather than by waiting
/// on real timers.
final class UpdateCheckScheduler {
    static let initialDelay: TimeInterval = 5 * 60
    static let repeatInterval: TimeInterval = 24 * 60 * 60

    private let updateChecker: UpdateChecking
    private let currentVersionProvider: () -> String?
    private var initialTimer: Timer?
    private var repeatingTimer: Timer?

    /// Fired on the main thread whenever a check finds a version newer
    /// than `currentVersionProvider()`.
    var onUpdateAvailable: ((String) -> Void)?

    init(
        updateChecker: UpdateChecking = GitHubReleaseUpdateChecker(),
        currentVersionProvider: @escaping () -> String? = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        }
    ) {
        self.updateChecker = updateChecker
        self.currentVersionProvider = currentVersionProvider
    }

    func start() {
        stop()
        initialTimer = Timer.scheduledTimer(withTimeInterval: Self.initialDelay, repeats: false) { [weak self] _ in
            self?.performCheck()
            self?.repeatingTimer = Timer.scheduledTimer(withTimeInterval: Self.repeatInterval, repeats: true) { [weak self] _ in
                self?.performCheck()
            }
        }
    }

    func stop() {
        initialTimer?.invalidate()
        repeatingTimer?.invalidate()
        initialTimer = nil
        repeatingTimer = nil
    }

    /// Not private: tests call this directly to exercise the fetch/compare
    /// logic synchronously instead of waiting on real `Timer`s. Only ever
    /// acts on `.updateAvailable` (via `onUpdateAvailable`) and logs
    /// `.failed` — `.upToDate` is silently a no-op, matching this being the
    /// unattended, scheduled path (nothing should interrupt the user for a
    /// routine "you're current" result).
    func performCheck() {
        checkNow { [weak self] result in
            switch result {
            case .updateAvailable(let latest):
                self?.onUpdateAvailable?(latest)
            case .failed(let error):
                // `checkNow`'s completion always runs on the main thread
                // (see its doc comment) even though the closure's type
                // isn't itself `@MainActor` — same pattern as
                // `WindowMoveEventTap.handle`'s `MainActor.assumeIsolated`.
                MainActor.assumeIsolated {
                    DebugLogger.shared.log("Update check failed: \(error.localizedDescription)")
                }
            case .upToDate:
                break
            }
        }
    }

    /// Runs a single check and reports every outcome (unlike `performCheck`)
    /// — for a user-initiated check (US-22), which must give feedback
    /// whether or not a new version turns out to be available. `completion`
    /// is always called on the main thread.
    func checkNow(completion: @escaping (UpdateCheckResult) -> Void) {
        guard let current = currentVersionProvider() else { return }
        updateChecker.fetchLatestVersion { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let latest):
                    if SemanticVersion.isNewer(latest, than: current) {
                        completion(.updateAvailable(latest))
                    } else {
                        completion(.upToDate)
                    }
                case .failure(let error):
                    completion(.failed(error))
                }
            }
        }
    }
}
