import Foundation

public enum GradingFailure: Error, Equatable, LocalizedError, Sendable {
  case criterionNotFound
  case scoreOutOfRange(maximum: PointValue)
  case invalidRubric(String)
  case incompleteScores([UUID])
  case unconfirmedScores([UUID])
  case documentUnavailable
  case invalidTransition(from: ReviewStatus, to: ReviewStatus)
  case arithmeticOverflow

  public var errorDescription: String? {
    switch self {
    case .criterionNotFound:
      return "This rubric criterion no longer exists."
    case .scoreOutOfRange(let maximum):
      return "Enter a score from 0 through \(maximum.decimalString)."
    case .invalidRubric(let message):
      return message
    case .incompleteScores:
      return "Enter a score for every rubric criterion before continuing."
    case .unconfirmedScores:
      return "Confirm every carried-forward score before continuing."
    case .documentUnavailable:
      return "The source document must be available before this grade can be reviewed."
    case .invalidTransition(let from, let to):
      return "A grade cannot move directly from \(from.rawValue) to \(to.rawValue)."
    case .arithmeticOverflow:
      return "The score total is too large."
    }
  }
}

public enum GradingEngine {
  public static func total(
    submission: WorkSubmission, assignment: WorkAssignment, partID: UUID? = nil
  ) throws -> PointValue {
    if let partID, !assignment.parts.contains(where: { $0.id == partID }) {
      throw GradingFailure.invalidRubric("The selected assignment part no longer exists.")
    }
    let criteria = assignment.criteria.filter { partID == nil || $0.partID == partID }
    var total: Int64 = 0
    for criterion in criteria {
      guard let entry = submission.scores[criterion.id] else {
        throw GradingFailure.incompleteScores([criterion.id])
      }
      guard entry.value.hundredths >= 0, entry.value <= criterion.maximum else {
        throw GradingFailure.scoreOutOfRange(maximum: criterion.maximum)
      }
      let result = total.addingReportingOverflow(entry.value.hundredths)
      guard !result.overflow else { throw GradingFailure.arithmeticOverflow }
      total = result.partialValue
    }
    return PointValue(total)
  }

  public static func setScore(
    _ text: String?, criterionID: UUID, submission: inout WorkSubmission,
    assignment: WorkAssignment, expectedReviewRevisionID: UUID? = nil
  ) throws {
    try requireCurrent(expectedReviewRevisionID, submission: submission)
    guard let criterion = assignment.criteria.first(where: { $0.id == criterionID }) else {
      throw GradingFailure.criterionNotFound
    }

    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let nextValue: PointValue? = trimmed.isEmpty ? nil : try PointValue.parse(trimmed)
    if let nextValue,
      nextValue.hundredths < 0 || nextValue > criterion.maximum
    {
      throw GradingFailure.scoreOutOfRange(maximum: criterion.maximum)
    }
    if let existing = submission.scores[criterionID], let nextValue,
      existing.value == nextValue, existing.confirmed
    {
      return
    }
    if submission.scores[criterionID] == nil, nextValue == nil { return }

    beginGradingEdit(submission: &submission)
    if let nextValue {
      submission.scores[criterionID] = ScoreEntry(value: nextValue, confirmed: true)
    } else {
      submission.scores.removeValue(forKey: criterionID)
    }
    appendCurrentState(
      submission: &submission, rubricRevisionID: assignment.rubricRevisionID,
      reason: "Score edited."
    )
  }

  public static func confirmScore(
    criterionID: UUID, submission: inout WorkSubmission, assignment: WorkAssignment,
    expectedReviewRevisionID: UUID? = nil
  ) throws {
    try requireCurrent(expectedReviewRevisionID, submission: submission)
    guard let criterion = assignment.criteria.first(where: { $0.id == criterionID }) else {
      throw GradingFailure.criterionNotFound
    }
    guard var entry = submission.scores[criterionID] else {
      throw GradingFailure.incompleteScores([criterionID])
    }
    guard entry.value.hundredths >= 0, entry.value <= criterion.maximum else {
      throw GradingFailure.scoreOutOfRange(maximum: criterion.maximum)
    }
    guard !entry.confirmed else { return }
    entry.confirmed = true
    submission.scores[criterionID] = entry
    submission.status = .draft
    submission.reviewRevisionID = UUID()
    appendCurrentState(
      submission: &submission, rubricRevisionID: assignment.rubricRevisionID,
      reason: "Carried-forward score confirmed."
    )
  }

