import Foundation
import Testing
@testable import JfredCore

@Suite struct WorkflowIconTests {
    @Test func epochStyleAbsoluteImagePathLoadsAsArtwork() throws {
        try withTempWorkflow { root in
            touch(root.appendingPathComponent("icon.png"))
            let clock = root.appendingPathComponent("Clock.icns")
            touch(clock)
            let resolved = WorkflowIcon.resolve(
                path: clock.path,
                type: "",
                workflowRoot: root.path,
                workflowSymbol: "clock"
            )
            #expect(resolved == .image(clock.path))
            #expect(resolved.resource == "image:\(clock.path)")
        }
    }

    @Test func unitConverterStyleEmptyItemFallsBackToWorkflowIcon() throws {
        try withTempWorkflow { root in
            let icon = root.appendingPathComponent("icon.png")
            touch(icon)
            let resolved = WorkflowIcon.resolve(
                path: "",
                type: "",
                workflowRoot: root.path,
                workflowSymbol: "ruler"
            )
            #expect(resolved == .image(icon.path))
            #expect(resolved.resource.hasPrefix("image:"))
        }
    }

    @Test func relativeImagePathResolvesAgainstWorkflowRoot() throws {
        try withTempWorkflow { root in
            let images = root.appendingPathComponent("images")
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            let flag = images.appendingPathComponent("flag.png")
            touch(flag)
            let resolved = WorkflowIcon.resolve(
                path: "images/flag.png",
                type: "",
                workflowRoot: root.path,
                workflowSymbol: "flag"
            )
            #expect(resolved == .image(flag.path))
        }
    }

    @Test func tildePathExpandsToAnImage() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent("Library/Caches/jfred-icon-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let picture = root.appendingPathComponent("note.icns")
        touch(picture)
        let relativeToHome = "~/" + picture.path.dropFirst(home.path.count + 1)
        #expect((relativeToHome as NSString).expandingTildeInPath == picture.path)
        let resolved = WorkflowIcon.resolve(
            path: relativeToHome,
            type: "",
            workflowRoot: "/tmp",
            workflowSymbol: "note"
        )
        #expect(resolved == .image(picture.path))
    }

    @Test func objectUIDIconIsUsedWhenItemAndWorkflowIconsAreMissing() throws {
        try withTempWorkflow { root in
            let uid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
            let objectIcon = root.appendingPathComponent("\(uid).png")
            touch(objectIcon)
            let resolved = WorkflowIcon.resolve(
                path: "",
                type: "",
                workflowRoot: root.path,
                workflowSymbol: "puzzlepiece.extension",
                objectUID: uid
            )
            #expect(resolved == .image(objectIcon.path))
        }
    }

    @Test func missingItemIconPrefersWorkflowIconOverObjectUID() throws {
        try withTempWorkflow { root in
            let uid = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            touch(root.appendingPathComponent("\(uid).png"))
            let workflowIcon = root.appendingPathComponent("icon.icns")
            touch(workflowIcon)
            // Object icons are the more specific fallback when a filter item
            // has no icon of its own; the workflow icon is next if no UID file exists.
            let withUID = WorkflowIcon.resolve(
                path: "",
                workflowRoot: root.path,
                workflowSymbol: "star",
                objectUID: uid
            )
            #expect(withUID == .image(root.appendingPathComponent("\(uid).png").path))

            let withoutUID = WorkflowIcon.resolve(
                path: "",
                workflowRoot: root.path,
                workflowSymbol: "star"
            )
            #expect(withoutUID == .image(workflowIcon.path))
        }
    }

    @Test func fileiconTypeUsesWorkspaceIconEvenForImageFiles() throws {
        try withTempWorkflow { root in
            let document = root.appendingPathComponent("document.png")
            touch(document)
            let resolved = WorkflowIcon.resolve(
                path: "document.png",
                type: "fileicon",
                workflowRoot: root.path,
                workflowSymbol: "doc"
            )
            #expect(resolved == .fileIcon(document.path))
            #expect(resolved.resource == "file:\(document.path)")
        }
    }

