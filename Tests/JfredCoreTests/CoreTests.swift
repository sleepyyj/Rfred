import Foundation
import Testing
@testable import JfredCore

struct CoreTests {
    @Test func calculatorPrecedence() {
        #expect(Calculator.evaluate("2+2*3") == 8)
        #expect(Calculator.evaluate("(2+2)*3") == 12)
        #expect(Calculator.evaluate("sqrt(9)") == 3)
        #expect(Calculator.evaluate("=10/4") == 2.5)
        #expect(Calculator.evaluate("contacts") == nil)
    }

    @Test func units() {
        let length = Units.convert("10 km in m")
        #expect(length?.value == 10000)
        #expect(length?.text == "10000 m")
        let temp = Units.convert("32 f in c")
        #expect(abs((temp?.value ?? -1) - 0) < 0.001)
        #expect(Units.convert("10 km in kg") == nil)
    }

    @Test func searchPrefixesAndFallbacks() {
        var context = SearchContext()
        context.apps = [
            AppRecord(id: "contacts", name: "Contacts", path: "/Applications/Contacts.app"),
            AppRecord(id: "console", name: "Console", path: "/Applications/Utilities/Console.app"),
            AppRecord(id: "color", name: "ColorSync Utility", path: "/Applications/Utilities/ColorSync Utility.app"),
        ]
        context.places = [
            AppRecord(id: "computer", name: "Computer", path: ""),
        ]
        let co = Search.results(for: "co", context: context).map(\.title)
        #expect(co.contains("Computer"))
        #expect(co.contains("Console"))
        #expect(co.contains("Contacts"))
        #expect(co.firstIndex(of: "Contacts")! < co.firstIndex(of: "Computer")!)
        #expect(co.firstIndex(of: "Console")! < co.firstIndex(of: "Computer")!)

        let missing = Search.results(for: "zzzz-no-such", context: context)
        #expect(missing.contains { $0.title.contains("Google") })
        #expect(Search.results(for: "", context: context).isEmpty)
        #expect(Search.results(for: " ", context: context).first?.kind == "text")
        #expect(Search.results(for: "2+2*3", context: context).first?.title == "8")
    }

    @Test func settingsFollowAppsThatContainTheQuery() {
        var context = SearchContext()
        context.apps = [
            AppRecord(id: "displaycal", name: "DisplayCal", path: "/Applications/DisplayCal.app"),
            AppRecord(id: "notes", name: "Notes", path: "/Applications/Notes.app"),
        ]
        context.settings = SettingsCatalog.all
        let rows = Search.results(for: "disp", context: context)
        let app = rows.firstIndex { $0.title == "DisplayCal" }
        let displays = rows.firstIndex { $0.id == "set:displays" }
        let notes = rows.firstIndex { $0.title == "Notes" }
        #expect(app != nil)
        #expect(displays != nil)
        #expect(app! < displays!)
        #expect(rows.filter { $0.kind == "settings" }.allSatisfy { fold($0.title).contains("disp") })
        if let notes, let displays {
            #expect(displays < notes)
        }
    }

    @Test func matchTierOutranksUsageAndShorterNames() {
        #expect(fieldMatch(query: "cal", target: "Calendar")?.tier == 1)
        #expect(fieldMatch(query: "cal", target: "Local")?.tier == 3) // contiguous substring, not fuzzy
        var context = SearchContext()
        context.apps = [
            AppRecord(id: "local", name: "Local", path: "/Applications/Local.app"),
            AppRecord(id: "calendar", name: "Calendar", path: "/System/Applications/Calendar.app"),
            AppRecord(id: "alpha", name: "Alpha", path: "/Applications/Alpha.app"),
            AppRecord(id: "alpine", name: "Alpine", path: "/Applications/Alpine.app"),
        ]
        context.selections["app:/Applications/Local.app"] = SelectionStat(count: 40, lastSelected: Date())
        let cal = Search.results(for: "cal", context: context)
        #expect(cal.first?.title == "Calendar")
        context.selections["app:/Applications/Alpine.app"] = SelectionStat(count: 5, lastSelected: Date())
        let rows = Search.results(for: "al", context: context)
        let alpine = rows.firstIndex { $0.title == "Alpine" }
        let alpha = rows.firstIndex { $0.title == "Alpha" }
        #expect(alpine != nil)
        #expect(alpha != nil)
        #expect(alpine! < alpha!)
    }

