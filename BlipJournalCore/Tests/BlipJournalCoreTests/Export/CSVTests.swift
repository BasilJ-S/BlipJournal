import Foundation
import Testing
@testable import BlipJournalCore

@Suite("CSV")
struct CSVTests {
    @Test("plain text is unchanged")
    func plain() {
        #expect(CSV.escape("hello") == "hello")
        #expect(CSV.escape("a-b_c.d") == "a-b_c.d")
        #expect(CSV.escape("mid dle space") == "mid dle space")
    }

    @Test("a comma forces quoting")
    func comma() {
        #expect(CSV.escape("a,b") == "\"a,b\"")
    }

    @Test("a quote forces quoting and is doubled")
    func quote() {
        #expect(CSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSV.escape("\"") == "\"\"\"\"")
    }

    @Test("CRLF inside a field is quoted and preserved")
    func crlf() {
        #expect(CSV.escape("a\r\nb") == "\"a\r\nb\"")
    }

    @Test("a lone CR or LF is quoted")
    func lf() {
        #expect(CSV.escape("a\nb") == "\"a\nb\"")
        #expect(CSV.escape("a\rb") == "\"a\rb\"")
    }

    @Test("leading or trailing whitespace is quoted")
    func edgeWhitespace() {
        #expect(CSV.escape(" a") == "\" a\"")
        #expect(CSV.escape("a ") == "\"a \"")
        #expect(CSV.escape("\ta") == "\"\ta\"")
        #expect(CSV.escape(" ") == "\" \"")
    }

    @Test("empty stays empty")
    func empty() {
        #expect(CSV.escape("") == "")
    }

    @Test("unicode passes through unquoted")
    func unicode() {
        #expect(CSV.escape("héllo wörld 🙂") == "héllo wörld 🙂")
        #expect(CSV.escape("日本語") == "日本語")
    }

    @Test("a quote followed by a combining mark is still doubled")
    func quoteWithCombiningMark() {
        // "\"" + U+0301 is one Character; the scalar-level scan and replace must see it.
        #expect(CSV.escape("a\"\u{301}b") == "\"a\"\"\u{301}b\"")
    }

    @Test("edge whitespace is detected on the scalar, not the grapheme cluster")
    func edgeWhitespaceScalar() {
        // U+0600 is a prepend character that swallows the following space into one
        // Character whose isWhitespace is false; the trailing space scalar still counts.
        #expect(CSV.escape("a\u{600} ") == "\"a\u{600} \"")
    }

    @Test("row joins with commas and ends with CRLF")
    func row() {
        #expect(CSV.row(["a", "b", "c"]) == "a,b,c\r\n")
        #expect(CSV.row(["a,b", "", "c\"d"]) == "\"a,b\",,\"c\"\"d\"\r\n")
        #expect(CSV.row([]) == "\r\n")
        #expect(CSV.row([""]) == "\r\n")
    }

    @Test("a row round-trips through the test reader")
    func roundTrip() {
        let fields = ["plain", "a,b", "q\"q", "l\nf", "c\r\nrlf", " pad ", "", "🙂"]
        #expect(CSVReader.parse(CSV.row(fields)) == [fields])
    }
}
