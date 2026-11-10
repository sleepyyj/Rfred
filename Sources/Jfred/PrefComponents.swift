import SwiftUI

/// Segmented tab strip used at the top of feature pages.
struct SettingsTabBar: View {
    @Binding var selection: String
    var tabs: [String]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab)
                        .font(.system(size: 13))
                        .foregroundStyle(selection == tab ? JfredColor.ink : JfredColor.sub)
                        .padding(.horizontal, 15)
                        .frame(height: 23)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == tab ? Color.white : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0xE2E1E0).opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Rounded table / list card used in preference pages.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: JfredMetrics.cardRadius, style: .continuous)
        content()
            .background(.regularMaterial, in: shape)
            .overlay(shape.stroke(Color.black.opacity(0.08), lineWidth: 1))
    }
}

/// Light inset panel that groups a table and its toolbar.
struct SettingsPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: JfredMetrics.cardRadius, style: .continuous)
                    .fill(Color(hex: 0xF2F2F2).opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: JfredMetrics.cardRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}

/// Small rounded search field used above tables.
struct SettingsFilterField: View {
    var placeholder: String
    @Binding var text: String
    var width: CGFloat = 242

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x7A7A7A))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: 28)
        .background(
            RoundedRectangle(cornerRadius: JfredMetrics.controlRadius, style: .continuous).fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: JfredMetrics.controlRadius, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
        )
    }
}

/// Right-aligned form label + controls on a 120pt label grid.
struct SettingsLabeled<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(JfredColor.ink)
                .frame(width: 120, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }
}

/// Small grey explanation text, aligned with the control column.
struct SettingsNote: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(JfredColor.sub)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 130)
    }
}

/// Grey page header used by every feature page (title, subtitle, help).
struct PageHeaderBand: View {
    var icon: String
    var tint: Color
    var title: String
    var subtitle: String
    var help: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(JfredColor.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(JfredColor.sub)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let help {
                Button(action: help) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(Color(hex: 0x8A8A8A))
                }
                .buttonStyle(.plain)
                .help("Open help for this page")
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 80)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
        }
    }
}

/// Preferences page canvas.
struct PageSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.clear)
    }
}

/// Big white rounded content panel used under the page header.
struct FormPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: JfredMetrics.cardRadius, style: .continuous)
        content()
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.white.opacity(0.92)))
            .overlay(shape.stroke(Color.black.opacity(0.06), lineWidth: 1))
    }
}
