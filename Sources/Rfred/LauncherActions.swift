import Foundation
import RfredCore

struct LauncherAction: Identifiable, Equatable {
    enum Kind: String {
        case open
        case reveal
        case copyPath
        case copyName
        case copyValue
        case openBrowser
        case quickLook
        case largeType
        case pasteClipboard
        case pasteValue
        case searchWeb
        case recentDocuments
        case showPackageContents
        case openWith
        case getInfo
        case copyTo
        case moveTo
        case delete
        case copyReplacing
        case moveReplacing
        case browseFolder
        case openTerminal
        case copyFile
        case openPath
        case unavailable
    }

    var kind: Kind
    var title: String
    var subtitle: String
    var symbol: String
    var argument: String = ""

    var id: String { "\(kind.rawValue):\(title):\(argument)" }

    var fileActionID: FileActionID? {
        switch kind {
        case .recentDocuments: .recentDocuments
        case .showPackageContents: .showPackageContents
        case .open: .open
        case .openWith: .openWith
        case .reveal: .reveal
        case .getInfo: .getInfo
        case .copyTo: .copyTo
        case .moveTo: .moveTo
        case .delete: .delete
        case .copyReplacing: .copyReplacing
        case .moveReplacing: .moveReplacing
        case .browseFolder: .browseFolder
        case .openTerminal: .openTerminal
        case .copyPath: .copyPath
        case .copyFile: .copyFile
        default: nil
        }
    }
}

extension FileActionID {
    var symbol: String {
        switch self {
        case .recentDocuments: "clock"
        case .showPackageContents: "shippingbox"
        case .open: "arrow.up.forward.app"
        case .openWith: "square.grid.2x2"
        case .reveal: "folder"
        case .getInfo: "info.circle"
        case .copyTo, .copyReplacing: "doc.on.doc"
        case .moveTo, .moveReplacing: "arrow.right.square"
        case .delete: "trash"
        case .browseFolder: "folder"
        case .openTerminal: "terminal"
        case .copyPath, .copyFile: "doc.on.clipboard"
        }
    }

    var actionKind: LauncherAction.Kind {
        switch self {
        case .recentDocuments: .recentDocuments
        case .showPackageContents: .showPackageContents
        case .open: .open
        case .openWith: .openWith
        case .reveal: .reveal
        case .getInfo: .getInfo
        case .copyTo: .copyTo
        case .moveTo: .moveTo
        case .delete: .delete
        case .copyReplacing: .copyReplacing
        case .moveReplacing: .moveReplacing
        case .browseFolder: .browseFolder
        case .openTerminal: .openTerminal
        case .copyPath: .copyPath
        case .copyFile: .copyFile
        }
    }
}
