import SwiftUI
import UniformTypeIdentifiers

/// Rubric and reference authoring for an assignment.
///
/// Edits are kept in a local draft until the corresponding Save action. Each
/// Each edit receives a new rubric revision; existing reviewed grades return
/// to draft so they can be checked against the current rubric.
public struct LiveRubricEditor: View {
  @Environment(\.dismiss) private var dismiss

  public let assignment: WorkAssignment
  public let readOnly: Bool
  public let saveError: String?
  public let onAssignmentChange: (WorkAssignment) -> Void
  public let onImportReference: (UUID) -> Void

  @State private var draft: WorkAssignment
  @State private var titleDraft: String
  @State private var courseDraft: String
  @State private var jsonText = ""
  @State private var importPreview: RubricImportPreview?
  @State private var importError: String?
  @State private var importIssues: [String] = []
  @State private var editMessage: String?
  @State private var isJSONImporterPresented = false
  @State private var isImportPanelExpanded = false

  public init(
    assignment: WorkAssignment,
    readOnly: Bool = false,
    saveError: String? = nil,
    onAssignmentChange: @escaping (WorkAssignment) -> Void,
    onImportReference: @escaping (UUID) -> Void
  ) {
    self.assignment = assignment
    self.readOnly = readOnly
    self.saveError = saveError
    self.onAssignmentChange = onAssignmentChange
    self.onImportReference = onImportReference
    _draft = State(initialValue: assignment)
    _titleDraft = State(initialValue: assignment.title)
    _courseDraft = State(initialValue: assignment.course)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        Group {
          assignmentDetails
          validationCard
          partsCard
          criteriaCard
          referencesCard
          jsonImportCard
        }
        .disabled(readOnly)
        if let saveError {
          LiveRubricError(text: saveError)
        }
        if let editMessage {
          Text(editMessage)
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(WorkspaceStyle.background)
    .fileImporter(
      isPresented: $isJSONImporterPresented,
      allowedContentTypes: [.json]
    ) { result in
      loadJSONFile(result)
    }
    .onChange(of: assignment.rubricRevisionID) { _, _ in
      syncFromAssignment()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Rubric editor")
          .font(.title3.weight(.semibold))
        LiveRubricBadge(text: "New revision on save")
        Spacer(minLength: 4)
        Text("Draft workspace")
          .font(.caption.weight(.medium))
          .foregroundStyle(WorkspaceStyle.secondary)
        Button("Done") {
          dismiss()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Close rubric editor")
      }
      Text("Define parts, criteria, guidance, and references before reviewing submissions.")
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var assignmentDetails: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Assignment")
        .font(.headline)
      HStack(alignment: .bottom, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Title")
            .font(.caption.weight(.medium))
            .foregroundStyle(WorkspaceStyle.secondary)
          TextField("Assignment title", text: $titleDraft)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Assignment title")
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Course")
            .font(.caption.weight(.medium))
            .foregroundStyle(WorkspaceStyle.secondary)
          TextField("Course or class", text: $courseDraft)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Assignment course")
        }
        Button("Save details") {
          saveDetails()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(titleDraft == draft.title && courseDraft == draft.course)
        .accessibilityLabel("Save assignment details")
      }
      Text("Saving title or course creates a new rubric revision so approvals can be rechecked.")
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .workspaceCard()
  }

  private var validationCard: some View {
    let validation = RubricEngine.validateRubric(draft)
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 7) {
        Image(systemName: validation.isValid ? "checkmark.seal" : "exclamationmark.triangle")
          .foregroundStyle(validation.isValid ? WorkspaceStyle.accent : .orange)
        Text(validation.isValid ? "Rubric is ready to review" : "Rubric needs attention")
          .font(.callout.weight(.semibold))
        Spacer(minLength: 4)
        if let maximum = validation.maximum {
          Text("Maximum \(maximum.decimalString) points")
            .font(.caption.monospaced())
            .foregroundStyle(WorkspaceStyle.secondary)
        }
      }
      if validation.issues.isEmpty {
        Text("Every part has criteria and every reference is associated with a valid part.")
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
      } else {
        ForEach(Array(validation.issues.enumerated()), id: \.offset) { _, issue in
          Label {
            Text("\(issue.path): \(issue.message)")
              .fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: "exclamationmark.circle")
          }
          .font(.caption)
          .foregroundStyle(.orange)
          .accessibilityElement(children: .combine)
        }
      }
    }
    .workspaceCard()
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      validation.isValid
        ? "Rubric is valid"
        : "Rubric has \(validation.issues.count) validation issues"
    )
  }

  private var partsCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Assignment parts")
            .font(.headline)
          Text("Parts define the review order and collect criteria and references.")
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 6)
        Button {
          addPart()
        } label: {
          Label("Add part", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .accessibilityLabel("Add assignment part")
      }
      if draft.parts.isEmpty {
        LiveRubricEmptyMessage(text: "No parts yet. Add one to begin a new assignment.")
      } else {
        ForEach(Array(draft.parts.enumerated()), id: \.element.id) { index, part in
          LiveRubricPartRow(
            part: part,
            canRemove: draft.parts.count > 1,
            canMoveUp: index > 0,
            canMoveDown: index < draft.parts.count - 1,
            onSave: { title in savePart(part.id, title: title) },
            onMoveUp: { movePart(part.id, by: -1) },
            onMoveDown: { movePart(part.id, by: 1) },
            onRemove: { removePart(part.id) }
          )
        }
      }
    }
    .workspaceCard()
  }

  private var criteriaCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Rubric criteria")
            .font(.headline)
          Text("Maximums accept up to two decimal places. Criteria are scored individually.")
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 6)
        Button {
          addCriterion()
        } label: {
          Label("Add criterion", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(draft.parts.isEmpty)
        .help(draft.parts.isEmpty ? "Add an assignment part first." : "Add a rubric criterion")
        .accessibilityLabel(
          draft.parts.isEmpty
            ? "Add criterion, disabled until a part exists" : "Add rubric criterion"
        )
      }
      if draft.parts.isEmpty {
        LiveRubricEmptyMessage(text: "Criteria become available after you add an assignment part.")
      } else {
        ForEach(draft.parts) { part in
          let criteria = draft.criteria.filter { $0.partID == part.id }
          VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
              Text(part.title.isEmpty ? "Untitled part" : part.title)
                .font(.caption.weight(.semibold))
              Spacer(minLength: 4)
              Text("\(criteria.count) \(criteria.count == 1 ? "criterion" : "criteria")")
                .font(.caption2.monospaced())
                .foregroundStyle(WorkspaceStyle.secondary)
            }
            if criteria.isEmpty {
              Text("No criteria assigned to this part.")
                .font(.caption)
                .foregroundStyle(WorkspaceStyle.secondary)
            } else {
              ForEach(criteria) { criterion in
                let globalIndex = draft.criteria.firstIndex(where: { $0.id == criterion.id }) ?? 0
                LiveRubricCriterionRow(
                  criterion: criterion,
                  parts: draft.parts,
                  canMoveUp: globalIndex > 0,
                  canMoveDown: globalIndex < draft.criteria.count - 1,
                  onSave: { title, guidance, maximumText in
                    saveCriterion(
                      criterion.id, title: title, guidance: guidance, maximumText: maximumText
                    )
                  },
                  onAssign: { partID in assignCriterion(criterion.id, to: partID) },
                  onMoveUp: { moveCriterion(criterion.id, by: -1) },
                  onMoveDown: { moveCriterion(criterion.id, by: 1) },
                  onRemove: { removeCriterion(criterion.id) }
                )
              }
            }
          }
          .padding(.top, 4)
        }
      }
    }
    .workspaceCard()
  }

  private var referencesCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("References")
            .font(.headline)
          Text("Attach answer keys, exemplars, or notes to an assignment part.")
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 6)
        if let part = draft.parts.first {
          Button {
            addReference(to: part.id)
          } label: {
            Label("Add reference", systemImage: "plus")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        }
      }
      if draft.parts.isEmpty {
        LiveRubricEmptyMessage(text: "Add an assignment part before adding a reference.")
      } else {
        ForEach(draft.parts) { part in
          VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
              Text(part.title.isEmpty ? "Untitled part" : part.title)
                .font(.caption.weight(.semibold))
              Spacer(minLength: 4)
              Button {
                onImportReference(part.id)
              } label: {
                Label("Import for part", systemImage: "square.and.arrow.down")
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .accessibilityLabel("Import reference for \(part.title)")
              Button {
                addReference(to: part.id)
              } label: {
                Image(systemName: "plus")
              }
              .buttonStyle(.borderless)
              .accessibilityLabel("Add reference for \(part.title)")
            }
            let references = draft.references.filter { $0.partID == part.id }
            if references.isEmpty {
              Text("No references attached to this part.")
                .font(.caption)
                .foregroundStyle(WorkspaceStyle.secondary)
            } else {
              ForEach(references) { reference in
                LiveRubricReferenceRow(
                  reference: reference,
                  onSave: { title, text in saveReference(reference.id, title: title, text: text) },
                  onRemove: { removeReference(reference.id) }
                )
              }
            }
          }
          .padding(.top, 4)
        }
      }
    }
    .workspaceCard()
  }

  private var jsonImportCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      DisclosureGroup(isExpanded: $isImportPanelExpanded) {
        VStack(alignment: .leading, spacing: 9) {
          Text(
            "Paste a schemaVersion 1 rubric JSON document or choose a .json file. Preview validates the complete replacement before anything changes."
          )
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
          TextEditor(text: $jsonText)
            .font(.caption.monospaced())
            .frame(minHeight: 150)
            .padding(5)
            .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkspaceStyle.border, lineWidth: 1))
            .accessibilityLabel("Rubric JSON input")
          HStack(spacing: 8) {
            Button {
              isJSONImporterPresented = true
            } label: {
              Label("Choose JSON file", systemImage: "doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
              previewJSON()
            } label: {
              Label("Preview JSON", systemImage: "checkmark.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button("Clear") {
              jsonText = ""
              importPreview = nil
              importError = nil
              importIssues = []
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
          }
          if let importError {
            LiveRubricError(text: importError)
          }
          if !importIssues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(Array(importIssues.enumerated()), id: \.offset) { _, issue in
                Label(issue, systemImage: "exclamationmark.circle")
                  .font(.caption)
                  .foregroundStyle(.orange)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Rubric JSON field errors")
          }
          if let preview = importPreview {
            importPreviewCard(preview)
          }
        }
        .padding(.top, 9)
      } label: {
        HStack(spacing: 7) {
          Image(systemName: "curlybraces")
            .foregroundStyle(WorkspaceStyle.accent)
          Text("Import rubric JSON")
            .font(.headline)
          Spacer(minLength: 4)
          LiveRubricBadge(text: "Preview before apply")
        }
      }
    }
    .workspaceCard()
  }

  private func importPreviewCard(_ preview: RubricImportPreview) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("Import preview")
          .font(.callout.weight(.semibold))
        Spacer(minLength: 5)
        Text(preview.validation.isValid ? "Valid" : "Needs attention")
          .font(.caption.weight(.semibold))
          .foregroundStyle(preview.validation.isValid ? WorkspaceStyle.accent : .orange)
      }
      Text(
        "\(preview.title) · \(preview.parts.count) parts · \(preview.criteria.count) criteria · \(preview.references.count) references"
      )
      .font(.caption.monospaced())
      .foregroundStyle(WorkspaceStyle.secondary)
      if preview.validation.issues.isEmpty {
        Text(
          "Applying replaces the rubric fields as one revision. Existing reviewed grades return to draft."
        )
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
        Button("Apply preview") {
          applyPreview(preview)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .accessibilityLabel("Apply valid rubric JSON preview")
      } else {
        ForEach(Array(preview.validation.issues.enumerated()), id: \.offset) { _, issue in
          Text("\(issue.path): \(issue.message)")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(11)
    .background(WorkspaceStyle.inset.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(WorkspaceStyle.border, lineWidth: 1))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Rubric JSON import preview")
  }

  private func saveDetails() {
    guard titleDraft != draft.title || courseDraft != draft.course else { return }
    applySemanticEdit { next in
      next.title = titleDraft
      next.course = courseDraft
    }
  }

  private func addPart() {
    applySemanticEdit { next in
      next.parts.append(WorkPart(title: "New part"))
    }
  }

  private func savePart(_ id: UUID, title: String) {
    guard let index = draft.parts.firstIndex(where: { $0.id == id }),
      draft.parts[index].title != title
    else {
      return
    }
    applySemanticEdit { next in
      guard let index = next.parts.firstIndex(where: { $0.id == id }) else { return }
      next.parts[index].title = title
    }
  }

  private func movePart(_ id: UUID, by offset: Int) {
    guard let index = draft.parts.firstIndex(where: { $0.id == id }) else { return }
    let destination = index + offset
    guard draft.parts.indices.contains(destination) else { return }
    applySemanticEdit { next in
      next.parts.swapAt(index, destination)
    }
  }

  private func removePart(_ id: UUID) {
    guard draft.parts.count > 1, draft.parts.contains(where: { $0.id == id }) else { return }
    applySemanticEdit { next in
      next.parts.removeAll { $0.id == id }
      next.criteria.removeAll { $0.partID == id }
      next.references.removeAll { $0.partID == id }
    }
  }

  private func addCriterion() {
    guard let partID = draft.parts.first?.id else { return }
    applySemanticEdit { next in
      next.criteria.append(
        WorkCriterion(
          partID: partID, title: "New criterion", guidance: "", maximum: PointValue(100))
      )
    }
  }

  private func saveCriterion(_ id: UUID, title: String, guidance: String, maximumText: String) {
    guard let maximum = try? PointValue.parse(maximumText), maximum.hundredths > 0 else { return }
    guard let index = draft.criteria.firstIndex(where: { $0.id == id }) else { return }
    let current = draft.criteria[index]
    guard current.title != title || current.guidance != guidance || current.maximum != maximum
    else {
      return
    }
    applySemanticEdit { next in
      guard let index = next.criteria.firstIndex(where: { $0.id == id }) else { return }
      next.criteria[index].title = title
      next.criteria[index].guidance = guidance
      next.criteria[index].maximum = maximum
    }
  }

  private func assignCriterion(_ id: UUID, to partID: UUID) {
    guard let index = draft.criteria.firstIndex(where: { $0.id == id }),
      draft.criteria[index].partID != partID
    else {
      return
    }
    applySemanticEdit { next in
      guard let index = next.criteria.firstIndex(where: { $0.id == id }) else { return }
      next.criteria[index].partID = partID
    }
  }

  private func moveCriterion(_ id: UUID, by offset: Int) {
    guard let index = draft.criteria.firstIndex(where: { $0.id == id }) else { return }
    let destination = index + offset
    guard draft.criteria.indices.contains(destination) else { return }
    applySemanticEdit { next in
      next.criteria.swapAt(index, destination)
    }
  }

  private func removeCriterion(_ id: UUID) {
    guard draft.criteria.count > 1 else {
      editMessage = "Keep at least one criterion in an assignment."
      return
    }
    applySemanticEdit { next in
      next.criteria.removeAll { $0.id == id }
    }
  }

  private func addReference(to partID: UUID) {
    applySemanticEdit { next in
      next.references.append(
        ReferenceMaterial(partID: partID, title: "New reference", text: "Reference text")
      )
    }
  }

  private func saveReference(_ id: UUID, title: String, text: String) {
    guard let index = draft.references.firstIndex(where: { $0.id == id }) else { return }
    guard draft.references[index].title != title || draft.references[index].text != text else {
      return
    }
    applySemanticEdit { next in
      guard let index = next.references.firstIndex(where: { $0.id == id }) else { return }
      next.references[index].title = title
      next.references[index].text = text
    }
  }

  private func removeReference(_ id: UUID) {
    applySemanticEdit { next in
      next.references.removeAll { $0.id == id }
    }
  }

  private func applySemanticEdit(_ mutation: (inout WorkAssignment) -> Void) {
    var next = draft
    mutation(&next)
    next.rubricRevisionID = UUID()
    importPreview = nil
    importError = nil
    importIssues = []
    editMessage = nil
    onAssignmentChange(next)
  }

  private func previewJSON() {
    do {
      importPreview = try RubricEngine.previewJSON(
        Data(jsonText.utf8), replacing: draft
      )
      importError = nil
      importIssues = []
    } catch let failure as RubricImportFailure {
      importPreview = nil
      switch failure {
      case .invalid(let issues):
        importError = "The rubric JSON has field errors."
        importIssues = issues.map { "\($0.path): \($0.message)" }
      default:
        importError = failure.localizedDescription
        importIssues = []
      }
    } catch {
      importPreview = nil
      importError = error.localizedDescription
      importIssues = []
    }
  }

  private func applyPreview(_ preview: RubricImportPreview) {
    var next = draft
    do {
      try RubricEngine.apply(preview, to: &next)
      importError = nil
      importIssues = []
      editMessage = "Rubric changes submitted for saving."
      onAssignmentChange(next)
    } catch {
      importError = error.localizedDescription
    }
  }

  private func loadJSONFile(_ result: Result<URL, Error>) {
    do {
      let url = try result.get()
      let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
      defer {
        if hasSecurityScopedAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }
      let data = try Data(contentsOf: url)
      jsonText = String(decoding: data, as: UTF8.self)
      importPreview = nil
      importError = nil
      importIssues = []
      isImportPanelExpanded = true
    } catch {
      importError = error.localizedDescription
      importIssues = []
    }
  }

  private func syncFromAssignment() {
    draft = assignment
    titleDraft = assignment.title
    courseDraft = assignment.course
    importPreview = nil
    importError = nil
    importIssues = []
    editMessage = nil
  }

  private func shortID(_ id: UUID) -> String {
    String(id.uuidString.prefix(8)).lowercased()
  }
}

private struct LiveRubricPartRow: View {
  let part: WorkPart
  let canRemove: Bool
  let canMoveUp: Bool
  let canMoveDown: Bool
  let onSave: (String) -> Void
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void
  let onRemove: () -> Void

  @State private var title: String

  init(
    part: WorkPart,
    canRemove: Bool,
    canMoveUp: Bool,
    canMoveDown: Bool,
    onSave: @escaping (String) -> Void,
    onMoveUp: @escaping () -> Void,
    onMoveDown: @escaping () -> Void,
    onRemove: @escaping () -> Void
  ) {
    self.part = part
    self.canRemove = canRemove
    self.canMoveUp = canMoveUp
    self.canMoveDown = canMoveDown
    self.onSave = onSave
    self.onMoveUp = onMoveUp
    self.onMoveDown = onMoveDown
    self.onRemove = onRemove
    _title = State(initialValue: part.title)
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: 7) {
      TextField("Part title", text: $title)
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Assignment part title")
      Button("Save") {
        onSave(title)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(title == part.title)
      .accessibilityLabel("Save part title")
      Divider().frame(height: 20)
      Button {
        onMoveUp()
      } label: {
        Image(systemName: "chevron.up")
      }
      .buttonStyle(.borderless)
      .disabled(!canMoveUp)
      .help(canMoveUp ? "Move part up" : "Part is first")
      .accessibilityLabel("Move \(part.title) up")
      Button {
        onMoveDown()
      } label: {
        Image(systemName: "chevron.down")
      }
      .buttonStyle(.borderless)
      .disabled(!canMoveDown)
      .help(canMoveDown ? "Move part down" : "Part is last")
      .accessibilityLabel("Move \(part.title) down")
      Button {
        onRemove()
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .disabled(!canRemove)
      .help(
        canRemove
          ? "Remove part and its criteria and references" : "An assignment needs at least one part"
      )
      .accessibilityLabel("Remove \(part.title)")
    }
    .padding(9)
    .background(WorkspaceStyle.inset.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkspaceStyle.border, lineWidth: 1))
  }
}

private struct LiveRubricCriterionRow: View {
  let criterion: WorkCriterion
  let parts: [WorkPart]
  let canMoveUp: Bool
  let canMoveDown: Bool
  let onSave: (String, String, String) -> Void
  let onAssign: (UUID) -> Void
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void
  let onRemove: () -> Void

  @State private var title: String
  @State private var guidance: String
  @State private var maximumText: String
  @State private var error: String?

  init(
    criterion: WorkCriterion,
    parts: [WorkPart],
    canMoveUp: Bool,
    canMoveDown: Bool,
    onSave: @escaping (String, String, String) -> Void,
    onAssign: @escaping (UUID) -> Void,
    onMoveUp: @escaping () -> Void,
    onMoveDown: @escaping () -> Void,
    onRemove: @escaping () -> Void
  ) {
    self.criterion = criterion
    self.parts = parts
    self.canMoveUp = canMoveUp
    self.canMoveDown = canMoveDown
    self.onSave = onSave
    self.onAssign = onAssign
    self.onMoveUp = onMoveUp
    self.onMoveDown = onMoveDown
    self.onRemove = onRemove
    _title = State(initialValue: criterion.title)
    _guidance = State(initialValue: criterion.guidance)
    _maximumText = State(initialValue: criterion.maximum.decimalString)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .bottom, spacing: 7) {
        TextField("Criterion title", text: $title)
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel("Criterion title")
        TextField("Max", text: $maximumText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 70)
          .multilineTextAlignment(.trailing)
          .accessibilityLabel("Maximum points for \(criterion.title)")
        Text("points")
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
        Button("Save") {
          guard let maximum = try? PointValue.parse(maximumText), maximum.hundredths > 0 else {
            error = "Use a positive point value with at most two decimal places."
            return
          }
          error = nil
          onSave(title, guidance, maximumText)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Save criterion")
      }
      HStack(alignment: .top, spacing: 7) {
        TextField("Performance guidance", text: $guidance, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(2...4)
          .accessibilityLabel("Performance guidance for \(criterion.title)")
        Picker("Assign criterion to part", selection: partBinding) {
          ForEach(parts) { part in
            Text(part.title.isEmpty ? "Untitled part" : part.title).tag(part.id)
          }
        }
        .labelsHidden()
        .frame(minWidth: 150)
        .accessibilityLabel("Part for \(criterion.title)")
      }
      HStack(spacing: 7) {
        if let error {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 4)
        Button {
          onMoveUp()
        } label: {
          Image(systemName: "chevron.up")
        }
        .buttonStyle(.borderless)
        .disabled(!canMoveUp)
        .accessibilityLabel("Move \(criterion.title) up")
        Button {
          onMoveDown()
        } label: {
          Image(systemName: "chevron.down")
        }
        .buttonStyle(.borderless)
        .disabled(!canMoveDown)
        .accessibilityLabel("Move \(criterion.title) down")
        Button {
          onRemove()
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Remove \(criterion.title)")
      }
    }
    .padding(9)
    .background(WorkspaceStyle.inset.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkspaceStyle.border, lineWidth: 1))
  }

  private var partBinding: Binding<UUID> {
    Binding(
      get: { criterion.partID },
      set: { onAssign($0) }
    )
  }
}

private struct LiveRubricReferenceRow: View {
  let reference: ReferenceMaterial
  let onSave: (String, String) -> Void
  let onRemove: () -> Void

  @State private var title: String
  @State private var text: String

  init(
    reference: ReferenceMaterial,
    onSave: @escaping (String, String) -> Void,
    onRemove: @escaping () -> Void
  ) {
    self.reference = reference
    self.onSave = onSave
    self.onRemove = onRemove
    _title = State(initialValue: reference.title)
    _text = State(initialValue: reference.text)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        TextField("Reference title", text: $title)
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel("Reference title")
        Button("Save") {
          onSave(title, text)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(title == reference.title && text == reference.text)
        Button {
          onRemove()
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Remove reference \(reference.title)")
      }
      TextEditor(text: $text)
        .font(.caption)
        .frame(minHeight: 60)
        .padding(4)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(WorkspaceStyle.border, lineWidth: 1))
        .accessibilityLabel("Reference text")
      Text("Reference text or a linked document is required.")
        .font(.caption2)
        .foregroundStyle(WorkspaceStyle.secondary)
    }
    .padding(9)
    .background(WorkspaceStyle.inset.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkspaceStyle.border, lineWidth: 1))
  }
}

private struct LiveRubricBadge: View {
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

private struct LiveRubricEmptyMessage: View {
  let text: String

  var body: some View {
    Label(text, systemImage: "tray")
      .font(.caption)
      .foregroundStyle(WorkspaceStyle.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct LiveRubricError: View {
  let text: String

  var body: some View {
    Label(text, systemImage: "exclamationmark.triangle")
      .font(.caption)
      .foregroundStyle(.red)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityElement(children: .combine)
  }
}
