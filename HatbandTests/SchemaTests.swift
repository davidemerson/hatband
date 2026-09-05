import SwiftData
import Testing
@testable import Hatband

@MainActor struct SchemaTests {
    private let allowed: [String: Set<String>] = [
        "OwnerRecord": ["blob"],
        "PersonRecord": ["personaID", "updatedAt", "sealed"],
    ]

    @Test func storedPropertiesAllowlisted() throws {
        let entities = Records.schema.entities
        #expect(entities.count == 2)
        for entity in entities {
            let permitted = try #require(allowed[entity.name], "unexpected entity \(entity.name)")
            let names = Set(entity.storedProperties.map { $0.name })
            #expect(names.isSubset(of: permitted), "\(entity.name) stores \(names)")
            #expect(!names.isEmpty)
        }
    }

    @Test func noRelationships() {
        for entity in Records.schema.entities {
            #expect(entity.relationships.isEmpty, "\(entity.name) has relationships")
        }
    }
}
