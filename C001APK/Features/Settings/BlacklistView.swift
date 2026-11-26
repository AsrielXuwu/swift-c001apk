import SwiftUI

public struct BlacklistView: View {
    public let isTopic: Bool

    @Environment(AppState.self) private var appState
    @State private var newEntry = ""

    public init(isTopic: Bool) { self.isTopic = isTopic }

    public var body: some View {
        List {
            Section(isTopic ? "添加屏蔽话题" : "添加屏蔽用户 UID") {
                HStack {
                    TextField(isTopic ? "输入话题名称" : "输入用户 UID", text: $newEntry)
                        .autocorrectionDisabled()
                    Button("添加") {
                        let trimmed = newEntry.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        if isTopic {
                            appState.blacklist.addTopic(trimmed)
                        } else if !appState.blacklist.isUserBlocked(trimmed) {
                            appState.blacklist.toggleUser(trimmed)
                        }
                        newEntry = ""
                    }
                    .disabled(newEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section(isTopic ? "已屏蔽话题" : "已屏蔽用户") {
                let items = isTopic ? appState.blacklist.blockedTopics : appState.blacklist.blockedUsers
                if items.isEmpty {
                    Text("暂无记录").foregroundStyle(.secondary)
                } else {
                    ForEach(items, id: \.self) { item in
                        HStack {
                            if isTopic {
                                Text("#\(item)#")
                            } else {
                                Button {
                                    appState.push(.user(uid: item))
                                } label: {
                                    Text("UID: \(item)")
                                }
                            }
                            Spacer()
                        }
                        .swipeActions {
                            Button("移出", role: .destructive) {
                                if isTopic {
                                    appState.blacklist.removeTopic(item)
                                } else {
                                    appState.blacklist.toggleUser(item)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isTopic ? "话题黑名单" : "用户黑名单")
        .navigationBarTitleDisplayMode(.inline)
    }
}
