import SwiftUI

enum ToolUI {
    static func statusLabel(_ status: String) -> String {
        switch status {
        case "active": return L10n.string("进行中")
        case "upcoming": return L10n.string("即将开始")
        case "ended": return L10n.string("已结束")
        case "archived": return L10n.string("已归档")
        default: return status
        }
    }

    static func rankingModeLabel(_ mode: String) -> String {
        switch mode {
        case "photo_vote": return L10n.string("作品投票")
        case "approved_count": return L10n.string("过图数量")
        case "approval_rate": return L10n.string("过图率")
        default: return mode
        }
    }

    static func todayLocal() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func clock(_ iso: String?) -> String? {
        guard let iso, iso.count >= 16 else { return nil }
        let normalized = iso.replacingOccurrences(of: "T", with: " ")
        let start = normalized.index(normalized.startIndex, offsetBy: 11)
        let end = normalized.index(start, offsetBy: 5)
        return String(normalized[start..<end])
    }
}

struct StatusChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(AppTheme.elevated, in: Capsule())
            .foregroundStyle(.secondary)
    }
}

struct LoginRequiredCard: View {
    @EnvironmentObject private var appModel: AppModel
    let message: String

    var body: some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.string("需要登录"), systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                Button(L10n.string("登录")) { appModel.showingLogin = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(18)
        }
    }
}
