import SwiftUI
import AppKit
import NodeBoltCore

// ===== 主面板(Popover) =====
struct PanelView: View {
    @ObservedObject private var state = AppState.shared
    @State private var query = ""
    @AppStorage(SettingsKeys.filterInfoNodes) private var filterInfo = false
    @AppStorage(SettingsKeys.filterRules) private var filterRules = defaultFilterRules
    @AppStorage(SettingsKeys.sortMode) private var sortMode = "default"
    @AppStorage(SettingsKeys.hideTimeout) private var hideTimeout = false

    @State private var showDetect = false

    var body: some View {
        if showDetect {
            DetectView(onBack: { showDetect = false })
        } else {
            nodePanel
        }
    }

    private var nodePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !state.hasError && !state.mode.isEmpty {
                modeBar
                Divider()
            }
            Group {
                if state.hasError {
                    errorBody
                } else {
                    nodeList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: 320, height: state.hasError ? 190 : 460)
        .onAppear {
            // 关键:让面板立即获得焦点,首次点击就能选节点(否则第一击被用于激活窗口)
            NSApp.activate(ignoringOtherApps: true)
            Task {
                await state.refresh()
                if UserDefaults.standard.bool(forKey: SettingsKeys.autoTest) {
                    await state.testAll()
                }
            }
        }
    }

    // 过滤 + 收藏置顶后的节点
    private var displayedNodes: [NodeItem] {
        var base = state.nodes
        if filterInfo {
            let rules = parseFilterRules(filterRules)
            base = base.filter { !isInfoNode($0.name, rules: rules) }
        }
        if hideTimeout {
            base = base.filter { !$0.failed }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? base : base.filter { $0.name.localizedCaseInsensitiveContains(q) }
        let sorted = sortNodes(filtered)
        let favs = sorted.filter { state.isFavorite($0.name) }
        let rest = sorted.filter { !state.isFavorite($0.name) }
        return favs + rest
    }

    private func sortNodes(_ list: [NodeItem]) -> [NodeItem] {
        func rank(_ n: NodeItem) -> Int {
            if let d = n.delay { return d }
            return n.failed ? Int.max : Int.max - 1   // 未测排在已测之后、超时之前
        }
        switch sortMode {
        case "delay": return list.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name < $1.name }
        case "name":  return list.sorted { $0.name < $1.name }
        default:      return list   // 默认:保持机场原始顺序
        }
    }

    private var sortLabel: String {
        switch sortMode {
        case "delay": return "延迟"
        case "name":  return "名称"
        default:      return "默认"
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button { sortMode = "default" } label: { Text((sortMode == "default" ? "✓ " : "    ") + "默认顺序") }
                Button { sortMode = "delay" }   label: { Text((sortMode == "delay"   ? "✓ " : "    ") + "按延迟") }
                Button { sortMode = "name" }    label: { Text((sortMode == "name"    ? "✓ " : "    ") + "按名称") }
            } label: {
                Label("排序:\(sortLabel)", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Toggle("隐藏超时", isOn: $hideTimeout)
                .toggleStyle(.checkbox)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    // 顶部:标题 + 当前节点 + 策略组切换
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "bolt.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text("NodeBolt").font(.headline)
                Text(state.currentNode.isEmpty ? "未选择节点" : "当前:\(state.currentNode)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if state.groups.count > 1 {
                Menu(state.activeGroup) {
                    ForEach(state.groups, id: \.self) { g in
                        Button { state.setActiveGroup(g) } label: {
                            if g == state.activeGroup { Label(g, systemImage: "checkmark") }
                            else { Text(g) }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(12)
    }

    // 运行模式切换
    private var modeBar: some View {
        HStack(spacing: 8) {
            Text("模式").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { state.mode },
                set: { newValue in Task { await state.setMode(newValue) } }
            )) {
                Text("规则").tag("rule")
                Text("全局").tag("global")
                Text("直连").tag("direct")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if state.modeSwitching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var errorBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(state.statusText, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("地址:\(state.currentBaseDisplay)")
                .font(.caption).foregroundStyle(.secondary)
            Button("重试连接") { Task { await state.refresh() } }
        }
        .padding(12)
    }

    private var nodeList: some View {
        VStack(spacing: 0) {
            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("搜索节点", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            controlsRow
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    let nodes = displayedNodes
                    if nodes.isEmpty {
                        Text(query.isEmpty ? "(无节点)" : "无匹配节点")
                            .foregroundStyle(.secondary).padding(.vertical, 12)
                    } else {
                        ForEach(nodes) { node in
                            NodeRow(
                                node: node,
                                isFavorite: state.isFavorite(node.name),
                                onTap: { Task { await state.switchTo(node.name) } },
                                onTest: { Task { await state.testOne(node.name) } },
                                onToggleFav: { state.toggleFavorite(node.name) }
                            )
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: .infinity)
        }
    }

    // 底部工具栏
    private var footer: some View {
        HStack(spacing: 10) {
            if state.isTesting {
                ProgressView().controlSize(.small)
                Text("测速中…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button { Task { await state.testAll() } } label: {
                    Label("测速", systemImage: "speedometer")
                }
                Button { Task { await state.switchFastest() } } label: {
                    Label("最快", systemImage: "bolt.fill")
                }
                Button { Task { await state.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            Spacer()
            Button { showDetect = true } label: {
                Image(systemName: "network")
            }
            Button { ManagementWindowController.shared.show() } label: {
                Image(systemName: "slider.horizontal.3")
            }
            Button { SettingsWindowController.shared.show() } label: {
                Image(systemName: "gearshape")
            }
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
        }
        .buttonStyle(.borderless)
        .padding(10)
    }
}

// ===== 单个节点行 =====
struct NodeRow: View {
    let node: NodeItem
    let isFavorite: Bool
    let onTap: () -> Void
    let onTest: () -> Void
    let onToggleFav: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: node.isCurrent ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(node.isCurrent ? Color.green : Color.secondary)
                    .font(.system(size: 12))
                if isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).font(.system(size: 9))
                }
                Text(node.name).lineLimit(1)
                Spacer()
                latencyView
            }
            .padding(.vertical, 5).padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(node.isCurrent ? Color.green.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("测试此节点延迟") { onTest() }
            Button(isFavorite ? "取消收藏" : "收藏(置顶)") { onToggleFav() }
        }
    }

    @ViewBuilder private var latencyView: some View {
        if node.testing {
            ProgressView().controlSize(.small)
        } else if node.failed {
            Text("超时").font(.caption.monospacedDigit()).foregroundStyle(.red)
        } else if let d = node.delay {
            Text("\(d) ms").font(.caption.monospacedDigit()).foregroundStyle(colorFor(d))
        } else {
            Text("—").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func colorFor(_ d: Int) -> Color {
        if d < 150 { return .green }
        if d < 400 { return .orange }
        return .red
    }
}
