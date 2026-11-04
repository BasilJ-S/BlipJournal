import SwiftUI

/// The same disclosure precedes every action that shares journal data.
struct ExportDisclosure: View {
    let includesAllData: Bool

    var body: some View {
        if includesAllData {
            Text("Includes all surveys and dates.").font(.footnote)
        }
        Text("Exported files are not encrypted. Anyone with the file can read your answers.")
            .font(.footnote)
            .foregroundStyle(.orange)
    }
}
