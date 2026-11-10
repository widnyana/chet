import AppKit
import ChetCore
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

enum GroupSort: String, CaseIterable, Identifiable {
    case sizeDesc, sizeAsc, nameAsc, nameDesc
    var id: String { rawValue }

    var label: String {
        switch self {
        case .sizeDesc: "Largest first"
        case .sizeAsc: "Smallest first"
        case .nameAsc: "Name A to Z"
        case .nameDesc: "Name Z to A"
        }
    }

    func sorted(_ groups: [ItemGroup]) -> [ItemGroup] {
        func size(_ g: ItemGroup) -> Int64 { g.items.reduce(0) { $0 + $1.reclaimableBytes } }
        switch self {
        case .sizeDesc: return groups.sorted { size($0) > size($1) }
        case .sizeAsc: return groups.sorted { size($0) < size($1) }
        case .nameAsc:
            return groups.sorted {
                $0.keeper.lastPathComponent.localizedStandardCompare($1.keeper.lastPathComponent)
                    == .orderedAscending
            }
        case .nameDesc:
            return groups.sorted {
                $0.keeper.lastPathComponent.localizedStandardCompare($1.keeper.lastPathComponent)
                    == .orderedDescending
            }
        }
    }
}

struct GroupedItemsView: View {
    @Environment(ScanModel.self) private var model
    let groups: [ItemGroup]
    @State private var sort: GroupSort = .sizeDesc

    private var sorted: [ItemGroup] { sort.sorted(groups) }

    private var isMedia: Bool {
        groups.allSatisfy { group in
            guard let type = UTType(filenameExtension: group.keeper.pathExtension) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .movie)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s3) {
                Text(groups.count == 1 ? "1 group" : "\(groups.count) groups")
                    .font(Typography.row)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Picker("Sort", selection: $sort) {
                    ForEach(GroupSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help("Change the order")
            }
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            Hairline()
            if isMedia {
                cards
            } else {
                list
            }
        }
        .background(Theme.paper)
    }

    private var cards: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s6) {
                ForEach(sorted) { group in
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        groupHeader(group)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: Spacing.s3)],
                            spacing: Spacing.s3
                        ) {
                            MediaCard(url: group.keeper, bytes: nil, isOn: nil)
                            ForEach(group.items) { item in
                                MediaCard(
                                    url: item.url, bytes: item.reclaimableBytes,
                                    isOn: model.isSelected(item.url))
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.s6)
            .pageHorizontalPadding()
        }
    }

    private var list: some View {
        List {
            ForEach(sorted) { group in
                Section {
                    HStack(spacing: Spacing.s2) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: group.keeper.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.keeper.lastPathComponent)
                                .font(Typography.row)
                                .lineLimit(1)
                            Text(Self.folder(group.keeper))
                                .font(Typography.caption)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        StatusLabel(text: "Keep", systemImage: "checkmark", tone: .neutral)
                    }
                    .frame(minHeight: Metrics.rowHeight)
                    .contextMenu { revealButton(group.keeper) }
                    ForEach(group.items) { item in
                        HStack(spacing: Spacing.s2) {
                            Toggle("Remove", isOn: model.isSelected(item.url))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .accessibilityLabel("Remove \(item.url.lastPathComponent)")
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable()
                                .frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.url.lastPathComponent)
                                    .font(Typography.row)
                                    .lineLimit(1)
                                Text(Self.folder(item.url))
                                    .font(Typography.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(item.reclaimableBytes.formatted(.byteCount(style: .file)))
                                .font(Typography.row)
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .frame(minHeight: Metrics.rowHeight)
                        .contextMenu { revealButton(item.url) }
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
    }

    private func groupHeader(_ group: ItemGroup) -> some View {
        let bytes = group.items.reduce(0) { $0 + $1.reclaimableBytes }
        return HStack(spacing: Spacing.s3) {
            Text(
                "1 file kept, \(group.items.count) can be removed · \(bytes.formatted(.byteCount(style: .file)))"
            )
            .font(Typography.section)
            .foregroundStyle(Theme.ink)
            Spacer()
            QuietActionButton(
                title: "Choose all copies",
                help: "Select every copy except the one that stays.",
                action: { model.setSelected(group.items.map(\.url), true) })
        }
    }

    private func revealButton(_ url: URL) -> some View {
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    static func folder(_ url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

struct MediaCard: View {
    let url: URL
    let bytes: Int64?
    let isOn: Binding<Bool>?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Thumbnail(url: url, side: 150)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipShape(.rect(corners: .fixed(8)))
            HStack(spacing: Spacing.s2) {
                if let isOn {
                    RowCheckbox(
                        isOn: isOn,
                        label: "Remove \(url.lastPathComponent)")
                } else {
                    StatusLabel(text: "Keep", systemImage: "checkmark", tone: .neutral)
                }
                Text(url.lastPathComponent)
                    .font(Typography.row)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Spacing.s1)
                if let bytes {
                    Text(bytes.formatted(.byteCount(style: .file)))
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .help(url.path)
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

struct Thumbnail: View {
    let url: URL
    var side: CGFloat = 40
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .padding(side / 5)
            }
        }
        .task(id: url) {
            image = await Self.load(url, side: side)
        }
    }

    @concurrent nonisolated static func load(_ url: URL, side: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side), scale: 2, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}
