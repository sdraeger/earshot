import SwiftUI

extension View {
    /// Sets notes under a settings control inside its own Form row, so an
    /// explanation reads as part of the setting instead of a row of its own.
    func settingsNote(_ notes: String...) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            self
            ForEach(notes.filter { !$0.isEmpty }, id: \.self) { note in
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
