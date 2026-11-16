import SwiftUI

// NOTE: SwiftUI's `@State` is a macro in recent SDKs, and the macro plugin only ships with
// Xcode. To keep Snitch buildable with just the Command Line Tools, local view state lives
// in tiny ObservableObjects held with `@StateObject` (which is not a macro).
final class Flag: ObservableObject {
    @Published var on = false
    /// Turns on, then back off after `seconds` (used for two-step "Stop?" confirmation).
    func pulse(_ seconds: Double = 3) {
        on = true
        Task { @MainActor in try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); self.on = false }
    }
}

struct PopoverView: View {
    @ObservedObject var store: Store
    @StateObject private var othersOpen = Flag()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text("🐀 Snitch").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        let projects = store.projects
        let others = store.others
        let searching = false

        if !store.hasScanned {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 90)
        } else if store.items.isEmpty {
            EmptyState(symbol: "checkmark.circle", title: "Nothing is running on localhost", detail: "Start your project and it will show up here.")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    if store.projects.isEmpty && !searching {
                        EmptyState(symbol: "checkmark.circle", title: "No project servers running", detail: "Start your project and it will show up here.")
                    }
                    ForEach(projects) { RowView(item: $0, store: store) }
                    if !others.isEmpty {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { othersOpen.on.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.right").rotationEffect(.degrees(othersOpen.on || searching ? 90 : 0)).font(.caption2.weight(.semibold))
                                Text("Apps & system (\(others.count))").font(.caption.weight(.medium))
                                Spacer()
                            }
                            .foregroundStyle(.secondary).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                        .accessibilityLabel("Apps and system, \(others.count) items")
                        if othersOpen.on || searching {
                            ForEach(others) { RowView(item: $0, store: store) }
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(pressureColor).frame(width: 8, height: 8).accessibilityHidden(true)
            if let message = store.message {
                Text(message).font(.caption).lineLimit(1)
            } else {
                Text("Mac memory: \(store.pressure.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.projects.count >= 2 { StopAllButton(store: store) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var pressureColor: Color {
        switch store.pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

struct EmptyState: View {
    let symbol: String, title: String, detail: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(.secondary)
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 110).padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}

struct StopAllButton: View {
    let store: Store
    @StateObject private var confirming = Flag()
    var body: some View {
        Button(confirming.on ? "Stop \(store.projects.count) servers?" : "Stop all") {
            if confirming.on { store.stopAllProjects(); confirming.on = false }
            else { confirming.pulse() }
        }
        .controlSize(.small)
        .tint(confirming.on ? .red : nil)
        .buttonStyle(.bordered)
        .help("Stop every project server")
    }
}

struct RowView: View {
    let item: ServerItem
    let store: Store
    @StateObject private var hover = Flag()
    @StateObject private var confirming = Flag()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let hint = item.hint {
                    Text(hint).font(.caption2).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                if item.exposed {
                    Label("Visible to your Wi-Fi network", systemImage: "wifi")
                        .font(.caption2).foregroundStyle(.orange)
                        .help("Other devices on this network can reach this server. Fine for apps, worth a look for dev servers.")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if let p = item.webPorts.first { store.open(item, port: p) } }

            Spacer(minLength: 4)

            if item.webPorts.count > 1 {
                Menu {
                    ForEach(item.webPorts, id: \.self) { p in Button("Open localhost:\(p)") { store.open(item, port: p) } }
                } label: { Image(systemName: "arrow.up.right.square") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Open in browser").accessibilityLabel("Open \(item.title) in browser")
            } else if let p = item.webPorts.first {
                Button { store.open(item, port: p) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless).help("Open localhost:\(p) in browser")
                    .accessibilityLabel("Open \(item.title) in browser")
            }

            if !item.isSystem { stopControl }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(hover.on ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hover.on = $0 }
        .opacity(store.stopping.contains(item.pid) ? 0.5 : 1)
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var stopControl: some View {
        if store.stopping.contains(item.pid) {
            ProgressView().controlSize(.small).frame(width: 40)
        } else if confirming.on {
            Button("Stop?") { confirming.on = false; store.stop(item) }
                .controlSize(.small).buttonStyle(.borderedProminent).tint(.red)
        } else {
            Button { confirming.pulse() } label: { Image(systemName: "stop.circle") }
                .buttonStyle(.borderless).help("Stop this server")
                .accessibilityLabel("Stop \(item.title)")
        }
    }

    private var subtitle: String {
        var parts = [Format.ports(item.ports), Format.bytes(item.memory)]
        parts.append(item.isForgotten ? "running \(Format.uptime(item.uptime)) — forgotten?" : "up \(Format.uptime(item.uptime))")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var contextMenu: some View {
        if let p = item.webPorts.first {
            Button("Open in Browser") { store.open(item, port: p) }
            Button("Copy URL") { store.copyURL(p) }
        }
        if item.cwd != nil, item.isProject {
            Divider()
            Button("Show Folder in Finder") { store.reveal(item) }
            ForEach(store.installedEditors, id: \.name) { e in
                Button("Open in \(e.name)") { store.openInEditor(item, app: e.url) }
            }
        }
        if !item.isSystem {
            Divider()
            Button("Stop", role: .destructive) { store.stop(item) }
        }
    }
}
