import SwiftUI

struct AboutView: View {
    init() {}

    var body: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        Form {
            Section { Text("Blip Journal").font(.title2).accessibilityAddTraits(.isHeader); Text("A private, simple way to notice patterns in your days by recording brief check-ins."); Text("Version \(version) (\(build))") }
            Section("Privacy") { Text("Blip Journal makes no network requests and collects no data.") }
            Section("Licence") { DisclosureGroup("MIT Licence") { Text(mitLicence).font(.footnote).textSelection(.enabled) } }
            Section { Link(destination: URL(string: "https://github.com/BasilJ-S/BlipJournal")!) { Label("View source repository", systemImage: "link") }.accessibilityLabel("View Blip Journal source repository") }
        }
        .navigationTitle("About")
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
