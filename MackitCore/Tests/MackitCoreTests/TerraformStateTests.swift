import Foundation
import Testing

@testable import MackitCore

struct TerraformStateTests {
    @Test func backendConfigFileAloneIsNotState() throws {
        let dir = try TempDir()
        let terraform = dir.url.appendingPathComponent("app/.terraform")
        try dir.text("app/.terraform/terraform.tfstate", "{}")
        try dir.text("app/.terraform/providers/registry.opentofu.org/x/bin", "x")
        #expect(TerraformState.holdsLocalState(terraform) == false)
    }

    @Test func copiedProjectStateIsDetected() throws {
        let dir = try TempDir()
        let cache = dir.url.appendingPathComponent("app/.terragrunt-cache/a/b")
        try dir.text("app/.terragrunt-cache/a/b/terraform.tfstate", "{}")
        #expect(TerraformState.holdsLocalState(cache))
    }

    @Test func backupsAndWorkspaceStateAreDetected() throws {
        let dir = try TempDir()
        let cache = dir.url.appendingPathComponent("app/.terragrunt-cache/a/b")
        try dir.text("app/.terragrunt-cache/a/b/terraform.tfstate.1234.backup", "{}")
        try dir.text("app/.terragrunt-cache/a/b/terraform.tfstate.d/staging/terraform.tfstate", "{}")
        #expect(TerraformState.holdsLocalState(cache))
    }

    @Test func stateOutsideToolDirsIsNotWalked() throws {
        let dir = try TempDir()
        let project = dir.url.appendingPathComponent("app")
        try dir.text("app/terraform.tfstate", "{}")
        #expect(TerraformState.holdsLocalState(project) == false)
    }
}