    @Test func shortQueryKeepsWordPrefixesOnly() {
        var context = SearchContext()
        context.apps = [
            AppRecord(id: "enhanced", name: "Enhanced Logging", path: "/System/Library/CoreServices/Enhanced Logging.app"),
            AppRecord(id: "handler", name: "CalendarFileHandler", path: "/System/Library/CoreServices/CalendarFileHandler.app"),
            AppRecord(id: "host", name: "Hostpane", path: "/Applications/Hostpane.app"),
            AppRecord(id: "hagi", name: "HagimiMonitor", path: "/Applications/HagimiMonitor.app"),
            AppRecord(id: "claude", name: "Claude Code URL Handler", path: "/Users/jim/Applications/Claude Code URL Handler.app"),
        ]
        context.settings = [SettingRecord(id: "sharing", name: "Sharing", url: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")]
        let rows = Search.results(for: "ha", context: context)
        #expect(rows.map(\.title) == ["HagimiMonitor", "Claude Code URL Handler"])
    }

    @Test func applicationsFolderRanksBeforeOtherApps() {
        var context = SearchContext()
        context.apps = [
            AppRecord(id: "apps", name: "Apps", path: "/System/Applications/Apps.app"),
            AppRecord(id: "alfred", name: "Alfred 5", path: "/Applications/Alfred 5.app"),
            AppRecord(id: "accounts", name: "Accounts", path: "/System/Library/PreferencePanes/Accounts.prefPane"),
        ]
        let rows = Search.results(for: "a", context: context)
        let alfred = rows.firstIndex { $0.title == "Alfred 5" }
        let apps = rows.firstIndex { $0.title == "Apps" }
        let accounts = rows.firstIndex { $0.title == "Accounts" }
        #expect(alfred != nil)
        #expect(apps != nil)
        #expect(accounts != nil)
        #expect(alfred! < apps!)
        #expect(alfred! < accounts!)
    }

    @Test func appsRankBeforeOtherMatches() {
        var context = SearchContext()
        context.apps = [
            AppRecord(id: "safari", name: "Safari", path: "/Applications/Safari.app"),
        ]
        let rows = Search.results(for: "s", context: context)
        let safari = rows.firstIndex { $0.title == "Safari" }
        let sleep = rows.firstIndex { $0.title == "Sleep" }
        #expect(rows.first?.kind == "app")
        #expect(safari != nil)
        #expect(sleep != nil)
        #expect(safari! < sleep!)
    }

    @Test func coreServicesHelpersStayOut() {
        var context = SearchContext()
        context.apps = [
            AppRecord(id: "enhanced", name: "Enhanced Logging", path: "/System/Library/CoreServices/Enhanced Logging.app"),
            AppRecord(id: "finder", name: "Finder", path: "/System/Library/CoreServices/Finder.app"),
            AppRecord(id: "keychain", name: "Keychain Access", path: "/System/Library/CoreServices/Applications/Keychain Access.app"),
        ]
        let rows = Search.results(for: "f", context: context)
        #expect(rows.contains { $0.title == "Finder" })
        #expect(!Search.results(for: "en", context: context).contains { $0.title == "Enhanced Logging" })
        let key = Search.results(for: "key", context: context)
        #expect(key.contains { $0.title == "Keychain Access" })
    }

    @Test func fileModeDoesNotReturnApps() {
        var context = SearchContext()
        context.apps = [AppRecord(id: "r", name: "Report", path: "/Applications/Report.app")]
        context.files = [AppRecord(id: "f", name: "Report.pdf", path: "/Users/me/Report.pdf")]
        let rows = Search.results(for: " report", context: context)
        #expect(rows.map(\.kind) == ["file"])
        #expect(Search.wantsFiles(raw: " report", preferences: context.preferences))
    }

    @Test func webKeyword() {
        let context = SearchContext()
        let rows = Search.results(for: "g jfred", context: context)
        #expect(rows.count == 1)
        #expect(rows[0].kind == "url")
        #expect(rows[0].payload.contains("google.com"))
    }

    @Test func usageBuckets() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            UsageEvent(date: now, category: "general"),
            UsageEvent(date: now, category: "hotkeys"),
        ]
        let stats = UsageMath.counts(events: events, days: 28, now: now)
        #expect(stats.total == 2)
        #expect(stats.series["general"]?.reduce(0, +) == 1)
        #expect(stats.series["hotkeys"]?.reduce(0, +) == 1)
    }
}

    @Test func disabledSystemCommandIsHidden() {
        var context = SearchContext()
        context.preferences.systemDisabled = ["sleep"]
        #expect(!Search.results(for: "sleep", context: context).contains { $0.id == "sys:sleep" })
        context.preferences.systemDisabled = []
        #expect(Search.results(for: "sleep", context: context).contains { $0.id == "sys:sleep" })
    }

    @Test func clipboardClearKeyword() {
        var context = SearchContext()
        context.preferences.clipboardEnabled = true
        context.preferences.clipboardClearKeywordEnabled = true
        let all = Search.results(for: "clear", context: context)
        #expect(all.contains { $0.kind == "clipclear" && $0.payload == "all" })
        let five = Search.results(for: "clear 5", context: context)
        #expect(five.contains { $0.kind == "clipclear" && $0.payload == "5" })
        context.preferences.clipboardClearKeywordEnabled = false
        #expect(!Search.results(for: "clear", context: context).contains { $0.kind == "clipclear" })
    }

    @Test func ejectAllRespectsEnableSwitch() {
        var context = SearchContext()
        context.preferences.ejectAllEnabled = false
        #expect(!Search.results(for: "ejectall", context: context).contains { $0.id == "sys:ejectall" })
        context.preferences.ejectAllEnabled = true
        #expect(Search.results(for: "ejectall", context: context).contains { $0.id == "sys:ejectall" })
    }

    @Test func fileBrowserListsDirectoriesFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jfred-browser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("beta.txt"))
        try Data("x".utf8).write(to: root.appendingPathComponent("alpha.txt"))
        let entries = FileBrowser.entries(for: root.path + "/")
        #expect(entries?.first?.isDirectory == true)
        #expect(entries?.first?.name == "Folder")
        #expect(entries?.contains { $0.name == "alpha.txt" } == true)
        #expect(FileBrowser.entries(for: root.path + "/al")?.map(\.name) == ["alpha.txt"])
        #expect(FileBrowser.entries(for: "not/a/path") == nil)
    }

    @Test func clipboardViewerIsHistory() {
        var context = SearchContext()
        context.preferences.clipboardEnabled = true
        context.preferences.clipboardSnippetsAtTop = false
        context.apps = [AppRecord(id: "app", name: "Clipboard", path: "/Applications/Clipboard.app")]
        let newer = ClipItem(text: "newer clip", date: Date(timeIntervalSince1970: 2))
        let older = ClipItem(text: "older clip", date: Date(timeIntervalSince1970: 1))
        context.clips = [newer, older]
        let rows = Search.results(for: "clipboard", context: context)
        #expect(rows.map(\.title) == ["newer clip", "older clip"])
        #expect(!rows.contains { $0.kind == "app" })
        context.clips = [ClipItem(text: "Image", date: Date(), kind: "image", imageFile: "/tmp/clip.png", sourcePath: "/Applications/Safari.app", sourceName: "Safari")]
        let image = Search.results(for: "clipboard", context: context).first
        #expect(image?.icon == "clipimage:/tmp/clip.png")
        #expect(image?.badge == "file:/Applications/Safari.app")
        #expect(image?.badgeName == "Safari")
    }

    @Test func clipboardViewerIncludesSnippets() {
        var context = SearchContext()
        context.preferences.clipboardEnabled = true
        context.preferences.clipboardSnippetsAtTop = true
        context.preferences.clipboardSnippetsWhenSearching = true
        context.snippets = [Snippet(name: "Address", keyword: ";addr", text: "1 Infinite Loop", autoExpand: true)]
        let all = Search.results(for: "clipboard", context: context)
        #expect(all.contains { $0.id == "snippets:all" })
        #expect(!all.contains { $0.kind == "snippet" })
        let filtered = Search.results(for: "clipboard infinite", context: context)
        #expect(filtered.contains { $0.kind == "snippet" && $0.title == "Address" })
    }

    @Test func clipboardTitlesKeepNewlinesAndDropObjectReplacement() {
        var context = SearchContext()
        context.preferences.clipboardEnabled = true
        context.preferences.clipboardSnippetsAtTop = false
        context.clips = [ClipItem(text: "one\ntwo\u{FFFC}\tend", date: Date())]
        let row = Search.results(for: "clipboard", context: context).first
        #expect(row?.title == "one⏎two⇥end")
        #expect(row?.subtitle == "Clipboard")
    }

    @Test func customTerminalPrefix() {
        var context = SearchContext()
        context.preferences.terminalPrefix = "!"
        let rows = Search.results(for: "!echo hi", context: context)
        #expect(rows.first?.kind == "terminal")
        #expect(rows.first?.payload == "echo hi")
    }

    @Test func newPreferencesRoundTrip() throws {
        var prefs = Preferences()
        prefs.clipboardAutoPaste = false
        prefs.fileBufferTimeoutMinutes = 9
        prefs.calculatorAdvanced = false
        prefs.dictionaryDefineKeyword = "lookup"
        prefs.terminalPrefix = "!"
        prefs.uaShowRightArrow = false
        prefs.dictionaryPasteOnAction = true
        prefs.snippetExpandPlaySound = false
        prefs.clipboardIgnoreApps = ["Keychain Access", "CustomApp"]
        prefs.clipboardRetentionImages = "1 week"
        prefs.customThemes = [CustomTheme(name: "Test Theme", width: 600)]
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(decoded.clipboardAutoPaste == false)
        #expect(decoded.fileBufferTimeoutMinutes == 9)
        #expect(decoded.calculatorAdvanced == false)
        #expect(decoded.dictionaryDefineKeyword == "lookup")
        #expect(decoded.terminalPrefix == "!")
        #expect(decoded.uaShowRightArrow == false)
        #expect(decoded.dictionaryPasteOnAction == true)
        #expect(decoded.snippetExpandPlaySound == false)
        #expect(decoded.clipboardIgnoreApps == ["Keychain Access", "CustomApp"])
        #expect(decoded.clipboardRetentionImages == "1 week")
        #expect(decoded.customThemes.first?.name == "Test Theme")
        #expect(decoded.customThemes.first?.width == 600)
    }

