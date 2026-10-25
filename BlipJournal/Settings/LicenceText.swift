import Foundation

/// Turns a licence file hard-wrapped for a terminal into text that wraps to the screen.
///
/// Only line breaks move; every word stays as written, so the bundled file can ship
/// verbatim, as its licence asks, while About shows it readably.
enum LicenceText {
    /// Joins the lines of each paragraph with single spaces and keeps blank-line paragraph
    /// breaks. Rules made only of dashes are dropped. A paragraph's all-caps heading line
    /// ("PREAMBLE") and every `Copyright <year>` line keep a line of their own.
    static func reflowed(_ text: String) -> String {
        var paragraphs: [[String]] = [[]]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !(paragraphs.last?.isEmpty ?? true) { paragraphs.append([]) }
            } else if line.allSatisfy({ $0 == "-" }) {
                continue
            } else {
                paragraphs[paragraphs.count - 1].append(line)
            }
        }
        return paragraphs
            .filter { !$0.isEmpty }
            .map(reflowParagraph)
            .joined(separator: "\n\n")
    }

    private static func reflowParagraph(_ lines: [String]) -> String {
        var output: [String] = []
        var canJoin = false
        for (index, line) in lines.enumerated() {
            let standsAlone = isCopyright(line) || (index == 0 && lines.count > 1 && isHeading(line))
            if canJoin && !standsAlone {
                output[output.count - 1] += " " + line
            } else {
                output.append(line)
            }
            canJoin = !standsAlone
        }
        return output.joined(separator: "\n")
    }

    /// "PERMISSION & CONDITIONS", but not an all-caps sentence, which has punctuation.
    private static func isHeading(_ line: String) -> Bool {
        line.contains(where: \.isLetter)
            && line.allSatisfy { $0.isUppercase || $0 == " " || $0 == "&" }
    }

    /// "Copyright 2014 The Nunito Project Authors", but not a wrapped "Copyright Holder."
    private static func isCopyright(_ line: String) -> Bool {
        line.hasPrefix("Copyright ") && line.dropFirst("Copyright ".count).first?.isNumber == true
    }
}
