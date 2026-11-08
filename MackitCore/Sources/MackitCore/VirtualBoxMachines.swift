import Foundation

/// Machine folders of the VirtualBox installation for a home folder.
/// Reads the tool's own registry instead of guessing the default location: VirtualBox
/// lets the user keep machines anywhere (`defaultMachineFolder`, per-machine `src`).
public enum VirtualBoxMachines {
    /// Registry file VirtualBox writes for every user account.
    static func registryURL(home: URL) -> URL {
        home.appendingPathComponent("Library/VirtualBox/VirtualBox.xml")
    }

    /// Machine folders for `home`: registry entries first, then the children of
    /// `<home>/VirtualBox VMs` when no registry exists or it lists no machine.
    public static func folders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let home = home.standardizedFileURL
        if let data = try? Data(contentsOf: registryURL(home: home)) {
            let registered = machineFolders(registryXML: data, home: home)
            if !registered.isEmpty { return registered }
        }
        return childDirectories(of: home.appendingPathComponent("VirtualBox VMs"))
    }

    /// Pure parser used by `folders` and by tests. A malformed or absent registry yields
    /// no sources and no default folder; this is a scan hint, not an error path.
    static func machineFolders(registryXML: Data, home: URL) -> [URL] {
        let parser = XMLParser(data: registryXML)
        let registry = RegistryParser()
        parser.delegate = registry
        // Machine paths are plain attributes; never fetch external DTDs or entities.
        parser.shouldResolveExternalEntities = false
        parser.parse()

        // One entry per machine folder: a registry can list several disks of one machine.
        var seen = Set<URL>()
        for source in registry.sources {
            let folder = resolve(source, home: home).deletingLastPathComponent()
            if isDirectory(folder) { seen.insert(folder) }
        }
        guard seen.isEmpty else { return seen.sorted { $0.path < $1.path } }

        guard let defaultFolder = registry.defaultMachineFolder else { return [] }
        return childDirectories(of: resolve(defaultFolder, home: home))
    }

    /// `~/x` is relative to `home`, `/x` is absolute, anything else relative to `home`.
    private static func resolve(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL
        }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        return home.appendingPathComponent(path).standardizedFileURL
    }

    /// Children of a folder that also look like VirtualBox machines. Only used for folders the
    /// registry did not name, so an unrelated folder sitting in a "VirtualBox VMs" directory is
    /// never offered for deletion.
    private static func childDirectories(of folder: URL) -> [URL] {
        let listing =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)) ?? []
        return listing.filter { isDirectory($0) && looksLikeMachine($0) }
            .sorted { $0.path < $1.path }
    }

    /// A machine folder holds its machine definition (`.vbox`) or a disk image.
    private static func looksLikeMachine(_ folder: URL) -> Bool {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.contains { diskExtensions.contains($0.pathExtension.lowercased()) }
    }

    private static let diskExtensions: Set<String> = ["vbox", "vdi", "vmdk", "vhd"]

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private final class RegistryParser: NSObject, XMLParserDelegate {
        private(set) var sources: [String] = []
        private(set) var defaultMachineFolder: String?

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName {
            case "MachineEntry":
                if let source = attributeDict["src"] { sources.append(source) }
            case "SystemProperties":
                if let folder = attributeDict["defaultMachineFolder"] { defaultMachineFolder = folder }
            default:
                break
            }
        }
    }
}
