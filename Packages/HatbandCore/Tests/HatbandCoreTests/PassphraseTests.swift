import Foundation
import Testing
@testable import HatbandCore

/// Deterministic generator for reproducible draws (Steele, Lea & Flood 2014).
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

private let words = Passphrase.wordlist
private let wordSet = Set(words)

@Test func wordlistHas7776Words() {
    #expect(words.count == 7776)
    #expect(words.count == 6 * 6 * 6 * 6 * 6)
    #expect(EFFWordlist.words.count == words.count)
}

@Test func wordlistIsLowercaseASCIILettersAndFourHyphens() {
    let allowed = Set("abcdefghijklmnopqrstuvwxyz-")
    #expect(words.allSatisfy { !$0.isEmpty && $0.allSatisfy { allowed.contains($0) } })
    #expect(words.filter { $0.contains("-") } == ["drop-down", "felt-tip", "t-shirt", "yo-yo"])
    #expect(words.allSatisfy { !$0.hasPrefix("-") && !$0.hasSuffix("-") })
}

@Test func wordlistIsUniqueAndByteSorted() {
    #expect(wordSet.count == words.count)
    for (a, b) in zip(words, words.dropFirst()) {
        #expect(a.utf8.lexicographicallyPrecedes(b.utf8), "\(a) precedes \(b)")
    }
}

@Test func wordlistBoundsAndLengths() {
    #expect(words.first == "abacus")
    #expect(words.last == "zoom")
    #expect(words.allSatisfy { (3...9).contains($0.count) })
    #expect(words[2009] == "dropbox")
}

@Test func bitsPerWordIsLog2OfTheListSize() {
    #expect(abs(Passphrase.bitsPerWord - log2(Double(words.count))) < 1e-12)
    #expect(abs(Passphrase.bitsPerWord - 12.925) < 0.001)
    #expect(Passphrase.defaultWords == 6)
    #expect(Double(Passphrase.defaultWords) * Passphrase.bitsPerWord > 77.5)
}

@Test func generatesSixWordsFromTheList() {
    for _ in 0..<100 {
        let passphrase = Passphrase.generate()
        let parts = passphrase.split(separator: " ", omittingEmptySubsequences: false)
        #expect(parts.count == 6)
        #expect(parts.allSatisfy { wordSet.contains(String($0)) })
        #expect(!passphrase.hasPrefix(" ") && !passphrase.hasSuffix(" ") && !passphrase.contains("  "))
    }
}

@Test(arguments: [1, 2, 6, 12, 40])
func generatesTheRequestedNumberOfWords(count: Int) {
    var rng = SplitMix64(state: UInt64(count))
    let parts = Passphrase.generate(words: count, using: &rng).split(separator: " ")
    #expect(parts.count == count)
    #expect(parts.allSatisfy { wordSet.contains(String($0)) })
    #expect(Passphrase.generate(words: count).split(separator: " ").count == count)
}

@Test func seededGeneratorIsReproducible() {
    var a = SplitMix64(state: 1904_06_16)
    var b = SplitMix64(state: 1904_06_16)
    var c = SplitMix64(state: 1922_02_02)
    let first = Passphrase.generate(using: &a)
    #expect(first == Passphrase.generate(using: &b))
    #expect(first != Passphrase.generate(using: &c))
    #expect(first != Passphrase.generate(using: &a), "the generator advances")
}

@Test func systemGeneratorDoesNotRepeat() {
    var seen = Set<String>()
    for _ in 0..<50 { seen.insert(Passphrase.generate()) }
    #expect(seen.count == 50)
}

@Test func drawsReachEveryWordAboutEqually() {
    var rng = SplitMix64(state: 42)
    var counts: [String: Int] = [:]
    let draws = 200_000
    for _ in 0..<(draws / 10) {
        for word in Passphrase.generate(words: 10, using: &rng).split(separator: " ") {
            counts[String(word), default: 0] += 1
        }
    }
    #expect(counts.count == words.count, "every word appears in 200k draws")
    let expected = Double(draws) / Double(words.count)
    #expect(counts.values.allSatisfy { Double($0) > expected / 6 && Double($0) < expected * 3 })
}