  public static func setFeedback(
    _ feedback: String, submission: inout WorkSubmission, assignment: WorkAssignment,
    expectedReviewRevisionID: UUID? = nil
  ) throws {
    try requireCurrent(expectedReviewRevisionID, submission: submission)
    guard feedback != submission.feedback else { return }
    beginGradingEdit(submission: &submission)
    submission.feedback = feedback
    appendCurrentState(
      submission: &submission, rubricRevisionID: assignment.rubricRevisionID,
      reason: "Feedback edited."
    )
  }

  public static func transition(
    submission: inout WorkSubmission, to status: ReviewStatus, assignment: WorkAssignment,
    expectedReviewRevisionID: UUID? = nil
  ) throws {
    try requireCurrent(expectedReviewRevisionID, submission: submission)
    switch (submission.status, status) {
    case (.draft, .reviewed), (.reviewed, .approved):
      break
    default:
      throw GradingFailure.invalidTransition(from: submission.status, to: status)
    }
    try validateCompleteness(submission: submission, assignment: assignment)

    submission.status = status
    submission.reviewRevisionID = UUID()
    if status == .approved {
      submission.approvedReviewRevisionID = submission.reviewRevisionID
      submission.approvedRubricRevisionID = assignment.rubricRevisionID
    }
    appendCurrentState(
      submission: &submission, rubricRevisionID: assignment.rubricRevisionID,
      reason: status == .approved ? "Grade approved." : "Grade reviewed."
    )
  }

  public static func invalidate(
    submission: inout WorkSubmission, rubricRevisionID: UUID, reason: String
  ) {
    submission.status = .draft
    submission.approvedReviewRevisionID = nil
    submission.approvedRubricRevisionID = nil
    submission.scores = submission.scores.mapValues {
      ScoreEntry(value: $0.value, confirmed: false)
    }
    submission.reviewRevisionID = UUID()
    appendCurrentState(
      submission: &submission, rubricRevisionID: rubricRevisionID,
      reason: reason.isEmpty ? "Grading evidence changed." : reason
    )
  }

  public static func validateCompleteness(
    submission: WorkSubmission, assignment: WorkAssignment
  ) throws {
    let rubric = RubricEngine.validateRubric(assignment)
    guard rubric.isValid else {
      throw GradingFailure.invalidRubric(
        rubric.issues.first?.message ?? "The rubric is invalid."
      )
    }
    guard !submission.documents.isEmpty else { throw GradingFailure.documentUnavailable }

    let missing = assignment.criteria.compactMap { criterion in
      submission.scores[criterion.id] == nil ? criterion.id : nil
    }
    guard missing.isEmpty else { throw GradingFailure.incompleteScores(missing) }

    var unconfirmed: [UUID] = []
    for criterion in assignment.criteria {
      guard let entry = submission.scores[criterion.id] else { continue }
      guard entry.value.hundredths >= 0, entry.value <= criterion.maximum else {
        throw GradingFailure.scoreOutOfRange(maximum: criterion.maximum)
      }
      if !entry.confirmed { unconfirmed.append(criterion.id) }
    }
    guard unconfirmed.isEmpty else { throw GradingFailure.unconfirmedScores(unconfirmed) }
  }

  private static func requireCurrent(
    _ expectedReviewRevisionID: UUID?, submission: WorkSubmission
  ) throws {
    if let expectedReviewRevisionID,
      expectedReviewRevisionID != submission.reviewRevisionID
    {
      throw WorkspaceFailure.staleRevision
    }
  }

  private static func beginGradingEdit(submission: inout WorkSubmission) {
    let invalidatesReviewedState =
      submission.status != .draft
      || submission.approvedReviewRevisionID != nil
      || submission.approvedRubricRevisionID != nil
    submission.status = .draft
    submission.approvedReviewRevisionID = nil
    submission.approvedRubricRevisionID = nil
    if invalidatesReviewedState {
      submission.scores = submission.scores.mapValues {
        ScoreEntry(value: $0.value, confirmed: false)
      }
    }
    submission.reviewRevisionID = UUID()
  }

  private static func appendCurrentState(
    submission: inout WorkSubmission, rubricRevisionID: UUID, reason: String
  ) {
    submission.history.append(
      ReviewHistoryEntry(
        reviewRevisionID: submission.reviewRevisionID,
        rubricRevisionID: rubricRevisionID,
        status: submission.status,
        scores: submission.scores,
        feedback: submission.feedback,
        reason: reason
      )
    )
  }
}
