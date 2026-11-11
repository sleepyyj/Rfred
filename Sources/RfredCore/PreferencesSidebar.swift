/// Source of truth for the Preferences sidebar sections and the default
/// selection. The app maps these ids onto its pane enum.
public enum PreferencesSidebar: Sendable {
    public static let topIDs = ["general", "features", "workflows", "appearance", "advanced"]
    public static let bottomIDs = ["usage", "help", "update"]
    public static var allIDs: [String] { topIDs + bottomIDs }
    public static let defaultSelection = "general"
}
