import Foundation
import Contacts

struct BrainContactsTool: BrainOSTool {
    let name = "search_contacts"
    let description = "Search for contacts by name, email, or phone number."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("The name, email, or phone number to search for.")
                ])
            ]),
            "required": .array([.string("query")])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = args["query"] as? String else {
            throw NSError(domain: "BrainContactsTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"])
        }
        
        let store = CNContactStore()
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(matchingName: query)
        
        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            let result = contacts.map { contact in
                [
                    "firstName": contact.givenName,
                    "lastName": contact.familyName,
                    "emails": contact.emailAddresses.map { $0.value as String },
                    "phones": contact.phoneNumbers.map { $0.value.stringValue }
                ]
            }
            let jsonData = try JSONSerialization.data(withJSONObject: result)
            return String(data: jsonData, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }
}
