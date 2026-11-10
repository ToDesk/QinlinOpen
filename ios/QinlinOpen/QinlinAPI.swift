import Foundation
import CryptoKit
import CommonCrypto

enum QinlinAPIError: LocalizedError {
    /// 服务端明确返回的失败（带业务 code）。
    case server(String, Int)
    /// 本地解析 / 网络层面的失败。
    case response(String)

    var errorDescription: String? {
        switch self {
        case .server(let message, _): return message
        case .response(let message): return message
        }
    }

    var code: Int {
        if case .server(_, let code) = self { return code }
        return -1
    }
}

/// 亲邻开门协议客户端。逻辑与 Android 端 QinlinApi.kt 一一对应：
/// 同一套签名串、同一个 AES-ECB 手机号加密、同一组请求头。
final class QinlinAPI {
    static let shared = QinlinAPI()

    private let baseURL = "https://mobileapi3.qinlinkeji.com/api"
    private let smsURL = "https://gateway2.qinlinkeji.com/member/sms/sendSecurityCode"

    private let appVersion = "5.2.6"
    private let appVersionCode = "3146"
    private let appChannel = 1
    private let signingSalt = "qiAnlPinP"
    private let hexAESKey = "FBC213C4C7BEEBD2AA4EDBF0F681C41B"
    private let smsAppId = "gbDjIZQSOpCMX49P"
    private let smsAppSecret = "OKFoQ9MmNXQtcyXROo4PnaFkfDPTHuDg"
    private let timeout: TimeInterval = 8

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpAdditionalHeaders = ["User-Agent": "Dart/3.8 (dart:io)"]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private init() {}

    // MARK: - 对外接口

    func sendSecurityCode(phone: String) async throws {
        let timestamp = Self.millisecondTimestamp()
        let nonce = Self.nonce(digits: 4)
        let sign = md5("appid=\(smsAppId)&mobile=\(phone)&nonce=\(nonce)&timestamp=\(timestamp)&version=v2&appsecret=\(smsAppSecret)")
        let body: [String: Any] = ["mobile": phone]
        let headers: [String: String] = [
            "appid": smsAppId,
            "version": "v2",
            "timestamp": "\(timestamp)",
            "nonce": nonce,
            "sign": sign,
        ]
        let response = try await postJSON(url: smsURL, body: body, headers: headers)
        _ = try requireSuccess(response)
    }

    func login(phone: String, securityCode: String) async throws -> LoginSession {
        let encryptedPhone = try encryptPhone(phone)
        let response = try await signedJSONPost(
            endpoint: "app/v1/login",
            sessionId: "",
            fields: [
                "mobile": encryptedPhone,
                "smsCode": securityCode,
                "appChannel": appChannel,
            ]
        )
        let data = try requireSuccess(response)
        guard let sessionId = findString(in: data, keys: ["sessionId", "sessionID", "token"]) else {
            throw QinlinAPIError.response("登录成功，但响应中没有 sessionId")
        }
        let userId = findString(in: data, keys: ["userId", "uid"])
        return LoginSession(sessionId: sessionId, userId: userId)
    }

    func loadDoorKeys(sessionId: String) async throws -> [DoorKey] {
        let communityResponse = try await signedJSONPost(
            endpoint: "app/user/v2/communityInfo",
            sessionId: sessionId,
            fields: ["method": "communityInfo"]
        )
        let communityData = try requireSuccess(communityResponse)

        var communities: [(id: String, name: String)] = []
        for item in objectsContaining(in: communityData, key: "communityId") {
            guard let id = item.stringValue(for: "communityId") else { continue }
            let name = item.firstString(for: ["communityName", "name", "communityShortName", "projectName"]) ?? ""
            if !communities.contains(where: { $0.id == id }) {
                communities.append((id, name))
            }
        }

        var keys: [DoorKey] = []
        for community in communities {
            let response = try await signedMultipartPost(
                endpoint: "app/user/v2/queryUserDoorByCacheNew",
                sessionId: sessionId,
                fields: ["communityId": numericOrString(community.id)]
            )
            let data = try requireSuccess(response)
            for item in objectsContaining(in: data, key: "doorControlId") {
                guard let doorId = item.stringValue(for: "doorControlId") else { continue }
                let doorName = item.firstString(
                    for: ["doorControlName", "doorName", "name", "deviceName", "remarkName"]
                ) ?? "钥匙 \(doorId)"
                let key = DoorKey(
                    communityId: community.id,
                    communityName: item.firstString(for: ["communityName", "projectName"]) ?? community.name,
                    doorControlId: doorId,
                    doorName: doorName
                )
                if !keys.contains(where: { $0.id == key.id }) {
                    keys.append(key)
                }
            }
        }

        keys.sort {
            ($0.communityName, $0.doorName) < ($1.communityName, $1.doorName)
        }
        return keys
    }

