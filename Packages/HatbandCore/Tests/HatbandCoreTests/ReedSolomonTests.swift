import Testing
@testable import HatbandCore

/// α^k computed independently of the library's multiply: repeated doubling
/// with reduction by the field polynomial.
private func alpha(_ exponent: Int) -> UInt8 {
    var value = 1
    for _ in 0..<exponent {
        value <<= 1
        if value & 0x100 != 0 { value ^= 0x11D }
    }
    return UInt8(value)
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Test func multiplyIdentities() {
    for a in 0...255 {
        let a = UInt8(a)
        #expect(ReedSolomon.multiply(a, 0) == 0)
        #expect(ReedSolomon.multiply(0, a) == 0)
        #expect(ReedSolomon.multiply(a, 1) == a)
        #expect(ReedSolomon.multiply(1, a) == a)
    }
    // x · x⁷ = x⁸ ≡ x⁴ + x³ + x² + 1.
    #expect(ReedSolomon.multiply(2, 0x80) == 0x1D)
    #expect(ReedSolomon.multiply(0x80, 2) == 0x1D)
}

@Test func multiplyIsCommutativeAndDistributive() {
    var rng = SplitMix(state: 1)
    for _ in 0..<2000 {
        let a = UInt8.random(in: .min ... .max, using: &rng)
        let b = UInt8.random(in: .min ... .max, using: &rng)
        let c = UInt8.random(in: .min ... .max, using: &rng)
        #expect(ReedSolomon.multiply(a, b) == ReedSolomon.multiply(b, a))
        #expect(ReedSolomon.multiply(a, b ^ c) == ReedSolomon.multiply(a, b) ^ ReedSolomon.multiply(a, c))
        #expect(ReedSolomon.multiply(ReedSolomon.multiply(a, b), c) == ReedSolomon.multiply(a, ReedSolomon.multiply(b, c)))
    }
}

@Test func alphaGeneratesTheMultiplicativeGroup() {
    var seen = Set<UInt8>()
    for k in 0..<255 { seen.insert(alpha(k)) }
    #expect(seen.count == 255)
    #expect(alpha(255) == 1)
    for k in 0..<254 { #expect(ReedSolomon.multiply(alpha(k), 2) == alpha(k + 1)) }
}

@Test func smallGenerators() {
    #expect(ReedSolomon.generator(degree: 0) == [1])
    #expect(ReedSolomon.generator(degree: 1) == [1, 1])
    #expect(ReedSolomon.generator(degree: 2) == [1, 3, 2])
}

/// Known coefficients, as exponents of α and as integers.
@Test(arguments: [
    (7, [0, 87, 229, 146, 149, 238, 102, 21], [1, 127, 122, 154, 164, 11, 68, 117]),
    (10, [0, 251, 67, 46, 61, 118, 70, 64, 94, 32, 45], [1, 216, 194, 159, 111, 199, 94, 95, 113, 157, 193]),
])
func knownGenerators(degree: Int, exponents: [Int], integers: [UInt8]) {
    let g = ReedSolomon.generator(degree: degree)
    #expect(g == integers)
    #expect(g == exponents.map(alpha))
}

@Test(arguments: 1...30)
func generatorHasTheExpectedRoots(degree: Int) {
    let g = ReedSolomon.generator(degree: degree)
    #expect(g.count == degree + 1)
    #expect(g[0] == 1)
    for k in 0..<degree {
        // Evaluate by Horner at α^k; a root gives zero.
        let value = g.reduce(UInt8(0)) { ReedSolomon.multiply($0, alpha(k)) ^ $1 }
        #expect(value == 0)
    }
    // α^degree is not a root.
    let value = g.reduce(UInt8(0)) { ReedSolomon.multiply($0, alpha(degree)) ^ $1 }
    #expect(value != 0)
}

@Test func isoWorkedExampleECC() {
    let data: [UInt8] = [0x10, 0x20, 0x0C, 0x56, 0x61, 0x80, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11]
    let ecc = ReedSolomon.remainder(of: data, generator: ReedSolomon.generator(degree: 10))
    #expect(ecc == [0xA5, 0x24, 0xD4, 0xC1, 0xED, 0x36, 0xC7, 0x87, 0x2C, 0x55])
}

/// The generator of degree 0 is 1, which divides everything: no remainder.
@Test func degreeZeroGeneratorHasNoRemainder() {
    let g = ReedSolomon.generator(degree: 0)
    #expect(g == [1])
    #expect(ReedSolomon.remainder(of: [1, 2, 3], generator: g) == [])
    #expect(ReedSolomon.remainder(of: [], generator: g) == [])
    #expect(ReedSolomon.remainder(of: [0xFF], generator: []) == [])
}

@Test func zeroDataHasZeroECC() {
    let g = ReedSolomon.generator(degree: 16)
    #expect(ReedSolomon.remainder(of: [UInt8](repeating: 0, count: 40), generator: g) == [UInt8](repeating: 0, count: 16))
    #expect(ReedSolomon.remainder(of: [], generator: g) == [UInt8](repeating: 0, count: 16))
}

/// The codeword `data ‖ ecc` is divisible by the generator, and any single
/// corrupted byte breaks that.
@Test(arguments: [7, 10, 13, 15, 16, 17, 18, 20, 22, 24, 26, 28, 30])
func encodeThenVerify(degree: Int) {
    var rng = SplitMix(state: UInt64(degree))
    let g = ReedSolomon.generator(degree: degree)
    for length in [1, 9, 19, 50, 123] {
        let data = (0..<length).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        let ecc = ReedSolomon.remainder(of: data, generator: g)
        #expect(ecc.count == degree)
        #expect(ReedSolomon.remainder(of: data + ecc, generator: g).allSatisfy { $0 == 0 })
        var corrupted = data + ecc
        let i = Int.random(in: 0..<corrupted.count, using: &rng)
        corrupted[i] ^= UInt8.random(in: 1 ... .max, using: &rng)
        #expect(!ReedSolomon.remainder(of: corrupted, generator: g).allSatisfy { $0 == 0 })
    }
}