    @Test func typelessExistingNonImageFileUsesWorkspaceIcon() throws {
        try withTempWorkflow { root in
            let app = root.appendingPathComponent("Tool.app")
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            let resolved = WorkflowIcon.resolve(
                path: "Tool.app",
                type: "",
                workflowRoot: root.path,
                workflowSymbol: "app"
            )
            #expect(resolved == .fileIcon(app.path))
        }
    }

    @Test func filetypeUsesTheGivenUTIOrExtension() {
        let uti = WorkflowIcon.resolve(path: "public.jpeg", type: "filetype", workflowSymbol: "doc")
        #expect(uti == .fileType("public.jpeg"))
        #expect(uti.resource == "filetype:public.jpeg")

        let ext = WorkflowIcon.resolve(path: "png", type: "FileType", workflowSymbol: "doc")
        #expect(ext == .fileType("png"))
    }

    @Test func missingFileiconOrImageFallsBackThenToSymbol() throws {
        try withTempWorkflow { root in
            let missingFileicon = WorkflowIcon.resolve(
                path: "missing.app",
                type: "fileicon",
                workflowRoot: root.path,
                workflowSymbol: "app"
            )
            #expect(missingFileicon == .symbol("app"))

            let missingImage = WorkflowIcon.resolve(
                path: "gone.png",
                workflowRoot: root.path,
                workflowSymbol: "star"
            )
            #expect(missingImage == .symbol("star"))
        }
    }

    @Test func remoteURLUsesGlobeSymbol() throws {
        try withTempWorkflow { root in
            touch(root.appendingPathComponent("icon.png"))
            let resolved = WorkflowIcon.resolve(
                path: "https://example.com/icon.png",
                workflowRoot: root.path,
                workflowSymbol: "star"
            )
            #expect(resolved == .symbol("globe"))
        }
    }

    @Test func typelessPDFIconLoadsAsArtworkNotWorkspaceIcon() throws {
        try withTempWorkflow { root in
            touch(root.appendingPathComponent("icon.png"))
            let base64 = root.appendingPathComponent("base64.pdf")
            let url = root.appendingPathComponent("url.pdf")
            let html = root.appendingPathComponent("html.pdf")
            touch(base64)
            touch(url)
            touch(html)

            #expect(WorkflowIcon.resolve(path: "base64.pdf", workflowRoot: root.path) == .image(base64.path))
            #expect(WorkflowIcon.resolve(path: "url.pdf", workflowRoot: root.path) == .image(url.path))
            #expect(WorkflowIcon.resolve(path: "html.pdf", workflowRoot: root.path) == .image(html.path))
            #expect(WorkflowIcon.isImagePath(base64.path))

            // fileicon still means the Finder document icon, even for a PDF.
            let fileicon = WorkflowIcon.resolve(
                path: "base64.pdf",
                type: "fileicon",
                workflowRoot: root.path
            )
            #expect(fileicon == .fileIcon(base64.path))
        }
    }

    @Test func endToEndDevToysEncodeShape() throws {
        try withTempWorkflow { root in
            touch(root.appendingPathComponent("icon.png"))
            let base64 = root.appendingPathComponent("base64.pdf")
            let url = root.appendingPathComponent("url.pdf")
            let html = root.appendingPathComponent("html.pdf")
            touch(base64)
            touch(url)
            touch(html)

            // DevToys encode shape: JSON items with empty titles and typeless
            // relative PDF icon paths in the workflow directory.
            let json = """
            {"items":[
              {"title":"","subtitle":"⌘+L, ↩ Copy Base64 Encode","arg":"","icon":{"path":"base64.pdf"}},
              {"title":"","subtitle":"⌘+L, ↩ Copy URL Encode","arg":"","icon":{"path":"url.pdf"}},
              {"title":"","subtitle":"⌘+L, ↩ Copy HTML Encode","arg":"","icon":{"path":"html.pdf"}}
            ]}
            """
            let items = WorkflowScriptFilterParser.parse(json).items
            #expect(items.map(\.title) == ["", "", ""])
            #expect(items.map(\.iconPath) == ["base64.pdf", "url.pdf", "html.pdf"])
            #expect(items.map(\.iconType) == ["", "", ""])

            let icons = items.map {
                WorkflowIcon.resolve(
                    path: $0.iconPath,
                    type: $0.iconType,
                    workflowRoot: root.path,
                    workflowSymbol: "puzzlepiece.extension"
                )
            }
            #expect(icons == [.image(base64.path), .image(url.path), .image(html.path)])
            #expect(icons.allSatisfy { $0.resource.hasPrefix("image:") })
        }
    }

