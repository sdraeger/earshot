import SwiftUI

/// A settings section's title: serif, sentence case, in the primary ink.
struct SettingsHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.top, 6)
    }
}

/// The page title above a settings page, with one line on what it holds.
struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .serif))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .background(Theme.paper)
    }
}