@Test func updateVersionsAndOfficialURLs() {
    #expect(AppVersion.compare("0.9.0", "0.10.0") == .orderedAscending)
    #expect(AppVersion.compare("v0.14.0", "0.14.0") == .orderedSame)
    #expect(AppVersion.compare("0.14.0", "0.14.0-beta") == .orderedDescending)
    #expect(AppVersion.compare("nope", "1.0.0") == nil)
    #expect(AppUpdateFeed.version(fromTag: "v0.14.0") == "0.14.0")
    #expect(AppUpdateFeed.version(fromTag: "0.14.0-beta") == nil)
    let url = URL(string: "https://github.com/weijing24/Jfred/releases/download/v0.14.0/Jfred-0.14.0-arm64.dmg")!
    #expect(AppUpdateFeed.isOfficialAssetURL(url, version: "0.14.0", architecture: "arm64"))
    #expect(!AppUpdateFeed.isOfficialAssetURL(url, version: "0.14.0", architecture: "x86_64"))
    #expect(!AppUpdateFeed.isOfficialAssetURL(URL(string: "http://github.com/weijing24/Jfred/releases/download/v0.14.0/Jfred-0.14.0-arm64.dmg")!, version: "0.14.0", architecture: "arm64"))
    #expect(!AppUpdateFeed.isOfficialAssetURL(URL(string: "https://github.com.evil/weijing24/Jfred/releases/download/v0.14.0/Jfred-0.14.0-arm64.dmg")!, version: "0.14.0", architecture: "arm64"))
    #expect(!AppUpdateFeed.isOfficialAssetURL(URL(string: "https://evilgithub.com/weijing24/Jfred/releases/download/v0.14.0/Jfred-0.14.0-arm64.dmg")!, version: "0.14.0", architecture: "arm64"))
    #expect(!AppUpdateFeed.isOfficialAssetURL(URL(string: "https://github.com/weijing24/Jfred/releases/download/v0.14.0/Jfred-0.14.0-arm64.dmg.evil")!, version: "0.14.0", architecture: "arm64"))
    #expect(!AppUpdateFeed.isOfficialAssetURL(URL(string: "https://github.com/other/Jfred/releases/download/v0.14.0/Jfred-0.14.0-arm64.dmg")!, version: "0.14.0", architecture: "arm64"))
    #expect(!AppUpdateFeed.isAllowedAssetHost("release-assets.githubusercontent.com.evil"))
    #expect(AppUpdateFeed.isAllowedAssetHost("release-assets.githubusercontent.com"))
    #expect(!AppUpdateFeed.isAllowedAPIHost("github.com"))
    #expect(UpdatePaths.isInstallableBundlePath("/Applications/Jfred.app"))
    #expect(!UpdatePaths.isInstallableBundlePath("/Volumes/Jfred/Jfred.app"))
    #expect(!UpdatePaths.isInstallableBundlePath("/private/var/folders/xx/AppTranslocation/ABC/d/Jfred.app"))
    #expect(!UpdatePaths.isInstallableBundlePath("/Applications/Other.app"))
    #expect(!UpdatePaths.isInstallableBundlePath("/tmp/Jfred.app\n/Applications/Jfred.app"))
}

