import SwiftUI

/// A short note that sits beside a preference state: a pending restart, a medium risk.
/// It is an opaque identifier for list comparison, not user-facing text.
struct PreferenceNote: Identifiable {
    let id: String
    let text: String
    let systemImage: String
    let tone: StatusTone
    var help: String?

    init(_ text: String, systemImage: String, tone: StatusTone, help: String? = nil) {
        self.id = text
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
        self.help = help
    }
}

/// One row in a preference list: name, one-line explanation, current state, the control
/// that changes it, and a way into the details. Geometry lives here, so every list that
/// uses the component keeps one rhythm.
struct PreferenceRow<Accessory: View>: View {
    let title: String
    let detail: String
    let state: String
    var notes: [PreferenceNote] = []
    var controlWidth = Metrics.controlColumn
    /// False while a global gate such as DRY_RUN is on: the control stays visible and inert.
    var isEnabled = true
    let accessory: Accessory
    var detailsIdentifier: String?
    let onDetails: () -> Void

    init(
        title: String, detail: String, state: String, notes: [PreferenceNote] = [],
        controlWidth: CGFloat = Metrics.controlColumn, isEnabled: Bool = true,
        detailsIdentifier: String? = nil,
        onDetails: @escaping () -> Void, @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.state = state
        self.notes = notes
        self.controlWidth = controlWidth
        self.isEnabled = isEnabled
        self.detailsIdentifier = detailsIdentifier
        self.onDetails = onDetails
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.row)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                HStack(spacing: Spacing.s2) {
                    Text(state)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    ForEach(notes) { note in
                        StatusLabel(
                            text: note.text, systemImage: note.systemImage, tone: note.tone,
                            help: note.help)
                    }
                }
            }
            Spacer(minLength: Spacing.s3)
            accessory
                .frame(width: controlWidth, alignment: .trailing)
                .disabled(!isEnabled)
            IconActionButton(
                systemImage: "info.circle", label: "Details for \(title)", action: onDetails
            )
            .modifier(OptionalAccessibilityIdentifier(identifier: detailsIdentifier))
        }
        .padding(.vertical, Spacing.s2)
    }
}

/// A label and its value in a detail sheet. The value can be selected, so a preference key
/// or a path can be copied out.
struct DefinitionRow: View {
    let label: String
    let value: String
    var monospaced = false
    var labelWidth: CGFloat = 110
    var identifier: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(monospaced ? Typography.caption : Typography.row)
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(OptionalAccessibilityIdentifier(identifier: identifier))
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s2)
    }
}