    @Test func endToEndEpochAndUnitConverterShapes() throws {
        try withTempWorkflow { root in
            let workflowIcon = root.appendingPathComponent("icon.png")
            let clock = root.appendingPathComponent("Clock.icns")
            let note = root.appendingPathComponent("AlertNoteIcon.icns")
            touch(workflowIcon)
            touch(clock)
            touch(note)

            // Epoch-converter shape: script-filter XML items with absolute .icns paths.
            let xml = """
            <?xml version="1.0"?><items>
              <item><title>Time</title><icon>\(clock.path)</icon></item>
              <item><title>Note</title><icon>\(note.path)</icon></item>
            </items>
            """
            let epochItems = WorkflowScriptFilterParser.parse(xml).items
            let epochIcons = epochItems.map {
                WorkflowIcon.resolve(
                    path: $0.iconPath,
                    type: $0.iconType,
                    workflowRoot: root.path,
                    workflowSymbol: "clock"
                )
            }
            #expect(epochIcons == [.image(clock.path), .image(note.path)])
            #expect(epochIcons.allSatisfy { $0.resource.hasPrefix("image:") })

            // Unit-converter shape: JSON items with no icon field; fall back to icon.png.
            let json = """
            {"items":[
              {"title":"1000 m","subtitle":"Kilometers → Meters","arg":"1000 m"},
              {"title":"10000 dm","arg":"10000 dm"}
            ]}
            """
            let convItems = WorkflowScriptFilterParser.parse(json).items
            let convIcons = convItems.map {
                WorkflowIcon.resolve(
                    path: $0.iconPath,
                    type: $0.iconType,
                    workflowRoot: root.path,
                    workflowSymbol: "ruler"
                )
            }
            let expected = WorkflowIconRef.image(workflowIcon.path)
            #expect(convIcons == [expected, expected])
            #expect(convIcons.allSatisfy { $0.resource == "image:\(workflowIcon.path)" })
        }
    }

    @Test func scriptFilterParserKeepsJSONAndXMLIconFields() {
        let json = """
        {"items":[
          {"title":"Abs","icon":{"path":"/tmp/Clock.icns"}},
          {"title":"Rel","icon":{"path":"icon.png"}},
          {"title":"File","icon":{"path":"/Applications/Safari.app","type":"fileicon"}},
          {"title":"Type","icon":{"path":"public.png","type":"filetype"}}
        ]}
        """
        let jsonItems = WorkflowScriptFilterParser.parse(json).items
        #expect(jsonItems.map(\.iconPath) == [
            "/tmp/Clock.icns", "icon.png", "/Applications/Safari.app", "public.png"
        ])
        #expect(jsonItems.map(\.iconType) == ["", "", "fileicon", "filetype"])

        let xml = """
        <?xml version="1.0"?><items>
          <item><title>Abs</title><icon>/tmp/Clock.icns</icon></item>
          <item><title>Rel</title><icon>icon.png</icon></item>
          <item><title>File</title><icon type="fileicon">/Applications/Safari.app</icon></item>
          <item><title>Type</title><icon type="filetype">public.png</icon></item>
        </items>
        """
        let xmlItems = WorkflowScriptFilterParser.parse(xml).items
        #expect(xmlItems.map(\.iconPath) == [
            "/tmp/Clock.icns", "icon.png", "/Applications/Safari.app", "public.png"
        ])
        #expect(xmlItems.map(\.iconType) == ["", "", "fileicon", "filetype"])
    }

    private func withTempWorkflow(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("jfred-icon-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func touch(_ url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
    }
}
