import AppKit
import MackitCore
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Duplicates and similar media. Photos and videos show as cards; other files as a list.
/// Each group shows the copy that stays, then the copies that may go.
struct GroupedItemsView: View {
    @Environment(ScanModel.self) private var model
    let groups: [ItemGroup]

    private var isMedia: Bool {
        groups.allSatisfy { group in
            guard let type = UTType(filenameExtension: group.keeper.pathExtension) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .movie)
        }
    }

    var body: some View {
        if isMedia { cards } else { list }
    }

    private var cards: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        header(group)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], spacing: 12)
                        {
                            MediaCard(url: group.keeper, bytes: nil, isOn: nil)
                            ForEach(group.items) { item in
                                MediaCard(url: item.url, bytes: item.reclaimableBytes, isOn: model.isSelected(item.url))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var list: some View {
        List {
            ForEach(groups) { group in
                Section {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: group.keeper.path))
                            .resizable()
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.keeper.lastPathComponent).lineLimit(1)
                            Text(Self.folder(group.keeper))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        KeepBadge()
                    }
                    .contextMenu { revealButton(group.keeper) }
                    ForEach(group.items) { item in
                        HStack(spacing: 10) {
                            Toggle("Clean", isOn: model.isSelected(item.url))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.url.lastPathComponent).lineLimit(1)
                                Text(Self.folder(item.url))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(item.reclaimableBytes.formatted(.byteCount(style: .file)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .contextMenu { revealButton(item.url) }
                    }
                } header: {
                    header(group)
                }
            }
        }
    }

    private func header(_ group: ItemGroup) -> some View {
        let bytes = group.items.reduce(0) { $0 + $1.reclaimableBytes }
        return Text("\(group.items.count + 1) copies · \(bytes.formatted(.byteCount(style: .file))) can be freed")
            .font(.headline)
    }

    private func revealButton(_ url: URL) -> some View {
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    static func folder(_ url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

struct KeepBadge: View {
    var body: some View {
        Label("Keep", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
            .help("This copy stays")
    }
}

/// One photo or video in a group: a big thumbnail, a checkbox (or a Keep badge), name and size.
struct MediaCard: View {
    let url: URL
    let bytes: Int64?
    let isOn: Binding<Bool>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Thumbnail(url: url, side: 150)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if let isOn {
                        Toggle("Clean", isOn: isOn)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .padding(8)
                    } else {
                        Label("Keep", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular.tint(.green), in: .capsule)
                            .padding(8)
                    }
                }
            Text(url.lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(bytes.map { $0.formatted(.byteCount(style: .file)) } ?? "Original")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(side / 5)
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
