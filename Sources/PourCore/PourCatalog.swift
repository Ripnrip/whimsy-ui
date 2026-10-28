import Foundation

/// A sample item for the demo list the menu sorts.
public struct PourItem: Equatable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    /// Days since it was added (smaller is newer).
    public let age: Int
    public let likes: Int
}

public enum PourCatalog {
    public static let items: [PourItem] = [
        PourItem(id: 0, title: "Marble Run", age: 9, likes: 120),
        PourItem(id: 1, title: "Paper Boats", age: 2, likes: 480),
        PourItem(id: 2, title: "Night Market", age: 31, likes: 910),
        PourItem(id: 3, title: "Lemon Tree", age: 14, likes: 75),
        PourItem(id: 4, title: "Harbor Fog", age: 5, likes: 260),
        PourItem(id: 5, title: "Copper Kettle", age: 60, likes: 640),
    ]

    /// Sorts for one of the default option names; an unknown name keeps the order.
    public static func sorted(_ items: [PourItem], by option: String) -> [PourItem] {
        switch option {
        case "Newest": return items.sorted { ($0.age, $0.id) < ($1.age, $1.id) }
        case "Oldest": return items.sorted { ($0.age, $1.id) > ($1.age, $0.id) }
        case "Popular": return items.sorted { ($0.likes, $1.id) > ($1.likes, $0.id) }
        case "A to Z": return items.sorted { $0.title < $1.title }
        default: return items
        }
    }
}
