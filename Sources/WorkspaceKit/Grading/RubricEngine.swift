import Foundation

public struct RubricValidationIssue: Hashable, Sendable {
  public var path: String
  public var message: String

  public init(path: String, message: String) {
    self.path = path
    self.message = message
  }
}

public struct RubricValidationResult: Sendable {
  public var issues: [RubricValidationIssue]
  public var maximum: PointValue?

  public var isValid: Bool { issues.isEmpty }

  public init(issues: [RubricValidationIssue], maximum: PointValue?) {
    self.issues = issues
    self.maximum = maximum
  }
}

public enum RubricImportFailure: Error, LocalizedError, Sendable {
  case unsupportedSchema(Int)
  case malformed(String)
  case invalid([RubricValidationIssue])
  case staleRubric

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchema(let version):
      return "Rubric schema version \(version) is not supported."
    case .malformed(let message):
      return "The rubric JSON could not be read: \(message)"
    case .invalid(let issues):
      return issues.first?.message ?? "The rubric is invalid."
    case .staleRubric:
      return "The rubric changed after this import was previewed. Preview it again."
    }
  }
}

public struct RubricImportPreview: Sendable {
  public let sourceRubricRevisionID: UUID?
  public let title: String
  public let course: String
  public let parts: [WorkPart]
  public let criteria: [WorkCriterion]
  public let references: [ReferenceMaterial]
  public let validation: RubricValidationResult

  public init(
    sourceRubricRevisionID: UUID?, title: String, course: String, parts: [WorkPart],
    criteria: [WorkCriterion], references: [ReferenceMaterial],
    validation: RubricValidationResult
  ) {
    self.sourceRubricRevisionID = sourceRubricRevisionID
    self.title = title
    self.course = course
    self.parts = parts
    self.criteria = criteria
    self.references = references
    self.validation = validation
  }
}