@Test func updateFeedSelectsTheMatchingRelease() throws {
    let sha = String(repeating: "ab", count: 32)
    let feed = """
    [
      {"tag_name":"v0.15.0","draft":true,"prerelease":false,"body":"draft","assets":[\(asset("0.15.0", sha, 10))]},
      {"tag_name":"v0.14.0-beta","prerelease":true,"body":"skip tag","assets":[\(asset("0.14.0-beta", sha, 10))]},
      {"tag_name":"v0.16.0","prerelease":true,"body":"pre","assets":[\(asset("0.16.0", sha, 10)),{"name":"notes.txt","browser_download_url":"https://evil.example/x","size":4,"digest":"sha256:\(sha)"}]},
      {"tag_name":"v0.13.0","prerelease":false,"body":"old","assets":[\(asset("0.13.0", sha, 10))]},
      {"tag_name":"v0.12.0","prerelease":false,"body":"bad","assets":[{"name":"Jfred-0.12.0-arm64.dmg","browser_download_url":"https://github.com/weijing24/Jfred/releases/download/v0.12.0/Jfred-0.12.0-arm64.dmg","size":10,"digest":"md5:\(sha)"}]},
      {"tag_name":"v0.11.0","prerelease":false,"body":"huge","assets":[{"name":"Jfred-0.11.0-arm64.dmg","browser_download_url":"https://github.com/weijing24/Jfred/releases/download/v0.11.0/Jfred-0.11.0-arm64.dmg","size":\(AppUpdateFeed.maxAssetBytes + 1),"digest":"sha256:\(sha)"}]},
      {"tag_name":"v0.14.0","prerelease":false,"body":"stable notes","assets":[\(asset("0.14.0", sha, 20, architecture: "x86_64")),\(asset("0.14.0", sha, 30))]}
    ]
    """
    let catalog = try AppUpdateFeed.parse(Data(feed.utf8), architecture: "arm64")
    #expect(catalog.publishedCount == 5)
    #expect(catalog.releases.map(\.version) == ["0.16.0", "0.13.0", "0.14.0"])
    #expect(catalog.releases.first { $0.version == "0.14.0" }?.asset.byteCount == 30)
    #expect(catalog.releases.first { $0.version == "0.14.0" }?.asset.sha256 == sha)
    let stable = AppUpdateFeed.offer(in: catalog, channel: .updates, current: "0.14.0")
    guard case .upToDate(_, let notes) = stable else {
        Issue.record("expected the installed stable release")
        return
    }
    #expect(notes == "stable notes")
    let behind = AppUpdateFeed.offer(in: catalog, channel: .updates, current: "0.13.0")
    guard case .available(let release) = behind else {
        Issue.record("expected 0.14.0")
        return
    }
    #expect(release.version == "0.14.0")
    let pre = AppUpdateFeed.offer(in: catalog, channel: .prereleases, current: "0.14.0")
    guard case .available(let preview) = pre else {
        Issue.record("expected the pre-release")
        return
    }
    #expect(preview.version == "0.16.0")
    #expect(preview.prerelease)
    let ahead = AppUpdateFeed.offer(in: catalog, channel: .updates, current: "9.0.0")
    guard case .upToDate = ahead else {
        Issue.record("a newer local build is up to date")
        return
    }
    let empty = try AppUpdateFeed.parse(Data("[]".utf8), architecture: "arm64")
    guard case .unavailable = AppUpdateFeed.offer(in: empty, channel: .updates, current: "0.14.0") else {
        Issue.record("expected no releases")
        return
    }
    #expect(throws: UpdateFeedError.self) {
        try AppUpdateFeed.parse(Data("{}".utf8), architecture: "arm64")
    }
    let long = String(repeating: "n", count: AppUpdateFeed.notesLimit + 5)
    let clipped = try AppUpdateFeed.parse(Data("""
    [{"tag_name":"v1.0.0","body":"\(long)","assets":[\(asset("1.0.0", sha, 10))]}]
    """.utf8), architecture: "arm64")
    #expect(clipped.releases[0].notes.hasSuffix("\n…"))
    #expect(clipped.releases[0].notes.count == AppUpdateFeed.notesLimit + 2)
}

