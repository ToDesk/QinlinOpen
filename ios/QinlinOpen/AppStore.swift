import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var phone = ""
    @Published var securityCode = ""
    @Published private(set) var loggedIn = false
    @Published private(set) var busy = false
    @Published private(set) var doors: [DoorKey] = []
    @Published private(set) var openingDoorId: String?
    @Published private(set) var successfulDoorId: String?
    @Published var toast: String?

    private let api = QinlinAPI.shared
    private let defaults = UserDefaults.standard
    private let configAccount = "config"
    private let orderKey = "doorOrder"
    private var configuration: SavedConfiguration?
    private var toastTask: Task<Void, Never>?
    private var successTask: Task<Void, Never>?

    init() {
        loadConfiguration()
        if configuration != nil {
            Task { await refreshDoors() }
        }
    }

    // MARK: - 登录

    func setPhone(_ value: String) {
        phone = String(value.filter(\.isNumber).prefix(11))
    }

    func setSecurityCode(_ value: String) {
        securityCode = String(value.filter(\.isNumber).prefix(8))
    }

    func sendSecurityCode() async {
        guard isValidPhone(phone) else {
            show("请输入 11 位手机号")
            return
        }
        await runBusy {
            try await api.sendSecurityCode(phone: phone)
            show("验证码已发送")
        }
    }

    func login() async {
        guard isValidPhone(phone), !securityCode.isEmpty else {
            show("请输入手机号和短信验证码")
            return
        }
        await runBusy {
            let session = try await api.login(phone: phone, securityCode: securityCode)
            let config = SavedConfiguration(
                sessionId: session.sessionId,
                userId: session.userId,
                phone: phone
            )
            configuration = config
            persist(config)
            loggedIn = true
            securityCode = ""
            await loadDoors()
            show("登录成功")
        }
    }

    func refreshDoors() async {
        guard configuration != nil, !busy else { return }
        await runBusy { await loadDoors() }
    }

    // MARK: - 开门

    func open(_ key: DoorKey) async {
        guard let config = configuration, !busy else { return }
        busy = true
        openingDoorId = key.id
        successfulDoorId = nil
        defer {
            busy = false
            if openingDoorId == key.id { openingDoorId = nil }
        }
        do {
            _ = try await api.openDoor(sessionId: config.sessionId, key: key)
            show("开门成功")
            successTask?.cancel()
            successfulDoorId = key.id
            successTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if self?.successfulDoorId == key.id { self?.successfulDoorId = nil }
                }
            }
        } catch {
            handle(error)
        }
    }

    // MARK: - 排序

    func move(from source: IndexSet, to destination: Int) {
        doors.move(fromOffsets: source, toOffset: destination)
        persistOrder()
    }

    func moveDoor(from index: Int, to target: Int) {
        guard doors.indices.contains(index), doors.indices.contains(target), index != target else { return }
        let item = doors.remove(at: index)
        doors.insert(item, at: target)
        persistOrder()
    }

    // MARK: - 退出

    func logout() {
        configuration = nil
        Keychain.delete(account: configAccount)
        defaults.removeObject(forKey: orderKey)
        loggedIn = false
        doors = []
        openingDoorId = nil
        successfulDoorId = nil
        securityCode = ""
        show("已退出")
    }

    // MARK: - 内部

    private func loadDoors() async {
        guard let config = configuration else { return }
        do {
            let fetched = try await api.loadDoorKeys(sessionId: config.sessionId)
            doors = ordered(fetched)
            loggedIn = true
            if doors.isEmpty { show("没有可用钥匙") }
        } catch {
            handle(error)
        }
    }

    private func ordered(_ keys: [DoorKey]) -> [DoorKey] {
        let saved = defaults.stringArray(forKey: orderKey) ?? []
        guard !saved.isEmpty else { return keys }
        let rank = Dictionary(uniqueKeysWithValues: saved.enumerated().map { ($1, $0) })
        return keys.sorted { lhs, rhs in
            let left = rank[lhs.id] ?? Int.max
            let right = rank[rhs.id] ?? Int.max
            if left == right { return (lhs.communityName, lhs.doorName) < (rhs.communityName, rhs.doorName) }
            return left < right
        }
    }

    private func persistOrder() {
        defaults.set(doors.map(\.id), forKey: orderKey)
    }

    private func loadConfiguration() {
        guard let data = Keychain.load(account: configAccount),
              let config = try? JSONDecoder().decode(SavedConfiguration.self, from: data) else {
            return
        }
        configuration = config
        phone = config.phone
        loggedIn = true
    }

    private func persist(_ config: SavedConfiguration) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? Keychain.save(data, account: configAccount)
    }

    private func runBusy(_ block: @escaping () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await block()
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        if let apiError = error as? QinlinAPIError, apiError.code == 401 {
            configuration = nil
            Keychain.delete(account: configAccount)
            loggedIn = false
            doors = []
            openingDoorId = nil
            successfulDoorId = nil
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        show(message.isEmpty ? "请求失败" : message)
    }

    private func isValidPhone(_ value: String) -> Bool {
        value.count == 11 && value.first == "1" && value.allSatisfy(\.isNumber)
    }

    private func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.toast = nil }
        }
    }
}
