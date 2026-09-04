/// Diceware-style passphrases from the EFF large wordlist. With 7776 words
/// each carries log2(7776) ≈ 12.9 bits; the default six give about 77.5.
public enum Passphrase {
    public static let wordlist: [String] = EFFWordlist.words
    /// log2(7776) = 5 × log2(6).
    public static let bitsPerWord: Double = 12.92481250360578
    public static let defaultWords = 6

    /// `words` words joined by single spaces, each drawn uniformly from the
    /// list (`Int.random` rejects rather than biases). Zero words is the
    /// empty string; a negative count is a programming error.
    public static func generate(words: Int = defaultWords, using rng: inout some RandomNumberGenerator) -> String {
        precondition(words >= 0, "a passphrase cannot have a negative number of words")
        var out: [String] = []
        out.reserveCapacity(words)
        for _ in 0..<words {
            out.append(wordlist[Int.random(in: wordlist.indices, using: &rng)])
        }
        return out.joined(separator: " ")
    }

    /// From the system's cryptographic random source.
    public static func generate(words: Int = defaultWords) -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(words: words, using: &rng)
    }
}
