import AppKit
import Foundation
import PDFKit
import WorkspaceKit

private struct WorkflowCheckFailure: Error, CustomStringConvertible {
  var description: String
}

@MainActor
func runWorkflowChecks() async throws {
  let explicitOutput = ProcessInfo.processInfo.environment["GRADING_ACCEPTANCE_OUTPUT"]
  let root =
    explicitOutput.map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.temporaryDirectory.appendingPathComponent("grading-workflow-\(UUID())")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { if explicitOutput == nil { try? FileManager.default.removeItem(at: root) } }
  let original = root.appendingPathComponent("Synthetic submission.pdf")
  try makeWorkflowPDF(at: original)
  let originalBytes = try Data(contentsOf: original)
  let repository = try WorkspaceRepository(rootURL: root.appendingPathComponent("Mac"))
  var workspace = try await repository.createWorkspace(title: "Synthetic acceptance")
  var assignment = WorkAssignment(title: "Algebra reasoning", course: "Synthetic mathematics")
  let part = WorkPart(title: "Explain the solution")
  assignment.parts = [part]
  let criterion = WorkCriterion(
    partID: part.id, title: "Reasoning", guidance: "Show a clear explanation",
    maximum: PointValue(1000))
  assignment.criteria = [criterion]
  assignment.references = [
    ReferenceMaterial(
      partID: part.id, title: "Answer key", text: "x = 3; subtract two, then divide by two.")
  ]
  var submission = WorkSubmission(candidateAlias: "Candidate SYN001")
  let inspection = try DocumentInspector.inspect(url: original)
  let asset = try await repository.storeAsset(
    from: original, typeIdentifier: inspection.typeIdentifier, containerID: workspace.containerID)
  let record = SourceDocumentRecord(
    originalName: original.lastPathComponent, asset: asset, pages: inspection.pages)
  submission.documents = [record]
  let input = DocumentInput(
    record: record, url: try await repository.assetURL(asset, containerID: workspace.containerID))
  let region = PageRegion(
    documentID: record.id, documentRevisionID: record.revisionID, pageID: record.pages[0].id,
    bounds: PageRectangle(x: 65, y: 540, width: 250, height: 55))
  submission.marks = [
    DocumentMark(region: region, kind: .highlight),
    DocumentMark(
      region: PageRegion(
        documentID: record.id, documentRevisionID: record.revisionID, pageID: record.pages[0].id,
        bounds: PageRectangle(x: 340, y: 460, width: 200, height: 70)), kind: .note,
      text: "Clear explanation."),
  ]
  submission.ocr = try await DocumentOCR.recognize(input: input, languages: ["en-US"])
  try require(!submission.ocr.blocks.isEmpty, "Synthetic text recognition returned no blocks")
  submission.ocr.blocks.append(TranscriptBlock(region: region, kind: .imageCrop))
  if let firstText = submission.ocr.blocks.firstIndex(where: { $0.kind == .text }) {
    submission.ocr.blocks[firstText].correction = "Teacher corrected synthetic text"
  }
  try GradingEngine.setScore(
    "8.75", criterionID: criterion.id, submission: &submission, assignment: assignment)
  try GradingEngine.setFeedback(
    "Clear reasoning; check the final units.", submission: &submission, assignment: assignment)
  try GradingEngine.transition(submission: &submission, to: .reviewed, assignment: assignment)
  try GradingEngine.transition(submission: &submission, to: .approved, assignment: assignment)
  assignment.submissions = [submission]
  workspace.assignments = [assignment]
  workspace.identities = [
    CandidateIdentity(candidateID: submission.candidateID, displayName: "Synthetic Student")
  ]
  workspace = try await repository.saveWorkspace(workspace, expectedRevision: workspace.revisionID)
  try WorkspaceIntegrity.validate(workspace)
  var invalid = workspace
  invalid.assignments[0].criteria.append(criterion)
  do {
    try WorkspaceIntegrity.validate(invalid)
    throw WorkflowCheckFailure(description: "Duplicate criterion IDs were accepted")
  } catch WorkspaceFailure.invalid {}
  invalid = workspace
  invalid.assignments[0].submissions[0].marks[0].region.documentRevisionID = UUID()
  do {
    try WorkspaceIntegrity.validate(invalid)
    throw WorkflowCheckFailure(description: "Stale source geometry was accepted")
  } catch WorkspaceFailure.invalid {}
  let snapshot = try GradeExportEngine.makeSnapshot(assignment: assignment)
  try require(
    snapshot.records.count == 1 && snapshot.records[0].total == PointValue(875),
    "Approved snapshot lost exact point values")
  let csv = try GradeExportEngine.csv(snapshot)
  try require(
    csv.contains("8.75") && !csv.contains("Synthetic Student"),
    "Default CSV must contain exact points without student name")
  try csv.write(
    to: root.appendingPathComponent("approved-grades.csv"), atomically: true, encoding: .utf8)
  try GradeExportEngine.json(snapshot).write(
    to: root.appendingPathComponent("approved-grades.json"))
  for flattened in [false, true] {
    let output = root.appendingPathComponent(flattened ? "flattened.pdf" : "editable.pdf")
    try DocumentPDFExporter.export(
      inputs: [input], marks: submission.marks, flattened: flattened, to: output)
    guard let pdf = PDFDocument(url: output), let page = pdf.page(at: 0) else {
      throw WorkflowCheckFailure(description: "Export PDF did not reopen")
    }
    try require(pdf.pageCount == 1, "Export changed page count")
    try require(
      flattened ? page.annotations.isEmpty : page.annotations.count == submission.marks.count,
      "Export annotation semantics incorrect")
    let inspected = try DocumentInspector.inspect(url: output)
    let exportedRecord = SourceDocumentRecord(
      originalName: output.lastPathComponent, asset: asset, pages: inspected.pages)
    let rendered = try DocumentRenderer.renderPage(
      input: DocumentInput(record: exportedRecord, url: output), pageID: exportedRecord.pages[0].id,
      scale: 1)
    let bitmap = NSBitmapImageRep(cgImage: rendered.image)
    try bitmap.representation(using: .png, properties: [:])?.write(
      to: output.deletingPathExtension().appendingPathExtension("png"))
  }
  try require(try Data(contentsOf: original) == originalBytes, "Original changed after export")
  let reopened = try WorkspaceRepository(rootURL: root.appendingPathComponent("Mac"))
  let reloaded = try await reopened.loadWorkspace(containerID: workspace.containerID)
  try require(reloaded == workspace, "Reopening changed saved workspace")
  let archive = root.appendingPathComponent("acceptance.gradingworkspace")
  _ = try await repository.exportWorkspace(containerID: workspace.containerID, destination: archive)
  let secondDevice = try WorkspaceRepository(
    rootURL: root.appendingPathComponent("iPad-simulation"))
  let imported = try await secondDevice.importWorkspace(from: archive)
  try require(
    imported.workspace.id == workspace.id
      && imported.workspace.containerID != workspace.containerID,
    "Transfer must preserve logical identity with new local container")
  try require(
    imported.workspace.assignments == workspace.assignments
      && imported.workspace.identities == workspace.identities,
    "Transfer lost marks, OCR, grades, or identities")
  let duplicate = try await secondDevice.importWorkspace(from: archive)
  try require(duplicate.wasDuplicate, "Same revision import was not recognized")
  var divergent = imported.workspace
  GradingEngine.invalidate(
    submission: &divergent.assignments[0].submissions[0],
    rubricRevisionID: assignment.rubricRevisionID, reason: "Synthetic equation crop moved")
  divergent.assignments[0].submissions[0].ocr.blocks[0].correction = "Changed after approval"
  divergent = try await secondDevice.saveWorkspace(
    divergent, expectedRevision: divergent.revisionID)
  let changedAssignment = divergent.assignments[0]
  try require(
    changedAssignment.submissions[0].status == .draft
      && changedAssignment.submissions[0].scores[criterion.id]?.confirmed == false,
    "Evidence edit did not invalidate approval and confirmation")
  do {
    try GradeExportEngine.validateCurrent(snapshot, against: changedAssignment)
    throw WorkflowCheckFailure(description: "Stale approved snapshot was accepted")
  } catch is GradeExportFailure {}
  do {
    _ = try await secondDevice.saveWorkspace(
      imported.workspace, expectedRevision: imported.workspace.revisionID)
    throw WorkflowCheckFailure(description: "Stale workspace write was accepted")
  } catch WorkspaceFailure.staleRevision {}
  let returnArchive = root.appendingPathComponent("continued.gradingworkspace")
  _ = try await secondDevice.exportWorkspace(
    containerID: divergent.containerID, destination: returnArchive)
  let returned = try await repository.importWorkspace(from: returnArchive)
  try require(
    returned.isSeparateCopy && !returned.wasDuplicate,
    "Divergent transfer must retain a separate copy")
  let untouched = try await repository.loadWorkspace(containerID: workspace.containerID)
  try require(untouched == workspace, "Divergent transfer replaced the active original")
  try require(try Data(contentsOf: original) == originalBytes, "Transfer changed source bytes")
}

@MainActor
private func makeWorkflowPDF(at url: URL) throws {
  var box = CGRect(x: 0, y: 0, width: 612, height: 792)
  guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
    throw WorkflowCheckFailure(description: "Cannot create synthetic PDF")
  }
  context.beginPDFPage(nil)
  context.setFillColor(NSColor.white.cgColor)
  context.fill(box)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black,
  ]
  for (line, y) in [
    ("SYNTHETIC STUDENT - DEVELOPMENT ONLY", 710.0), ("Explain how to solve the equation.", 650),
    ("2x + 2 = 8", 560), ("Subtract two from both sides, then divide by two.", 490),
    ("Therefore x = 3.", 430),
  ] {
    line.draw(at: CGPoint(x: 65, y: y), withAttributes: attributes)
  }
  NSGraphicsContext.restoreGraphicsState()
  context.endPDFPage()
  context.closePDF()
}
private func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  guard try condition() else { throw WorkflowCheckFailure(description: message) }
}
