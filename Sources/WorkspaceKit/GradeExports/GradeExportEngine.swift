import Foundation

public enum GradeExportFormat: String, CaseIterable, Codable, Hashable, Sendable {
  case csv
  case json
  case editablePDF
  case flattenedPDF

  public var title: String {
    switch self {
    case .csv: return "CSV"
    case .json: return "JSON"
    case .editablePDF: return "Editable annotated PDF"
    case .flattenedPDF: return "Flattened annotated PDF"
    }
  }
}

public struct GradeExportOptions: Sendable {
  public var formats: Set<GradeExportFormat>
  public var includeIdentities: Bool

  public init(
    formats: Set<GradeExportFormat> = Set(GradeExportFormat.allCases),
    includeIdentities: Bool = false
  ) {
    self.formats = formats
    self.includeIdentities = includeIdentities
  }
}

public enum GradeExportExclusion: String, CaseIterable, Codable, Sendable {
  case notApproved
  case staleApproval
  case incompleteScores
  case unconfirmedScores
  case documentUnavailable

  public var title: String {
    switch self {
    case .notApproved: return "Not approved"
    case .staleApproval: return "Approval is out of date"
    case .incompleteScores: return "Missing or invalid scores"
    case .unconfirmedScores: return "Scores need confirmation"
    case .documentUnavailable: return "Document unavailable"
    }
  }
}

public struct GradeExportPreflight: Sendable {
  public let eligibleSubmissionIDs: [UUID]
  public let excludedCounts: [GradeExportExclusion: Int]

  public var approvedCount: Int { eligibleSubmissionIDs.count }
  public var excludedCount: Int { excludedCounts.values.reduce(0, +) }

  public init(
    eligibleSubmissionIDs: [UUID], excludedCounts: [GradeExportExclusion: Int]
  ) {
    self.eligibleSubmissionIDs = eligibleSubmissionIDs
    self.excludedCounts = excludedCounts
  }
}

public struct GradeExportCriterion: Hashable, Sendable {
  public let id: UUID
  public let title: String
  public let maximum: PointValue

  public init(id: UUID, title: String, maximum: PointValue) {
    self.id = id
    self.title = title
    self.maximum = maximum
  }
}

public struct GradeExportDocumentRevision: Hashable, Sendable {
  public let documentID: UUID
  public let revisionID: UUID

  public init(documentID: UUID, revisionID: UUID) {
    self.documentID = documentID
    self.revisionID = revisionID
  }
}

public struct ApprovedGradeExportRecord: Hashable, Sendable {
  public let submissionID: UUID
  public let candidateID: UUID
  public let candidateAlias: String
  public let identifiedName: String?
  public let reviewRevisionID: UUID
  public let scores: [UUID: PointValue]
  public let total: PointValue
  public let feedback: String
  public let documentRevisions: [GradeExportDocumentRevision]
  public let ocrRevisionID: UUID
  public let markIDs: [UUID]

  public init(
    submissionID: UUID, candidateID: UUID, candidateAlias: String,
    identifiedName: String?, reviewRevisionID: UUID, scores: [UUID: PointValue],
    total: PointValue, feedback: String,
    documentRevisions: [GradeExportDocumentRevision], ocrRevisionID: UUID,
    markIDs: [UUID]
  ) {
    self.submissionID = submissionID
    self.candidateID = candidateID
    self.candidateAlias = candidateAlias
    self.identifiedName = identifiedName
    self.reviewRevisionID = reviewRevisionID
    self.scores = scores
    self.total = total
    self.feedback = feedback
    self.documentRevisions = documentRevisions
    self.ocrRevisionID = ocrRevisionID
    self.markIDs = markIDs
  }
}

public struct GradeExportSnapshot: Sendable {
  public let schemaVersion: Int
  public let generatedAt: Date
  public let assignmentID: UUID
  public let assignmentTitle: String
  public let rubricRevisionID: UUID
  public let criteria: [GradeExportCriterion]
  public let records: [ApprovedGradeExportRecord]
  public let preflight: GradeExportPreflight
  public let includesIdentities: Bool

  public init(
    schemaVersion: Int = 1, generatedAt: Date, assignmentID: UUID,
    assignmentTitle: String, rubricRevisionID: UUID,
    criteria: [GradeExportCriterion], records: [ApprovedGradeExportRecord],
    preflight: GradeExportPreflight, includesIdentities: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.assignmentID = assignmentID
    self.assignmentTitle = assignmentTitle
    self.rubricRevisionID = rubricRevisionID
    self.criteria = criteria
    self.records = records
    self.preflight = preflight
    self.includesIdentities = includesIdentities
  }
}