    func openDoor(sessionId: String, key: DoorKey) async throws -> String {
        let fields: [String: Any] = [
            "appChannel": appChannel,
            "doorControlId": numericOrString(key.doorControlId),
            "communityId": numericOrString(key.communityId),
        ]
        let signed = signFields(fields, sessionId: sessionId)
        var query: [String: Any] = ["sessionId": sessionId]
        signed.forEach { query[$0.key] = $0.value }
        let response = try await request(
            url: "\(baseURL)/open/doorcontrol/v2/open?\(encodeQuery(query))",
            contentType: "application/json; charset=utf-8",
            body: Data()
        )
        _ = try requireSuccess(response)
        let message = (response["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return message.isEmpty ? "开门请求已发送" : message
    }

    // MARK: - 签名

    private func signedJSONPost(
        endpoint: String,
        sessionId: String,
        fields: [String: Any]
    ) async throws -> [String: Any] {
        let signed = signFields(fields, sessionId: sessionId)
        let body = try JSONSerialization.data(withJSONObject: signed, options: [])
        return try await request(
            url: "\(baseURL)/\(endpoint)?\(encodeQuery(["sessionId": sessionId]))",
            contentType: "application/json; charset=utf-8",
            body: body
        )
    }

    private func signedMultipartPost(
        endpoint: String,
        sessionId: String,
        fields: [String: Any]
    ) async throws -> [String: Any] {
        let signed = signFields(fields, sessionId: sessionId)
        let boundary = "qinlin-open-\(Self.nonce(digits: 12))"
        var body = ""
        for (name, value) in signed.sorted(by: { $0.key < $1.key }) {
            body += "--\(boundary)\r\n"
            body += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            body += "\(stringify(value))\r\n"
        }
        body += "--\(boundary)--\r\n"
        return try await request(
            url: "\(baseURL)/\(endpoint)?\(encodeQuery(["sessionId": sessionId]))",
            contentType: "multipart/form-data; boundary=\(boundary)",
            body: Data(body.utf8)
        )
    }

    private func signFields(_ fields: [String: Any], sessionId: String) -> [String: Any] {
        let timestamp = Self.millisecondTimestamp()
        let nonce = Self.nonce(digits: 5)
        var signValues = fields
        signValues["nonce"] = nonce
        signValues["timestamp"] = timestamp
        signValues["token"] = sessionId
        signValues["version"] = appVersion
        let sign = md5("\(encodeQuery(signValues))&key=\(signingSalt)")

        var output = fields
        output["timestamp"] = timestamp
        output["version"] = appVersion
        output["nonce"] = nonce
        output["sign"] = sign
        return output
    }

    // MARK: - 网络

    private func postJSON(url: String, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        return try await request(
            url: url,
            contentType: "application/json; charset=utf-8",
            body: data,
            extraHeaders: headers
        )
    }

    private func request(
        url: String,
        contentType: String,
        body: Data,
        extraHeaders: [String: String] = [:]
    ) async throws -> [String: Any] {
        guard let target = URL(string: url) else {
            throw QinlinAPIError.response("请求地址无效")
        }
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (key, value) in commonHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let payload: (Data, URLResponse)
        do {
            payload = try await session.data(for: request)
        } catch {
            throw QinlinAPIError.response("网络请求失败：\(error.localizedDescription)")
        }

        let data = payload.0
        let status = (payload.1 as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw QinlinAPIError.response("服务器返回空响应（HTTP \(status)）")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = json as? [String: Any] else {
            throw QinlinAPIError.response("服务器返回了无法解析的内容（HTTP \(status)）")
        }
        return object
    }

    private func commonHeaders() -> [String: String] {
        [
            "openid": DeviceIdentity.openId,
            "qversioncode": appVersionCode,
            "qchannel": "google",
            "qplatform": "0",
            "qvendor": "apple",
        ]
    }

    // MARK: - 响应解析

    private func requireSuccess(_ response: [String: Any]) throws -> Any {
        let success = response["success"] as? Bool ?? false
        let code = (response["code"] as? NSNumber)?.intValue ?? Int.min
        if !success && code != 0 && !(200...299).contains(code) {
            let message = (response["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw QinlinAPIError.server(message.isEmpty ? "请求失败（code=\(code)）" : message, code)
        }
        return normalized(response["data"])
    }

    private func normalized(_ value: Any?) -> Any {
        guard let text = value as? String else { return value ?? (NSNull() as Any) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
           let data = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) {
            return data
        }
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]"),
           let data = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) {
            return data
        }
        return value ?? (NSNull() as Any)
    }

    /// 递归找出所有包含指定字段的对象。
    private func objectsContaining(in root: Any, key: String) -> [[String: Any]] {
        var matches: [[String: Any]] = []
        func visit(_ value: Any?) {
            let node = normalized(value)
            if let dictionary = node as? [String: Any] {
                if let field = dictionary[key], !(field is NSNull) {
                    matches.append(dictionary)
                }
                for (_, child) in dictionary { visit(child) }
            } else if let array = node as? [Any] {
                for child in array { visit(child) }
            }
        }
        visit(root)
        return matches
    }

    /// 深度优先查找第一个命中的字符串字段。
    private func findString(in root: Any, keys: [String]) -> String? {
        var result: String?
        func visit(_ value: Any?) {
            if result != nil { return }
            let node = normalized(value)
            if let dictionary = node as? [String: Any] {
                for key in keys {
                    if let found = dictionary.stringValue(for: key) {
                        result = found
                        return
                    }
                }
                for (_, child) in dictionary { visit(child) }
            } else if let array = node as? [Any] {
                for child in array { visit(child) }
            }
        }
        visit(root)
        return result
    }

    // MARK: - 工具

    private func encodeQuery(_ values: [String: Any]) -> String {
        values.keys.sorted().map { key in
            "\(encodeQueryComponent(key))=\(encodeQueryComponent(stringify(values[key] ?? "")))"
        }.joined(separator: "&")
    }

    /// 与 Java 的 URLEncoder.encode(value, "UTF-8") 保持一致，并把 %3A 还原成冒号。
    private func encodeQueryComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.*")
        var output = ""
        for scalar in value.unicodeScalars {
            if scalar.value == 0x20 {
                output += "+"
            } else if allowed.contains(scalar) {
                output += String(scalar)
            } else {
                for byte in String(scalar).utf8 {
                    output += String(format: "%%%02X", byte)
                }
            }
        }
        return output.replacingOccurrences(of: "%3A", with: ":")
    }

    private func stringify(_ value: Any) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return "\(value)"
    }

    private func numericOrString(_ value: String) -> Any {
        if let number = Int64(value) { return number }
        return value
    }

    private func md5(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    /// AES/ECB/PKCS5Padding，与 Android 端 encryptPhone 一致。
    private func encryptPhone(_ phone: String) throws -> String {
        guard let key = Data(hexString: hexAESKey) else {
            throw QinlinAPIError.response("AES 密钥无效")
        }
        let input = Data(phone.utf8)
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var encryptedLength = 0

        let status = output.withUnsafeMutableBytes { outputBytes -> Int32 in
            input.withUnsafeBytes { inputBytes -> Int32 in
                key.withUnsafeBytes { keyBytes -> Int32 in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count,
                        nil,
                        inputBytes.baseAddress, input.count,
                        outputBytes.baseAddress, outputBytes.count,
                        &encryptedLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw QinlinAPIError.response("手机号加密失败")
        }
        return output.prefix(encryptedLength).map { String(format: "%02X", $0) }.joined()
    }

    private static func millisecondTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func nonce(digits: Int) -> String {
        (0..<digits).map { _ in String(Int.random(in: 0...9)) }.joined()
    }
}

private extension Dictionary where Key == String, Value == Any {
    func stringValue(for key: String) -> String? {
        guard let raw = self[key], !(raw is NSNull) else { return nil }
        let text = (raw as? String) ?? "\(raw)"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty || trimmed == "null") ? nil : trimmed
    }

    func firstString(for keys: [String]) -> String? {
        for key in keys {
            if let value = stringValue(for: key) { return value }
        }
        return nil
    }
}

extension Data {
    init?(hexString: String) {
        let cleaned = hexString.replacingOccurrences(of: " ", with: "")
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
