import Foundation
import WorkspaceKit

private struct GradingCheckFailure: Error, CustomStringConvertible {
  var description: String
}

private func gradingExpect(
  _ condition: @autoclosure () throws -> Bool, _ message: String,
  file: StaticString = #filePath, line: UInt = #line
) throws {
  guard try condition() else {
    throw GradingCheckFailure(description: "\(file):\(line): \(message)")
  }
}

public func runGradingChecks() throws {
  try exactPointParsingCheck()
  try rubricValidationAndAtomicImportCheck()
  try gradingLifecycleAndInvalidationCheck()
  try statisticsCohortAndBoundaryCheck()
  try approvedExportCheck()
}

private func exactPointParsingCheck() throws {
  try gradingExpect(try PointValue.parse("0").hundredths == 0, "zero should parse")
  try gradingExpect(try PointValue.parse(" 12.3 ").hundredths == 1_230, "tenths should parse")
  try gradingExpect(try PointValue.parse(".5").hundredths == 50, "leading decimal should parse")
  try gradingExpect(
    try PointValue.parse("-0.01").hundredths == -1, "signed values should parse exactly")
  do {
    _ = try PointValue.parse("1.001")
    throw GradingCheckFailure(description: "values with three decimal places must fail")
  } catch PointValueParseFailure.tooManyDecimalPlaces {}
  do {
    _ = try PointValue.parse("999999999999999999999")
    throw GradingCheckFailure(description: "overflowing values must fail")
  } catch PointValueParseFailure.overflow {}
}

private func rubricValidationAndAtomicImportCheck() throws {
  var assignment = makeAssignment()
  try gradingExpect(
    RubricEngine.validateRubric(assignment).maximum == PointValue(1_000),
    "rubric maximum should equal criterion maxima"
  )

  let original = assignment
  let invalid = """
    {"schemaVersion":1,"title":"Imported","course":"Math","parts":[],"criteria":[],"references":[]}
    """.data(using: .utf8)!
  do {
    _ = try RubricEngine.previewJSON(invalid, replacing: assignment)
    throw GradingCheckFailure(description: "invalid import should fail preview")
  } catch RubricImportFailure.invalid {}
  try gradingExpect(assignment == original, "failed preview must not mutate its assignment")

  let partID = UUID()
  let criterionID = UUID()
  let valid = """
    {
      "schemaVersion": 1,
      "title": "Imported",
      "course": "Math",
      "parts": [{"id":"\(partID)","title":"Part A"}],
      "criteria": [{
        "id":"\(criterionID)","partID":"\(partID)","title":"Reasoning",
        "guidance":"Show work","maximumPoints":"2.25"
      }],
      "references": [{
        "id":"\(UUID())","partID":"\(partID)","title":"Key","text":"Expected reasoning"
      }]
    }
    """.data(using: .utf8)!
  let preview = try RubricEngine.previewJSON(valid, replacing: assignment)
  try RubricEngine.apply(preview, to: &assignment)
  try gradingExpect(assignment.title == "Imported", "valid import should apply")
  try gradingExpect(
    assignment.criteria[0].maximum == PointValue(225), "import points must remain exact")
  try gradingExpect(
    assignment.submissions[0].status == .draft, "rubric import should invalidate approval")
}

private func gradingLifecycleAndInvalidationCheck() throws {
  let assignment = makeAssignment()
  let firstID = assignment.criteria[0].id
  let secondID = assignment.criteria[1].id
  var submission = assignment.submissions[0]

  let initialRevision = submission.reviewRevisionID
  do {
    try GradingEngine.setScore(
      "5.01", criterionID: firstID, submission: &submission, assignment: assignment
    )
    throw GradingCheckFailure(description: "scores above a criterion maximum must fail")
  } catch GradingFailure.scoreOutOfRange {}
  try gradingExpect(
    submission.reviewRevisionID == initialRevision,
    "a rejected score must not create a review revision"
  )
  try GradingEngine.setScore(
    "0", criterionID: firstID, submission: &submission, assignment: assignment,
    expectedReviewRevisionID: submission.reviewRevisionID
  )
  try gradingExpect(
    submission.scores[firstID]?.value == PointValue(0), "explicit zero must be stored")
  try GradingEngine.setScore(
    "4.25", criterionID: firstID, submission: &submission, assignment: assignment)
  try GradingEngine.setScore(
    "5", criterionID: secondID, submission: &submission, assignment: assignment)
  try GradingEngine.setFeedback("Clear work", submission: &submission, assignment: assignment)
  try gradingExpect(
    try GradingEngine.total(submission: submission, assignment: assignment) == PointValue(925),
    "total must derive from exact criterion values"
  )
  try GradingEngine.transition(submission: &submission, to: .reviewed, assignment: assignment)
  try GradingEngine.transition(submission: &submission, to: .approved, assignment: assignment)
  try gradingExpect(
    submission.approvedReviewRevisionID == submission.reviewRevisionID,
    "approval must pin the exact review revision"
  )

  let staleRevision = submission.reviewRevisionID
  GradingEngine.invalidate(
    submission: &submission, rubricRevisionID: assignment.rubricRevisionID,
    reason: "Document changed."
  )
  try gradingExpect(submission.status == .draft, "evidence change should return grade to draft")
  try gradingExpect(
    submission.scores.values.allSatisfy { !$0.confirmed },
    "matching scores should remain but require confirmation"
  )
  try gradingExpect(
    submission.history.contains(where: { $0.status == .approved }),
    "invalidation must retain the immutable approved history entry"
  )
  do {
    try GradingEngine.setFeedback(
      "Stale", submission: &submission, assignment: assignment,
      expectedReviewRevisionID: staleRevision
    )
    throw GradingCheckFailure(description: "stale edits must fail")
  } catch WorkspaceFailure.staleRevision {}
  try GradingEngine.confirmScore(
    criterionID: firstID, submission: &submission, assignment: assignment
  )
  try GradingEngine.confirmScore(
    criterionID: secondID, submission: &submission, assignment: assignment
  )
  try GradingEngine.transition(submission: &submission, to: .reviewed, assignment: assignment)
}

