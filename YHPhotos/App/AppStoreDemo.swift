#if DEBUG
import Foundation
import SwiftUI

/// Deterministic, offline-friendly data used only while capturing App Store media.
/// Enable it with the `-AppStoreDemo` launch argument.
enum AppStoreDemo {
    enum Screen: String {
        case discover
        case aviation
        case photo
        case map
        case tools
        case inspector
    }

    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-AppStoreDemo")

    static var screen: Screen {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-AppStoreScreen"),
              arguments.indices.contains(index + 1),
              let screen = Screen(rawValue: arguments[index + 1]) else {
            return .discover
        }
        return screen
    }

    static let sessionUser = SessionUser(
        id: 88,
        username: "skyfan",
        displayName: "SkyFan",
        avatarFilename: nil,
        avatar: nil,
        role: "user",
        legal: nil
    )

    private static func localized(_ simplified: String, _ traditional: String, _ english: String) -> String {
        let arguments = ProcessInfo.processInfo.arguments
        let overrideLanguage: String? = if let index = arguments.firstIndex(of: "-AppStoreDemoLanguage"), arguments.indices.contains(index + 1) {
            arguments[index + 1]
        } else {
            nil
        }
        let language = (overrideLanguage ?? Locale.preferredLanguages.first ?? "zh-hans").lowercased()
        if language.hasPrefix("en") { return english }
        if language.hasPrefix("zh-hant") || language.hasPrefix("zh-hk") || language.hasPrefix("zh-tw") || language.hasPrefix("zh-mo") {
            return traditional
        }
        return simplified
    }

