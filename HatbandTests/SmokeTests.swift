import HatbandCore
import Testing
@testable import Hatband

struct SmokeTests {
    @Test func vectorsLoad() throws {
        let vectors = try Vectors.all()
        #expect(vectors.count == 10)
        #expect(try Vectors.card("typical-signed").signatureIsValid)
    }
}
