import Testing
import JfredCore

struct PreferencesSidebarTests {
    @Test func sidebarExposesAllPanesAndADefaultSelection() {
        #expect(PreferencesSidebar.allIDs == [
            "general", "features", "workflows", "appearance", "advanced",
            "usage", "help", "update",
        ])
        #expect(PreferencesSidebar.defaultSelection == "general")
        #expect(PreferencesSidebar.allIDs.contains(PreferencesSidebar.defaultSelection))
        #expect(PreferencesSidebar.defaultSelection == PreferencesSidebar.topIDs.first)
        #expect(PreferencesSidebar.bottomIDs.last == "update")
        #expect(Set(PreferencesSidebar.allIDs).count == PreferencesSidebar.allIDs.count)
    }
}
