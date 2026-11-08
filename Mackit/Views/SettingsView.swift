import MackitCore
import SwiftUI

/// SwiftUI's `Settings` scene titles its window "<AppName> Settings" and offers no
/// title modifier. The design language wants the plain word, so the hosting window's
/// title is fixed when the view lands in it.
struct SettingsWindowTitle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.title = "Settings" }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.title = "Settings" }
    }
}

/// The app's Settings page (Cmd+,): which steps run, which folders are skipped, and the
/// thresholds the steps read. Values apply to the next scan, never to one already running.
struct SettingsView: View {
    @Environment(ScanModel.self) private var model
    @State private var newExclusion = ""

    /// Steps the user may switch off. Rules and the folder index always run.
    private let optionalSteps: [ScanStep] = [.largeFiles, .duplicates, .leftovers, .photos, .videos, .snapshots]

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ForEach(optionalSteps, id: \.rawValue) { step in
                    Toggle(
                        step.title,
                        isOn: Binding(
                            get: { model.isStepEnabled(step) },
                            set: { model.setStep(step, enabled: $0) }))
                }
            } header: {
                Text("Scan steps")
            } footer: {
                Text("The rules step and the folder index always run: they feed the sidebar and the disk map.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }

            Section {
                Toggle(isOn: $model.scanOutsideHome) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Read folders outside your home folder")
                            .font(Typography.body)
                        Text("Scan and clean paths outside ~, such as VirtualBox machines on another disk. Off by default.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                if model.excludedPaths.isEmpty {
                    Text("No excluded folders. Add one below and every scan skips it.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                ForEach(model.excludedPaths, id: \.self) { path in
                    HStack(spacing: Spacing.s2) {
                        Text(path)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Spacing.s2)
                        Button {
                            model.removeExcludedPath(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop excluding this folder")
                        .accessibilityLabel("Stop excluding \(path)")
                    }
                }
                HStack(spacing: Spacing.s2) {
                    TextField("Add a folder, for example ~/Downloads/keep", text: $newExclusion)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        if model.addExcludedPath(newExclusion) { newExclusion = "" }
                    }
                    .disabled(newExclusion.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !newExclusion.isEmpty, ScanModel.normalizedPath(newExclusion) == nil {
                    Text("Write ~/folder or /folder. A relative path excludes nothing.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            } header: {
                Text("Scan scope")
            } footer: {
                Text("Excluded folders are never scanned and never cleaned. Write ~ for your home folder.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }

            Section("Duplicate files") {
                Toggle(isOn: $model.includeTempInDuplicates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include caches, build folders, and tool state")
                            .font(Typography.body)
                        Text("Search inside caches, build folders, and Terraform or Terragrunt dirs. Off by default.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                Stepper(value: $model.duplicateMinSizeMB, in: 1...100) {
                    Text("Smallest file worth hashing: \(model.duplicateMinSizeMB) MB")
                        .font(Typography.body)
                }
            }

            Section("Large files") {
                Stepper(value: $model.largeFileMinSizeMB, in: 50...2000, step: 50) {
                    Text("List files of at least \(model.largeFileMinSizeMB) MB")
                        .font(Typography.body)
                }
                Stepper(value: $model.largeFileOldAgeDays, in: 30...730, step: 30) {
                    Text("Treat files untouched for \(model.largeFileOldAgeDays) days as old")
                        .font(Typography.body)
                }
            }

            Section("Performance") {
                Picker("Folder walk threads", selection: $model.scanThreads) {
                    Text("Auto").tag(0)
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("8").tag(8)
                }
                Text("Auto uses one thread per core. Fewer threads finish slower and keep the fan quiet.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .formStyle(.grouped)
        .tint(Theme.accent)
        .frame(width: 480, height: 660)
        .background(SettingsWindowTitle())
    }
}
