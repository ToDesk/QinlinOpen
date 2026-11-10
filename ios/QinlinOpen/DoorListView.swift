import SwiftUI

struct DoorListView: View {
    @ObservedObject var store: AppStore
    @State private var editMode: EditMode = .inactive
    @State private var confirmLogout = false

    var body: some View {
        List {
            Section {
                if store.doors.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(store.doors) { key in
                        Button {
                            guard editMode == .inactive else { return }
                            Task { await store.open(key) }
                        } label: {
                            DoorRow(
                                key: key,
                                state: rowState(for: key),
                                busy: store.busy
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            Button("开门") { Task { await store.open(key) } }
                            Button("上移") { moveUp(key) }
                            Button("下移") { moveDown(key) }
                        }
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
            } header: {
                HStack {
                    Text("钥匙 · \(store.doors.count)")
                    Spacer()
                    if store.busy { ProgressView().controlSize(.mini) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .refreshable { await store.refreshDoors() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode == .active ? "完成" : "排序") {
                    withAnimation {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
                .disabled(store.doors.isEmpty)
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("刷新钥匙") { Task { await store.refreshDoors() } }
                    Button("退出登录", role: .destructive) { confirmLogout = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("退出登录后需要重新验证手机号。", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { store.logout() }
            Button("取消", role: .cancel) {}
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.slash")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("没有可用钥匙")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("重新读取") { Task { await store.refreshDoors() } }
                .buttonStyle(.bordered)
                .disabled(store.busy)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func rowState(for key: DoorKey) -> DoorRow.State {
        if store.openingDoorId == key.id { return .opening }
        if store.successfulDoorId == key.id { return .success }
        return .idle
    }

    private func moveUp(_ key: DoorKey) {
        guard let index = store.doors.firstIndex(of: key), index > 0 else { return }
        store.moveDoor(from: index, to: index - 1)
    }

    private func moveDown(_ key: DoorKey) {
        guard let index = store.doors.firstIndex(of: key), index < store.doors.count - 1 else { return }
        store.moveDoor(from: index, to: index + 1)
    }
}

struct DoorRow: View {
    enum State: Equatable {
        case idle, opening, success
    }

    let key: DoorKey
    let state: State
    let busy: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconBackground)
                Image(systemName: state == .success ? "checkmark" : "door.left.hand.open")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(key.doorName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(key.communityName.isEmpty ? "点击卡片开门" : key.communityName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            switch state {
            case .opening:
                ProgressView()
            case .success:
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.accent)
            case .idle:
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(busy && state == .idle ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var iconBackground: Color {
        switch state {
        case .success: return Theme.accent
        case .opening: return Color(red: 0.36, green: 0.38, blue: 0.44)
        case .idle: return Color(red: 0.16, green: 0.20, blue: 0.24)
        }
    }
}
