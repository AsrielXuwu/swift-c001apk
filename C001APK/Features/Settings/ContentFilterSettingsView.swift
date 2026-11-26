import CoolapkKit
import SwiftUI

public struct ContentFilterSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var newKeyword = ""
    @State private var newRuleKind: FilterRuleKind = .text
    @State private var newReason = ""

    public init() {}

    public var body: some View {
        @Bindable var filter = appState.contentFilter

        Form {
            Section {
                Toggle("开启内容过滤", isOn: $filter.enabled)
                Picker("过滤强度", selection: $filter.level) {
                    ForEach(FilterLevel.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
            } footer: {
                Text("默认关闭，仅在本机静默过滤列表内容；不会调用账号拉黑或举报接口。标准档较温和，严格档覆盖更多边缘词句。")
            }

            Section("内置与订阅分类") {
                Toggle("启用话题过滤名单", isOn: Binding(
                    get: { filter.isListEnabled(.topic) },
                    set: { filter.setListEnabled(.topic, $0) }
                ))
                Toggle("启用作者过滤名单", isOn: Binding(
                    get: { filter.isListEnabled(.author) },
                    set: { filter.setListEnabled(.author, $0) }
                ))
                Button {
                    Task { await filter.checkForUpdates() }
                } label: {
                    HStack {
                        Text("更新过滤规则订阅 (r\(filter.ruleSet.revision))")
                        Spacer()
                        if filter.isUpdating { ProgressView() }
                    }
                }
                .disabled(filter.isUpdating)

                if let msg = filter.updateMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("添加个人规则") {
                Picker("类型", selection: $newRuleKind) {
                    Text("关键词").tag(FilterRuleKind.text)
                    Text("话题名").tag(FilterRuleKind.topic)
                    Text("作者 UID").tag(FilterRuleKind.author)
                }
                TextField(newRuleKind == .author ? "输入 UID" : "输入关键词或话题", text: $newKeyword)
                    .autocorrectionDisabled()
                TextField("原因备注（可选）", text: $newReason)
                Button("添加个人规则") {
                    filter.addPersonalRule(kind: newRuleKind, keyword: newKeyword, reason: newReason)
                    newKeyword = ""
                    newReason = ""
                }
                .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !filter.personalRules.isEmpty {
                Section("个人规则（\(filter.personalRules.count)）") {
                    ForEach(filter.personalRules) { rule in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.reason)
                                .font(.body)
                            let target = rule.values.first ?? rule.groups.first?.first ?? ""
                            Text("\(rule.kind.rawValue): \(target)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                filter.removePersonalRule(id: rule.id)
                            }
                        }
                    }
                }
            }

            Section("预设规则开关") {
                ForEach(filter.ruleSet.rules) { rule in
                    Toggle(isOn: Binding(
                        get: { !filter.disabledRuleIDs.contains(rule.id) },
                        set: { filter.setRuleDisabled(rule.id, !$0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.reason)
                            Text("\(rule.kind.rawValue) · \(rule.level.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !filter.allowedAuthorUIDs.isEmpty {
                Section("例外作者") {
                    ForEach(Array(filter.allowedAuthorUIDs).sorted(), id: \.self) { uid in
                        HStack {
                            Text("UID: \(uid)")
                            Spacer()
                            Button("移除") {
                                filter.allowAuthor(uid, allowed: false)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("屏蔽傻逼内容")
        .navigationBarTitleDisplayMode(.inline)
    }
}