public enum RubricEngine {
  public static func validateRubric(_ assignment: WorkAssignment) -> RubricValidationResult {
    var issues: [RubricValidationIssue] = []
    if assignment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.init(path: "title", message: "Assignment title is required."))
    }
    if assignment.parts.isEmpty {
      issues.append(.init(path: "parts", message: "Add at least one assignment part."))
    }

    let partIDs = Set(assignment.parts.map(\.id))
    if partIDs.count != assignment.parts.count {
      issues.append(.init(path: "parts", message: "Assignment part IDs must be unique."))
    }
    for (index, part) in assignment.parts.enumerated()
    where part.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.init(path: "parts[\(index)].title", message: "Each part needs a title."))
    }

    if assignment.criteria.isEmpty {
      issues.append(.init(path: "criteria", message: "Add at least one rubric criterion."))
    }
    let criterionIDs = Set(assignment.criteria.map(\.id))
    if criterionIDs.count != assignment.criteria.count {
      issues.append(.init(path: "criteria", message: "Rubric criterion IDs must be unique."))
    }

    var total: Int64 = 0
    var totalOverflow = false
    var criteriaByPart: [UUID: Int] = [:]
    for (index, criterion) in assignment.criteria.enumerated() {
      let path = "criteria[\(index)]"
      if !partIDs.contains(criterion.partID) {
        issues.append(
          .init(
            path: "\(path).partID", message: "Each criterion must belong to an assignment part."))
      } else {
        criteriaByPart[criterion.partID, default: 0] += 1
      }
      if criterion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(path: "\(path).title", message: "Each criterion needs a title."))
      }
      if criterion.maximum.hundredths <= 0 {
        issues.append(
          .init(
            path: "\(path).maximumPoints", message: "Criterion maxima must be greater than zero."))
      }
      let result = total.addingReportingOverflow(criterion.maximum.hundredths)
      total = result.partialValue
      totalOverflow = totalOverflow || result.overflow
    }
    for (index, part) in assignment.parts.enumerated() where criteriaByPart[part.id] == nil {
      issues.append(
        .init(path: "parts[\(index)]", message: "Each part needs at least one criterion."))
    }

    let referenceIDs = Set(assignment.references.map(\.id))
    if referenceIDs.count != assignment.references.count {
      issues.append(.init(path: "references", message: "Reference IDs must be unique."))
    }
    for (index, reference) in assignment.references.enumerated() {
      let path = "references[\(index)]"
      if !partIDs.contains(reference.partID) {
        issues.append(
          .init(
            path: "\(path).partID", message: "Each reference must belong to an assignment part."))
      }
      if reference.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(path: "\(path).title", message: "Each reference needs a title."))
      }
      if reference.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && reference.document == nil
      {
        issues.append(.init(path: path, message: "A reference needs text or a document."))
      }
    }

    if totalOverflow {
      issues.append(.init(path: "criteria", message: "The rubric maximum is too large."))
    }
    return RubricValidationResult(
      issues: issues,
      maximum: totalOverflow || assignment.criteria.isEmpty ? nil : PointValue(total)
    )
  }

  public static func maximum(for assignment: WorkAssignment) throws -> PointValue {
    let validation = validateRubric(assignment)
    guard validation.isValid, let maximum = validation.maximum else {
      throw RubricImportFailure.invalid(validation.issues)
    }
    return maximum
  }

  public static func maximum(for partID: UUID, in assignment: WorkAssignment) throws -> PointValue {
    guard assignment.parts.contains(where: { $0.id == partID }) else {
      throw RubricImportFailure.invalid([
        .init(path: "partID", message: "The selected assignment part no longer exists.")
      ])
    }
    var total: Int64 = 0
    for criterion in assignment.criteria where criterion.partID == partID {
      let result = total.addingReportingOverflow(criterion.maximum.hundredths)
      guard !result.overflow else {
        throw RubricImportFailure.invalid([
          .init(path: "criteria", message: "The part maximum is too large.")
        ])
      }
      total = result.partialValue
    }
    return PointValue(total)
  }

  public static func previewJSON(
    _ data: Data, replacing current: WorkAssignment? = nil
  ) throws -> RubricImportPreview {
    let payload: RubricImportPayload
    do {
      payload = try JSONDecoder().decode(RubricImportPayload.self, from: data)
    } catch {
      throw RubricImportFailure.malformed(error.localizedDescription)
    }
    guard payload.schemaVersion == 1 else {
      throw RubricImportFailure.unsupportedSchema(payload.schemaVersion)
    }

    let parts = payload.parts.map { item in
      var part = WorkPart(title: item.title)
      part.id = item.id
      return part
    }
    var parsingIssues: [RubricValidationIssue] = []
    let criteria = payload.criteria.enumerated().map { index, item in
      let maximum: PointValue
      do {
        maximum = try PointValue.parse(item.maximumPoints)
      } catch {
        maximum = PointValue()
        parsingIssues.append(
          .init(
            path: "criteria[\(index)].maximumPoints",
            message: error.localizedDescription
          )
        )
      }
      var criterion = WorkCriterion(
        partID: item.partID, title: item.title, guidance: item.guidance ?? "",
        maximum: maximum
      )
      criterion.id = item.id
      return criterion
    }
    let references = (payload.references ?? []).map { item in
      var reference = ReferenceMaterial(
        partID: item.partID, title: item.title, text: item.text ?? ""
      )
      reference.id = item.id
      return reference
    }

    var proposed = WorkAssignment(title: payload.title, course: payload.course ?? "")
    proposed.parts = parts
    proposed.criteria = criteria
    proposed.references = references
    var validation = validateRubric(proposed)
    validation.issues = parsingIssues + validation.issues
    guard validation.isValid else { throw RubricImportFailure.invalid(validation.issues) }
    return RubricImportPreview(
      sourceRubricRevisionID: current?.rubricRevisionID, title: payload.title,
      course: payload.course ?? "", parts: parts, criteria: criteria, references: references,
      validation: validation
    )
  }

  public static func apply(_ preview: RubricImportPreview, to assignment: inout WorkAssignment)
    throws
  {
    guard
      preview.sourceRubricRevisionID == nil
        || preview.sourceRubricRevisionID == assignment.rubricRevisionID
    else { throw RubricImportFailure.staleRubric }
    if preview.sourceRubricRevisionID == nil,
      !assignment.parts.isEmpty || !assignment.criteria.isEmpty || !assignment.references.isEmpty
    {
      throw RubricImportFailure.staleRubric
    }

    var proposed = WorkAssignment(title: preview.title, course: preview.course)
    proposed.parts = preview.parts
    proposed.criteria = preview.criteria
    proposed.references = preview.references
    let currentValidation = validateRubric(proposed)
    guard currentValidation.isValid else {
      throw RubricImportFailure.invalid(currentValidation.issues)
    }

    assignment.title = preview.title
    assignment.course = preview.course
    assignment.parts = preview.parts
    assignment.criteria = preview.criteria
    assignment.references = preview.references
    assignment.rubricRevisionID = UUID()
    let criterionIDs = Set(assignment.criteria.map(\.id))
    for index in assignment.submissions.indices {
      assignment.submissions[index].scores = assignment.submissions[index].scores.filter {
        criterionIDs.contains($0.key)
      }
      GradingEngine.invalidate(
        submission: &assignment.submissions[index],
        rubricRevisionID: assignment.rubricRevisionID,
        reason: "Rubric, assignment parts, or grading references changed."
      )
    }
  }
}

private struct RubricImportPayload: Decodable {
  var schemaVersion: Int
  var title: String
  var course: String?
  var parts: [Part]
  var criteria: [Criterion]
  var references: [Reference]?

  struct Part: Decodable {
    var id: UUID
    var title: String
  }
  struct Criterion: Decodable {
    var id: UUID
    var partID: UUID
    var title: String
    var guidance: String?
    var maximumPoints: String
  }
  struct Reference: Decodable {
    var id: UUID
    var partID: UUID
    var title: String
    var text: String?
  }
}