public enum GradeExportFailure: Error, LocalizedError, Sendable {
  case invalidRubric(String)
  case invalidSnapshot(String)
  case noApprovedGrades
  case staleSnapshot

  public var errorDescription: String? {
    switch self {
    case .invalidRubric(let message): return message
    case .invalidSnapshot(let message): return "The export snapshot is invalid: \(message)"
    case .noApprovedGrades: return "There are no current approved grades to export."
    case .staleSnapshot: return "Grades changed after export preparation. Prepare the export again."
    }
  }
}

public enum GradeExportEngine {
  public static func preflight(assignment: WorkAssignment) -> GradeExportPreflight {
    var eligible: [UUID] = []
    var excluded: [GradeExportExclusion: Int] = [:]
    for submission in assignment.submissions {
      if let reason = exclusion(for: submission, assignment: assignment) {
        excluded[reason, default: 0] += 1
      } else {
        eligible.append(submission.id)
      }
    }
    return GradeExportPreflight(
      eligibleSubmissionIDs: eligible, excludedCounts: excluded
    )
  }

  public static func makeSnapshot(
    assignment: WorkAssignment, identities: [UUID: String] = [:],
    includeIdentities: Bool = false, generatedAt: Date = Date()
  ) throws -> GradeExportSnapshot {
    let validation = RubricEngine.validateRubric(assignment)
    guard validation.isValid else {
      throw GradeExportFailure.invalidRubric(
        validation.issues.first?.message ?? "The rubric is invalid."
      )
    }
    let preflight = preflight(assignment: assignment)
    let eligibleIDs = Set(preflight.eligibleSubmissionIDs)
    let criteria = assignment.criteria.map {
      GradeExportCriterion(id: $0.id, title: $0.title, maximum: $0.maximum)
    }
    let records: [ApprovedGradeExportRecord] = try assignment.submissions.compactMap { submission in
      guard eligibleIDs.contains(submission.id) else { return nil }
      let scores = Dictionary(
        uniqueKeysWithValues: assignment.criteria.compactMap { criterion in
          submission.scores[criterion.id].map { (criterion.id, $0.value) }
        })
      return ApprovedGradeExportRecord(
        submissionID: submission.id, candidateID: submission.candidateID,
        candidateAlias: submission.candidateAlias,
        identifiedName: includeIdentities ? identities[submission.candidateID] : nil,
        reviewRevisionID: submission.reviewRevisionID, scores: scores,
        total: try GradingEngine.total(submission: submission, assignment: assignment),
        feedback: submission.feedback,
        documentRevisions: submission.documents.map {
          GradeExportDocumentRevision(documentID: $0.id, revisionID: $0.revisionID)
        },
        ocrRevisionID: submission.ocr.revisionID,
        markIDs: submission.marks.map(\.id)
      )
    }
    return GradeExportSnapshot(
      generatedAt: generatedAt, assignmentID: assignment.id,
      assignmentTitle: assignment.title, rubricRevisionID: assignment.rubricRevisionID,
      criteria: criteria, records: records, preflight: preflight,
      includesIdentities: includeIdentities
    )
  }

