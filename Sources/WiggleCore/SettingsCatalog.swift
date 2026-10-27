import Foundation

/// One settings row: a title to search, an SF Symbol name, a short subtitle and a tile hue.
public struct SettingsRow: Identifiable, Equatable, Hashable, Sendable {
    public var id: Int
    public var title: String
    public var subtitle: String
    public var symbol: String
    /// Tile colour as a hue (0…1); the views use it at fixed saturation and brightness.
    public var hue: Double

    public init(id: Int, title: String, subtitle: String, symbol: String, hue: Double) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.hue = hue
    }
}

/// The demo list: twenty familiar settings rows (ASCII titles, so every platform folds case alike).
public enum SettingsCatalog {
    public static let rows: [SettingsRow] = [
        ("Wi-Fi", "Home-5G", "wifi", 0.60),
        ("Bluetooth", "On", "wave.3.right", 0.60),
        ("Airplane Mode", "Off", "airplane", 0.08),
        ("Cellular", "Roaming off", "antenna.radiowaves.left.and.right", 0.36),
        ("Personal Hotspot", "Not sharing", "personalhotspot", 0.36),
        ("Notifications", "Banners, sounds", "bell.badge.fill", 0.99),
        ("Sounds & Haptics", "Ringer on", "speaker.wave.3.fill", 0.97),
        ("Focus", "Reading until 22:00", "moon.fill", 0.72),
        ("Screen Time", "2 h 14 min today", "hourglass", 0.72),
        ("General", "About, storage, updates", "gear", 0.0),
        ("Control Center", "12 controls", "switch.2", 0.0),
        ("Display & Brightness", "Auto, True Tone", "sun.max.fill", 0.60),
        ("Home Screen", "App Library", "apps.iphone", 0.66),
        ("Accessibility", "Vision, motion, touch", "accessibility", 0.58),
        ("Wallpaper", "Dunes at dusk", "photo.on.rectangle", 0.53),
        ("Siri & Search", "Listen for \"Hey Siri\"", "mic.fill", 0.80),
        ("Face ID & Passcode", "Unlock, Apple Pay", "faceid", 0.36),
        ("Emergency SOS", "Call with side button", "sos", 0.99),
        ("Battery", "86%, charging", "battery.100", 0.36),
        ("Privacy & Security", "Location, tracking", "hand.raised.fill", 0.60),
    ].enumerated().map { i, r in SettingsRow(id: i, title: r.0, subtitle: r.1, symbol: r.2, hue: r.3) }
}
