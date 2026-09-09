import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class LiveWorkspaceStore {
  private(set) var workspace: WorkspaceData?
  private(set) var summaries: [WorkspaceSummary] = []
  private(set) var inputs: [DocumentInput] = []
  private(set) var referenceInputs: [DocumentInput] = []
  private(set) var isBusy = false
  private(set) var busyMessage = ""
  var errorMessage: String?
  var notice: String?
  var assignmentID: UUID?
  var submissionID: UUID?
  var documentID: UUID?
  var focusedRegion: PageRegion?
  var masksEnabled = false
  var appearance: WorkspaceAppearance = .system
  var ocrLanguages: [String] = ["en-US"]
  var supportedOCRLanguages: [String] = []
  var isRecognizing = false
  var isExporting = false
  private var repository: WorkspaceRepository?
  private var ocrTask: Task<Void, Never>?
  private var operationWaiters: [CheckedContinuation<Void, Never>] = []
  private var markUndo: [[DocumentMark]] = []

  var assignment: WorkAssignment? { workspace?.assignments.first { $0.id == assignmentID } }
  var submission: WorkSubmission? { assignment?.submissions.first { $0.id == submissionID } }
  var selectedInput: DocumentInput? { inputs.first { $0.record.id == documentID } ?? inputs.first }
  var candidateNames: [UUID: String] {
    Dictionary(
      (workspace?.identities ?? []).map { ($0.candidateID, $0.displayName) },
      uniquingKeysWith: { a, _ in a })
  }
  var canUndoMark: Bool { !markUndo.isEmpty }

  func start() async {
    guard repository == nil else { return }
    do {
      let root: URL
      if let override = ProcessInfo.processInfo.environment["GRADING_WORKSPACE_ROOT"] {
        root = URL(fileURLWithPath: override, isDirectory: true)
      } else {
        root = try FileManager.default.url(
          for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent("GradingWorkspace", isDirectory: true)
      }
      repository = try WorkspaceRepository(rootURL: root)
      try await reloadSummaries()
      supportedOCRLanguages = try DocumentOCR.supportedLanguages()
    } catch { report(error) }
  }

  func selectWorkspace(_ containerID: UUID) async {
    guard !isBusy, let repository else { return }
    await operation("Opening workspace") {
      self.workspace = try await repository.loadWorkspace(containerID: containerID)
      self.assignmentID = self.workspace?.assignments.first?.id
      self.submissionID = self.assignment?.submissions.first?.id
      self.markUndo = []
      try await self.refreshInputs()
    }
  }

  func createWorkspace(_ title: String) async {
    guard let repository else { return }
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    await operation("Creating workspace") {
      self.workspace = try await repository.createWorkspace(title: title)
      self.assignmentID = nil
      self.submissionID = nil
      self.inputs = []
      self.referenceInputs = []
      try await self.reloadSummaries()
    }
  }

  func selectAssignment(_ id: UUID) async {
    guard !isBusy else { return }
    assignmentID = id
    submissionID = assignment?.submissions.first?.id
    documentID = nil
    focusedRegion = nil
    markUndo = []
    do { try await refreshInputs() } catch { report(error) }
  }

  func selectSubmission(_ id: UUID) async {
    guard !isBusy else { return }
    submissionID = id
    documentID = nil
    focusedRegion = nil
    markUndo = []
    do { try await refreshInputs() } catch { report(error) }
  }

  func createAssignment(title: String, course: String) async {
    await edit("Creating assignment") { data in
      let value = WorkAssignment(
        title: title.trimmingCharacters(in: .whitespacesAndNewlines), course: course)
      guard !value.title.isEmpty else {
        throw WorkspaceFailure.invalid("Enter an assignment title.")
      }
      data.assignments.append(value)
      self.assignmentID = value.id
      self.submissionID = nil
    }
  }

  func createCandidate(name: String) async {
    guard let assignmentID else { return }
    await edit("Creating candidate") { data in
      guard let index = data.assignments.firstIndex(where: { $0.id == assignmentID }) else {
        throw WorkspaceFailure.staleRevision
      }
      let candidate = WorkSubmission(candidateAlias: "Candidate \(UUID().uuidString.prefix(6))")
      data.assignments[index].submissions.append(candidate)
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        data.identities.append(
          CandidateIdentity(candidateID: candidate.candidateID, displayName: trimmed))
      }
      self.submissionID = candidate.id
    }
  }

  func saveAssignment(_ updated: WorkAssignment, expectedRubricRevision: UUID) async {
    await edit("Saving rubric") { data in
      guard let index = data.assignments.firstIndex(where: { $0.id == updated.id }),
        data.assignments[index].rubricRevisionID == expectedRubricRevision
      else { throw WorkspaceFailure.staleRevision }
      let validation = RubricEngine.validateRubric(updated)
      guard validation.isValid else {
        throw WorkspaceFailure.invalid(validation.issues.first?.message ?? "Invalid rubric.")
      }
      var value = updated
      value.submissions = data.assignments[index].submissions
      value.rubricRevisionID = UUID()
      let validCriteria = Set(value.criteria.map(\.id))
      for i in value.submissions.indices {
        value.submissions[i].scores = value.submissions[i].scores.filter {
          validCriteria.contains($0.key)
        }
        GradingEngine.invalidate(
          submission: &value.submissions[i], rubricRevisionID: value.rubricRevisionID,
          reason: "Rubric or reference changed")
      }
      data.assignments[index] = value
    }
  }

  func saveSubmission(_ updated: WorkSubmission, expectedReviewRevision: UUID) async {
    guard let assignmentID else { return }
    await edit("Saving review") { data in
      guard let a = data.assignments.firstIndex(where: { $0.id == assignmentID }),
        let s = data.assignments[a].submissions.firstIndex(where: { $0.id == updated.id }),
        data.assignments[a].submissions[s].reviewRevisionID == expectedReviewRevision
      else { throw WorkspaceFailure.staleRevision }
      data.assignments[a].submissions[s] = updated
    }
  }

  func importDocuments(_ urls: [URL], referencePartID: UUID? = nil) async {
    guard !isExporting, let repository, let base = workspace, let assignmentID else { return }
    let selectedSubmissionID = submissionID
    await operation("Validating and copying documents") {
      // Validate the complete batch before copying any bytes into the workspace.
      for url in urls {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        _ = try DocumentInspector.inspect(url: url)
      }
      var imported: [SourceDocumentRecord] = []
      for url in urls {
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let inspection = try DocumentInspector.inspect(url: url)
        let asset = try await repository.storeAsset(
          from: url, typeIdentifier: inspection.typeIdentifier, containerID: base.containerID)
        imported.append(
          SourceDocumentRecord(
            originalName: url.lastPathComponent, asset: asset, pages: inspection.pages))
      }
      var changed = base
      guard let a = changed.assignments.firstIndex(where: { $0.id == assignmentID }) else {
        throw WorkspaceFailure.staleRevision
      }
      if let partID = referencePartID {
        guard changed.assignments[a].parts.contains(where: { $0.id == partID }) else {
          throw WorkspaceFailure.invalid("Choose a valid assignment part.")
        }
        for item in imported {
          changed.assignments[a].references.append(
            ReferenceMaterial(partID: partID, title: item.originalName, document: item))
        }
        changed.assignments[a].rubricRevisionID = UUID()
        let revision = changed.assignments[a].rubricRevisionID
        for s in changed.assignments[a].submissions.indices {
          GradingEngine.invalidate(
            submission: &changed.assignments[a].submissions[s], rubricRevisionID: revision,
            reason: "Reference document imported")
        }
      } else {
        guard
          let s = changed.assignments[a].submissions.firstIndex(where: {
            $0.id == selectedSubmissionID
          })
        else { throw WorkspaceFailure.invalid("Choose a candidate before importing documents.") }
        let existing = Set(changed.assignments[a].submissions[s].documents.map { $0.asset.sha256 })
        var seen = existing
        let unique = imported.filter { seen.insert($0.asset.sha256).inserted }
        guard !unique.isEmpty else {
          self.notice = "These documents are already attached to this candidate."
          return
        }
        changed.assignments[a].submissions[s].documents += unique
        GradingEngine.invalidate(
          submission: &changed.assignments[a].submissions[s],
          rubricRevisionID: changed.assignments[a].rubricRevisionID,
          reason: "Submission document imported")
      }
      self.workspace = try await repository.saveWorkspace(
        changed, expectedRevision: base.revisionID)
      try await self.refreshInputs()
      try await self.reloadSummaries()
    }
  }

  func addMark(_ mark: DocumentMark) async {
    let prior = submission?.marks ?? []
    await editSubmissionEvidence("Saving annotation") { submission in submission.marks.append(mark)
    }
    if errorMessage == nil { markUndo.append(prior) }
  }
  func removeMark(_ id: UUID) async {
    let prior = submission?.marks ?? []
    await editSubmissionEvidence("Removing annotation") { $0.marks.removeAll { $0.id == id } }
    if errorMessage == nil { markUndo.append(prior) }
  }
  func undoMark() async {
    guard let previous = markUndo.last else { return }
    await editSubmissionEvidence("Undoing annotation") { $0.marks = previous }
    if errorMessage == nil { markUndo.removeLast() }
  }
  func addCrop(_ region: PageRegion) async {
    await editSubmissionEvidence("Saving equation crop") { value in
      value.ocr.blocks.removeAll { block in
        guard block.kind == .text, block.region.pageID == region.pageID else { return false }
        let a = region.bounds
        let b = block.region.bounds
        return b.x >= a.x && b.y >= a.y && b.x + b.width <= a.x + a.width
          && b.y + b.height <= a.y + a.height
      }
      value.ocr.blocks.append(TranscriptBlock(region: region, kind: .imageCrop))
      value.ocr.blocks = Self.sourceOrdered(value.ocr.blocks, documents: value.documents)
      value.ocr.revisionID = UUID()
    }
  }
  func saveBlocks(_ blocks: [TranscriptBlock]) async {
    await editSubmissionEvidence("Saving transcription") { value in
      value.ocr.blocks = blocks
      value.ocr.revisionID = UUID()
    }
  }
  func focus(_ region: PageRegion) {
    documentID = region.documentID
    focusedRegion = region
  }

  func recognize() {
    guard !isRecognizing, !inputs.isEmpty, let current = submission, let assignmentID else {
      return
    }
    let documentInputs = inputs
    let languages = ocrLanguages
    let expectedReview = current.reviewRevisionID
    isRecognizing = true
    ocrTask = Task {
      defer {
        isRecognizing = false
        ocrTask = nil
      }
      do {
        var result = OCRRecord()
        result.languages = languages
        for input in documentInputs {
          try Task.checkCancellation()
          let pageResult = try await DocumentOCR.recognize(input: input, languages: languages)
          result.requestRevision = pageResult.requestRevision
          result.blocks += pageResult.blocks
        }
        try Task.checkCancellation()
        guard self.assignmentID == assignmentID, self.submission?.id == current.id,
          self.submission?.reviewRevisionID == expectedReview
        else { throw WorkspaceFailure.staleRevision }
        let preserved = current.ocr.blocks.filter { $0.kind == .imageCrop || $0.correction != nil }
        result.blocks.removeAll { candidate in
          preserved.contains { previous in
            guard previous.region.documentRevisionID == candidate.region.documentRevisionID,
              previous.region.pageID == candidate.region.pageID
            else { return false }
            let a = previous.region.bounds
            let b = candidate.region.bounds
            let overlap =
              max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
              * max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
            return overlap >= min(a.width * a.height, b.width * b.height) * 0.5
          }
        }
        result.blocks += preserved
        result.blocks = Self.sourceOrdered(result.blocks, documents: current.documents)
        let replacement = result
        await editSubmissionEvidence("Saving recognition", expectedReviewRevision: expectedReview) {
          guard $0.id == current.id else { throw WorkspaceFailure.staleRevision }
          $0.ocr = replacement
        }
        if replacement.blocks.isEmpty {
          notice =
            "No text was recognized. You can still add equation crops and grade the original."
        }
      } catch is CancellationError {
        notice = "Recognition cancelled; saved transcription was preserved."
      } catch { report(error) }
    }
  }
  func cancelRecognition() { ocrTask?.cancel() }

  func prepareGradeExport(options: GradeExportOptions, snapshot: GradeExportSnapshot) async -> URL?
  {
    guard let repository, let base = workspace else { return nil }
    var output: URL?
    await operation("Preparing approved exports") {
      guard let assignment = base.assignments.first(where: { $0.id == snapshot.assignmentID })
      else { throw GradeExportFailure.staleSnapshot }
      try GradeExportEngine.validateCurrent(snapshot, against: assignment)
      guard !snapshot.records.isEmpty, !options.formats.isEmpty else {
        throw GradeExportFailure.noApprovedGrades
      }
      let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
        "grading-export-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      do {
        if options.formats.contains(.csv) {
          try GradeExportEngine.csv(snapshot).write(
            to: destination.appendingPathComponent("approved-grades.csv"), atomically: true,
            encoding: .utf8)
        }
        if options.formats.contains(.json) {
          try GradeExportEngine.json(snapshot).write(
            to: destination.appendingPathComponent("approved-grades.json"), options: .atomic)
        }
        for record in snapshot.records {
          guard
            let submission = assignment.submissions.first(where: { $0.id == record.submissionID })
          else { throw GradeExportFailure.staleSnapshot }
          var inputs: [DocumentInput] = []
          for source in submission.documents {
            inputs.append(
              DocumentInput(
                record: source,
                url: try await repository.assetURL(source.asset, containerID: base.containerID)))
          }
          for flattened in [false, true] {
            let format: GradeExportFormat = flattened ? .flattenedPDF : .editablePDF
            if options.formats.contains(format) {
              let name =
                "candidate-\(submission.candidateID.uuidString.prefix(8))-\(flattened ? "flattened" : "editable").pdf"
              let exportInputs = inputs
              let marks = submission.marks
              let target = destination.appendingPathComponent(name)
              try await Task.detached {
                try DocumentPDFExporter.export(
                  inputs: exportInputs, marks: marks, flattened: flattened, to: target)
              }.value
            }
          }
        }
        let current = try await repository.loadWorkspace(containerID: base.containerID)
        guard let currentAssignment = current.assignments.first(where: { $0.id == assignment.id })
        else { throw GradeExportFailure.staleSnapshot }
        try GradeExportEngine.validateCurrent(snapshot, against: currentAssignment)
        self.isExporting = true
        output = destination
      } catch {
        try? FileManager.default.removeItem(at: destination)
        throw error
      }
    }
    return output
  }

  func exportArchive(to destination: URL) async {
    guard let repository, let workspace else { return }
    await operation("Creating workspace archive") {
      _ = try await repository.exportWorkspace(
        containerID: workspace.containerID, destination: destination)
      self.notice = "Workspace archive created. It contains originals and identity mappings."
    }
  }
  func importArchive(from url: URL) async {
    guard let repository else { return }
    await operation("Checking workspace archive") {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let result = try await repository.importWorkspace(from: url)
      try await self.reloadSummaries()
      self.notice =
        result.wasDuplicate
        ? "This workspace revision is already available."
        : result.isSeparateCopy
          ? "Imported as a separate copy. Your current workspace is unchanged; choose a workspace to open it."
          : "Workspace imported. Choose it from the workspace list."
    }
  }

  private func editSubmissionEvidence(
    _ message: String, expectedReviewRevision: UUID? = nil,
    change: (inout WorkSubmission) throws -> Void
  ) async {
    guard let assignmentID, let submissionID else { return }
    await edit(message) { data in
      guard let a = data.assignments.firstIndex(where: { $0.id == assignmentID }),
        let s = data.assignments[a].submissions.firstIndex(where: { $0.id == submissionID })
      else { throw WorkspaceFailure.staleRevision }
      if let expectedReviewRevision,
        data.assignments[a].submissions[s].reviewRevisionID != expectedReviewRevision
      {
        throw WorkspaceFailure.staleRevision
      }
      let revision = data.assignments[a].rubricRevisionID
      GradingEngine.invalidate(
        submission: &data.assignments[a].submissions[s], rubricRevisionID: revision, reason: message
      )
      try change(&data.assignments[a].submissions[s])
    }
  }
  private func edit(_ message: String, change: (inout WorkspaceData) throws -> Void) async {
    guard let repository else { return }
    guard !isExporting else {
      errorMessage = "Finish or cancel the export before editing this workspace."
      return
    }
    await operation(message) {
      guard let current = self.workspace else {
        throw WorkspaceFailure.unavailable("Open a workspace first.")
      }
      var changed = current
      try change(&changed)
      self.workspace = try await repository.saveWorkspace(
        changed, expectedRevision: current.revisionID)
      try await self.refreshInputs()
      try await self.reloadSummaries()
    }
  }
  private func operation(_ message: String, body: () async throws -> Void) async {
    if isBusy { await withCheckedContinuation { operationWaiters.append($0) } }
    isBusy = true
    busyMessage = message
    errorMessage = nil
    notice = nil
    defer {
      if operationWaiters.isEmpty {
        isBusy = false
        busyMessage = ""
      } else {
        operationWaiters.removeFirst().resume()
      }
    }
    do {
      try Task.checkCancellation()
      try await body()
    } catch { report(error) }
  }
  private func reloadSummaries() async throws {
    guard let repository else { return }
    summaries = try await repository.listWorkspaces()
  }
  private func refreshInputs() async throws {
    guard let repository, let workspace else {
      inputs = []
      referenceInputs = []
      return
    }
    inputs = []
    referenceInputs = []
    var next: [DocumentInput] = []
    for record in submission?.documents ?? [] {
      let url = try await repository.assetURL(record.asset, containerID: workspace.containerID)
      next.append(DocumentInput(record: record, url: url))
    }
    inputs = next
    if !next.contains(where: { $0.record.id == documentID }) { documentID = next.first?.record.id }
    var refs: [DocumentInput] = []
    for record in assignment?.references.compactMap(\.document) ?? [] {
      refs.append(
        DocumentInput(
          record: record,
          url: try await repository.assetURL(record.asset, containerID: workspace.containerID)))
    }
    referenceInputs = refs
  }
  private static func sourceOrdered(_ blocks: [TranscriptBlock], documents: [SourceDocumentRecord])
    -> [TranscriptBlock]
  {
    blocks.sorted { left, right in
      let ld = documents.firstIndex { $0.id == left.region.documentID } ?? Int.max
      let rd = documents.firstIndex { $0.id == right.region.documentID } ?? Int.max
      if ld != rd { return ld < rd }
      let pages = ld < documents.count ? documents[ld].pages : []
      let lp = pages.firstIndex { $0.id == left.region.pageID } ?? Int.max
      let rp = pages.firstIndex { $0.id == right.region.pageID } ?? Int.max
      if lp != rp { return lp < rp }
      let ly = left.region.bounds.y + left.region.bounds.height
      let ry = right.region.bounds.y + right.region.bounds.height
      if ly != ry { return ly > ry }
      return left.region.bounds.x < right.region.bounds.x
    }
  }
  private func report(_ error: Error) { errorMessage = error.localizedDescription }
}
