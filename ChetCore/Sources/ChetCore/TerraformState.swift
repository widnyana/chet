import Foundation

/// Local Terraform and OpenTofu state: providers and modules re-download, state does not.
/// Terragrunt copies the working directory into `.terragrunt-cache`, so a cache can carry it.
public enum TerraformState {
    /// Directory names whose contents can hold state.
    public static let toolDirNames: Set<String> = [".terraform", ".terragrunt-cache"]

    /// Where `terraform init` and `tofu init` record the backend configuration. This file names
    /// the backend (bucket, key, region); it is not resource state, and init rewrites it.
    static let backendConfigDirectory = ".terraform"
    static let backendConfigName = "terraform.tfstate"

    /// True when anything below `url` is a state file, ignoring the backend-config file.
    /// Cheap for every path that is not inside a tool directory.
    public static func holdsLocalState(_ url: URL) -> Bool {
        guard url.pathComponents.contains(where: toolDirNames.contains) else { return false }
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true })
        else { return false }
        for case let candidate as URL in enumerator {
            if candidate.lastPathComponent == backendConfigName,
                candidate.deletingLastPathComponent().lastPathComponent == backendConfigDirectory
            {
                continue
            }
            // Covers terraform.tfstate, its backups, errored.tfstate, and terraform.tfstate.d.
            if candidate.lastPathComponent.contains(".tfstate") { return true }
        }
        return false
    }
}