    static func responseData(path: String, query: [URLQueryItem]) throws -> Data? {
        switch path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
        case "api/photos/featured":
            return try encode(Array(photos.prefix(3)))
        case "api/photos":
            return try encode(photos)
        case "api/stats":
            return try encode([
                "pendingPhotos": 27,
                "totalUsers": 12_846,
                "totalPhotos": 48_692,
                "totalLikes": 286_420,
                "todayPhotos": 126,
                "todayUsers": 38,
                "todayPending": 9,
                "onlineModerators": [
                    ["id": 3, "displayName": "AeroLens", "avatar": NSNull(), "role": "moderator", "lastActive": "2026-09-29T09:40:00Z"]
                ]
            ])
        case "api/map/airports":
            return try encode(airports)
        case "api/photos/1":
            return try encode(photoDetail)
        default:
            return nil
        }
    }

    private static let imageBaseURL = "http://127.0.0.1:8765"
    static let sampleImageURL = URL(string: "\(imageBaseURL)/sample-b-hyq.jpg")!

    private static let photos: [[String: Any]] = [
        photo(
            id: 1,
            title: localized("夜幕下的 B-HYQ", "夜幕下的 B-HYQ", "Cathay Pacific A330 at blue hour"),
            image: "sample-b-hyq.jpg",
            author: "SkyFan",
            aircraftType: "Airbus A330-343",
            registration: "B-HYQ",
            operatorName: localized("国泰航空", "國泰航空", "Cathay Pacific"),
            airport: localized("香港国际机场", "香港國際機場", "Hong Kong International Airport"),
            views: 12_840,
            likes: 328,
            comments: 24,
            featured: true
        ),
        photo(
            id: 2,
            title: localized("晴空中的 B-6942", "晴空中的 B-6942", "B-6942 under clear skies"),
            image: "sample-b-6942.jpg",
            author: "AeroLens",
            aircraftType: "Airbus A321-213",
            registration: "B-6942",
            operatorName: localized("中国国际航空", "中國國際航空", "Air China"),
            airport: localized("北京首都国际机场", "北京首都國際機場", "Beijing Capital International Airport"),
            views: 8_630,
            likes: 286,
            comments: 18,
            featured: false
        ),
        photo(
            id: 3,
            title: localized("星空联盟涂装离港", "星空聯盟塗裝離港", "Star Alliance departure"),
            image: "sample-c-gock.jpg",
            author: "CloudChaser",
            aircraftType: "Airbus A330-343",
            registration: "C-GOCK",
            operatorName: localized("加拿大航空", "加拿大航空", "Air Canada"),
            airport: localized("多伦多皮尔逊国际机场", "多倫多皮爾遜國際機場", "Toronto Pearson International Airport"),
            views: 7_420,
            likes: 194,
            comments: 11,
            featured: true
        ),
        photo(
            id: 4,
            title: localized("蓝天下的经典窄体客机", "藍天下的經典窄體客機", "A classic narrow-body under blue skies"),
            image: "sample-b-6942.jpg",
            author: "Runway27",
            aircraftType: "Airbus A321-213",
            registration: "B-6942",
            operatorName: localized("中国国际航空", "中國國際航空", "Air China"),
            airport: localized("上海虹桥国际机场", "上海虹橋國際機場", "Shanghai Hongqiao International Airport"),
            views: 6_810,
            likes: 173,
            comments: 9,
            featured: false
        ),
        photo(
            id: 5,
            title: localized("晨光中的星盟 A330", "晨光中的星盟 A330", "Star Alliance A330 in morning light"),
            image: "sample-c-gock.jpg",
            author: "WingView",
            aircraftType: "Airbus A330-343",
            registration: "C-GOCK",
            operatorName: localized("加拿大航空", "加拿大航空", "Air Canada"),
            airport: localized("温哥华国际机场", "溫哥華國際機場", "Vancouver International Airport"),
            views: 5_990,
            likes: 162,
            comments: 7,
            featured: false
        ),
        photo(
            id: 6,
            title: localized("夜航准备", "夜航準備", "Ready for a night flight"),
            image: "sample-b-hyq.jpg",
            author: "NightSpotter",
            aircraftType: "Airbus A330-343",
            registration: "B-HYQ",
            operatorName: localized("国泰航空", "國泰航空", "Cathay Pacific"),
            airport: localized("香港国际机场", "香港國際機場", "Hong Kong International Airport"),
            views: 5_420,
            likes: 151,
            comments: 6,
            featured: false
        )
    ]

    private static func photo(
        id: Int,
        title: String,
        image: String,
        author: String,
        aircraftType: String,
        registration: String,
        operatorName: String,
        airport: String,
        views: Int,
        likes: Int,
        comments: Int,
        featured: Bool
    ) -> [String: Any] {
        let imageURL = "\(imageBaseURL)/\(image)"
        return [
            "id": id,
            "title": title,
            "image": imageURL,
            "thumb": imageURL,
            "publicUrl": imageURL,
            "pageUrl": "https://www.yhphotos.top/photos/\(id)",
            "domain": "aviation",
            "author": ["id": 80 + id, "displayName": author, "avatar": NSNull(), "role": "user"],
            "aircraftType": aircraftType,
            "registration": registration,
            "operator": operatorName,
            "airport": airport,
            "trainNumber": NSNull(),
            "trainModel": NSNull(),
            "bureau": NSNull(),
            "station": NSNull(),
            "simPlatform": NSNull(),
            "livery": NSNull(),
            "views": views,
            "likes": likes,
            "comments": comments,
            "featured": featured,
            "hot": featured,
            "hotReason": featured ? localized("编辑精选", "編輯精選", "Editors’ Choice") : NSNull(),
            "createdAt": "2026-09-28T12:00:00Z"
        ]
    }

    private static let airports: [[String: Any]] = [
        ["id": 1, "name": localized("香港国际机场", "香港國際機場", "Hong Kong International Airport"), "nameEn": "Hong Kong International Airport", "city": "香港", "iata": "HKG", "icao": "VHHH", "lat": 22.3080, "lng": 113.9185, "count": 428],
        ["id": 2, "name": localized("广州白云国际机场", "廣州白雲國際機場", "Guangzhou Baiyun International Airport"), "nameEn": "Guangzhou Baiyun International Airport", "city": localized("广州", "廣州", "Guangzhou"), "iata": "CAN", "icao": "ZGGG", "lat": 23.3924, "lng": 113.2988, "count": 186],
        ["id": 3, "name": localized("深圳宝安国际机场", "深圳寶安國際機場", "Shenzhen Bao'an International Airport"), "nameEn": "Shenzhen Bao'an International Airport", "city": localized("深圳", "深圳", "Shenzhen"), "iata": "SZX", "icao": "ZGSZ", "lat": 22.6393, "lng": 113.8107, "count": 96],
        ["id": 4, "name": localized("澳门国际机场", "澳門國際機場", "Macau International Airport"), "nameEn": "Macau International Airport", "city": localized("澳门", "澳門", "Macau"), "iata": "MFM", "icao": "VMMC", "lat": 22.1496, "lng": 113.5915, "count": 52],
        ["id": 5, "name": localized("珠海金湾机场", "珠海金灣機場", "Zhuhai Jinwan Airport"), "nameEn": "Zhuhai Jinwan Airport", "city": localized("珠海", "珠海", "Zhuhai"), "iata": "ZUH", "icao": "ZGSD", "lat": 22.0064, "lng": 113.3760, "count": 44]
    ]

    private static let photoDetail: [String: Any] = [
        "id": 1,
        "title": localized("夜幕下的 B-HYQ", "夜幕下的 B-HYQ", "Cathay Pacific A330 at blue hour"),
        "description": localized("蓝色时刻的香港机场，前景 A330 正在滑向跑道。", "藍色時刻的香港機場，前景 A330 正在滑向跑道。", "Blue hour at Hong Kong airport as an A330 taxis toward the runway."),
        "image": "\(imageBaseURL)/sample-b-hyq.jpg",
        "domain": "aviation",
        "author": ["id": 88, "displayName": "SkyFan", "avatar": NSNull(), "role": "user"],
        "aviation": ["registration": "B-HYQ", "aircraftType": "Airbus A330-343", "operator": localized("国泰航空", "國泰航空", "Cathay Pacific"), "airport": localized("香港国际机场", "香港國際機場", "Hong Kong International Airport"), "airportCode": "HKG"],
        "railway": ["trainNumber": NSNull(), "trainModel": NSNull(), "locomotiveNumber": NSNull(), "depot": NSNull(), "line": NSNull(), "station": NSNull()],
        "sim": ["platform": NSNull(), "addon": NSNull(), "livery": NSNull()],
        "shotAt": "2026-09-21",
        "views": 12_840,
        "likes": 328,
        "comments": 24,
        "liked": false,
        "favorited": true,
        "entities": ["aircraftType": 12, "airline": 18, "airport": 1, "registration": 314, "trainModel": NSNull(), "bureau": NSNull(), "line": NSNull(), "station": NSNull()]
    ]

    private static func encode(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

#endif
