import Foundation
let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
var journal = try decoder.decode(Journal.self, from: Data(contentsOf: URL(fileURLWithPath: "ios/PlenaraTests/Fixtures/journal-build-1001.json")))
journal.migrateRelationshipFields()
for index in 0..<3 {
    var p = Person(); p.id = UUID(uuidString: "99999999-0000-0000-0000-00000000000\(index)")!; p.name = ["Amara Fixture", "Daniel Fixture", "Leo Fixture"][index]; p.sourceContactID = "fictional-build1007-\(index)"; p.created = Date(timeIntervalSinceReferenceDate: 700000000)
    journal.people.append(p)
}
try journal.validate()
let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .deferredToDate; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(journal).write(to: URL(fileURLWithPath: "ios/PlenaraTests/Fixtures/journal-build-1007.json"))
print("Frozen build-1007 model output: \(journal.people.count) people, \(journal.moments.count) moments")
