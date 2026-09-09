import SwiftUI

/// Prepares an immutable approved-grade snapshot for the selected output
/// formats. The workspace creates files from that approved snapshot.
public struct GradeExportPanel: View {
  public let assignment: WorkAssignment
  public let identities: [UUID: String]
  public let onExport: (GradeExportOptions, GradeExportSnapshot) -> Void

  @State private var selectedFormats: Set<GradeExportFormat>
  @State private var includeIdentities: Bool
  @State private var errorMessage: String?

  public init(
    assignment: WorkAssignment,
    identities: [UUID: String],
    onExport: @escaping (GradeExportOptions, GradeExportSnapshot) -> Void
  ) {
    self.assignment = assignment
    self.identities = identities
    self.onExport = onExport
    let defaults = GradeExportOptions()
    _selectedFormats = State(initialValue: defaults.formats)
    _includeIdentities = State(initialValue: defaults.includeIdentities)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header
        preflightCard
        formatsCard
        identityCard
        exportAction
        if let errorMessage {
          ExportMessage(text: errorMessage, systemImage: "exclamationmark.triangle")
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(WorkspaceStyle.background)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Grade export")
          .font(.title3.weight(.semibold))
        ExportBadge(text: "Approved only")
        Spacer(minLength: 8)
        ExportBadge(text: "Local workspace")
      }
      Text("Choose approved grades to export as CSV, JSON, or annotated PDFs.")
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var preflight: GradeExportPreflight {
    GradeExportEngine.preflight(assignment: assignment)
  }

  private var preflightCard: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Preflight")
          .font(.headline)
        Spacer(minLength: 8)
        Text("\(preflight.approvedCount) approved")
          .font(.caption.weight(.semibold).monospaced())
          .foregroundStyle(preflight.approvedCount == 0 ? .orange : WorkspaceStyle.accent)
      }
      Text(
        "Only current approved grades with complete, confirmed scores and an available document can be included."
      )
      .font(.caption)
      .foregroundStyle(WorkspaceStyle.secondary)
      .fixedSize(horizontal: false, vertical: true)
      if preflight.excludedCounts.isEmpty {
        Text("No submissions are excluded by the current preflight.")
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
      } else {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(GradeExportExclusion.allCases, id: \.self) { exclusion in
            if let count = preflight.excludedCounts[exclusion], count > 0 {
              HStack(spacing: 8) {
                Text(exclusion.title)
                Spacer(minLength: 8)
                Text(String(count))
                  .font(.caption.monospaced())
              }
              .font(.caption)
              .foregroundStyle(WorkspaceStyle.secondary)
            }
          }
        }
      }
    }
    .workspaceCard()
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Export preflight")
    .accessibilityValue(
      preflight.approvedCount == 0
        ? "No approved grades; \(preflight.excludedCount) excluded"
        : "\(preflight.approvedCount) approved, \(preflight.excludedCount) excluded"
    )
  }

  private var formatsCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Formats")
        .font(.headline)
      Text("Choose one or more outputs. All selected formats use the same approved snapshot.")
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
      ForEach(GradeExportFormat.allCases, id: \.self) { format in
        Toggle(isOn: formatBinding(for: format)) {
          VStack(alignment: .leading, spacing: 2) {
            Text(format.title)
              .font(.caption.weight(.medium))
            Text(formatHelp(for: format))
              .font(.caption)
              .foregroundStyle(WorkspaceStyle.secondary)
          }
        }
        .toggleStyle(.switch)
        .accessibilityLabel("Include \(format.title)")
      }
    }
    .workspaceCard()
  }

  private var identityCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(isOn: $includeIdentities) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Include candidate identities")
            .font(.callout.weight(.semibold))
          Text(
            "Optional names are opt-in and are omitted by default. Candidate IDs and aliases remain in the export details."
          )
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .toggleStyle(.switch)
      .accessibilityHint("Identity inclusion is off by default")
      if includeIdentities && identities.isEmpty {
        Text("No identity mapping is available; the snapshot will contain no identified names.")
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .workspaceCard()
  }

  private var exportAction: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        prepareSnapshot()
      } label: {
        Label("Prepare export snapshot", systemImage: "square.and.arrow.up")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canPrepare)
      .help(actionHelp)
      .accessibilityLabel(canPrepare ? "Prepare export snapshot" : actionHelp)
      Text(actionExplanation)
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .workspaceCard()
  }

  private var canPrepare: Bool {
    preflight.approvedCount > 0 && !selectedFormats.isEmpty
  }

  private var actionHelp: String {
    if preflight.approvedCount == 0 {
      return "Export is unavailable until at least one current grade is approved."
    }
    if selectedFormats.isEmpty {
      return "Choose at least one export format."
    }
    return "Prepare an immutable snapshot of current approved grades."
  }

  private var actionExplanation: String {
    if preflight.approvedCount == 0 {
      return
        "No approved grades are available. Excluded submissions remain in the workspace for review."
    }
    return "After preflight, the workspace creates the selected files from this approved snapshot."
  }

  private func formatBinding(for format: GradeExportFormat) -> Binding<Bool> {
    Binding(
      get: { selectedFormats.contains(format) },
      set: { isSelected in
        if isSelected {
          selectedFormats.insert(format)
        } else {
          selectedFormats.remove(format)
        }
        errorMessage = nil
      }
    )
  }

  private func formatHelp(for format: GradeExportFormat) -> String {
    switch format {
    case .csv:
      return "Tabular grade records and provenance identifiers."
    case .json:
      return "Schema-versioned records and rubric metadata."
    case .editablePDF:
      return "Annotated document output that remains editable."
    case .flattenedPDF:
      return "Annotated document output flattened for sharing."
    }
  }

  private func prepareSnapshot() {
    guard canPrepare else {
      errorMessage = actionHelp
      return
    }
    do {
      let options = GradeExportOptions(
        formats: selectedFormats, includeIdentities: includeIdentities
      )
      let snapshot = try GradeExportEngine.makeSnapshot(
        assignment: assignment,
        identities: identities,
        includeIdentities: includeIdentities
      )
      onExport(options, snapshot)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct ExportBadge: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(WorkspaceStyle.secondary)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(WorkspaceStyle.inset, in: Capsule())
  }
}

private struct ExportMessage: View {
  let text: String
  let systemImage: String

  var body: some View {
    Label(text, systemImage: systemImage)
      .font(.caption.weight(.medium))
      .foregroundStyle(.orange)
      .fixedSize(horizontal: false, vertical: true)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
      .accessibilityElement(children: .combine)
  }
}