  public static func validateCurrent(
    _ snapshot: GradeExportSnapshot, against assignment: WorkAssignment,
    identities: [UUID: String] = [:]
  ) throws {
    try validateStructure(snapshot)
    guard snapshot.assignmentID == assignment.id,
      snapshot.assignmentTitle == assignment.title,
      snapshot.rubricRevisionID == assignment.rubricRevisionID,
      snapshot.criteria
        == assignment.criteria.map({
          GradeExportCriterion(id: $0.id, title: $0.title, maximum: $0.maximum)
        })
    else { throw GradeExportFailure.staleSnapshot }
    let current = Dictionary(uniqueKeysWithValues: assignment.submissions.map { ($0.id, $0) })
    let currentPreflight = preflight(assignment: assignment)
    guard
      Set(snapshot.records.map(\.submissionID))
        == Set(currentPreflight.eligibleSubmissionIDs),
      snapshot.preflight.eligibleSubmissionIDs == currentPreflight.eligibleSubmissionIDs,
      snapshot.preflight.excludedCounts == currentPreflight.excludedCounts
    else { throw GradeExportFailure.staleSnapshot }
    for record in snapshot.records {
      guard let submission = current[record.submissionID],
        exclusion(for: submission, assignment: assignment) == nil,
        submission.candidateID == record.candidateID,
        submission.candidateAlias == record.candidateAlias,
        submission.reviewRevisionID == record.reviewRevisionID,
        submission.feedback == record.feedback,
        record.documentRevisions
          == submission.documents.map({
            GradeExportDocumentRevision(documentID: $0.id, revisionID: $0.revisionID)
          }),
        record.ocrRevisionID == submission.ocr.revisionID,
        record.markIDs == submission.marks.map(\.id),
        !snapshot.includesIdentities || record.identifiedName == identities[record.candidateID]
      else { throw GradeExportFailure.staleSnapshot }
      let currentScores = Dictionary(
        uniqueKeysWithValues: assignment.criteria.compactMap { criterion in
          submission.scores[criterion.id].map { (criterion.id, $0.value) }
        })
      guard record.scores == currentScores,
        record.total == (try GradingEngine.total(submission: submission, assignment: assignment))
      else { throw GradeExportFailure.staleSnapshot }
    }
  }

  public static func csv(_ snapshot: GradeExportSnapshot) throws -> String {
    guard !snapshot.records.isEmpty else { throw GradeExportFailure.noApprovedGrades }
    try validateStructure(snapshot)
    var headers = [
      "assignment_id", "rubric_revision_id", "submission_id", "candidate_id",
      "candidate_alias", "candidate", "review_revision_id", "document_revisions",
      "ocr_revision_id", "mark_ids",
    ]
    headers += snapshot.criteria.map { "criterion_\($0.id.uuidString)_\($0.title)" }
    headers += ["total", "feedback"]

    var rows = [headers]
    for record in snapshot.records {
      let candidate = record.identifiedName ?? record.candidateID.uuidString
      var row = [
        snapshot.assignmentID.uuidString, snapshot.rubricRevisionID.uuidString,
        record.submissionID.uuidString, record.candidateID.uuidString,
        record.candidateAlias, candidate, record.reviewRevisionID.uuidString,
        record.documentRevisions.map {
          "\($0.documentID.uuidString):\($0.revisionID.uuidString)"
        }.joined(separator: ";"),
        record.ocrRevisionID.uuidString,
        record.markIDs.map(\.uuidString).joined(separator: ";"),
      ]
      row += snapshot.criteria.map { record.scores[$0.id]?.decimalString ?? "" }
      row += [record.total.decimalString, record.feedback]
      rows.append(row)
    }
    return rows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\r\n")
      + "\r\n"
  }

