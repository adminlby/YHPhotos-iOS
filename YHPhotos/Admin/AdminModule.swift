import Foundation

enum AdminSection: String, CaseIterable, Identifiable, Sendable {
    case overview = "总览"
    case review = "审核"
    case governance = "治理"
    case support = "支持"
    case aviation = "航空情报"
    case operations = "运营"
    case system = "安全与系统"
    case developer = "开发者与高级工具"

    var id: String { rawValue }
}

/// The canonical native copy of the website administration information
/// architecture. Keep paths and permission arrays aligned with AdminLayout.tsx.
enum AdminModule: String, CaseIterable, Identifiable, Hashable, Sendable {
    case dashboard
    case reviewCenter
    case appeals
    case rejectionReasons
    case reports
    case users
    case content
    case bounties
    case revisions
    case featured
    case groups
    case groupPolicy
    case priority
    case tickets
    case feedback
    case requests
    case forecast
    case reference
    case photoTypes
    case ruleDocuments
    case announcements
    case news
    case ranking
    case jury
    case badges
    case risk
    case team
    case quota
    case settings
    case rbac
    case audit
    case faultInjection
    case juryScheduler
    case priorityGrant
    case badgeEngine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "仪表盘"
        case .reviewCenter: "审核中心"
        case .appeals: "申诉处理"
        case .rejectionReasons: "驳回理由"
        case .reports: "举报"
        case .users: "用户"
        case .content: "内容"
        case .bounties: "悬赏管理"
        case .revisions: "修正版审计"
        case .featured: "精选"
        case .groups: "小组"
        case .groupPolicy: "小组创建条件"
        case .priority: "优先队列"
        case .tickets: "工单"
        case .feedback: "反馈"
        case .requests: "纠错与授权"
        case .forecast: "好货预报"
        case .reference: "字典库"
        case .photoTypes: "上传类型"
        case .ruleDocuments: "规则文档"
        case .announcements: "公告"
        case .news: "资讯"
        case .ranking: "赛事排行"
        case .jury: "评审团"
        case .badges: "徽章"
        case .risk: "风控"
        case .team: "团队与合作商"
        case .quota: "配额管理"
        case .settings: "站点设置"
        case .rbac: "权限管理"
        case .audit: "审计日志"
        case .faultInjection: "故障注入"
        case .juryScheduler: "评审团调度"
        case .priorityGrant: "优先额度授予"
        case .badgeEngine: "徽章引擎"
        }
    }

    var section: AdminSection {
        switch self {
        case .dashboard: .overview
        case .reviewCenter, .appeals, .rejectionReasons: .review
        case .reports, .users, .content, .bounties, .revisions, .featured, .groups, .groupPolicy, .priority: .governance
        case .tickets, .feedback, .requests: .support
        case .forecast: .aviation
        case .reference, .photoTypes, .ruleDocuments, .announcements, .news, .ranking, .jury, .badges: .operations
        case .risk, .team, .quota, .settings, .rbac, .audit: .system
        case .faultInjection, .juryScheduler, .priorityGrant, .badgeEngine: .developer
        }
    }

    var path: String {
        switch self {
        case .dashboard: "/admin"
        case .reviewCenter: "/admin/review"
        case .appeals: "/admin/appeals"
        case .rejectionReasons: "/admin/reasons"
        case .reports: "/admin/reports"
        case .users: "/admin/users"
        case .content: "/admin/content"
        case .bounties: "/admin/bounties"
        case .revisions: "/admin/revisions"
        case .featured: "/admin/featured"
        case .groups: "/admin/groups"
        case .groupPolicy: "/admin/group-policy"
        case .priority: "/admin/priority"
        case .tickets: "/admin/tickets"
        case .feedback: "/admin/feedback"
        case .requests: "/admin/requests"
        case .forecast: "/admin/forecast"
        case .reference: "/admin/reference"
        case .photoTypes: "/admin/photo-types"
        case .ruleDocuments: "/admin/rule-documents"
        case .announcements: "/admin/announcements"
        case .news: "/admin/news"
        case .ranking: "/admin/ranking"
        case .jury: "/admin/jury"
        case .badges: "/admin/badges"
        case .risk: "/admin/risk"
        case .team: "/admin/team"
        case .quota: "/admin/quota"
        case .settings: "/admin/settings"
        case .rbac: "/admin/rbac"
        case .audit: "/admin/audit"
        case .faultInjection: "/admin/dev/fault-injection"
        case .juryScheduler: "/admin/dev/jury"
        case .priorityGrant: "/admin/dev/priority"
        case .badgeEngine: "/admin/dev/badges"
        }
    }

    var permissions: [String] {
        switch self {
        case .dashboard: ["admin.access"]
        case .reviewCenter: ["review.queue.view"]
        case .appeals: ["review.appeal"]
        case .rejectionReasons: ["review.reason.manage"]
        case .reports: ["report.photo.handle", "report.user.handle"]
        case .users: ["user.view"]
        case .content: ["content.photo.edit", "content.photo.delete", "content.photo.feature", "content.comment.moderate", "content.collection.manage", "content.tag.manage"]
        case .bounties: ["content.bounty.manage"]
        case .revisions: ["revision.audit.view"]
        case .featured: ["content.photo.feature"]
        case .groups: ["group.manage", "group.post.moderate"]
        case .groupPolicy: ["group.policy.manage"]
        case .priority: ["priority.application.handle"]
        case .tickets: ["ticket.handle"]
        case .feedback: ["feedback.handle"]
        case .requests: ["correction.handle", "license.handle"]
        case .forecast: ["forecast.settings.view", "forecast.cache.view"]
        case .reference: ["reference.manage"]
        case .photoTypes: ["photo_type.manage"]
        case .ruleDocuments: ["rules.document.manage"]
        case .announcements: ["announcement.manage"]
        case .news: ["news.manage"]
        case .ranking: ["ranking.manage"]
        case .jury: ["jury.manage"]
        case .badges: ["badge.manage"]
        case .risk: ["risk.keyword.manage", "risk.ip.manage", "risk.monitor.view"]
        case .team: ["team.manage"]
        case .quota: ["system.quota.rules"]
        case .settings: [
            "system.settings", "system.watermark", "system.warning.rules", "system.email.view",
            "system.apikey.view", "system.apikey.create", "system.apikey.edit",
            "system.apikey.whitelist", "system.apikey.enable", "system.apikey.disable",
            "system.apikey.ban", "system.apikey.rotate", "system.apikey.logs",
            "system.apikey.delete", "system.apikey.applications", "system.apikey.manage",
        ]
        case .rbac: ["rbac.manage"]
        case .audit: ["audit.view.own", "audit.view.all"]
        case .faultInjection: ["system.fault_injection"]
        case .juryScheduler, .priorityGrant, .badgeEngine: ["system.devtools"]
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .reviewCenter: "checklist"
        case .appeals: "scale.3d"
        case .rejectionReasons: "nosign"
        case .reports: "flag.fill"
        case .users: "person.crop.circle"
        case .content: "photo.on.rectangle.angled"
        case .bounties: "gift.fill"
        case .revisions: "clock.arrow.circlepath"
        case .featured: "star.fill"
        case .groups: "person.3.fill"
        case .groupPolicy: "slider.horizontal.3"
        case .priority: "bolt.fill"
        case .tickets: "lifepreserver.fill"
        case .feedback: "bubble.left.and.bubble.right.fill"
        case .requests: "doc.text.fill"
        case .forecast: "airplane.departure"
        case .reference: "books.vertical.fill"
        case .photoTypes: "tag.fill"
        case .ruleDocuments: "doc.richtext.fill"
        case .announcements: "megaphone.fill"
        case .news: "newspaper.fill"
        case .ranking: "trophy.fill"
        case .jury: "checkmark.seal.fill"
        case .badges: "medal.fill"
        case .risk: "shield.lefthalf.filled.trianglebadge.exclamationmark"
        case .team: "person.text.rectangle.fill"
        case .quota: "chart.bar.fill"
        case .settings: "gearshape.fill"
        case .rbac: "lock.shield.fill"
        case .audit: "clock.badge.checkmark.fill"
        case .faultInjection: "ladybug.fill"
        case .juryScheduler: "waveform.path.ecg"
        case .priorityGrant: "hand.raised.fingers.spread.fill"
        case .badgeEngine: "engine.combustion.fill"
        }
    }

    func isAllowed(for identity: AdminIdentity) -> Bool {
        identity.can(anyOf: permissions)
    }

}
