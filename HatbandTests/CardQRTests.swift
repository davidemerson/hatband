import HatbandCore
import Testing
@testable import Hatband

struct CardQRTests {
    @Test func compactFitsLockScreen() throws {
        for name in ["compact-name-only", "compact-two-channels"] {
            let url = try Vectors.url(name)
            let code = try #require(CardQR.code(for: url, form: .lockScreen))
            #expect(code.version <= Budget.lockScreenMaxVersion)
            #expect(code.version == Budget(card: try Vectors.card(name)).version)
            #expect(CardQR.code(for: url, form: .fullQR)?.version == code.version)
        }
    }

    @Test func maximalFitsFullQR() throws {
        let url = try Vectors.url("maximal-qr-signed")
        let code = try #require(CardQR.code(for: url, form: .fullQR))
        #expect(code.version <= Budget.fullQRMaxVersion)
        #expect(code.version > Budget.lockScreenMaxVersion)
        #expect(CardQR.code(for: url, form: .lockScreen) == nil)
    }

    @Test func fileVectorRefusedForLockScreen() throws {
        let url = try Vectors.url("file-with-photo-and-key")
        #expect(CardQR.code(for: url, form: .lockScreen) == nil)
        let full = try #require(CardQR.code(for: url, form: .fullQR))
        #expect(full.version == Budget.fullQRMaxVersion)
    }

    @Test func fileFormReturnsNil() throws {
        #expect(CardQR.code(for: try Vectors.url("minimal"), form: .file) == nil)
        #expect(CardQR.code(for: try Vectors.url("compact-name-only"), form: .file) == nil)
    }

    @Test func garbageReturnsNil() {
        let huge = String(repeating: "x", count: 5000)
        #expect(CardQR.code(for: huge, form: .fullQR) == nil)
        #expect(CardQR.code(for: huge, form: .lockScreen) == nil)
        let mediumGarbage = String(repeating: "https://hatband.link/#1", count: 20)
        #expect(CardQR.code(for: mediumGarbage, form: .lockScreen) == nil)
    }
}
