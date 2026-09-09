import Foundation

public enum GradeStatisticsCohort: String, CaseIterable, Codable, Sendable {
  case approved
  case draftAndReviewed

  public var title: String {
    switch self {
    case .approved: return "Approved"
    case .draftAndReviewed: return "Complete drafts and reviewed"
    }
  }
}

public enum GradeStatisticsScope: Hashable, Sendable {
  case overall
  case part(UUID)
}

public enum GradeStatisticsExclusion: String, CaseIterable, Codable, Sendable {
  case statusNotIncluded
  case staleApproval
  case missingScores
  case unconfirmedScores
  case documentUnavailable

  public var title: String {
    switch self {
    case .statusNotIncluded: return "Other review status"
    case .staleApproval: return "Approval is out of date"
    case .missingScores: return "Missing scores"
    case .unconfirmedScores: return "Scores need confirmation"
    case .documentUnavailable: return "Document unavailable"
    }
  }
}

public struct GradeStatisticsBin: Identifiable, Hashable, Sendable {
  public let id: Int
  public let lowerBound: Double
  public let upperBound: Double
  public let includesUpperBound: Bool
  public let count: Int
  public let label: String

  public init(
    id: Int, lowerBound: Double, upperBound: Double, includesUpperBound: Bool,
    count: Int, label: String
  ) {
    self.id = id
    self.lowerBound = lowerBound
    self.upperBound = upperBound
    self.includesUpperBound = includesUpperBound
    self.count = count
    self.label = label
  }
}

public struct GradeStatisticsSnapshot: Sendable {
  public let cohort: GradeStatisticsCohort
  public let scope: GradeStatisticsScope
  public let maximum: PointValue
  public let scores: [PointValue]
  public let excludedCounts: [GradeStatisticsExclusion: Int]
  public let mean: Double?
  public let median: Double?
  public let modes: [PointValue]
  public let range: PointValue?
  public let populationStandardDeviation: Double?
  public let bins: [GradeStatisticsBin]

  public var includedCount: Int { scores.count }
  public var excludedCount: Int { excludedCounts.values.reduce(0, +) }

  public init(
    cohort: GradeStatisticsCohort, scope: GradeStatisticsScope, maximum: PointValue,
    scores: [PointValue], excludedCounts: [GradeStatisticsExclusion: Int],
    mean: Double?, median: Double?, modes: [PointValue], range: PointValue?,
    populationStandardDeviation: Double?, bins: [GradeStatisticsBin]
  ) {
    self.cohort = cohort
    self.scope = scope
    self.maximum = maximum
    self.scores = scores
    self.excludedCounts = excludedCounts
    self.mean = mean
    self.median = median
    self.modes = modes
    self.range = range
    self.populationStandardDeviation = populationStandardDeviation
    self.bins = bins
  }
}

public enum StatisticsEngine {
  public static func snapshot(
    assignment: WorkAssignment, scope: GradeStatisticsScope = .overall,
    cohort: GradeStatisticsCohort = .approved
  ) throws -> GradeStatisticsSnapshot {
    let rubricValidation = RubricEngine.validateRubric(assignment)
    guard rubricValidation.isValid else {
      throw GradingFailure.invalidRubric(
        rubricValidation.issues.first?.message ?? "The rubric is invalid."
      )
    }

    let partID: UUID?
    let maximum: PointValue
    switch scope {
    case .overall:
      partID = nil
      maximum = try RubricEngine.maximum(for: assignment)
    case .part(let id):
      partID = id
      maximum = try RubricEngine.maximum(for: id, in: assignment)
    }

    var scores: [PointValue] = []
    var exclusions: [GradeStatisticsExclusion: Int] = [:]
    for submission in assignment.submissions {
      if let exclusion = exclusion(
        for: submission, assignment: assignment, cohort: cohort
      ) {
        exclusions[exclusion, default: 0] += 1
      } else {
        scores.append(
          try GradingEngine.total(
            submission: submission, assignment: assignment, partID: partID
          )
        )
      }
    }

    let sorted = scores.sorted()
    guard !sorted.isEmpty else {
      return GradeStatisticsSnapshot(
        cohort: cohort, scope: scope, maximum: maximum, scores: [],
        excludedCounts: exclusions, mean: nil, median: nil, modes: [], range: nil,
        populationStandardDeviation: nil, bins: []
      )
    }

    let pointAmounts = sorted.map { Double($0.hundredths) / 100 }
    let mean = pointAmounts.reduce(0, +) / Double(pointAmounts.count)
    let median: Double
    if pointAmounts.count.isMultiple(of: 2) {
      let upper = pointAmounts.count / 2
      median = (pointAmounts[upper - 1] + pointAmounts[upper]) / 2
    } else {
      median = pointAmounts[pointAmounts.count / 2]
    }
    let variance =
      pointAmounts.reduce(0) { partial, score in
        let difference = score - mean
        return partial + difference * difference
      } / Double(pointAmounts.count)

    var frequencies: [Int64: Int] = [:]
    for score in sorted { frequencies[score.hundredths, default: 0] += 1 }
    let highestFrequency = frequencies.values.max() ?? 0
    let modes =
      highestFrequency < 2
      ? []
      : frequencies.filter { $0.value == highestFrequency }.keys.sorted().map(PointValue.init)

    return GradeStatisticsSnapshot(
      cohort: cohort, scope: scope, maximum: maximum, scores: sorted,
      excludedCounts: exclusions, mean: mean, median: median, modes: modes,
      range: PointValue(sorted.last!.hundredths - sorted.first!.hundredths),
      populationStandardDeviation: variance.squareRoot(),
      bins: histogram(scores: sorted, maximum: maximum)
    )
  }

  private static func exclusion(
    for submission: WorkSubmission, assignment: WorkAssignment,
    cohort: GradeStatisticsCohort
  ) -> GradeStatisticsExclusion? {
    switch cohort {
    case .approved:
      guard submission.status == .approved else { return .statusNotIncluded }
      guard submission.approvedReviewRevisionID == submission.reviewRevisionID,
        submission.approvedRubricRevisionID == assignment.rubricRevisionID
      else { return .staleApproval }
    case .draftAndReviewed:
      guard submission.status == .draft || submission.status == .reviewed else {
        return .statusNotIncluded
      }
    }
    guard !submission.documents.isEmpty else { return .documentUnavailable }

    for criterion in assignment.criteria {
      guard let entry = submission.scores[criterion.id] else { return .missingScores }
      if !entry.confirmed { return .unconfirmedScores }
      if entry.value.hundredths < 0 || entry.value > criterion.maximum {
        return .missingScores
      }
    }
    return nil
  }

  private static func histogram(
    scores: [PointValue], maximum: PointValue
  ) -> [GradeStatisticsBin] {
    guard maximum.hundredths > 0, !scores.isEmpty else { return [] }
    let maximumPoints = Double(maximum.hundredths) / 100
    var counts = Array(repeating: 0, count: 10)
    for score in scores {
      let ratio = Double(score.hundredths) / Double(maximum.hundredths)
      let index = min(max(Int((ratio * 10).rounded(.down)), 0), 9)
      counts[index] += 1
    }
    return (0..<10).map { index in
      let lower = maximumPoints * Double(index) / 10
      let upper = maximumPoints * Double(index + 1) / 10
      return GradeStatisticsBin(
        id: index, lowerBound: lower, upperBound: upper, includesUpperBound: index == 9,
        count: counts[index], label: "\(boundaryLabel(lower))–\(boundaryLabel(upper))"
      )
    }
  }

  private static func boundaryLabel(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
  }
}
