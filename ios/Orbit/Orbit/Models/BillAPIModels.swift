import Foundation

struct BillDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var amount: Double?
    var currency: String
    var dueDate: Date
    var recurrence: String?
    var isPaid: Bool
    var reminderDaysBefore: Int
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
}

struct BillCreateRequest: Encodable, Sendable {
    var name: String
    var amount: Double?
    var currency: String = "INR"
    var dueDate: Date
    var recurrence: String?
    var isPaid: Bool = false
    var reminderDaysBefore: Int = 3
    var notes: String?
}

struct BillUpdateRequest: Encodable, Sendable {
    var name: String?
    var amount: Double?
    var currency: String?
    var dueDate: Date?
    var recurrence: String?
    var isPaid: Bool?
    var reminderDaysBefore: Int?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case name
        case amount
        case currency
        case dueDate
        case recurrence
        case isPaid
        case reminderDaysBefore
        case notes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(recurrence, forKey: .recurrence)
        try container.encodeIfPresent(isPaid, forKey: .isPaid)
        try container.encodeIfPresent(reminderDaysBefore, forKey: .reminderDaysBefore)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}
