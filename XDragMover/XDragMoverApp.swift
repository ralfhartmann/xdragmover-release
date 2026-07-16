import SwiftUI

/// No window is declared here on purpose. The debug log window is only
/// meant to appear when the app is launched with `--debug` (see README,
/// "Debug mode"), and a `WindowGroup` scene would auto-open unconditionally
/// at launch. `AppDelegate` creates and shows that window imperatively
/// instead, once it has checked the launch arguments. `Settings` is used
/// here purely as a placeholder scene (SwiftUI requires at least one) that
/// never opens a window on its own.
@main
struct XDragMoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
