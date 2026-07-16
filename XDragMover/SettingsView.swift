import SwiftUI
import Foundation
import AppKit

/// The Settings window content (US-8): exposes every behavior that
/// already has an adjustable knob under the hood with no UI of its own —
/// see `AppSettings` for what's persisted and why "Start at Login" isn't.
///
/// Deliberately plain `VStack`/`HStack` layout (plus a `Picker` in
/// `.segmented` style standing in for tabs — see `Tab` below) rather than
/// `Form`/`Section`/`TabView`: a real crash (`NSHostingView` throwing
/// inside `updateWindowContentSizeExtremaIfNecessary` while computing the
/// window's minimum content size) was reproduced twice with `Form` hosted
/// this way (an `NSWindow(contentViewController:)` outside the normal
/// SwiftUI `WindowGroup` lifecycle — see `AppDelegate.showSettingsWindow`).
/// `TabView` doesn't crash here, but was confirmed live to render unusably:
/// without a real `NSWindow` toolbar backing this manually-hosted window,
/// SwiftUI collapses every tab into a single hidden ">>" overflow chevron
/// in a synthesized toolbar instead of showing a normal tab bar — present
/// but undiscoverable. A `Picker(selection:)` with `.pickerStyle(.segmented)`
/// driving a plain `switch` over the selected tab has no such toolbar
/// dependency and renders identically regardless of hosting context.
///
/// Every tab's content below is a plain computed property on this same
/// `SettingsView`, not a separate `View` type taking its own parameters —
/// with everything reading directly from `self` (`settings`,
/// `$startAtLogin`, `$showingWindowPicker`, `loginItemManaging`,
/// `isValidPattern`, `modifierCheckbox`), there is no separate binding/
/// parameter list per tab that could pass the wrong value or fall out of
/// sync with another tab. Each tab additionally wraps its own content in a
/// `ScrollView` (the same proven-safe pattern as `DebugLogView` and the
/// excluded-window pattern list below), so a tab growing more settings
/// later can never again end up flush against the window edges the way the
/// single, non-scrolling full-content `VStack` this replaced eventually did.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let loginItemManaging: LoginItemManaging
    let showDebugConsole: () -> Void
    let checkForUpdatesNow: () -> Void
    let close: () -> Void

    /// Not `private`: `AppDelegate.showSettingsWindow(initialTab:)` needs to
    /// name a case (`.about`, for the "About" menu item) when constructing
    /// this view. `.about` is declared last so it's also the last tab shown
    /// — see `Tab.allCases`, iterated in declaration order by `body`'s
    /// `Picker`.
    enum Tab: String, CaseIterable, Hashable {
        case general = "General"
        case gestures = "Gestures"
        case excludedWindows = "Excluded Windows"
        case focusFollowsMouse = "Focus Follows Mouse"
        case about = "About"
    }

    @State private var selectedTab: Tab
    @State private var startAtLogin: Bool
    @State private var showingWindowPicker = false

    /// Whether the user has already dismissed the experimental-feature
    /// warning (via its "Don't show this again" checkbox) shown the first
    /// time focus-follows-mouse is turned on — see `focusFollowsMouseTab`.
    /// A simple, self-contained UI preference with no other component
    /// needing to react to it, so `@AppStorage` (matching
    /// `DebugLogView.scrollLockEnabled`'s reasoning) rather than a new
    /// `AppSettings` property.
    @AppStorage("FocusFollowsMouseWarningDismissed") private var ffmWarningDismissed = false

    /// Captured once at `init` — which, since `AppDelegate.showSettingsWindow`
    /// now creates a fresh `SettingsView` every time the window opens
    /// (rather than reusing one cached forever), genuinely reflects
    /// whatever was in effect at this specific opening. Cancel restores
    /// both of these.
    private let initialSnapshot: AppSettings.Snapshot
    private let initialStartAtLogin: Bool

    init(
        settings: AppSettings,
        loginItemManaging: LoginItemManaging,
        showDebugConsole: @escaping () -> Void,
        checkForUpdatesNow: @escaping () -> Void,
        initialTab: Tab = .general,
        close: @escaping () -> Void
    ) {
        self.settings = settings
        self.loginItemManaging = loginItemManaging
        self.showDebugConsole = showDebugConsole
        self.checkForUpdatesNow = checkForUpdatesNow
        self.close = close
        _selectedTab = State(initialValue: initialTab)
        _startAtLogin = State(initialValue: loginItemManaging.isEnabled)
        initialSnapshot = settings.makeSnapshot()
        initialStartAtLogin = loginItemManaging.isEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    // `tab.rawValue` is a plain String at this call site, not
                    // a string literal — Text(_:) only auto-localizes via
                    // the String Catalog for the LocalizedStringKey
                    // overload, so this needs an explicit conversion.
                    Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(20)

            Group {
                switch selectedTab {
                case .general: generalTab
                case .gestures: gesturesTab
                case .excludedWindows: excludedWindowsTab
                case .focusFollowsMouse: focusFollowsMouseTab
                case .about: aboutTab
                }
            }

            Divider()
            HStack {
                Button("Quit XDragMover") { quit() }
                Spacer()
                Button("Cancel") { cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { close() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560, height: 460)
        .sheet(isPresented: $showingWindowPicker) {
            WindowPickerView(provider: CGWindowListProvider()) { ownerName in
                let pattern = WindowExclusionList.exactPattern(forOwnerName: ownerName)
                if !settings.excludedWindowPatterns.contains(pattern) {
                    settings.excludedWindowPatterns.append(pattern)
                }
            }
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Start at Login", isOn: $startAtLogin)
                    .onChange(of: startAtLogin) { newValue in
                        do {
                            try loginItemManaging.setEnabled(newValue)
                        } catch {
                            DebugLogger.shared.log("Failed to change \"Start at Login\": \(error.localizedDescription)")
                            startAtLogin = loginItemManaging.isEnabled
                        }
                    }

                Toggle("Hide from Menu Bar", isOn: $settings.hideMenuBarIconEnabled)

                Text("Once hidden, relaunch XDragMover (e.g. from Finder or Launchpad) to bring this Settings window back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Check for Updates", isOn: $settings.checkForUpdatesEnabled)

                Text("Checks github.com for a newer release 5 minutes after launch, then once a day. Nothing else is sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Check Now") { checkForUpdatesNow() }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private var gesturesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Enable window move (drag anywhere)", isOn: $settings.moveEnabled)
                Toggle("Enable window resize (drag anywhere)", isOn: $settings.resizeEnabled)

                Text("Modifier key")
                    .font(.subheadline)
                HStack(spacing: 16) {
                    modifierCheckbox("Command", .command)
                    modifierCheckbox("Option", .option)
                    modifierCheckbox("Control", .control)
                    modifierCheckbox("Shift", .shift)
                }

                Text("Held together with a click to start a move or resize. Shift alone isn't allowed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Middle-Click Dock Icon for New Instance", isOn: $settings.middleClickDockNewInstanceEnabled)

                Text("Middle-clicking an app's Dock icon opens a new window/instance of it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private var excludedWindowsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Apps in this list can never be moved or resized by XDragMover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 4) {
                    ForEach(Array(settings.excludedWindowPatterns.indices), id: \.self) { index in
                        HStack {
                            let binding = excludedWindowPatternBinding(at: index)
                            TextField("regex", text: binding)
                                .textFieldStyle(.roundedBorder)
                                .foregroundStyle(isValidPattern(binding.wrappedValue) ? Color.primary : Color.red)
                            Button {
                                guard settings.excludedWindowPatterns.indices.contains(index) else { return }
                                settings.excludedWindowPatterns.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Button("Add from Open Windows…") { showingWindowPicker = true }
                    Button("Add Pattern") { settings.excludedWindowPatterns.append("") }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private var focusFollowsMouseTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Experimental — relies on an undocumented macOS mechanism and can behave unreliably in some apps (e.g. Firefox).", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Toggle("Enable", isOn: Binding(
                    get: { settings.focusFollowsMouseEnabled },
                    set: { newValue in
                        guard newValue, !ffmWarningDismissed else {
                            settings.focusFollowsMouseEnabled = newValue
                            return
                        }
                        let response = Self.presentFocusFollowsMouseWarning()
                        if response.dismissPermanently {
                            ffmWarningDismissed = true
                        }
                        if response.shouldEnable {
                            settings.focusFollowsMouseEnabled = true
                        }
                    }
                ))

                HStack {
                    Text("50ms")
                    Slider(value: $settings.focusFollowsMouseDelayMS, in: 50...1000, step: 10)
                    Text("1s")
                    // A drag-based Slider alone is imprecise for a 10ms
                    // step across a 950ms range (95 discrete positions
                    // packed into a narrow control) — easy to overshoot the
                    // exact value you want. The Stepper gives a precise,
                    // click-or-hold way to land on an exact value; the
                    // Slider stays for fast coarse positioning.
                    Stepper(
                        "",
                        value: $settings.focusFollowsMouseDelayMS,
                        in: 50...1000,
                        step: 10
                    )
                    .labelsHidden()
                }
                .disabled(!settings.focusFollowsMouseEnabled)

                Text("\(Int(settings.focusFollowsMouseDelayMS))ms — how long the cursor must stay still before the window under it receives input")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    /// Replaces the old modal `NSAlert` shown for "About XDragMover" — a
    /// real tab has room for the "Show Debug Console" button without the
    /// awkwardness of a secondary alert button, and reuses this window's
    /// own already-solved "come to the front on this menu-bar-only app"
    /// handling (`AppDelegate.showSettingsWindow`) instead of needing its
    /// own `NSApp.activate` + `runModal` call.
    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 96, height: 96)
                }

                Text("XDragMover")
                    .font(.title2)
                    .bold()

                Text("Version \(Self.appVersion) (\(Self.appBuild))")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(Self.appCopyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Show Debug Console") { showDebugConsole() }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private static var appCopyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
    }

    private func isValidPattern(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    /// Bounds-checked in both directions, unlike indexing
    /// `settings.excludedWindowPatterns[index]` directly: removing a row
    /// shrinks the array, but `excludedWindowsTab`'s `ForEach` closures for
    /// the *other*, still-live rows keep capturing their now-stale
    /// `index` until SwiftUI finishes reconciling — live-crash-reported
    /// (`EXC_BREAKPOINT`, Swift's array-bounds-check trap) deep inside
    /// SwiftUI's `Binding`/`Location` update machinery when one of those
    /// stale closures fired mid-re-render. A stale index here is simply a
    /// harmless no-op instead.
    private func excludedWindowPatternBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard settings.excludedWindowPatterns.indices.contains(index) else { return "" }
                return settings.excludedWindowPatterns[index]
            },
            set: { newValue in
                guard settings.excludedWindowPatterns.indices.contains(index) else { return }
                settings.excludedWindowPatterns[index] = newValue
            }
        )
    }

    /// Shown the first time focus-follows-mouse is turned on (see the
    /// `Toggle` binding in `focusFollowsMouseTab`), warning that it's
    /// experimental — see README's "Configurable focus-follows-mouse"
    /// section for the full reasoning (undocumented WindowServer mechanism,
    /// some apps like Firefox not fully respecting it). Uses the same
    /// activate-then-modal-`NSAlert` pattern as `StatusMenuController.quit`/
    /// `showAbout` and `AppSettings.presentMigrationAlert`, for the same
    /// reason: this is a menu-bar-only (`.accessory`-eligible) app, so the
    /// alert needs to force itself forward rather than relying on normal
    /// window activation.
    private static func presentFocusFollowsMouseWarning() -> (shouldEnable: Bool, dismissPermanently: Bool) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Focus Follows Mouse Is Experimental")
        alert.informativeText = String(localized: "This relies on an undocumented macOS mechanism that Apple could change or remove without notice, and some apps (e.g. Firefox) don't fully respect it — it may behave unreliably.")
        alert.addButton(withTitle: String(localized: "Enable Anyway"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let dontShowAgain = NSButton(checkboxWithTitle: String(localized: "Don't show this again"), target: nil, action: nil)
        dontShowAgain.state = .off
        alert.accessoryView = dontShowAgain
        NSApp.activate(ignoringOtherApps: true)
        let shouldEnable = alert.runModal() == .alertFirstButtonReturn
        return (shouldEnable, dontShowAgain.state == .on)
    }

    /// A checkbox bound to whether `modifier` is included in
    /// `settings.gestureModifier`, toggled by adding/removing just that bit
    /// from the current set. Rejects the resulting combination (leaving the
    /// checkbox visually unchanged, since the getter re-reads the
    /// unmodified setting) if it wouldn't be `isValid` — e.g. unchecking
    /// everything but Shift.
    // `title` is `LocalizedStringKey`, not `String`: a plain String
    // parameter would receive the caller's literal ("Command", "Option", …)
    // as an already-resolved String by the time it reaches Toggle(_:isOn:),
    // which silently skips String Catalog lookup — Toggle only auto-
    // localizes through its LocalizedStringKey-taking overload.
    private func modifierCheckbox(_ title: LocalizedStringKey, _ modifier: GestureModifier) -> some View {
        Toggle(title, isOn: Binding(
            get: { settings.gestureModifier.contains(modifier) },
            set: { isOn in
                var newModifier = settings.gestureModifier
                if isOn {
                    newModifier.insert(modifier)
                } else {
                    newModifier.remove(modifier)
                }
                guard newModifier.isValid else { return }
                settings.gestureModifier = newModifier
            }
        ))
        .toggleStyle(.checkbox)
    }

    /// Mirrors `StatusMenuController.quit()` exactly (same strings, same
    /// activate-then-modal-`NSAlert` confirmation pattern) so both entry
    /// points behave identically and share the same String Catalog
    /// entries rather than duplicating new ones.
    private func quit() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit XDragMover?")
        alert.informativeText = String(localized: "Window move, resize, and focus-follows-mouse will stop working until you relaunch it.")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func cancel() {
        settings.restore(initialSnapshot)
        if startAtLogin != initialStartAtLogin {
            do {
                try loginItemManaging.setEnabled(initialStartAtLogin)
                startAtLogin = initialStartAtLogin
            } catch {
                DebugLogger.shared.log("Failed to revert \"Start at Login\": \(error.localizedDescription)")
            }
        }
        close()
    }
}

#Preview {
    SettingsView(
        settings: AppSettings(defaults: UserDefaults(suiteName: "preview")!),
        loginItemManaging: SMAppServiceLoginItemManager(),
        showDebugConsole: {},
        checkForUpdatesNow: {},
        close: {}
    )
}
