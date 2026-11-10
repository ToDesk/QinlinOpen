import SwiftUI

@main
struct QinlinOpenApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var store = AppStore()

    var body: some View {
        NavigationStack {
            Group {
                if store.loggedIn {
                    DoorListView(store: store)
                } else {
                    LoginView(store: store)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("QinlinOpen")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                if let toast = store.toast {
                    ToastView(text: toast)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.toast)
        }
        .tint(Theme.accent)
    }
}

enum Theme {
    static let accent = Color(red: 0.09, green: 0.45, blue: 0.42)
    static let card = Color(.secondarySystemGroupedBackground)
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(.black.opacity(0.82), in: Capsule())
    }
}

// MARK: - 登录页

struct LoginView: View {
    @ObservedObject var store: AppStore
    @State private var countdown = 0
    @State private var timer: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                field(
                    title: "手机号",
                    placeholder: "11 位手机号",
                    keyboard: .phonePad,
                    contentType: .telephoneNumber,
                    text: Binding(
                        get: { store.phone },
                        set: { store.setPhone($0) }
                    )
                )

                HStack(spacing: 10) {
                    field(
                        title: "短信验证码",
                        placeholder: "6 位验证码",
                        keyboard: .numberPad,
                        contentType: .oneTimeCode,
                        text: Binding(
                            get: { store.securityCode },
                            set: { store.setSecurityCode($0) }
                        )
                    )

                    Button {
                        sendCode()
                    } label: {
                        Text(countdown > 0 ? "\(countdown)s" : "发送")
                            .font(.subheadline.weight(.medium))
                            .frame(width: 72, height: 46)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.busy || countdown > 0)
                }

                Button {
                    Task { await store.login() }
                } label: {
                    HStack {
                        if store.busy { ProgressView().tint(.white) }
                        Text(store.busy ? "请稍候" : "登录并读取钥匙")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.busy)

                Text("登录令牌只保存在本机 Keychain，退出登录会立即清除。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("登录")
                .font(.title2.weight(.semibold))
            Text("使用亲邻账号的手机号 + 短信验证码登录，随后拉取账号下的全部门禁钥匙。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private func field(
        title: String,
        placeholder: String,
        keyboard: UIKeyboardType,
        contentType: UITextContentType?,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .disabled(store.busy)
        }
    }

    private func sendCode() {
        Task { await store.sendSecurityCode() }
        countdown = 60
        timer?.cancel()
        timer = Task {
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
            }
        }
    }
}
