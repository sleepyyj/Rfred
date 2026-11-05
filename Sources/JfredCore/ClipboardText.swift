import Foundation

public enum ClipboardText {
    public struct Row: Equatable, Sendable {
        public var title: String
        public var subtitle: String
    }

    /// U+FFFC is the object-replacement character. Several of them beside
    /// non-Latin text hang CoreText line truncation on macOS 26.
    public static func sanitized(_ raw: String) -> String {
        guard raw.unicodeScalars.contains(where: { $0 == "\u{FFFC}" }) else { return raw }
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where scalar != "\u{FFFC}" {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// One-line title, with the overflow in the subtitle when the clip is long.
    public static func row(text: String, fallback: String, titleLimit: Int = 120) -> Row {
        let single = sanitized(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\t", with: "⇥")
        let title = String(single.prefix(titleLimit))
        guard single.count > titleLimit else {
            return Row(title: title, subtitle: fallback)
        }
        let rest = single.dropFirst(titleLimit)
        return Row(title: title, subtitle: String(rest.prefix(titleLimit)))
    }
}
