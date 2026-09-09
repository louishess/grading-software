import Foundation

/// Validates cross-feature references before a workspace reaches the UI or disk.
/// An assignment may start empty; reviewed work must have a complete valid rubric.
public enum WorkspaceIntegrity {
  public static func validate(_ workspace: WorkspaceData) throws {
    try unique(workspace.assignments.map(\.id), "assignment")
    for assignment in workspace.assignments {
      try unique(assignment.parts.map(\.id), "part")
      try unique(assignment.criteria.map(\.id), "criterion")
      try unique(assignment.references.map(\.id), "reference")
      let parts = Set(assignment.parts.map(\.id))
      for criterion in assignment.criteria {
        guard parts.contains(criterion.partID), criterion.maximum.hundredths > 0 else {
          throw WorkspaceFailure.invalid("A criterion has an invalid part or maximum.")
        }
      }
      for reference in assignment.references {
        guard parts.contains(reference.partID) else {
          throw WorkspaceFailure.invalid("A reference points to a missing assignment part.")
        }
        if let document = reference.document { try validate(document) }
      }
      try unique(assignment.submissions.map(\.id), "submission")
      for submission in assignment.submissions {
        try unique(submission.documents.map(\.id), "document")
        try unique(submission.marks.map(\.id), "annotation")
        try unique(submission.ocr.blocks.map(\.id), "transcription block")
        try unique(submission.history.map(\.id), "history entry")
        for document in submission.documents { try validate(document) }
        for mark in submission.marks {
          try validate(mark.region, documents: submission.documents)
          guard mark.lineWidth.isFinite,
            mark.kind == .displayMask ? mark.lineWidth >= 0 : mark.lineWidth > 0,
            mark.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
          else {
            throw WorkspaceFailure.invalid("An annotation has invalid drawing coordinates.")
          }
          if let transform = mark.pencilCanvasTransform {
            guard transform.count == 6, transform.allSatisfy(\.isFinite) else {
              throw WorkspaceFailure.invalid("An ink drawing has an invalid canvas transform.")
            }
          }
        }
        for block in submission.ocr.blocks {
          try validate(block.region, documents: submission.documents)
          if let confidence = block.confidence {
            guard confidence.isFinite && (0...1).contains(confidence) else {
              throw WorkspaceFailure.invalid("An OCR confidence value is invalid.")
            }
          }
        }
        for (id, entry) in submission.scores {
          guard let criterion = assignment.criteria.first(where: { $0.id == id }),
            entry.value.hundredths >= 0,
            !entry.confirmed || entry.value <= criterion.maximum
          else {
            throw WorkspaceFailure.invalid("A saved score has an invalid criterion or point value.")
          }
        }
        if submission.status != .draft {
          try GradingEngine.validateCompleteness(submission: submission, assignment: assignment)
        }
        if submission.status == .approved {
          guard submission.approvedReviewRevisionID == submission.reviewRevisionID,
            submission.approvedRubricRevisionID == assignment.rubricRevisionID,
            submission.history.contains(where: {
              $0.status == .approved && $0.reviewRevisionID == submission.reviewRevisionID
                && $0.rubricRevisionID == assignment.rubricRevisionID
                && $0.scores == submission.scores && $0.feedback == submission.feedback
            })
          else {
            throw WorkspaceFailure.invalid("Approval provenance does not match the saved review.")
          }
        } else if submission.approvedReviewRevisionID != nil
          || submission.approvedRubricRevisionID != nil
        {
          throw WorkspaceFailure.invalid("Unapproved work contains a current approval identifier.")
        }
      }
    }
  }

  private static func validate(_ document: SourceDocumentRecord) throws {
    guard !document.pages.isEmpty else {
      throw WorkspaceFailure.invalid("A document has no pages.")
    }
    try unique(document.pages.map(\.id), "page")
    try unique(document.pages.map(\.index), "page index")
    for page in document.pages {
      guard page.index >= 0, page.rotation.isMultiple(of: 90),
        valid(page.mediaBox), valid(page.cropBox)
      else {
        throw WorkspaceFailure.invalid("A document contains invalid page geometry.")
      }
    }
  }

  private static func validate(_ region: PageRegion, documents: [SourceDocumentRecord]) throws {
    guard region.coordinateVersion == 1,
      let document = documents.first(where: { $0.id == region.documentID }),
      document.revisionID == region.documentRevisionID,
      let page = document.pages.first(where: { $0.id == region.pageID }),
      valid(region.bounds), contains(page.cropBox, region.bounds)
    else {
      throw WorkspaceFailure.invalid(
        "A source-linked region has invalid page coordinates or revision.")
    }
  }
  private static func valid(_ rect: PageRectangle) -> Bool {
    rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite
      && rect.width > 0 && rect.height > 0
      && (rect.x + rect.width).isFinite && (rect.y + rect.height).isFinite
  }
  private static func contains(_ outer: PageRectangle, _ inner: PageRectangle) -> Bool {
    let tolerance = 0.01
    return inner.x >= outer.x - tolerance && inner.y >= outer.y - tolerance
      && inner.x + inner.width <= outer.x + outer.width + tolerance
      && inner.y + inner.height <= outer.y + outer.height + tolerance
  }
  private static func unique<T: Hashable>(_ values: [T], _ label: String) throws {
    guard Set(values).count == values.count else {
      throw WorkspaceFailure.invalid("Duplicate \(label) identifiers are not allowed.")
    }
  }
}