@Test func updateChecksumMatchesFileBytes() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("jfred-hash-\(UUID().uuidString)")
    try Data("hello".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(try UpdateChecksum.sha256Hex(file: url) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    #expect(UpdateChecksum.matches(file: url, sha256: "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824"))
    #expect(!UpdateChecksum.matches(file: url, sha256: String(repeating: "ab", count: 32)))
}

@Test func liveGitHubFeedParsesWhenRequested() async throws {
    guard ProcessInfo.processInfo.environment["JFRED_UPDATE_LIVE"] == "1" else { return }
    var request = URLRequest(url: AppUpdateFeed.releasesURL())
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("Jfred-test", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode
    #expect(status == 200)
    let catalog = try AppUpdateFeed.parse(data, architecture: "arm64")
    #expect(!catalog.releases.isEmpty)
    guard case .available(let release) = AppUpdateFeed.offer(in: catalog, channel: .updates, current: "0.0.0") else {
        Issue.record("expected a published update")
        return
    }
    #expect(AppUpdateFeed.isOfficialAssetURL(release.asset.downloadURL, version: release.version, architecture: "arm64"))
    guard case .upToDate = AppUpdateFeed.offer(in: catalog, channel: .updates, current: "999.0.0") else {
        Issue.record("a future version should be current")
        return
    }
}

@Test func ordinaryTypingIsNotASlowFileQuery() {
    let prefs = Preferences()
    #expect(!Search.exclusiveSlowQuery(raw: "cal", preferences: prefs))
    #expect(!Search.wantsFiles(raw: "cal", preferences: prefs))
    #expect(Search.exclusiveSlowQuery(raw: "open report", preferences: prefs))
    #expect(Search.exclusiveSlowQuery(raw: " report", preferences: prefs))
    #expect(Search.exclusiveSlowQuery(raw: "find report", preferences: prefs))
    #expect(Search.exclusiveSlowQuery(raw: "in notes", preferences: prefs))
    #expect(!Search.wantsFiles(raw: "in notes", preferences: prefs))
}

private func asset(_ version: String, _ sha: String, _ size: Int64, architecture: String = "arm64") -> String {
    let name = AppUpdateFeed.assetName(version: version, architecture: architecture)
    return #"{"name":"\#(name)","browser_download_url":"https://github.com/weijing24/Jfred/releases/download/v\#(version)/\#(name)","size":\#(size),"digest":"sha256:\#(sha)"}"#
}


    @Test func fileOpenPolicy() {
        let policy = FileOpenPolicy(
            revealInsteadOfOpening: false,
            openFoldersInFinder: true,
            runAppleScripts: true,
            touchFolders: true,
            touchAliases: true
        )
        #expect(policy.steps(exists: true, isDirectory: true, isAppleScript: false, resolvesElsewhere: false) == [.reveal, .touch])
        #expect(policy.steps(exists: true, isDirectory: false, isAppleScript: true, resolvesElsewhere: false) == [.runAppleScript])
        #expect(policy.steps(exists: true, isDirectory: false, isAppleScript: false, resolvesElsewhere: true) == [.open, .touchResolvedTarget])
        let reveal = FileOpenPolicy(revealInsteadOfOpening: true, openFoldersInFinder: true, runAppleScripts: true, touchFolders: true, touchAliases: true)
        #expect(reveal.steps(exists: true, isDirectory: true, isAppleScript: false, resolvesElsewhere: false) == [.reveal])
    }

    @Test func systemEffectsIgnoreDisabledCommandsAndParseVolume() {
        #expect(ActionExecutor.systemEffect(id: "sleep", disabled: ["sleep"], ejectScope: "local") == nil)
        #expect(ActionExecutor.systemEffect(id: "volume:40", disabled: [], ejectScope: "local") == .setOutputVolume(40))
        #expect(ActionExecutor.systemEffect(id: "volume:140", disabled: [], ejectScope: "local") == nil)
        #expect(ActionExecutor.systemEffect(id: "eject", disabled: [], ejectScope: "all") == .eject(all: true))
        #expect(ActionExecutor.systemEffect(id: "ejectall", disabled: [], ejectScope: "local") == .eject(all: true))
        #expect(ActionExecutor.systemEffect(id: "nope", disabled: [], ejectScope: "local") == .unknown("nope"))
    }

    @Test func clipboardRetentionFollowsClipKind() {
        var preferences = Preferences()
        preferences.clipboardRetentionText = "1 day"
        preferences.clipboardRetentionImages = "1 week"
        preferences.clipboardRetentionFiles = "never"
        #expect(ClipboardRetention.label(forKind: "text", preferences: preferences) == "1 day")
        #expect(ClipboardRetention.interval(for: "1 week") == 604_800.0)
        #expect(ClipboardRetention.interval(for: "never") == nil)
        #expect(Calculator.allows("=sqrt(9)", advanced: false) == false)
        #expect(Calculator.allows("2+2", advanced: false) == true)
        #expect(Calculator.allows("=10/4", advanced: true) == true)
    }

private struct FakeWorkflowRunner: WorkflowScriptRunning {
    var output: String

    func run(_ request: WorkflowScriptRequest) async -> WorkflowScriptOutput {
        WorkflowScriptOutput(stdout: output, status: 0)
    }
}

struct WorkflowGraphTests {
    @Test func importsAlfredObjectGraph() throws {
        let info: [String: Any] = [
            "bundleid": "com.example.test",
            "name": "Example",
            "createdby": "Tester",
            "description": "A test workflow",
            "disabled": false,
            "objects": [
                ["uid": "KW", "type": "alfred.workflow.input.scriptfilter", "version": 3,
                 "config": ["keyword": "ex", "withspace": false, "script": "echo", "type": 0, "scriptargtype": 1]],
                ["uid": "ACT", "type": "alfred.workflow.output.clipboard", "version": 3,
                 "config": ["clipboardtext": "{query}"]],
            ],
            "connections": [
                "KW": [["destinationuid": "ACT", "modifiers": 0, "modifiersubtext": ""]]
            ],
            "uidata": [
                "KW": ["xpos": 20, "ypos": 40],
                "ACT": ["xpos": 300, "ypos": 40],
            ],
        ]
        let workflow = try #require(WorkflowImporter.workflow(from: info, rootPath: "/tmp/example"))
        #expect(workflow.bundleID == "com.example.test")
        #expect(workflow.name == "Example")
        #expect(workflow.objects.count == 2)
        #expect(workflow.connections.count == 1)
        #expect(workflow.keyword == "ex")
        #expect(workflow.objects[0].kind == .scriptFilter)
        #expect(workflow.objects[0].position.x == 20)
        #expect(workflow.objects[1].kind == .clipboard)
    }

    @Test func scriptFilterResultsAndGraphRun() async throws {
        let filter = WorkflowObject(kind: .scriptFilter, config: [
            "keyword": .string("gh"), "withspace": .boolean(true),
            "script": .string("search"), "type": .integer(0), "scriptargtype": .integer(1),
        ])
        let script = WorkflowObject(kind: .runScript, config: [
            "script": .string("handle"), "type": .integer(0), "scriptargtype": .integer(1),
        ])
        let clipboard = WorkflowObject(kind: .clipboard, config: ["clipboardtext": .string("copied: {query}")])
        let workflow = Workflow(
            name: "GitHub", author: "Tester", symbol: "puzzlepiece.extension", tint: "561D7E",
            enabled: true, builtin: nil,
            objects: [filter, script, clipboard],
            connections: [
                WorkflowConnection(source: filter.id, destination: script.id),
                WorkflowConnection(source: script.id, destination: clipboard.id),
            ],
            rootPath: "/tmp/example"
        )
        let match = try #require(WorkflowEngine.match(in: [workflow], query: "gh swift"))
        #expect(match.invocation.keyword == "gh")
        #expect(match.invocation.argument == "swift")

        let filterOutput = """
        {"items":[{"title":"Swift","subtitle":"Language","arg":"swift-arg","valid":true}],"variables":{"session":"1"}}
        """
        let filterEngine = WorkflowEngine(workflow: workflow, runner: FakeWorkflowRunner(output: filterOutput))
        let results = try #require(await filterEngine.results(for: match.invocation))
        #expect(results.items.count == 1)
        #expect(results.items[0].argument == "swift-arg")
        #expect(results.variables["session"] == "1")

        let runEngine = WorkflowEngine(workflow: workflow, runner: FakeWorkflowRunner(output: "handled"))
        let state = await runEngine.run(invocation: match.invocation, item: results.items[0])
        #expect(state.logs.count == 2)
        #expect(state.effects == [.copy("copied: handled")])
    }

    @Test func conditionalUsesSourceOutputBranch() async throws {
        let conditionUID = "BRANCH-RED"
        let keyword = WorkflowObject(kind: .keyword, config: ["keyword": .string("colour")])
        let conditional = WorkflowObject(kind: .conditional, config: [
            "conditions": .array([
                .object([
                    "uid": .string(conditionUID),
                    "inputstring": .string("{query}"),
                    "matchstring": .string("red"),
                    "matchmode": .integer(0),
                    "outputlabel": .string("red"),
                ])
            ])
        ])
        let red = WorkflowObject(kind: .clipboard, config: ["clipboardtext": .string("red path")])
        let other = WorkflowObject(kind: .clipboard, config: ["clipboardtext": .string("other path")])
        let workflow = Workflow(
            name: "Conditional", author: "Tester", symbol: "bolt.fill", tint: "561D7E",
            enabled: true, builtin: nil,
            objects: [keyword, conditional, red, other],
            connections: [
                WorkflowConnection(source: keyword.id, destination: conditional.id),
                WorkflowConnection(source: conditional.id, destination: red.id, sourceOutputUID: conditionUID),
                WorkflowConnection(source: conditional.id, destination: other.id),
            ]
        )
        let invocation = WorkflowInvocation(workflowID: workflow.id, inputID: keyword.id, keyword: "colour", argument: "red")
        let engine = WorkflowEngine(workflow: workflow, runner: FakeWorkflowRunner(output: ""))
        let state = await engine.run(invocation: invocation)
        #expect(state.effects == [.copy("red path")])
    }

    @Test func scriptFilterParsesJSONAndFilters() throws {
        let text = """
        ignoring log line
        {"variables":{"fruit":"banana"},"items":[
          {"title":"My Family Photos","subtitle":"Pictures","arg":["one","two"],"mods":{"cmd":{"arg":"three"}}},
          {"title":"Family Videos","arg":"video"}
        ]}
        """
        let result = WorkflowScriptFilterParser.parse(text)
        #expect(result.items.count == 2)
        #expect(result.variables["fruit"] == "banana")
        #expect(result.items[0].arguments == ["one", "two"])
        #expect(result.items[0].applying(modifier: .command).argument == "three")
        #expect(WorkflowScriptFilterParser.filter(result.items, query: "photos", mode: 0).count == 1)
        #expect(WorkflowScriptFilterParser.filter(result.items, query: "family", mode: 1).count == 1)
    }

    @Test func legacyWorkflowDecodesAndKeepsActions() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","keyword":"do","author":"Me",
         "symbol":"bolt.fill","tint":"561D7E","enabled":true,"actions":[
           {"id":"00000000-0000-0000-0000-000000000002","kind":"copy","value":"{query}"}
         ]}
        """
        let workflow = try JSONDecoder().decode(Workflow.self, from: Data(json.utf8))
        #expect(workflow.name == "Legacy")
        #expect(workflow.keyword == "do")
        #expect(workflow.definitionVersion == 0)
        #expect(workflow.objects.count == 2)
        #expect(workflow.connections.count == 1)
        #expect(workflow.actions.count == 1)
        #expect(workflow.actions[0].kind == .copy)

        let encoded = try JSONEncoder().encode(workflow)
        let decoded = try JSONDecoder().decode(Workflow.self, from: encoded)
        #expect(decoded.name == "Legacy")
        #expect(decoded.objects.count == 2)
    }

    @Test func templateExpandsVariablesAndQuotedQuery() {
        let variables = ["name": "World"]
        let result = WorkflowTemplate.expand("echo \"{query}\" {var:name}", query: "hello world", variables: variables, escaping: 127)
        #expect(result.contains("hello world"))
        #expect(result.contains("World"))
        #expect(result.hasPrefix("echo \"hello world\""))
        #expect(WorkflowTemplate.conditionalMatches("Left", pattern: "left", mode: 0, caseSensitive: false))
        #expect(WorkflowTemplate.conditionalMatches("10", pattern: "5", mode: 2, caseSensitive: false))
        #expect(WorkflowTemplate.conditionalMatches("left", pattern: "le", mode: 4, caseSensitive: false))
        #expect(!WorkflowTemplate.conditionalMatches("right", pattern: "left", mode: 0, caseSensitive: false))
    }
}

extension WorkflowGraphTests {
    @Test func importsInstalledJfredWorkflowsWhenPresent() throws {
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Jfred/ImportedWorkflows", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.hasDirectoryPath {
            let plist = entry.appendingPathComponent("info.plist")
            guard let data = try? Data(contentsOf: plist),
                  let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { continue }
            let workflow = try #require(WorkflowImporter.workflow(from: info, rootPath: entry.path))
            #expect(!workflow.bundleID.isEmpty)
            #expect(!workflow.objects.isEmpty)
            for connection in workflow.connections {
                #expect(workflow.object(id: connection.source) != nil)
                #expect(workflow.object(id: connection.destination) != nil)
            }
        }
    }

    @Test func runPayloadRoundTripsItemAndModifiers() throws {
        let item = WorkflowItem(
            uid: "one",
            title: "One",
            arguments: ["arg"],
            variables: ["key": "value"],
            mods: ["cmd": WorkflowItemMod(arguments: ["cmd-arg"])]
        )
        let payload = WorkflowRunPayload(
            workflowID: UUID(),
            inputID: UUID(),
            keyword: "wf",
            argument: "query",
            item: item
        )
        let decoded = try #require(payload.json.flatMap(WorkflowRunPayload.decode))
        #expect(decoded.workflowID == payload.workflowID)
        #expect(decoded.item?.arguments == ["arg"])
        #expect(decoded.item?.applying(modifier: .command).argument == "cmd-arg")
    }
}

extension WorkflowGraphTests {
    @Test func processRunnerExecutesBashWithArguments() async {
        let output = await ProcessWorkflowRunner().run(WorkflowScriptRequest(
            workflowID: UUID(),
            objectID: UUID(),
            bundleID: "com.example.runner",
            workflowName: "Runner",
            workflowVersion: "1.0",
            keyword: "run",
            language: .bash,
            source: #"printf '{"items":[{"title":"%s","arg":"%s"}]}' "$1" "$1""#,
            sourceFile: "",
            argumentMode: .argv,
            escaping: 0,
            query: "hello world",
            arguments: ["hello world"],
            variables: [:],
            directory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "alfred_workflow_cache": NSTemporaryDirectory() + "jfred-runner-test",
            ]
        ))
        #expect(output.isSuccess)
        let result = WorkflowScriptFilterParser.parse(output.stdout)
        #expect(result.items.first?.title == "hello world")
        #expect(result.items.first?.argument == "hello world")
    }
}

extension WorkflowGraphTests {
    @Test func xmlScriptFilterUsesFirstDocumentAndArgChild() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <items>
          <item valid="yes"><title>2023-11-15T06:13:20</title><subtitle>Local time</subtitle><arg>2023-11-15T06:13:20</arg></item>
        </items>
        <?xml version="1.0" encoding="utf-8"?>
        <items><item valid="no"><title>Error item</title></item></items>
        """
        let result = WorkflowScriptFilterParser.parse(xml)
        #expect(result.items.count == 1)
        #expect(result.items[0].title == "2023-11-15T06:13:20")
        #expect(result.items[0].argument == "2023-11-15T06:13:20")
    }

    @Test func allDefaultOutputsRun() async throws {
        let filter = WorkflowObject(kind: .scriptFilter, config: ["keyword": .string("ts"), "script": .string("x")])
        let clipboard = WorkflowObject(kind: .clipboard, config: ["clipboardtext": .string("{query}")])
        let notification = WorkflowObject(kind: .notification, config: ["title": .string("Time: {query}"), "text": .string("Copied")])
        let workflow = Workflow(
            name: "Fanout", author: "Tester", symbol: "bolt.fill", tint: "561D7E",
            enabled: true, builtin: nil,
            objects: [filter, clipboard, notification],
            connections: [
                WorkflowConnection(source: filter.id, destination: clipboard.id),
                WorkflowConnection(source: filter.id, destination: notification.id),
            ]
        )
        let item = WorkflowItem(title: "Result", arguments: ["1700000000"])
        let invocation = WorkflowInvocation(workflowID: workflow.id, inputID: filter.id, keyword: "ts", argument: "1700000000")
        let state = await WorkflowEngine(workflow: workflow, runner: FakeWorkflowRunner(output: "")).run(invocation: invocation, item: item)
        #expect(state.effects.contains(.copy("1700000000")))
        #expect(state.effects.contains(.notification(title: "Time: 1700000000", text: "Copied")))
    }
}

