import SwiftUI

/// Disclosure lines end with the warning, which receives emphasis.
struct ExportDisclosure: View {
    let lines: [String]

    var body: some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            Text(line)
                .font(.footnote)
                .foregroundStyle(index == lines.count - 1 ? Color.orange : Color.primary)
        }
    }
}
