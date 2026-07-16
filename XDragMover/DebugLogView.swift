import SwiftUI

/// The debug window content described in the README: a scrolling list of
/// timestamped debug lines, plus a status indicator for the Accessibility
/// permission.
struct DebugLogView: View {
    @ObservedObject var logger: DebugLogger
    @ObservedObject var permissionManager: AccessibilityPermissionManager

    /// When on, new log lines no longer auto-scroll the view to the bottom,
    /// so the user can freely scroll back through history without being
    /// yanked back down on every new entry. Off (auto-scroll-to-newest) is
    /// the default; persisted via `@AppStorage` since it's a simple,
    /// self-contained UI preference with no other component needing to
    /// react to it — unlike `AppSettings`' properties, which broadcast
    /// changes to event taps/controllers.
    @AppStorage("DebugConsoleScrollLockEnabled") private var scrollLockEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusBar
            Divider()
            logList
        }
        .frame(minWidth: 480, minHeight: 320)
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(permissionManager.isTrusted ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            // Explicit LocalizedStringKey conversion: a ternary of two
            // string literals infers as plain String at this call site, and
            // Text(_:) only auto-localizes via the String Catalog through
            // its LocalizedStringKey-taking overload.
            Text(LocalizedStringKey(permissionManager.isTrusted
                 ? "Accessibility access granted"
                 : "Accessibility access not granted"))
                .font(.callout)
            Spacer()
            Toggle(isOn: $scrollLockEnabled) {
                Image(systemName: scrollLockEnabled ? "lock.fill" : "lock.open")
            }
            .toggleStyle(.button)
            // The default `.toggleStyle(.button)` chrome renders the same
            // neutral-grey background whether on or off — an icon-only
            // (Text-less) label doesn't get the usual tinted "pressed"
            // look, so without an explicit `.tint` the button visually
            // looks inactive/unpressed even while scroll lock is engaged.
            // `.tint` makes the on-state fill with the accent color, the
            // same way other macOS toolbar toggle buttons indicate "active".
            .tint(.accentColor)
            .help("Scroll Lock: keep the console scrolled to the newest line when off, or scroll freely when on.")
            Button("Clear") { logger.clear() }
        }
        .padding(10)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(logger.entries) { entry in
                        Text(entry.formatted)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .onChange(of: logger.entries.count) { _ in
                guard !scrollLockEnabled, let last = logger.entries.last else { return }
                withAnimation {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

#Preview {
    let logger = DebugLogger()
    logger.log("XDragMover started.")
    logger.log("Window under mouse: Finder – \"Downloads\" (#42)")
    return DebugLogView(logger: logger, permissionManager: AccessibilityPermissionManager())
}
