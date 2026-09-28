import Foundation

struct AdminLock: Codable, Sendable {
    let byMe: Bool
    let byName: String?
    let until: String?
}

struct AdminRejectionReason: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let code: String?
    let title: String
    let content: String?
    let category: String?
    let requiresAnnotation: Bool?
}

struct AdminRejectionReasonsResponse: Codable, Sendable {
    let items: [AdminRejectionReason]
}

struct AdminActionResponse: Codable, Sendable {
    let ok: Bool?
    let seconds: Int?
    let mode: String?
    let status: String?
    let deleted: Bool?
}

struct AdminAppeal: Codable, Identifiable, Sendable {
    struct Handler: Codable, Sendable { let displayName: String }
    struct Appellant: Codable, Sendable {
        let id: Int
        let displayName: String
        let avatar: String?
    }
    struct Photo: Codable, Sendable {
        let title: String
        let domain: String
        let thumb: String?
        let rejectionReason: String?
        let moderator: String?
        let href: String
    }

    let id: Int
    let photoId: Int
    let reason: String
    let status: String
    let handlerReply: String?
    let handler: Handler?
    let createdAt: String?
    let handledAt: String?
    let lock: AdminLock?
    let photo: Photo
    let appellant: Appellant
}

struct AdminAppealsResponse: Codable, Sendable {
    let items: [AdminAppeal]
    let total: Int
    let offset: Int?
    let limit: Int?
    let lockSeconds: Int
}

struct AdminAppealResolveBody: Encodable, Sendable {
    let decision: String
    let reply: String?
}

struct AdminReviewQueueItem: Codable, Identifiable, Sendable {
    struct Uploader: Codable, Sendable {
        let id: Int
        let displayName: String
        let avatar: String?
    }
    struct FirstPass: Codable, Sendable {
        let decision: String
        let reviewer: String?
        let reason: String?
    }

    let id: Int
    let title: String
    let thumb: String?
    let domain: String
    let createdAt: String?
    let uploader: Uploader
    let lock: AdminLock?
    let dupHit: Bool
    let conflict: Bool
    let firstPass: FirstPass?
    let priority: Bool
    let hot: Bool
}

struct AdminReviewQueueResponse: Codable, Sendable {
    let items: [AdminReviewQueueItem]
    let total: Int
    let offset: Int
    let limit: Int
}

struct AdminReviewDetail: Codable, Sendable {
    struct DuplicateMatch: Codable, Sendable {
        struct Target: Codable, Sendable {
            let id: Int
            let title: String
            let status: String
            let thumb: String?
            let uploader: String
            let href: String
        }

        let distance: Int?
        let exact: Bool
        let target: Target?
    }

    struct Uploader: Codable, Sendable {
        struct Stats: Codable, Sendable {
            let total: Int
            let approved: Int
            let rejected: Int
        }
        let id: Int
        let username: String
        let displayName: String
        let avatar: String?
        let joinedAt: String?
        let banned: Bool
        let stats: Stats
    }
    struct History: Codable, Identifiable, Sendable {
        let id: Int
        let stage: String
        let decision: String
        let reason: String?
        let note: String?
        let reasonTitle: String?
        let reviewer: String?
        let createdAt: String?
    }

    let id: Int
    let title: String
    let description: String?
    let status: String
    let domain: String
    let createdAt: String?
    let image: String?
    let thumb: String?
    let canViewOriginal: Bool
    let originalUrl: String?
    let fileSize: Int?
    let photoType: String?
    let category: String?
    let hot: Bool
    let hotReason: String?
    let rejectionReason: String?
    let moderatorMessage: String?
    let lock: AdminLock?
    let lockSeconds: Int
    let firstPass: AdminReviewQueueItem.FirstPass?
    let canFinalize: Bool
    let canFirstPass: Bool
    let canEscalate: Bool
    let canDelete: Bool
    let inConflict: Bool
    let canResolveConflict: Bool
    let uploader: Uploader
    let hashed: Bool
    let dup: DuplicateMatch?
    let history: [History]
    let reviewAnnotations: [AdminReviewAnnotation]?
}

struct AdminReviewAnnotation: Codable, Identifiable, Hashable, Sendable {
    enum Tool: String, Codable, CaseIterable, Sendable {
        case ellipse, rect, path, arrow
    }
    struct Point: Codable, Hashable, Sendable {
        let x: Double
        let y: Double
    }
    struct Geometry: Codable, Hashable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    let id: String
    let tool: Tool
    let reasonId: Int?
    let reasonText: String
    let color: String
    let strokeWidth: Double
    let geometry: Geometry?
    let points: [Point]?
}

struct AdminReviewNoteBody: Encodable, Sendable { let note: String? }

struct AdminReviewRejectBody: Encodable, Sendable {
    let rejectionReasonId: Int?
    let rejectionReasonIds: [Int]
    let reason: String?
    let note: String?
    let annotations: [AdminReviewAnnotation]

    enum CodingKeys: String, CodingKey {
        case rejectionReasonId = "rejection_reason_id"
        case rejectionReasonIds = "rejection_reason_ids"
        case reason, note, annotations
    }
}
