import Testing
@testable import OpenBlipCore

@Suite("SeededRandomNumberGenerator")
struct SeededRandomNumberGeneratorTests {
    @Test("the same seed yields the same sequence")
    func deterministic() {
        var a = SeededRandomNumberGenerator(seed: 42)
        var b = SeededRandomNumberGenerator(seed: 42)
        let first = (0..<64).map { _ in a.next() }
        let second = (0..<64).map { _ in b.next() }
        #expect(first == second)
    }

    @Test("different seeds yield different sequences")
    func seedsDiffer() {
        var a = SeededRandomNumberGenerator(seed: 1)
        var b = SeededRandomNumberGenerator(seed: 2)
        let first = (0..<16).map { _ in a.next() }
        let second = (0..<16).map { _ in b.next() }
        #expect(first != second)
        #expect(Set(first).count == first.count, "no repeats in a short run")
    }

    @Test("matches the SplitMix64 reference output for seed 0")
    func referenceVector() {
        // First outputs of SplitMix64 with state 0, as published by Vigna.
        var rng = SeededRandomNumberGenerator(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(rng.next() == 0x06C4_5D18_8009_454F)
    }

    @Test("works as a RandomNumberGenerator for the standard library")
    func drivesStandardLibrary() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let values = (0..<100).map { _ in Int.random(in: 0..<10, using: &rng) }
        #expect(values.allSatisfy { (0..<10).contains($0) })
        #expect(Set(values).count > 1)
    }
}
