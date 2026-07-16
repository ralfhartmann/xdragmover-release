import SwiftUI

/// A sheet, presented from `SettingsView`, listing currently-open apps to
/// pick one to protect from move/resize. Deduplicated by `ownerName` (one
/// row per distinct app, not per window) since the generated exclusion
/// pattern protects the whole app, not one specific window instance.
///
/// Deliberately plain `ScrollView`/`LazyVStack`, not `List` — matches
/// `DebugLogView`'s proven-safe layout for this app's SwiftUI hosting setup
/// (see `SettingsView`'s doc comment for the `Form`/`Section` crash this
/// avoids).
struct WindowPickerView: View {
    let provider: WindowListProviding
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var ownerNames: [String] {
        Set(
            provider.currentWindows()
                .filter { $0.layer == WindowUnderMouseFinder.normalWindowLayer }
                .map(\.ownerName)
        )
        .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Select an app to protect its windows from move/resize.")
                .font(.callout)
                .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ownerNames, id: \.self) { name in
                        Button {
                            onSelect(name)
                            dismiss()
                        } label: {
                            Text(name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        Divider()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(10)
        }
        .frame(width: 360, height: 400)
    }
}

#Preview {
    struct PreviewProvider: WindowListProviding {
        func currentWindows() -> [WindowInfo] {
            [
                WindowInfo(windowNumber: 1, ownerName: "Finder", title: "Downloads", bounds: .zero, layer: 0),
                WindowInfo(windowNumber: 2, ownerName: "Calculator", title: nil, bounds: .zero, layer: 0),
            ]
        }
    }
    return WindowPickerView(provider: PreviewProvider(), onSelect: { _ in })
}
