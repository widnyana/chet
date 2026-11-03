import AppKit
import MackitCore
import SwiftUI

struct CategoryDetailView: View {
    @Environment(ScanModel.self) private var model
    let category: CategoryState

    var body: some View {
        Group {
            if let groups = model.groups[category.id] {
                GroupedItemsView(groups: groups)
            } else {
                Table(category.items) {
                    TableColumn("Clean") { item in
                        Toggle("", isOn: model.isSelected(item.url)).labelsHidden()
                    }
                    .width(44)
                    TableColumn("Name") { item in
                        Text(item.url.lastPathComponent).help(item.url.path)
                    }
                    TableColumn("Size") { item in
                        Text(item.reclaimableBytes.formatted(.byteCount(style: .file))).monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Modified") { item in
                        Text(item.stamp.modified, format: .dateTime.year().month().day())
                    }
                    .width(110)
                    TableColumn("Risk") { item in
                        RiskBadge(risk: item.risk)
                    }
                    .width(70)
                    TableColumn("") { item in
                        RevealButton(url: item.url)
                    }
                    .width(28)
                }
            }
        }
        .navigationTitle(category.title)
        .navigationSubtitle(category.bytes.formatted(.byteCount(style: .file)))
        .toolbar {
            ToolbarItemGroup {
                Button("Select all") { model.setSelected(category.items.map(\.url), true) }
                Button("Select none") { model.setSelected(category.items.map(\.url), false) }
            }
        }
    }
}

struct RiskBadge: View {
    let risk: Risk

    var body: some View {
        Text(risk == .safe ? "Safe" : "Review")
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(risk == .safe ? Color.green.opacity(0.2) : Color.orange.opacity(0.2), in: Capsule())
    }
}

struct RevealButton: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .buttonStyle(.borderless)
        .help("Reveal in Finder")
    }
}