  public static func json(_ snapshot: GradeExportSnapshot) throws -> Data {
    guard !snapshot.records.isEmpty else { throw GradeExportFailure.noApprovedGrades }
    try validateStructure(snapshot)
    let payload = JSONPayload(
      schemaVersion: snapshot.schemaVersion,
      generatedAt: ISO8601DateFormatter().string(from: snapshot.generatedAt),
      assignment: .init(
        id: snapshot.assignmentID, title: snapshot.assignmentTitle,
        rubricRevisionID: snapshot.rubricRevisionID
      ),
      includesIdentities: snapshot.includesIdentities,
      criteria: snapshot.criteria.map {
        .init(id: $0.id, title: $0.title, maximumPoints: $0.maximum.decimalString)
      },
      records: snapshot.records.map { record in
        .init(
          submissionID: record.submissionID, candidateID: record.candidateID,
          candidateAlias: record.candidateAlias, identifiedName: record.identifiedName,
          reviewRevisionID: record.reviewRevisionID,
          scores: snapshot.criteria.map {
            .init(criterionID: $0.id, points: record.scores[$0.id]?.decimalString ?? "")
          }, totalPoints: record.total.decimalString, feedback: record.feedback,
          documentRevisions: record.documentRevisions.map {
            .init(documentID: $0.documentID, revisionID: $0.revisionID)
          }, ocrRevisionID: record.ocrRevisionID, markIDs: record.markIDs
        )
      }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(payload)
  }

  private static func exclusion(
    for submission: WorkSubmission, assignment: WorkAssignment
  ) -> GradeExportExclusion? {
    guard submission.status == .approved else { return .notApproved }
    guard submission.approvedReviewRevisionID == submission.reviewRevisionID,
      submission.approvedRubricRevisionID == assignment.rubricRevisionID
    else { return .staleApproval }
    guard !submission.documents.isEmpty else { return .documentUnavailable }
    for criterion in assignment.criteria {
      guard let score = submission.scores[criterion.id],
        score.value.hundredths >= 0, score.value <= criterion.maximum
      else { return .incompleteScores }
      if !score.confirmed { return .unconfirmedScores }
    }
    return nil
  }

  private static func csvField(_ source: String) -> String {
    let firstMeaningful = source.drop(while: \.isWhitespace).first
    let beginsWithControl = source.first.map { "\t\r\n".contains($0) } ?? false
    let dangerous =
      beginsWithControl
      || (firstMeaningful.map { "=+-@".contains($0) } ?? false)
    let safe = dangerous ? "'" + source : source
    return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }

  private static func validateStructure(_ snapshot: GradeExportSnapshot) throws {
    guard snapshot.schemaVersion == 1 else {
      throw GradeExportFailure.invalidSnapshot("Unsupported schema version.")
    }
    let criterionIDs = snapshot.criteria.map(\.id)
    guard Set(criterionIDs).count == criterionIDs.count else {
      throw GradeExportFailure.invalidSnapshot("Criterion IDs are duplicated.")
    }
    guard snapshot.criteria.allSatisfy({ $0.maximum.hundredths > 0 }) else {
      throw GradeExportFailure.invalidSnapshot("Criterion maxima must be greater than zero.")
    }
    let submissionIDs = snapshot.records.map(\.submissionID)
    guard Set(submissionIDs).count == submissionIDs.count else {
      throw GradeExportFailure.invalidSnapshot("Submission IDs are duplicated.")
    }
    guard Set(snapshot.preflight.eligibleSubmissionIDs) == Set(submissionIDs),
      snapshot.preflight.excludedCounts.values.allSatisfy({ $0 >= 0 })
    else {
      throw GradeExportFailure.invalidSnapshot("Preflight counts do not match the records.")
    }
    if !snapshot.includesIdentities,
      snapshot.records.contains(where: { $0.identifiedName != nil })
    {
      throw GradeExportFailure.invalidSnapshot("Identities were included without permission.")
    }
    let expectedScoreIDs = Set(criterionIDs)
    for record in snapshot.records {
      guard
        Set(record.documentRevisions.map(\.documentID)).count
          == record.documentRevisions.count,
        Set(record.markIDs).count == record.markIDs.count
      else {
        throw GradeExportFailure.invalidSnapshot("Evidence identifiers are duplicated.")
      }
      guard Set(record.scores.keys) == expectedScoreIDs else {
        throw GradeExportFailure.invalidSnapshot("A record does not contain every criterion score.")
      }
      var total: Int64 = 0
      for criterion in snapshot.criteria {
        guard let score = record.scores[criterion.id], score.hundredths >= 0,
          score <= criterion.maximum
        else {
          throw GradeExportFailure.invalidSnapshot("A criterion score is missing or out of range.")
        }
        let result = total.addingReportingOverflow(score.hundredths)
        guard !result.overflow else {
          throw GradeExportFailure.invalidSnapshot("A score total overflowed.")
        }
        total = result.partialValue
      }
      guard record.total == PointValue(total), !record.documentRevisions.isEmpty else {
        throw GradeExportFailure.invalidSnapshot("A total or document reference is invalid.")
      }
    }
  }
}

private struct JSONPayload: Encodable {
  var schemaVersion: Int
  var generatedAt: String
  var assignment: Assignment
  var includesIdentities: Bool
  var criteria: [Criterion]
  var records: [Record]

  struct Assignment: Encodable {
    var id: UUID
    var title: String
    var rubricRevisionID: UUID
  }
  struct Criterion: Encodable {
    var id: UUID
    var title: String
    var maximumPoints: String
  }
  struct Record: Encodable {
    var submissionID: UUID
    var candidateID: UUID
    var candidateAlias: String
    var identifiedName: String?
    var reviewRevisionID: UUID
    var scores: [Score]
    var totalPoints: String
    var feedback: String
    var documentRevisions: [DocumentRevision]
    var ocrRevisionID: UUID
    var markIDs: [UUID]
  }
  struct Score: Encodable {
    var criterionID: UUID
    var points: String
  }
  struct DocumentRevision: Encodable {
    var documentID: UUID
    var revisionID: UUID
  }
}
