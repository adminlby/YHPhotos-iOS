import Foundation

enum PhotoDomain: String, Codable, CaseIterable, Identifiable, Sendable {
    case aviation
    case railway
    case flightSim = "flight_sim"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .aviation: L10n.string("航空")
        case .railway: L10n.string("铁路")
        case .flightSim: L10n.string("模拟飞行")
        }
    }
    var icon: String {
        switch self {
        case .aviation: "airplane"
        case .railway: "tram.fill"
        case .flightSim: "gamecontroller.fill"
        }
    }
}

struct PhotoAuthor: Codable, Hashable, Sendable {
    let id: Int
    let displayName: String
    let avatar: String?
    let role: String?
}

struct Photo: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let image: String
    let thumb: String?
    let publicUrl: String?
    let pageUrl: String?
    let domain: PhotoDomain
    let author: PhotoAuthor
    let aircraftType: String?
    let registration: String?
    let `operator`: String?
    let airport: String?
    let trainNumber: String?
    let trainModel: String?
    let bureau: String?
    let station: String?
    let simPlatform: String?
    let livery: String?
    let views: Int
    let likes: Int
    let comments: Int
    let featured: Bool?
    let hot: Bool?
    let hotReason: String?
    let createdAt: String

    var imageURL: URL? { URL(string: image) }
    var thumbnailURL: URL? { URL(string: thumb ?? image) }

    var primaryMetadata: String {
        switch domain {
        case .aviation:
            [self.operator, aircraftType].compactMap { $0 }.joined(separator: " · ")
        case .railway:
            [bureau, trainModel].compactMap { $0 }.joined(separator: " · ")
        case .flightSim:
            [simPlatform, aircraftType].compactMap { $0 }.joined(separator: " · ")
        }
    }

    var secondaryMetadata: String {
        switch domain {
        case .aviation:
            [registration, airport].compactMap { $0 }.joined(separator: " · ")
        case .railway:
            [trainNumber, station].compactMap { $0 }.joined(separator: " · ")
        case .flightSim:
            [livery].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

struct CommunityStats: Codable, Sendable {
    let pendingPhotos: Int
    let totalUsers: Int
    let totalPhotos: Int
    let totalLikes: Int
    let todayPhotos: Int
    let todayUsers: Int
    let todayPending: Int
    let onlineModerators: [OnlineModerator]
}

struct OnlineModerator: Codable, Identifiable, Sendable {
    let id: Int
    let displayName: String
    let avatar: String?
    let role: String
    let lastActive: String?
}

struct MapAirport: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let nameEn: String?
    let city: String?
    let iata: String?
    let icao: String?
    let lat: Double
    let lng: Double
    let count: Int
}

struct PublicProfile: Codable, Identifiable, Sendable {
    struct Statistics: Codable, Sendable {
        let approvedPhotos: Int
        let totalViews: Int
        let totalLikes: Int
        let followers: Int
        let following: Int
    }

    let id: Int
    let username: String
    let displayName: String
    let avatar: String?
    let role: String
    let bio: String?
    let createdAt: String?
    let stats: Statistics
    let isFollowing: Bool
    let isBlocked: Bool
    let isSelf: Bool
}

struct UserBadge: Codable, Identifiable, Sendable {
    let code: String
    let name: String
    let description: String?
    let icon: String?
    let category: String?
    let count: Int?
    let awardedAt: String?
    var id: String { code }
}

struct PublicSpottingSummary: Codable, Sendable {
    let aviation: [SpottingCard]
    let railway: [SpottingCard]
}

struct SpottingCard: Codable, Identifiable, Sendable {
    let kind: String
    let label: String
    let got: Int
    let total: Int?
    var id: String { kind }
}

struct MeOverview: Codable, Sendable {
    struct Profile: Codable, Sendable {
        let id: Int
        let username: String
        let email: String
        let displayName: String
        let avatar: String?
        let role: String
        let bio: String?
        let createdAt: String?
    }
    struct Counts: Codable, Sendable {
        let total: Int
        let pending: Int
        let approved: Int
        let rejected: Int
        let appealing: Int
    }
    struct Totals: Codable, Sendable {
        let views: Int
        let likes: Int
    }

    let profile: Profile
    let counts: Counts
    let totals: Totals
}

struct MyPhoto: Codable, Identifiable, Sendable {
    struct GroupInfo: Codable, Sendable { let id: Int; let name: String }
    struct AppealInfo: Codable, Sendable {
        let id: Int
        let status: String
        let reason: String?
        let reply: String?
    }
    let id: Int
    let title: String
    let status: String
    let domain: PhotoDomain
    let thumb: String?
    let image: String?
    let views: Int
    let likes: Int
    let comments: Int
    let rejectionReason: String?
    let secondRejection: String?
    let moderatorMessage: String?
    let hasRevisions: Bool?
    let hasReviewAnnotations: Bool?
    let group: GroupInfo?
    let canAppeal: Bool?
    let appeal: AppealInfo?
    let createdAt: String?
    let approvedAt: String?
}

struct SessionUser: Codable, Identifiable, Sendable {
    let id: Int
    let username: String
    let displayName: String
    let avatarFilename: String?
    let role: String

    enum CodingKeys: String, CodingKey {
        case id, username, role
        case displayName = "display_name"
        case avatarFilename = "avatar_filename"
    }
}

struct SessionEnvelope: Codable, Sendable { let user: SessionUser }

struct PublicSettings: Codable, Sendable {
    let ssoEnabled: Bool
    let ssoConfigured: Bool
    let ssoAccountURL: String?

    enum CodingKeys: String, CodingKey {
        case ssoEnabled = "sso_enabled"
        case ssoConfigured = "sso_configured"
        case ssoAccountURL = "sso_account_url"
    }
}

struct LoginResponse: Codable, Sendable {
    let user: SessionUser?
    let twoFactor: Bool?
    let challenge: String?
    let methods: [String]?
    let remember: Bool?
}

struct PhotoDetail: Codable, Identifiable, Sendable {
    struct Aviation: Codable, Sendable {
        let registration: String?
        let aircraftType: String?
        let `operator`: String?
        let airport: String?
        let airportCode: String?
    }
    struct Railway: Codable, Sendable {
        let trainNumber: String?
        let trainModel: String?
        let locomotiveNumber: String?
        let depot: String?
        let line: String?
        let station: String?
    }
    struct Simulation: Codable, Sendable {
        let platform: String?
        let addon: String?
        let livery: String?
    }
    struct Entities: Codable, Sendable {
        let aircraftType: Int?
        let airline: Int?
        let airport: Int?
        let registration: Int?
        let trainModel: Int?
        let bureau: Int?
        let line: Int?
        let station: Int?
    }

    let id: Int
    let title: String
    let description: String?
    let image: String
    let domain: PhotoDomain
    let author: PhotoAuthor
    let aviation: Aviation
    let railway: Railway
    let sim: Simulation
    let shotAt: String?
    let views: Int
    let likes: Int
    let comments: Int
    let liked: Bool
    let favorited: Bool
    let entities: Entities?
}

struct EntityGallery: Codable, Sendable {
    struct Metadata: Codable, Identifiable, Sendable {
        let label: String
        let value: String
        var id: String { "\(label)-\(value)" }
    }

    let kind: String
    let id: Int
    let title: String
    let subtitle: String?
    let meta: [Metadata]
    let photos: [Photo]
}

struct Conversation: Codable, Identifiable, Sendable {
    struct OtherUser: Codable, Sendable {
        let id: Int
        let displayName: String
        let avatar: String?
    }
    let id: Int
    let other: OtherUser
    let lastMessage: String?
    let lastMessageMine: Bool
    let lastMessageAt: String?
    let unread: Int
}

struct SiteNotification: Codable, Identifiable, Sendable {
    let id: Int
    let type: String
    let title: String?
    let content: String?
    let link: String?
    var isRead: Bool
    let createdAt: String?
}

struct SiteNotificationResponse: Codable, Sendable {
    let unread: Int
    let total: Int?
    let items: [SiteNotification]
}

struct LikeResponse: Codable, Sendable {
    let liked: Bool
    let likes: Int
}

struct FollowResponse: Codable, Sendable {
    let following: Bool
    let followers: Int
}