struct FileActionTests {
    @Test func applicationMenuMatchesFileActions() {
        let titles = FileActions.items(kind: "app", path: "/Applications/Orbit.app").map(\.title)
        #expect(titles == [
            "Recent Documents...",
            "Show Package Contents",
            "Open",
            "Open with...",
            "Reveal in Finder",
            "Get Info",
            "Copy to...",
            "Move to...",
            "Delete",
            "Copy [with Replace] to...",
            "Move [with Replace] to...",
            "Browse Folder in Jfred",
            "Open Terminal Here",
            "Copy Path to Clipboard",
            "Copy File to Clipboard",
        ])
        #expect(FileActions.items(kind: "app", path: "/Applications/Orbit.app").first?.subtitle == "Show recent documents for application")
        #expect(FileActions.items(kind: "file", path: "/tmp/notes.txt").isEmpty)
        #expect(FileActions.items(kind: "app", path: "Orbit").isEmpty)
    }

    @Test func recentDocumentBookmarksKeepBookBlobs() throws {
        let book = Data("bookdemo".utf8)
        let plist: [String: Any] = ["$objects": ["$null", book, "Bookmark", Data("nope".utf8)]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        #expect(RecentDocuments.bookmarkBlobs(in: data) == [book])
        #expect(RecentDocuments.bookmarkBlobs(in: Data("not a plist".utf8)).isEmpty)
    }

    @Test func textEditRecentDocumentsPointAtExistingFiles() {
        let path = "/System/Applications/TextEdit.app"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let items = RecentDocuments.urls(forAppAt: path)
        #expect(items.allSatisfy { $0.path.hasPrefix("/") && FileManager.default.fileExists(atPath: $0.path) })
    }
}
