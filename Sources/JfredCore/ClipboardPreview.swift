import Foundation
import ImageIO

/// Formatting and image metadata for the clipboard history preview pane.
public enum ClipboardPreview {
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "heif", "webp", "bmp", "ico", "raw", "dng",
    ]

    public struct Model: Equatable, Sendable {
        public var headerTitle: String
        public var headerPath: String?
        public var headerIconPath: String?
        public var imagePath: String?
        public var text: String?
        public var caption: String

        public init(
            headerTitle: String = "",
            headerPath: String? = nil,
            headerIconPath: String? = nil,
            imagePath: String? = nil,
            text: String? = nil,
            caption: String = ""
        ) {
            self.headerTitle = headerTitle
            self.headerPath = headerPath
            self.headerIconPath = headerIconPath
            self.imagePath = imagePath
            self.text = text
            self.caption = caption
        }

        public static let empty = Model()
    }

    public enum ResultClickIntent: Equatable, Sendable {
        case select
        case activate
    }

    /// Clipboard history: a single click only highlights so the preview can
    /// follow; a double click activates (copy/paste). Other launcher modes
    /// still activate on the first click.
    public static func resultClickIntent(clickCount: Int, clipboardViewer: Bool) -> ResultClickIntent {
        if clipboardViewer {
            return clickCount >= 2 ? .activate : .select
        }
        return .activate
    }

    /// Same keyword match the clipboard viewer search uses, including the `clip` alias.
    public static func isViewerQuery(_ raw: String, keyword: String) -> Bool {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty, argument(of: key, in: raw) != nil { return true }
        if key.caseInsensitiveCompare("clip") != .orderedSame, argument(of: "clip", in: raw) != nil {
            return true
        }
        return false
    }

    public static func isImageFile(path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    public static func abbreviatedPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    public static func byteSizeLabel(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unit = 0
        while size >= 1000, unit < units.count - 1 {
            size /= 1000
            unit += 1
        }
        if unit == 0 {
            return "\(bytes) B"
        }
        if size >= 10 {
            return "\(Int(size.rounded())) \(units[unit])"
        }
        let tenths = (size * 10).rounded() / 10
        if tenths == tenths.rounded() {
            return "\(Int(tenths)) \(units[unit])"
        }
        return String(format: "%.1f \(units[unit])", tenths)
    }

    public static func dimensionLabel(width: Int, height: Int, byteCount: Int64? = nil) -> String {
        let size = "\(width)x\(height)"
        if let byteCount {
            return "\(size) (\(byteSizeLabel(byteCount)))"
        }
        return size
    }

    public static func imageListTitle(path: String?) -> String {
        guard let path, !path.isEmpty else { return "Image" }
        let bytes = fileByteCount(at: path)
        if let pixels = imagePixelSize(at: path) {
            return "Image: \(dimensionLabel(width: pixels.width, height: pixels.height, byteCount: bytes))"
        }
        if let bytes {
            return "Image: \(byteSizeLabel(bytes))"
        }
        return "Image"
    }

    public static func fileListTitle(paths: [String]) -> String {
        let names = paths.prefix(2).map { URL(fileURLWithPath: $0).lastPathComponent }
        if names.isEmpty { return "File" }
        return "File: " + names.joined(separator: ", ")
    }

    public static func copiedCaption(
        date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)
        let chinese = locale.identifier.lowercased().hasPrefix("zh")
        if calendar.isDate(date, inSameDayAs: now) {
            return chinese ? "今天 \(time) 复制" : "Copied Today \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return chinese ? "昨天 \(time) 复制" : "Copied Yesterday \(time)"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("yMMMd")
        let day = dateFormatter.string(from: date)
        return chinese ? "\(day) \(time) 复制" : "Copied \(day) \(time)"
    }

    public static func imagePixelSize(at path: String) -> (width: Int, height: Int)? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let width = intProperty(properties[kCGImagePropertyPixelWidth])
        let height = intProperty(properties[kCGImagePropertyPixelHeight])
        guard let width, let height, width > 0, height > 0 else { return nil }
        return (width, height)
    }

    public static func fileByteCount(at path: String) -> Int64? {
        guard let value = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber else {
            return nil
        }
        return value.int64Value
    }

    /// Downsampled preview. Does not upscale; ImageIO reads a thumbnail off the source.
    public static func thumbnail(at path: String, maxPixelSize: Int) -> CGImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil), maxPixelSize > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public static func model(
        for clip: ClipItem,
        now: Date = Date(),
        home: String = NSHomeDirectory(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> Model {
        let caption = copiedCaption(date: clip.date, now: now, calendar: calendar, locale: locale)
        let kind = clip.kind ?? "text"
        switch kind {
        case "image":
            let path = clip.imageFile
            let header = imageHeader(path: path)
            return Model(
                headerTitle: header,
                headerPath: nil,
                headerIconPath: path,
                imagePath: path,
                text: nil,
                caption: caption
            )
        case "file":
            let paths = clip.filePaths ?? []
            let first = paths.first
            let previewImage = first.flatMap { isImageFile(path: $0) ? $0 : nil }
            let headerPath = first.map { abbreviatedPath($0, home: home) }
            let headerTitle: String
            if paths.count > 1 {
                headerTitle = "\(paths.count) files"
            } else if let first {
                headerTitle = URL(fileURLWithPath: first).lastPathComponent
            } else {
                headerTitle = clip.text
            }
            return Model(
                headerTitle: headerTitle,
                headerPath: headerPath,
                headerIconPath: first,
                imagePath: previewImage,
                text: previewImage == nil ? paths.map { abbreviatedPath($0, home: home) }.joined(separator: "\n") : nil,
                caption: caption
            )
        default:
            return Model(
                headerTitle: "",
                headerPath: nil,
                headerIconPath: nil,
                imagePath: nil,
                text: clip.text,
                caption: caption
            )
        }
    }

    private static func imageHeader(path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        let bytes = fileByteCount(at: path)
        if let pixels = imagePixelSize(at: path) {
            return dimensionLabel(width: pixels.width, height: pixels.height, byteCount: bytes)
        }
        if let bytes {
            return byteSizeLabel(bytes)
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func intProperty(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