private func statisticsCohortAndBoundaryCheck() throws {
  var assignment = makeAssignment()
  let empty = try StatisticsEngine.snapshot(assignment: assignment)
  try gradingExpect(empty.includedCount == 0, "an empty approved cohort should have n zero")
  try gradingExpect(empty.mean == nil && empty.bins.isEmpty, "empty metrics must be unavailable")
  for index in assignment.submissions.indices {
    let criterionIDs = assignment.criteria.map(\.id)
    try GradingEngine.setScore(
      index == 0 ? "0" : "5", criterionID: criterionIDs[0],
      submission: &assignment.submissions[index], assignment: assignment
    )
    try GradingEngine.setScore(
      "5", criterionID: criterionIDs[1], submission: &assignment.submissions[index],
      assignment: assignment
    )
  }
  try GradingEngine.transition(
    submission: &assignment.submissions[0], to: .reviewed, assignment: assignment
  )
  try GradingEngine.transition(
    submission: &assignment.submissions[0], to: .approved, assignment: assignment
  )

  let approved = try StatisticsEngine.snapshot(assignment: assignment)
  try gradingExpect(approved.includedCount == 1, "approved cohort should exclude drafts")
  try gradingExpect(
    approved.scores[0] == PointValue(500), "explicit zero criterion remains in total")
  try gradingExpect(approved.bins.count == 10, "nonempty distributions use ten bins")
  try gradingExpect(approved.bins.map(\.count).reduce(0, +) == 1, "each score belongs to one bin")

  let drafts = try StatisticsEngine.snapshot(
    assignment: assignment, cohort: .draftAndReviewed
  )
  try gradingExpect(drafts.includedCount == 1, "complete draft cohort should remain separate")
  try gradingExpect(drafts.bins.last?.count == 1, "maximum score must be included in final bin")
  try gradingExpect(drafts.populationStandardDeviation == 0, "one-score population SD is zero")
  try gradingExpect(drafts.modes.isEmpty, "one score does not create a repeated mode")

  for _ in 0..<2 {
    var next = assignment.submissions[1]
    next.id = UUID()
    next.candidateID = UUID()
    next.reviewRevisionID = UUID()
    next.scores = [:]
    next.feedback = ""
    next.status = .draft
    next.approvedReviewRevisionID = nil
    next.approvedRubricRevisionID = nil
    next.history = []
    assignment.submissions.append(next)
    let index = assignment.submissions.count - 1
    try GradingEngine.setScore(
      "5", criterionID: assignment.criteria[0].id,
      submission: &assignment.submissions[index], assignment: assignment
    )
    try GradingEngine.setScore(
      "5", criterionID: assignment.criteria[1].id,
      submission: &assignment.submissions[index], assignment: assignment
    )
    try GradingEngine.transition(
      submission: &assignment.submissions[index], to: .reviewed, assignment: assignment
    )
    try GradingEngine.transition(
      submission: &assignment.submissions[index], to: .approved, assignment: assignment
    )
  }
  let repeated = try StatisticsEngine.snapshot(assignment: assignment)
  try gradingExpect(
    repeated.includedCount == 3, "approved statistics include one current grade each")
  try gradingExpect(repeated.modes == [PointValue(1_000)], "repeated tied modes use exact totals")
  try gradingExpect(repeated.bins.last?.count == 2, "the final bin includes every maximum score")
}

