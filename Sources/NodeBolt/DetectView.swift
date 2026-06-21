import SwiftUI
import AppKit
import NodeBoltCore

struct DetectView: View {
    @ObservedObject private var state = AppState.shared
    @AppStorage(SettingsKeys.filterRules) private var filterRules = defaultFilterRules
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("检测").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    subSection
                    Divider()
                    connectivitySection
                    Divider()
                    ipSection
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 320, height: 460)
        .onAppear {
            if !state.probes.contains(where: { $0.done }) { Task { await state.runConnectivity() } }
            if state.ipResults.isEmpty { Task { await state.runIPCheck() } }
        }
    }

    private var subSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("订阅信息").font(.subheadline.bold())
            if state.subInfos.isEmpty {
                Text("未获取到订阅流量信息(机场可能未通过 provider 提供)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(state.subInfos) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.caption.bold())
                        Text("剩余 \(formatBytes(s.remaining)) / 总 \(formatBytes(s.total))")
                            .font(.caption).foregroundStyle(.secondary)
                        if s.expire > 0 {
                            Text("到期 \(expireText(s.expire))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            let infos = airportInfoLines
            if !infos.isEmpty {
                Text("机场信息").font(.caption.bold()).padding(.top, 2)
                ForEach(infos, id: \.self) { line in infoLine(line) }
            }
        }
    }

    private var airportInfoLines: [String] {
        let rules = parseFilterRules(filterRules)
        return state.nodes.map { $0.name }.filter { isInfoNode($0, rules: rules) }
    }

    @ViewBuilder private func infoLine(_ s: String) -> some View {
        if let url = firstURL(in: s) {
            Button { NSWorkspace.shared.open(url) } label: {
                Text(s).font(.caption).foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        } else {
            Text(s).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func firstURL(in s: String) -> URL? {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let m = d.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        return m?.url
    }

    private func expireText(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let days = Int(date.timeIntervalSinceNow / 86400)
        return "\(df.string(from: date)) (\(days)天)"
    }

    private var connectivitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("网络连通性").font(.subheadline.bold())
                Spacer()
                Button("重新检测") { Task { await state.runConnectivity() } }
                    .buttonStyle(.borderless).font(.caption)
            }
            ForEach(state.probes) { p in
                HStack {
                    Text(p.name)
                    Spacer()
                    if p.testing {
                        ProgressView().controlSize(.small)
                    } else if let d = p.delay {
                        Text("\(d) ms").font(.caption.monospacedDigit()).foregroundStyle(colorFor(d))
                    } else if p.done {
                        Text("不可达").font(.caption).foregroundStyle(.red)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var ipSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("代理出口 IP").font(.subheadline.bold())
                Spacer()
                Button("重新查询") { Task { await state.runIPCheck() } }
                    .buttonStyle(.borderless).font(.caption)
            }
            // 数据源切换(实时对比)
            Picker("", selection: Binding(get: { state.ipSource }, set: { state.ipSource = $0 })) {
                ForEach(IPSource.allCases, id: \.self) { s in Text(s.rawValue).tag(s) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if state.ipChecking {
                HStack { ProgressView().controlSize(.small); Text("查询中…").foregroundStyle(.secondary) }
            } else if let info = state.ipResults[state.ipSource] {
                ipDetailView(info)
            } else {
                Text("该数据源查询失败").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func ipDetailView(_ info: IPInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(info.ip).font(.body.monospaced())
                Button { copy(info.ip) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).font(.caption)
            }
            if !info.country.isEmpty || !info.city.isEmpty {
                Text("地区:\(info.country) \(info.city)").font(.caption).foregroundStyle(.secondary)
            }
            if !info.isp.isEmpty {
                Text("ISP:\(info.isp)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            ForEach(info.details) { d in
                HStack(spacing: 4) {
                    Text("\(d.label):").font(.caption).foregroundStyle(.secondary)
                    Text(d.value).font(.caption).foregroundStyle(riskColor(d))
                }
            }
        }
    }

    // 风险类字段:是=红,否=绿;其余默认色
    private func riskColor(_ d: IPDetail) -> Color {
        if ["数据中心", "VPN", "代理", "Tor", "滥用"].contains(d.label) {
            return d.value == "是" ? .red : .green
        }
        return .primary
    }

    private func colorFor(_ d: Int) -> Color {
        if d < 150 { return .green }
        if d < 400 { return .orange }
        return .red
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
