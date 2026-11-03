import AppKit
import MackitCore
import QuickLookThumbnailing
import SwiftUI

/// Duplicates and similar media: each group shows the copy that stays, then the copies that may go.
struct GroupedItemsView: View {
    @Environment(ScanModel.self) private var model
    let groups: [ItemGroup]

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    HStack {
                        Thumbnail(url: group.keeper)
                        VStack(alignment: .leading) {
                            Text(group.keeper.lastPathComponent)
                            Text("Keeps this copy").font(.caption).foregroundStyle(.green)
                        }
                        Spacer()
                        RevealButton(url: group.keeper)
                    }
                    ForEach(group.items) { item in
                        HStack {
                            Toggle("", isOn: model.isSelected(item.url)).labelsHidden()
                            Thumbnail(url: item.url)
                            VStack(alignment: .leading) {
                                Text(item.url.lastPathComponent)
                                Text(item.url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(item.reclaimableBytes.formatted(.byteCount(style: .file)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            RevealButton(url: item.url)
                        }
                    }
                } header: {
                    Text("\(group.items.count + 1) copies")
                }
            }
        }
    }
}

struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "doc").foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: url) {
            image = await Self.load(url)
        }
    }

    @concurrent nonisolated static func load(_ url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 80, height: 80), scale: 2, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}
