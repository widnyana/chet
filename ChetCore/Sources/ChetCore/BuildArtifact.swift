import Foundation

public struct BuildArtifact: Sendable, Equatable, Hashable {
    public let name: String
    public let label: String
    public let requiresSibling: String?
    public let isVirtualEnvironment: Bool

    public init(
        name: String, label: String, requiresSibling: String? = nil, isVirtualEnvironment: Bool = false
    ) {
        self.name = name
        self.label = label
        self.requiresSibling = requiresSibling
        self.isVirtualEnvironment = isVirtualEnvironment
    }

    public static let virtualEnvironment = BuildArtifact(
        name: "venv", label: "Python venv", isVirtualEnvironment: true)

    public static let catalog: [BuildArtifact] = [
        BuildArtifact(name: "target", label: "Rust target"),
        BuildArtifact(name: "node_modules", label: "Node modules"),
        BuildArtifact(name: "vendor", label: "PHP vendor", requiresSibling: "composer.json"),
        BuildArtifact(name: ".build", label: "Swift build"),
        BuildArtifact(name: ".gradle", label: "Gradle"),
        BuildArtifact(name: "DerivedData", label: "Xcode DerivedData"),
        BuildArtifact(name: "Pods", label: "CocoaPods"),
        BuildArtifact(name: ".vite", label: "Vite"),
        BuildArtifact(name: ".next", label: "Next.js"),
        BuildArtifact(name: ".turbo", label: "Turborepo"),
        BuildArtifact(name: "build", label: "Build output"),
        BuildArtifact(name: ".dart_tool", label: "Dart tool"),
        virtualEnvironment,
        BuildArtifact(name: ".terraform", label: "Terraform"),
        BuildArtifact(name: ".terragrunt-cache", label: "Terragrunt cache"),
    ]

    /// Build-dir labels for rule roots that are matched by path, not by folder name.
    public static let rootLabels: [String: String] = [".terraform.d/plugin-cache": "Terraform plugins"]

    /// The environment's own bootstrapper writes `pyvenv.cfg`, so its presence, not the folder
    /// name, identifies a virtual environment (`.venv-codegen`, `venv`, `list`).
    public static func isVirtualEnvironment(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent("pyvenv.cfg").path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    /// Label for a matched directory, resolved from the catalog alone: the artifact's label, or
    /// `Python venv` for a directory holding `pyvenv.cfg`. Nil when the directory is not a build
    /// artifact.
    public static func label(for url: URL, in artifacts: [BuildArtifact] = catalog) -> String? {
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent()
        for artifact in artifacts {
            if artifact.isVirtualEnvironment {
                if isVirtualEnvironment(url) { return artifact.label }
                continue
            }
            guard artifact.name == name else { continue }
            if let sibling = artifact.requiresSibling,
                !FileManager.default.fileExists(atPath: parent.appendingPathComponent(sibling).path)
            {
                continue
            }
            return artifact.label
        }
        return nil
    }

    public static func label(forRoot root: String) -> String? { rootLabels[root] }

    public static func isPackageStore(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name == "store" || name == ".pnpm-store" || name == "_cacache" { return true }
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(
                atPath: url.appendingPathComponent("index.db").path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else { return false }
        let children = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return children.contains { child in
            guard child.hasPrefix("v") else { return false }
            let digits = child.dropFirst()
            return !digits.isEmpty && digits.allSatisfy(\.isNumber)
        }
    }
}
