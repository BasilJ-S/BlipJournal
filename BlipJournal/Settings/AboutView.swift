import SwiftUI

struct AboutView: View {
    init() {}

    var body: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        Form {
            Section {
                HStack(spacing: 16) {
                    BlipMark(size: 76)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Blip Journal").font(.system(.title2, design: .rounded).weight(.heavy))
                        Text("Version \(version) (\(build))").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Text("A private, simple way to notice patterns in your days by recording brief check-ins.")
            }
            Section("Privacy") { Text("Blip Journal makes no network requests and collects no data.") }
            Section("Licence") { DisclosureGroup("MIT Licence") { Text(mitLicence).font(.footnote).textSelection(.enabled) } }
            Section { Link(destination: URL(string: "https://github.com/BasilJ-S/BlipJournal")!) { Label("View source repository", systemImage: "link") }.accessibilityLabel("View Blip Journal source repository") }
        }
        .blipScreen("About")
    }

    private var mitLicence: String { """
        MIT License

        Copyright (c) 2026 Basil Jancso-Szabo

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """ }
}
