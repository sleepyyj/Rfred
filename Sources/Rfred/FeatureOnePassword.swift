import AppKit
import SwiftUI
import RfredCore

extension FeaturesPane {
    var onePassword: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("1Password 8 Integration")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Rfred uses the 1Password CLI (op) to list and open items. Sign in with op signin first, then enable the integration below.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Get 1Password 8 Integration Workflow") {
                    if let url = URL(string: "https://alfred.app/workflows/alfredapp/1password/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(18)
            .frame(maxWidth: 620, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0x2F7F7F)))
            SettingsLabeled(title: "Integration:") {
                Toggle("Enable 1Password Bookmarks", isOn: model.bindPref(\.onePasswordEnabled))
                    .toggleStyle(.checkbox)
            }
            SettingsNote("Rfred can import and present your 1Password items in the results. This allows you to quickly open items from 1Password.")
            SettingsLabeled(title: "Status:") {
                Text(model.opItems.isEmpty ? "No items loaded. Turn this on after op item list works in Terminal." : "\(model.opItems.count) items loaded.")
                    .font(.system(size: 12))
                    .foregroundStyle(RfredColor.sub)
                Button("Reload items") { model.reloadOnePassword() }
            }
            SettingsNote("Only item names are read. Rfred never asks for or stores your 1Password master password.")
        }
    }

}
