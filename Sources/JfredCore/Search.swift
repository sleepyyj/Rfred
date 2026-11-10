import Foundation

public enum Search {
    /// Matches kept for the launcher. The window shows a shorter viewport and scrolls.
    public static let resultLimit = 40

    public static func results(for raw: String, context: SearchContext) -> [SearchResult] {
        if raw.hasPrefix(" "), context.preferences.quickSearchEnabled {
            return cap(fileResults(query: raw.trimmingCharacters(in: .whitespacesAndNewlines), context: context), context: context)
        }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultEmptyResults(context: context)
        }
        if let forced = context.forcedResults {
            return Array(forced.prefix(12))
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !context.preferences.terminalPrefix.isEmpty, trimmed.hasPrefix(context.preferences.terminalPrefix) {
            let command = String(trimmed.dropFirst(context.preferences.terminalPrefix.count)).trimmingCharacters(in: .whitespaces)
            return [make(
                id: "term:\(command)",
                title: command.isEmpty ? "Run in Terminal" : command,
                subtitle: "Run in \(context.preferences.terminalApp)",
                icon: "symbol:terminal",
                kind: "terminal",
                payload: command,
                category: "action",
                score: 2
            )]
        }
        let prefs = context.preferences
        func keywordQuery(_ keyword: String, enabled: Bool) -> String? {
            let key = keyword.trimmingCharacters(in: .whitespaces)
            guard enabled, !key.isEmpty else { return nil }
            return argument(of: key, in: trimmed)
        }
        if let openQuery = keywordQuery(prefs.fileOpenKeyword, enabled: prefs.fileOpenEnabled)
            ?? keywordQuery(prefs.fileFindKeyword, enabled: prefs.fileFindEnabled) {
            let rows = fileResults(query: openQuery, context: context)
            return Array(rows.prefix(max(1, prefs.fileSearchMax)))
        }
        if let inside = keywordQuery(prefs.fileInsideKeyword, enabled: prefs.fileInsideEnabled), let spotlight = context.spotlight {
            return spotlightFileResults(spotlight(inside, false), context: context, limit: prefs.fileSearchMax)
        }
        if let tags = keywordQuery(prefs.fileTagsKeyword, enabled: prefs.fileTagsEnabled), let spotlight = context.spotlight {
            return spotlightFileResults(spotlight(tags, true), context: context, limit: prefs.fileSearchMax)
        }
        if let volume = volumeValue(trimmed) {
            return [make(
                id: "sys:volume:\(volume)",
                title: "Set Volume to \(volume)",
                subtitle: "Output volume",
                icon: "symbol:speaker.wave.2",
                kind: "system",
                payload: "volume:\(volume)",
                category: "action",
                score: 2
            )]
        }

        let webHits = mergedWebKeywords(for: trimmed, context: context)
        if !webHits.isEmpty {
            return cap(webHits, context: context)
        }
        if let viewer = clipboardViewerResults(for: trimmed, context: context) {
            return viewer
        }

        var found: [SearchResult] = []
        if context.preferences.calculatorEnabled, Calculator.allows(trimmed, advanced: context.preferences.calculatorAdvanced), let value = Calculator.evaluate(trimmed) {
            let text = Calculator.format(value)
            found.append(make(
                id: "calc:\(text)",
                title: text,
                subtitle: "Calculator  ·  \(trimmed)",
                icon: "symbol:plus.forwardslash.minus",
                kind: "calculation",
                payload: text,
                category: "general",
                score: 1.8
            ))
        }
        if let conversion = Units.convert(trimmed) {
            found.append(make(
                id: "unit:\(conversion.text)",
                title: conversion.text,
                subtitle: "Unit Converter  ·  \(trimmed)",
                icon: "symbol:ruler",
                kind: "calculation",
                payload: conversion.text,
                category: "general",
                score: 1.75
            ))
        }
        if context.preferences.dictionaryEnabled, context.preferences.dictionaryDefineEnabled, let word = argument(of: context.preferences.dictionaryDefineKeyword, in: trimmed) {
            let subtitle = context.definition?.replacingOccurrences(of: "\n", with: " ") ?? "Open Dictionary"
            found.append(make(
                id: "dict:\(word)",
                title: word.isEmpty ? "Dictionary" : word,
                subtitle: String(subtitle.prefix(180)),
                icon: "symbol:character.book.closed",
                kind: "dictionary",
                payload: word,
                category: "general",
                score: 1.7
            ))
        }

        let needle = trimmed
        func push(_ item: SearchResult?) {
            if let item { found.append(item) }
        }

        for app in context.apps where includeApp(path: app.path) {
            push(scored(
                query: needle,
                fields: matchFields(forName: app.name, aliases: app.aliases),
                id: "app:\(app.path)",
                title: app.name,
                subtitle: app.path,
                icon: "file:\(app.path)",
                kind: "app",
                payload: app.path,
                category: "general",
                context: context
            ))
        }
        for place in context.places {
            push(scored(
                query: needle,
                fields: [place.name],
                id: "place:\(place.id)",
                title: place.name,
                subtitle: place.id == "computer" ? "Open Computer in Finder" : place.path,
                icon: place.path.isEmpty ? "symbol:desktopcomputer" : "file:\(place.path)",
                kind: "place",
                payload: place.id,
                category: "navigation",
                context: context
            ))
        }
        if context.preferences.systemSettingsEnabled {
            let foldedQuery = fold(needle)
            for setting in context.settings where !foldedQuery.isEmpty && fold(setting.name).contains(foldedQuery) {
                push(scored(
                    query: needle,
                    fields: [setting.name],
                    id: "set:\(setting.id)",
                    title: setting.name,
                    subtitle: "System Settings",
                    icon: "symbol:gearshape",
                    kind: "settings",
                    payload: setting.url,
                    category: "general",
                    context: context
                ))
            }
        }
        for snippet in context.snippets where context.preferences.snippetsEnabled {
            let snippetFields: [String]
            switch context.preferences.snippetMatching {
            case "name": snippetFields = [snippet.name]
            case "keyword": snippetFields = [snippet.keyword]
            default: snippetFields = [snippet.name, snippet.keyword]
            }
            let snippetSubtitle = context.preferences.snippetShowKeywordInResult
                ? snippet.keyword + "  ·  " + snippet.text.replacingOccurrences(of: "\n", with: " ")
                : snippet.text.replacingOccurrences(of: "\n", with: " ")
            push(scored(
                query: needle,
                fields: snippetFields,
                id: "snip:\(snippet.id.uuidString)",
                title: snippet.name,
                subtitle: snippetSubtitle,
                icon: "symbol:text.quote",
                kind: "snippet",
                payload: snippet.id.uuidString,
                category: "expansion",
                context: context,
                floor: fold(needle) == fold(snippet.keyword) ? 1.55 : nil
            ))
        }
        for command in SystemCommand.all {
            if context.preferences.systemDisabled.contains(command.id) { continue }
            if command.id == "ejectall", !context.preferences.ejectAllEnabled { continue }
            let customKeyword = context.preferences.systemKeywords[command.id]
            let commandFields = customKeyword.map { [$0, command.title] } ?? ([command.title] + command.keywords)
            push(scored(
                query: needle,
                fields: commandFields,
                id: "sys:\(command.id)",
                title: command.title,
                subtitle: command.subtitle,
                icon: "symbol:\(command.symbol)",
                kind: "system",
                payload: command.id,
                category: command.category,
                context: context
            ))
        }
        for workflow in context.workflows where workflow.enabled {
            push(scored(
                query: needle,
                fields: [workflow.name, workflow.keyword],
                id: "complete:\(workflow.id.uuidString)",
                title: workflow.name,
                subtitle: workflow.keyword,
                icon: workflow.resolvedIcon().resource,
                kind: "complete",
                payload: workflow.keyword + " ",
                category: "action",
                context: context
            ))
        }
        let bookmarkMode = context.preferences.bookmarkResultMode
        var bookmarkNeedle = needle
        var showBookmarks = bookmarkMode == "default"
        if bookmarkMode == "keyword" {
            let keyword = context.preferences.bookmarkKeyword.lowercased()
            if !keyword.isEmpty, needle.lowercased().hasPrefix(keyword + " ") {
                showBookmarks = true
                bookmarkNeedle = String(needle.dropFirst(keyword.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        if showBookmarks, bookmarkNeedle.count >= 2 {
            for link in context.links {
                push(scored(
                    query: bookmarkNeedle,
                    fields: [link.title, link.url],
                    id: "link:\(link.id)",
                    title: link.title.isEmpty ? link.url : link.title,
                    subtitle: link.source + "  ·  " + link.url,
                    icon: "symbol:bookmark",
                    kind: "url",
                    payload: link.url,
                    category: "navigation",
                    context: context,
                    dampen: 0.88
                ))
            }
        }
        if context.preferences.clipboardEnabled, context.preferences.clipboardClearKeywordEnabled,
           let cleared = clearKeywordQuery(trimmed, keyword: context.preferences.clipboardClearKeyword) {
            let title = cleared == nil ? "Clear All Clipboard History" : "Clear Clipboard History (last \(cleared!) minutes)"
            found.append(make(
                id: "clipclear:\(cleared.map(String.init) ?? "all")",
                title: title,
                subtitle: "Clear Jfred's clipboard history",
                icon: "symbol:trash",
                kind: "clipclear",
                payload: cleared.map(String.init) ?? "all",
                category: "clipboard",
                score: 2
            ))
        }
        if context.preferences.onePasswordEnabled {
            for item in context.opItems {
                push(scored(
                    query: needle,
                    fields: [item.name],
                    id: "op:\(item.id)",
                    title: item.name,
                    subtitle: "1Password",
                    icon: "symbol:key",
                    kind: "copy",
                    payload: item.path,
                    category: "action",
                    context: context
                ))
            }
        }

        let ranked = dedupe(found, query: needle, context: context)
        if context.preferences.fallbackMode == "always" {
            let head = Array(ranked.prefix(resultLimit))
            return Array((head + fallbacks(for: trimmed, context: context, score: 0.2)).prefix(resultLimit + 3))
        }
        if ranked.isEmpty && context.preferences.fallbackMode != "never" {
            return cap(fallbacks(for: trimmed, context: context, score: 1), query: needle, context: context)
        }
        return cap(ranked, query: needle, context: context)
    }

    public static func wantsFiles(raw: String, preferences: Preferences) -> Bool {
        if raw.hasPrefix(" "), preferences.quickSearchEnabled { return true }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywords = [
            (preferences.fileOpenKeyword, preferences.fileOpenEnabled),
            (preferences.fileFindKeyword, preferences.fileFindEnabled),
        ]
        for (keyword, enabled) in keywords where enabled && !keyword.isEmpty {
            if argument(of: keyword, in: trimmed) != nil { return true }
        }
        if preferences.searchAllFileTypes && trimmed.count >= 3 { return true }
        let extras = preferences.extraFolders || preferences.extraDocuments || preferences.extraText || preferences.extraImages || preferences.extraArchives || preferences.extraScripts
        return extras && trimmed.count >= 3
    }

    /// File-name and Spotlight queries. Their rows replace the app ranking, so the
    /// launcher must not publish that ranking while the lookup is still running.
    public static func exclusiveSlowQuery(raw: String, preferences: Preferences) -> Bool {
        if raw.hasPrefix(" "), preferences.quickSearchEnabled { return true }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywords = [
            (preferences.fileOpenKeyword, preferences.fileOpenEnabled),
            (preferences.fileFindKeyword, preferences.fileFindEnabled),
            (preferences.fileInsideKeyword, preferences.fileInsideEnabled),
            (preferences.fileTagsKeyword, preferences.fileTagsEnabled),
        ]
        for (keyword, enabled) in keywords {
            let key = keyword.trimmingCharacters(in: .whitespaces)
            guard enabled, !key.isEmpty else { continue }
            if argument(of: key, in: trimmed) != nil { return true }
        }
        return false
    }

    public static func wantsDefinition(raw: String) -> String? {
        argument(of: "define", in: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func fileResults(query: String, context: SearchContext) -> [SearchResult] {
        if query.isEmpty {
            return [make(id: "file:hint", title: "File search", subtitle: "Type a file name", icon: "symbol:doc", kind: "text", payload: "", category: "navigation", score: 1)]
        }
        let hidden = Set(context.preferences.hiddenFileTypes)
        return context.files.filter { !isHiddenFile($0.path, hiddenTypes: hidden) }.compactMap { file in
            scored(
                query: query,
                fields: [file.name, URL(fileURLWithPath: file.path).lastPathComponent],
                id: "file:\(file.path)",
                title: file.name,
                subtitle: file.path,
                icon: context.preferences.fileUseTypeIconsForExternal && file.path.hasPrefix("/Volumes/") ? "symbol:doc" : "file:\(file.path)",
                kind: "file",
                payload: file.path,
                category: "navigation",
                context: context
            )
        }
    }

    private static let hiddenExtensions: [String: Set<String>] = [
        "Emails": ["eml", "msg", "email"],
        "Contacts": ["vcf"],
        "Calendar": ["ics"],
        "Bookmarks": ["webloc", "url", "plist"],
        "Images": ["png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "webp", "svg"],
        "Messages": ["ichat"],
        "Music": ["mp3", "m4a", "aac", "flac", "wav", "aiff", "ogg"],
        "Plist files": ["plist"],
        "Source files": ["swift", "c", "h", "m", "mm", "cpp", "hpp", "py", "js", "ts", "jsx", "tsx", "go", "rs", "java", "kt", "rb", "sh", "zsh", "fish", "lua", "php"],
    ]

    private static func isHiddenFile(_ path: String, hiddenTypes: Set<String>) -> Bool {
        guard !hiddenTypes.isEmpty else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        for type in hiddenTypes where hiddenExtensions[type]?.contains(ext) == true { return true }
        return false
    }

    private static func spotlightFileResults(_ records: [AppRecord], context: SearchContext, limit: Int) -> [SearchResult] {
        records.prefix(max(1, limit)).map { record in
            make(
                id: "file:\(record.path)",
                title: record.name,
                subtitle: record.path,
                icon: "file:\(record.path)",
                kind: "file",
                payload: record.path,
                category: "navigation",
                score: 2
            )
        }
    }

    private static func fallbacks(for query: String, context: SearchContext, score: Double) -> [SearchResult] {
        context.preferences.webSearches.filter { $0.enabled && $0.fallback }.map { search in
            make(
                id: "web:\(search.id):\(query)",
                title: "Search \(search.title) for ‘\(query)’",
                subtitle: context.preferences.resolvedURL(for: search, query: query),
                icon: "symbol:\(search.symbol)",
                kind: "url",
                payload: context.preferences.resolvedURL(for: search, query: query),
                category: "navigation",
                score: score
            )
        }
    }

    private static func scored(
        query: String,
        fields: [String],
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        kind: String,
        payload: String,
        category: String,
        context: SearchContext,
        dampen: Double = 1,
        floor: Double? = nil
    ) -> SearchResult? {
        var match = bestFieldMatch(query: query, fields: fields)
        if var found = match {
            found.score *= dampen
            match = found
        } else if let floor {
            match = FieldMatch(tier: 0, score: floor)
        }
        // Alfred keeps a query to a name or word prefix. A mid-word
        // substring ("Sharing" for "ha") or a fuzzy hit ("Hostpane") stays out.
        guard let match, match.tier <= 2 else { return nil }
        return make(id: id, title: title, subtitle: subtitle, icon: icon, kind: kind, payload: payload, category: category, score: match.score, tier: match.tier)
    }

    private static func make(id: String, title: String, subtitle: String, icon: String, kind: String, payload: String, category: String, score: Double, tier: Int = 0, badge: String = "", badgeName: String = "") -> SearchResult {
        SearchResult(id: id, title: title, subtitle: subtitle, icon: icon, kind: kind, payload: payload, category: category, score: score, tier: tier, badge: badge, badgeName: badgeName)
    }

    /// Background helpers under CoreServices are not launcher apps.
    /// `/System/Library/CoreServices/Applications` and Finder stay.
    private static func includeApp(path: String) -> Bool {
        let folded = fold(path)
        let marker = "/system/library/coreservices/"
        guard let range = folded.range(of: marker) else { return true }
        let rest = folded[range.upperBound...]
        if rest.hasPrefix("applications/") { return true }
        if rest == "finder.app" || rest.hasPrefix("finder.app/") { return true }
        return false
    }

    /// `/Applications` apps whose names contain the query, then other apps that contain it,
    /// then System Settings panes, then remaining matches.
    private static func rankBand(_ item: SearchResult, query: String) -> Int {
        let folded = fold(query)
        let nameHit = !folded.isEmpty && fold(item.title).contains(folded)
        let applications = item.kind == "app" && item.payload.range(of: "/Applications/", options: [.anchored, .caseInsensitive]) != nil
        if applications && nameHit { return 0 }
        if item.kind == "app" && nameHit { return 1 }
        if item.kind == "settings" { return 2 }
        if applications { return 3 }
        if item.kind == "app" { return 4 }
        return 5
    }

    private static func dedupe(_ items: [SearchResult], query: String = "", context: SearchContext? = nil) -> [SearchResult] {
        let folded = fold(query)
        let shortQuery = folded.count > 0 && folded.count <= 3
        let latched = context?.preferences.topResultLatching == true ? context?.knowledge[folded] : nil
        let now = context?.now ?? Date()
        let sorted = items.sorted { lhs, rhs in
            let lhsBand = rankBand(lhs, query: query)
            let rhsBand = rankBand(rhs, query: query)
            if lhsBand != rhsBand { return lhsBand < rhsBand }
            let lhsLatch = lhs.id == latched
            let rhsLatch = rhs.id == latched
            if lhsLatch != rhsLatch {
                // Short queries lean harder on the latched top result.
                if shortQuery { return lhsLatch }
                return lhsLatch
            }
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            let lhsStat = context?.selections[lhs.id]
            let rhsStat = context?.selections[rhs.id]
            let lhsFreq = selectionFrecency(count: lhsStat?.count ?? 0, lastSelected: lhsStat?.lastSelected ?? .distantPast, now: now)
            let rhsFreq = selectionFrecency(count: rhsStat?.count ?? 0, lastSelected: rhsStat?.lastSelected ?? .distantPast, now: now)
            let lhsTotal = lhs.score + min(0.45, lhsFreq * 0.08)
            let rhsTotal = rhs.score + min(0.45, rhsFreq * 0.08)
            if shortQuery && lhsLatch != rhsLatch { return lhsLatch }
            if abs(lhsTotal - rhsTotal) > 0.0001 { return lhsTotal > rhsTotal }
            if lhsFreq != rhsFreq { return lhsFreq > rhsFreq }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        var seen = Set<String>()
        return sorted.filter { seen.insert($0.id).inserted }
    }

    /// Recent apps, clipboard clips and usage-backed rows shown for an empty query.
    private static func defaultEmptyResults(context: SearchContext) -> [SearchResult] {
        var rows: [SearchResult] = []
        let now = context.now
        let rankedApps = context.apps
            .filter { includeApp(path: $0.path) }
            .compactMap { app -> (AppRecord, Double)? in
                let id = "app:\(app.path)"
                guard let stat = context.selections[id], stat.count > 0 else { return nil }
                return (app, selectionFrecency(count: stat.count, lastSelected: stat.lastSelected, now: now))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
        for (app, freq) in rankedApps {
            rows.append(make(
                id: "app:\(app.path)",
                title: app.name,
                subtitle: app.path,
                icon: "file:\(app.path)",
                kind: "app",
                payload: app.path,
                category: "general",
                score: 1.2 + min(0.4, freq * 0.05)
            ))
        }
        if context.preferences.clipboardEnabled {
            for clip in context.clips.prefix(5) {
                let kind = clip.kind ?? "text"
                let row = ClipboardText.row(
                    text: clip.text,
                    fallback: kind == "image" ? "Clipboard image" : (kind == "file" ? "Clipboard files" : "Clipboard")
                )
                let icon: String
                if kind == "image", let file = clip.imageFile, !file.isEmpty {
                    icon = "clipimage:\(file)"
                } else if kind == "file" {
                    icon = "symbol:doc.on.doc"
                } else {
                    icon = "symbol:doc.on.clipboard"
                }
                rows.append(make(
                    id: "clip:\(clip.id.uuidString)",
                    title: row.title,
                    subtitle: "Clipboard History",
                    icon: icon,
                    kind: "clipboard",
                    payload: clip.id.uuidString,
                    category: "clipboard",
                    score: 1.05
                ))
            }
        }
        if rows.isEmpty {
            for app in context.apps.prefix(8) where includeApp(path: app.path) {
                rows.append(make(
                    id: "app:\(app.path)",
                    title: app.name,
                    subtitle: app.path,
                    icon: "file:\(app.path)",
                    kind: "app",
                    payload: app.path,
                    category: "general",
                    score: 1
                ))
            }
        }
        return Array(rows.prefix(resultLimit))
    }

    private static func cap(_ items: [SearchResult], query: String = "", context: SearchContext? = nil) -> [SearchResult] {
        let ranked = dedupe(items, query: query, context: context)
        let settings = ranked.filter { $0.kind == "settings" }
        guard ranked.count > resultLimit, !settings.isEmpty else {
            return Array(ranked.prefix(resultLimit))
        }
        let others = ranked.filter { $0.kind != "settings" }
        let room = max(0, resultLimit - settings.count)
        let keptOthers = Array(others.prefix(room))
        let merged = dedupe(keptOthers + settings, query: query, context: context)
        return Array(merged.prefix(resultLimit))
    }

    /// Clipboard viewer is its own result list. Newest clips stay first.
    private static func clipboardViewerResults(for trimmed: String, context: SearchContext) -> [SearchResult]? {
        guard context.preferences.clipboardEnabled else { return nil }
        guard let clipQuery = argument(of: context.preferences.clipboardViewerKeyword, in: trimmed) ?? argument(of: "clip", in: trimmed) else { return nil }
        var rows: [SearchResult] = []
        if context.preferences.clipboardSnippetsAtTop, clipQuery.isEmpty {
            rows.append(make(
                id: "snippets:all",
                title: "All Snippets",
                subtitle: "Browse snippets in the launcher",
                icon: "symbol:text.quote",
                kind: "snippets",
                payload: "",
                category: "expansion",
                score: 2
            ))
        }
        var snippets: [SearchResult] = []
        if context.preferences.clipboardSnippetsWhenSearching, !clipQuery.isEmpty {
            for snippet in context.snippets {
                let hay = snippet.name + " " + snippet.keyword + " " + snippet.text
                guard clipQuery.isEmpty || fold(hay).contains(fold(clipQuery)) else { continue }
                snippets.append(make(
                    id: "snippet:\(snippet.id.uuidString):clip",
                    title: snippet.name,
                    subtitle: snippet.keyword + "  ·  " + snippet.text.replacingOccurrences(of: "\n", with: " "),
                    icon: "symbol:text.quote",
                    kind: "snippet",
                    payload: snippet.id.uuidString,
                    category: "expansion",
                    score: context.preferences.clipboardSnippetsAtTop ? 1.8 : 1.38
                ))
            }
        }
        let filtered = context.clips.filter { clipQuery.isEmpty || fold($0.text).contains(fold(clipQuery)) }
        var clips: [SearchResult] = []
        for clip in filtered {
            let kind = clip.kind ?? "text"
            let title: String
            let subtitle: String
            let icon: String
            switch kind {
            case "image":
                title = ClipboardPreview.imageListTitle(path: clip.imageFile)
                if !clip.text.isEmpty, clip.text != "Image" {
                    subtitle = ClipboardText.row(text: clip.text, fallback: "Clipboard image").title
                } else {
                    subtitle = "Clipboard image"
                }
                icon = clip.imageFile.map { "clipimage:\($0)" } ?? "symbol:photo"
            case "file":
                let paths = clip.filePaths ?? []
                title = ClipboardPreview.fileListTitle(paths: paths)
                subtitle = paths.map { ClipboardPreview.abbreviatedPath($0) }.joined(separator: "  ·  ")
                icon = paths.first.map { "file:\($0)" } ?? "symbol:doc"
            default:
                let row = ClipboardText.row(text: clip.text, fallback: "Clipboard")
                title = row.title
                subtitle = row.subtitle
                icon = "symbol:doc.on.clipboard"
            }
            let source = clip.sourcePath ?? ""
            clips.append(make(
                id: "clip:\(clip.id.uuidString)",
                title: title,
                subtitle: subtitle,
                icon: icon,
                kind: "clipboard",
                payload: clip.id.uuidString,
                category: "clipboard",
                score: 1.4,
                badge: source.isEmpty ? "" : "file:\(source)",
                badgeName: clip.sourceName ?? ""
            ))
        }
        if context.preferences.clipboardSnippetsAtTop {
            rows.append(contentsOf: snippets)
            rows.append(contentsOf: clips)
        } else {
            rows.append(contentsOf: clips)
            rows.append(contentsOf: snippets)
        }
        if rows.isEmpty {
            rows.append(make(
                id: "clipboard:empty",
                title: "No clipboard history",
                subtitle: "Copies show up here after you copy something",
                icon: "symbol:doc.on.clipboard",
                kind: "text",
                payload: "",
                category: "clipboard",
                score: 1
            ))
        }
        return Array(rows.prefix(resultLimit))
    }

    private static func clearKeywordQuery(_ query: String, keyword: String) -> Int?? {
        let key = keyword.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        let folded = fold(query.trimmingCharacters(in: .whitespaces))
        guard folded == fold(key) || folded.hasPrefix(fold(key) + " ") else { return nil }
        let rest = query.trimmingCharacters(in: .whitespaces).dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return .some(nil) }
        if let minutes = Int(rest), minutes == 5 || minutes == 15 { return .some(minutes) }
        return nil
    }

    private static func volumeValue(_ query: String) -> Int? {
        let pattern = #"^(?:vol|volume)\s+([0-9]{1,3})$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(query.startIndex..., in: query)
        guard let match = expression.firstMatch(in: query, range: range),
              let valueRange = Range(match.range(at: 1), in: query),
              let value = Int(query[valueRange]), (0...100).contains(value)
        else { return nil }
        return value
    }

}

extension Search {
    public static func mergedWebKeywords(for raw: String, context: SearchContext) -> [SearchResult] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows: [SearchResult] = []
        for search in context.preferences.webSearches where search.enabled {
            guard let arg = argument(of: search.keyword, in: trimmed) else { continue }
            let query = arg.isEmpty ? "" : arg
            rows.append(make(
                id: "webkw:\(search.id):\(query)",
                title: query.isEmpty ? search.title : "Search \(search.title) for ‘\(query)’",
                subtitle: query.isEmpty ? search.keyword : context.preferences.resolvedURL(for: search, query: query),
                icon: "symbol:\(search.symbol)",
                kind: query.isEmpty ? "complete" : "url",
                payload: query.isEmpty ? search.keyword + " " : context.preferences.resolvedURL(for: search, query: query),
                category: "navigation",
                score: 1.6
            ))
        }
        return rows
    }
}
