import Foundation

struct ActivityEvent: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case listener
        case preset
        case disk
        case device
        case process
    }

    let id = UUID()
    let date: Date
    let kind: Kind
    let message: String
}
