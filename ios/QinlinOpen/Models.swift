import Foundation

/// 一把门禁钥匙，对应 Android 端的 DoorKey。
struct DoorKey: Identifiable, Hashable, Codable {
    let communityId: String
    let communityName: String
    let doorControlId: String
    let doorName: String

    var id: String { "\(communityId):\(doorControlId)" }

    var displayName: String {
        communityName.isEmpty ? doorName : "\(communityName) \(doorName)"
    }
}

struct LoginSession {
    let sessionId: String
    let userId: String?
}

/// 保存在 Keychain 里的登录配置。
struct SavedConfiguration: Codable {
    var sessionId: String
    var userId: String?
    var phone: String
}
