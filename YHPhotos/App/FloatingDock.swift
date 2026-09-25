import SwiftUI

struct FloatingDock: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 0) {
            dockButton(.discover)
            dockButton(.wiki)
            Button { appModel.select(.upload) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(AppTheme.accent, in: Circle())
                    .shadow(color: AppTheme.accent.opacity(0.5), radius: 12)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("上传")
            dockButton(.messages)
            dockButton(.profile)
        }
        .padding(.horizontal, 8)
        .frame(height: AppTheme.dockHeight)
        .appGlass(in: Capsule(), interactive: true)
    }

    private func dockButton(_ section: AppSection) -> some View {
        Button { appModel.select(section) } label: {
            VStack(spacing: 4) {
                Image(systemName: section.icon)
                    .font(.system(size: 21, weight: .medium))
                Text(section.title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(appModel.selectedSection == section ? AppTheme.accent : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if section == .messages, appModel.unreadMessages > 0 {
                    Text(appModel.unreadMessages > 99 ? "99+" : "\(appModel.unreadMessages)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                        .offset(x: -7, y: 8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(appModel.selectedSection == section ? .isSelected : [])
    }
}
