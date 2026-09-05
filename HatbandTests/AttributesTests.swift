import Foundation
import HatbandCore
import Testing
@testable import Hatband

struct AttributesSizeTests {
    /// ActivityKit caps the encoded attributes plus state at 4 KB; a
    /// 600-character URL and a 64-byte name leave that far behind.
    @Test func payloadUnderBudget() throws {
        let prefix = HB1.urlPrefix + String(HB1.formatTag)
        let url = prefix + String(repeating: "A", count: 600 - prefix.count)
        let name = String(repeating: "N", count: 64)
        #expect(url.count == 600)
        #expect(name.utf8.count == 64)
        let attributes = HatbandAttributes(personaID: "0011223344556677", color: 3)
        let state = HatbandAttributes.ContentState(url: url, name: name, alwaysOn: true, endsAt: Date())
        let encoder = JSONEncoder()
        let attributesSize = try encoder.encode(attributes).count
        let stateSize = try encoder.encode(state).count
        let total = attributesSize + stateSize
        #expect(total < 4096)
        #expect(total < 1024)
    }
}