private func approvedExportCheck() throws {
  var assignment = makeAssignment()
  let criterionIDs = assignment.criteria.map(\.id)
  try GradingEngine.setScore(
    "5", criterionID: criterionIDs[0], submission: &assignment.submissions[0],
    assignment: assignment
  )
  try GradingEngine.setScore(
    "5", criterionID: criterionIDs[1], submission: &assignment.submissions[0],
    assignment: assignment
  )
  try GradingEngine.setFeedback(
    "\t@HYPERLINK(\"unsafe\")", submission: &assignment.submissions[0],
    assignment: assignment
  )
  try GradingEngine.transition(
    submission: &assignment.submissions[0], to: .reviewed, assignment: assignment
  )
  try GradingEngine.transition(
    submission: &assignment.submissions[0], to: .approved, assignment: assignment
  )

  let snapshot = try GradeExportEngine.makeSnapshot(
    assignment: assignment,
    identities: [assignment.submissions[0].candidateID: "\n=Student"],
    includeIdentities: true, generatedAt: Date(timeIntervalSince1970: 0)
  )
  try gradingExpect(snapshot.records.count == 1, "only the approved submission should export")
  let csv = try GradeExportEngine.csv(snapshot)
  try gradingExpect(csv.contains("\"'\n=Student\""), "identified names must be formula-safe")
  try gradingExpect(csv.contains("\"'\t@HYPERLINK"), "feedback must be formula-safe")
  let json = try GradeExportEngine.json(snapshot)
  let jsonText = String(decoding: json, as: UTF8.self)
  try gradingExpect(jsonText.contains("\"10\""), "JSON totals must be exact decimal strings")
  try gradingExpect(jsonText.contains("documentRevisions"), "JSON must identify document revisions")
  try gradingExpect(jsonText.contains("ocrRevisionID"), "JSON must identify the OCR revision")
  try GradeExportEngine.validateCurrent(
    snapshot, against: assignment,
    identities: [assignment.submissions[0].candidateID: "\n=Student"]
  )

  let record = snapshot.records[0]
  let malformedRecord = ApprovedGradeExportRecord(
    submissionID: record.submissionID, candidateID: record.candidateID,
    candidateAlias: record.candidateAlias, identifiedName: record.identifiedName,
    reviewRevisionID: record.reviewRevisionID, scores: [:], total: record.total,
    feedback: record.feedback, documentRevisions: record.documentRevisions,
    ocrRevisionID: record.ocrRevisionID, markIDs: record.markIDs
  )
  let malformedSnapshot = GradeExportSnapshot(
    generatedAt: snapshot.generatedAt, assignmentID: snapshot.assignmentID,
    assignmentTitle: snapshot.assignmentTitle,
    rubricRevisionID: snapshot.rubricRevisionID, criteria: snapshot.criteria,
    records: [malformedRecord], preflight: snapshot.preflight,
    includesIdentities: snapshot.includesIdentities
  )
  do {
    _ = try GradeExportEngine.json(malformedSnapshot)
    throw GradingCheckFailure(description: "malformed snapshots must fail safely")
  } catch GradeExportFailure.invalidSnapshot {}

  let alteredRecord = ApprovedGradeExportRecord(
    submissionID: record.submissionID, candidateID: record.candidateID,
    candidateAlias: record.candidateAlias, identifiedName: record.identifiedName,
    reviewRevisionID: record.reviewRevisionID, scores: record.scores,
    total: record.total, feedback: "Altered", documentRevisions: record.documentRevisions,
    ocrRevisionID: record.ocrRevisionID, markIDs: record.markIDs
  )
  let alteredSnapshot = GradeExportSnapshot(
    generatedAt: snapshot.generatedAt, assignmentID: snapshot.assignmentID,
    assignmentTitle: snapshot.assignmentTitle,
    rubricRevisionID: snapshot.rubricRevisionID, criteria: snapshot.criteria,
    records: [alteredRecord], preflight: snapshot.preflight,
    includesIdentities: snapshot.includesIdentities
  )
  do {
    try GradeExportEngine.validateCurrent(
      alteredSnapshot, against: assignment,
      identities: [assignment.submissions[0].candidateID: "\n=Student"]
    )
    throw GradingCheckFailure(description: "altered snapshots must be rejected")
  } catch GradeExportFailure.staleSnapshot {}

  var changed = assignment
  try GradingEngine.setFeedback(
    "Changed", submission: &changed.submissions[0], assignment: changed
  )
  do {
    try GradeExportEngine.validateCurrent(
      snapshot, against: changed,
      identities: [assignment.submissions[0].candidateID: "\n=Student"]
    )
    throw GradingCheckFailure(description: "changed grades must make an export snapshot stale")
  } catch GradeExportFailure.staleSnapshot {}
}

private func makeAssignment() -> WorkAssignment {
  var assignment = WorkAssignment(title: "Synthetic assignment", course: "Math")
  let part = WorkPart(title: "Part A")
  assignment.parts = [part]
  assignment.criteria = [
    WorkCriterion(partID: part.id, title: "Method", maximum: PointValue(500)),
    WorkCriterion(partID: part.id, title: "Explanation", maximum: PointValue(500)),
  ]
  assignment.references = [
    ReferenceMaterial(partID: part.id, title: "Answer key", text: "Synthetic reference")
  ]
  let asset = AssetReference(
    sha256: String(repeating: "a", count: 64), byteCount: 1,
    typeIdentifier: "com.adobe.pdf", relativePath: "synthetic.pdf"
  )
  var first = WorkSubmission(candidateAlias: "Candidate 001")
  first.documents = [SourceDocumentRecord(originalName: "synthetic.pdf", asset: asset, pages: [])]
  var second = WorkSubmission(candidateAlias: "Candidate 002")
  second.documents = [SourceDocumentRecord(originalName: "synthetic.pdf", asset: asset, pages: [])]
  assignment.submissions = [first, second]
  return assignment
}
