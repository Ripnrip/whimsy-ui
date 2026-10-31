import Foundation

/// The invented invitation on the front and the note hidden under it.
public struct DogEarContent: Equatable, Sendable {
    public var kicker: String
    public var title: String
    public var host: String
    public var when: String
    public var line: String
    public var noteTitle: String
    public var noteBody: String
    public var noteFooter: String

    public init(kicker: String, title: String, host: String, when: String, line: String,
                noteTitle: String, noteBody: String, noteFooter: String) {
        self.kicker = kicker; self.title = title; self.host = host; self.when = when; self.line = line
        self.noteTitle = noteTitle; self.noteBody = noteBody; self.noteFooter = noteFooter
    }

    public static let halloween = DogEarContent(
        kicker: "YOU ARE INVITED",
        title: "Midnight Masquerade",
        host: "at the Hollow House",
        when: "Fri 31 Oct, 8 PM",
        line: "Costumes required. Candy encouraged.",
        noteTitle: "Psst, the password",
        noteBody: "Knock three times and whisper \"moonberry\". Parking is in the pumpkin patch behind the barn.",
        noteFooter: "13 Hollow Lane")

    public var frontLabel: String { "Halloween invitation. \(kicker.capitalized): \(title) \(host), \(when). \(line)" }
    public var noteLabel: String { "Hidden note. \(noteTitle). \(noteBody) \(noteFooter)." }
}
