import Foundation

struct ActivityEvent: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case listener
        case preset
        case disk
        case device
        case process
        case bandwidth
    }

    var id = UUID()
    let date: Date
    let kind: Kind
    let message: String
}
