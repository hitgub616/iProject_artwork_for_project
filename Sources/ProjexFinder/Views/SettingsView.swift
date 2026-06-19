import SwiftUI

/// App settings sheet. Currently focused on appearance; designed to grow.
struct SettingsView: View {
    @Bindable var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 18)

            Divider()

            // MARK: Appearance
            VStack(alignment: .leading, spacing: 10) {
                Label("Appearance", systemImage: "paintpalette")
                    .font(.headline)
                    .padding(.top, 18)

                Picker("Theme", selection: $store.appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.label, systemImage: theme.symbol).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("Choose how iProject looks. **System** follows your macOS appearance.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 440, height: 260)
    }
}
