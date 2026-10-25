import Foundation
import Testing
@testable import BlipJournal

@Suite("LicenceText")
struct LicenceTextTests {
    /// Excerpts of the bundled OFL.txt, with its wrapping, rules and trailing space.
    private let sample = """
        Copyright 2014 The Nunito Project Authors (https://github.com/googlefonts/nunito)
        Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono)

        This Font Software is licensed under the SIL Open Font License, Version 1.1.
        This license is copied below, and is also available with a FAQ at:
        http://scripts.sil.org/OFL


        -----------------------------------------------------------
        SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
        -----------------------------------------------------------

        PREAMBLE
        The goals of the Open Font License (OFL) are to stimulate worldwide
        development of collaborative font projects. The
        fonts, including any derivative works, can be bundled, embedded,\u{20}
        redistributed and/or sold with any software.

        3) No Modified Version of the Font Software may use the Reserved Font
        Name(s) unless explicit written permission is granted by the corresponding
        Copyright Holder. This restriction only applies to the primary font name as
        presented to the users.

        DISCLAIMER
        THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
        EXPRESS OR IMPLIED.
        """

    private var paragraphs: [String] {
        LicenceText.reflowed(sample).components(separatedBy: "\n\n")
    }

    @Test func joinsWrappedLinesAndKeepsParagraphBreaks() {
        #expect(paragraphs.count == 6)
        #expect(paragraphs[1] == "This Font Software is licensed under the SIL Open Font License, Version 1.1. "
            + "This license is copied below, and is also available with a FAQ at: http://scripts.sil.org/OFL")
    }

    @Test func dropsDashRulesAndCollapsesBlankRuns() {
        #expect(paragraphs[2] == "SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007")
        #expect(!LicenceText.reflowed(sample).contains("---"))
        #expect(!LicenceText.reflowed(sample).contains("\n\n\n"))
    }

    @Test func headingKeepsItsOwnLineButAllCapsBodyJoins() {
        #expect(paragraphs[3].hasPrefix("PREAMBLE\nThe goals of the Open Font License (OFL) are to stimulate worldwide development"))
        #expect(paragraphs[5] == "DISCLAIMER\nTHE FONT SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.")
    }

    @Test func copyrightLinesStaySeparateButAWrappedCopyrightHolderJoins() {
        #expect(paragraphs[0].components(separatedBy: "\n").count == 2)
        #expect(paragraphs[4].contains("granted by the corresponding Copyright Holder. This restriction"))
        #expect(!paragraphs[4].contains("\n"))
    }

    @Test func keepsEveryWordAndLeavesNoDoubleSpaces() {
        let words = { (text: String) in
            text.split(whereSeparator: \.isWhitespace).filter { !$0.allSatisfy { $0 == "-" } }
        }
        let reflowed = LicenceText.reflowed(sample)
        #expect(words(reflowed) == words(sample))
        #expect(!reflowed.contains("  "))
    }

    @Test func emptyInputStaysEmpty() {
        #expect(LicenceText.reflowed("") == "")
        #expect(LicenceText.reflowed("\n\n---\n\n") == "")
    }
}
