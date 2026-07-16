import Foundation
import ServiceManagement

/// Abstraction over "is this app registered to launch at login, and can
/// that be changed", so `StatusMenuController`'s toggle logic can be unit
/// tested without actually registering/unregistering a real login item.
protocol LoginItemManaging {
    /// Whether the app is currently registered to start at login.
    var isEnabled: Bool { get }

    /// Registers (`true`) or unregisters (`false`) the app as a login item.
    func setEnabled(_ enabled: Bool) throws
}

/// Thrown instead of ever calling `SMAppService` when the app isn't running
/// from a stable, installed location.
enum LoginItemError: LocalizedError {
    case appNotInStableLocation(path: String)

    var errorDescription: String? {
        switch self {
        case .appNotInStableLocation(let path):
            return """
            Refusing to change the login item while running from \
            \"\(path)\", which is not /Applications or ~/Applications.
            """
        }
    }
}

/// Real implementation backed by `SMAppService` (available since macOS 13,
/// which matches this project's deployment target — no legacy
/// `SMLoginItemSetEnabled`/helper-tool machinery needed).
struct SMAppServiceLoginItemManager: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registering/unregistering a login item ties it to the app's current
    /// bundle path. Doing this from a `make run`/`make debug` build (which
    /// lives in this project's own `build/` folder) or an Xcode/DerivedData
    /// build points the login item at a path that gets overwritten or
    /// deleted on the next build — and, worse, calling `SMAppService`
    /// register/unregister at all from such an unstable, non-Gatekeeper-
    /// approved location has been observed to make the *calling* app
    /// process itself quit outright, for both register and unregister,
    /// rather than just failing cleanly. Refusing to even attempt the call
    /// unless the app is running from a stable, installed location avoids
    /// that entirely; see DEVELOPMENT.md for how to verify this against a
    /// real `make package`/`make release` build.
    func setEnabled(_ enabled: Bool) throws {
        let path = Bundle.main.bundlePath
        guard Self.isStableApplicationsPath(path) else {
            throw LoginItemError.appNotInStableLocation(path: path)
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Whether `path` is inside `/Applications` or `~/Applications`.
    /// `homeDirectory` defaults to the real home directory but is
    /// parameterized so this pure check can be unit tested with fabricated
    /// paths, independent of `Bundle.main` (which always reflects the test
    /// runner's own location, not a real app bundle, under `make test`).
    static func isStableApplicationsPath(_ path: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        path.hasPrefix("/Applications/") || path.hasPrefix(homeDirectory + "/Applications/")
    }
}
