import SwiftUI

/// The editable review surface for one assignment and one submission.
///
/// The pane owns only transient field state. The caller remains responsible for
/// persisting the value passed to `onSubmissionChange` and for applying any
/// assignment level changes passed to `onAssignmentChange`.
public struct LiveReviewPane: View {
  public let assignment: WorkAssignment
  public let submission: WorkSubmission?
  public let readOnly: Bool
  public let onAssignmentChange: (WorkAssignment) -> Void
  public let onSubmissionChange: (WorkSubmission) -> Void
  public let onImportReference: (UUID) -> Void

  @State private var scoreDrafts: [UUID: String]
  @State private var feedbackDraft: String
  @State private var scoreErrors: [UUID: String] = [:]
  @State private var feedbackError: String?
  @State private var actionError: String?
  @State private var isFeedbackDirty = false
  @State private var isRubricEditorPresented = false

  public init(
    assignment: WorkAssignment,
    submission: WorkSubmission?,
    readOnly: Bool,
    onAssignmentChange: @escaping (WorkAssignment) -> Void,
    onSubmissionChange: @escaping (WorkSubmission) -> Void,
    onImportReference: @escaping (UUID) -> Void
  ) {
    self.assignment = assignment
    self.submission = submission
    self.readOnly = readOnly
    self.onAssignmentChange = onAssignmentChange
    self.onSubmissionChange = onSubmissionChange
    self.onImportReference = onImportReference
    _scoreDrafts = State(initialValue: Self.scoreTexts(for: assignment, submission: submission))
    _feedbackDraft = State(initialValue: submission?.feedback ?? "")
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        rubricCard
        if let submission {
          statusCard(for: submission)
          scoringCard(for: submission)
          feedbackCard(for: submission)
          historyCard(for: submission)
        } else {
          emptyState
        }
        referencesCard
        if let actionError {
          LiveReviewMessage(text: actionError, systemImage: "exclamationmark.triangle")
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(WorkspaceStyle.background)
    .onChange(of: submission?.id) { _, _ in
      syncTransientState()
    }
    .onChange(of: submission?.reviewRevisionID) { _, _ in
      syncTransientState()
    }
    .sheet(isPresented: $isRubricEditorPresented) {
      LiveRubricEditor(
        assignment: assignment,
        onAssignmentChange: onAssignmentChange,
        onImportReference: onImportReference
      )
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Review")
          .font(.title3.weight(.semibold))
        LiveReviewBadge(text: readOnly ? "Read only" : "Teacher review")
        Spacer(minLength: 4)
        LiveReviewBadge(text: assignment.title)
      }
      Text(assignment.course.isEmpty ? "Assignment grading workspace" : assignment.course)
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
    }
  }

  private var rubricCard: some View {
    let validation = RubricEngine.validateRubric(assignment)
    return VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Rubric")
            .font(.headline)
          Text(
            "\(assignment.parts.count) parts · \(assignment.criteria.count) criteria · \(assignment.references.count) references"
          )
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 8)
        LiveReviewBadge(text: readOnly ? "View only" : "Teacher editing")
      }
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        Image(
          systemName: validation.isValid
            ? "checkmark.seal"
            : "exclamationmark.triangle"
        )
        .foregroundStyle(validation.isValid ? WorkspaceStyle.accent : .orange)
        Text(
          validation.isValid
            ? rubricMaximumText
            : "Rubric needs attention before a grade can be reviewed."
        )
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      Button {
        isRubricEditorPresented = true
      } label: {
        Label(
          readOnly ? "Edit rubric" : "Open rubric editor",
          systemImage: "slider.horizontal.3"
        )
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(readOnly)
      .help(
        readOnly
          ? "Rubric editing is disabled in read-only review."
          : "Open the assignment rubric editor"
      )
      .accessibilityLabel(
        readOnly
          ? "Edit rubric, disabled in read-only review"
          : "Open rubric editor"
      )
      if readOnly {
        Text(
          "Rubric details are view only on this device. Teacher editing is available in the full review workspace."
        )
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .workspaceCard()
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Assignment rubric")
  }

  private var rubricMaximumText: String {
    guard let maximum = try? RubricEngine.maximum(for: assignment) else {
      return "Rubric is valid."
    }
    return "Maximum \(maximum.decimalString) points."
  }

  private func statusCard(for submission: WorkSubmission) -> some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text(submission.candidateAlias)
            .font(.headline)
          Text("Review status")
            .font(.caption.weight(.medium))
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 8)
        LiveReviewStatusBadge(status: submission.status)
      }

      HStack(alignment: .top, spacing: 8) {
        Image(systemName: statusSymbol(for: submission.status))
          .foregroundStyle(statusColor(for: submission.status))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(statusTitle(for: submission.status))
            .font(.caption.weight(.semibold))
          Text(statusMessage(for: submission.status, submission: submission))
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      HStack(spacing: 8) {
        if submission.status == .draft {
          transitionButton(
            title: "Mark reviewed", systemImage: "checkmark.circle", to: .reviewed,
            explanation: "Review every criterion before marking this grade reviewed."
          )
        } else if submission.status == .reviewed {
          transitionButton(
            title: "Approve grade", systemImage: "checkmark.seal", to: .approved,
            explanation: "Approval makes this current revision eligible for export."
          )
        } else {
          Text("Approved revisions are preserved in the history below.")
            .font(.caption.weight(.medium))
            .foregroundStyle(WorkspaceStyle.secondary)
        }
      }

      VStack(alignment: .leading, spacing: 3) {
        revisionLine(
          title: "Current review revision", value: shortID(submission.reviewRevisionID)
        )
        if let approvedReviewRevisionID = submission.approvedReviewRevisionID {
          revisionLine(
            title: "Approved revision", value: shortID(approvedReviewRevisionID)
          )
        }
        if let approvedRubricRevisionID = submission.approvedRubricRevisionID {
          revisionLine(
            title: "Approved rubric", value: shortID(approvedRubricRevisionID)
          )
        }
      }
    }
    .workspaceCard()
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      "\(submission.candidateAlias), \(submission.status.rawValue) review status"
    )
  }

  private func scoringCard(for submission: WorkSubmission) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Rubric scores")
            .font(.headline)
          Text("Enter points for each criterion. Blank means missing; 0 is an explicit score.")
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 6)
        totalBadge(for: submission)
      }

      if assignment.criteria.isEmpty {
        LiveReviewMessage(
          text: "Add rubric criteria before entering scores.", systemImage: "list.bullet")
      } else {
        ForEach(assignment.parts) { part in
          let criteria = assignment.criteria.filter { $0.partID == part.id }
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
              Text(part.title)
                .font(.caption.weight(.semibold))
              Spacer(minLength: 4)
              if let maximum = try? RubricEngine.maximum(for: part.id, in: assignment) {
                Text("out of \(maximum.decimalString)")
                  .font(.caption.monospaced())
                  .foregroundStyle(WorkspaceStyle.secondary)
              }
            }
            if criteria.isEmpty {
              Text("No criteria are assigned to this part.")
                .font(.caption)
                .foregroundStyle(WorkspaceStyle.secondary)
            } else {
              ForEach(criteria) { criterion in
                scoreRow(criterion: criterion, submission: submission)
              }
            }
          }
          .padding(.top, 4)
        }
      }
    }
    .workspaceCard()
  }

  private func scoreRow(criterion: WorkCriterion, submission: WorkSubmission) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text(criterion.title)
            .font(.callout.weight(.medium))
          if !criterion.guidance.isEmpty {
            Text(criterion.guidance)
              .font(.caption)
              .foregroundStyle(WorkspaceStyle.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 5)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          TextField(
            "—", text: scoreBinding(for: criterion), onEditingChanged: { _ in }
          )
          .textFieldStyle(.roundedBorder)
          .frame(width: 74)
          .multilineTextAlignment(.trailing)
          .disabled(readOnly)
          .accessibilityLabel("Score for \(criterion.title)")
          .accessibilityValue(scoreAccessibilityValue(for: criterion, submission: submission))
          #if os(iOS)
            .keyboardType(.decimalPad)
          #endif
          .onSubmit {
            commitScore(for: criterion)
          }
          Text("/ \(criterion.maximum.decimalString)")
            .font(.caption.monospaced())
            .foregroundStyle(WorkspaceStyle.secondary)
          Button("Save score") {
            commitScore(for: criterion)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(readOnly || !scoreNeedsSave(for: criterion, submission: submission))
          .help(
            readOnly
              ? "Score editing is disabled in read-only review."
              : "Save the score for \(criterion.title)"
          )
          .accessibilityLabel(
            readOnly
              ? "Save score for \(criterion.title), disabled in read-only review"
              : "Save score for \(criterion.title)"
          )
        }
      }

      HStack(spacing: 8) {
        if let entry = submission.scores[criterion.id] {
          if entry.confirmed {
            Label("Confirmed", systemImage: "checkmark.circle.fill")
              .foregroundStyle(WorkspaceStyle.accent)
          } else {
            Label("Carried forward; confirm", systemImage: "arrow.uturn.forward.circle")
              .foregroundStyle(.orange)
            Button("Confirm") { confirmScore(for: criterion) }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .disabled(readOnly)
              .help(
                readOnly
                  ? "Score confirmation is disabled in read-only review."
                  : "Confirm this carried-forward score"
              )
              .accessibilityLabel("Confirm carried-forward score for \(criterion.title)")
          }
        } else {
          Label("Missing score", systemImage: "circle.dashed")
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 4)
        if let scoreError = scoreErrors[criterion.id] {
          Text(scoreError)
            .font(.caption)
            .foregroundStyle(.red)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
        }
      }
      .font(.caption.weight(.medium))
    }
    .padding(10)
    .background(WorkspaceStyle.inset.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(WorkspaceStyle.border, lineWidth: 1))
  }

  private func feedbackCard(for submission: WorkSubmission) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 7) {
        Image(systemName: "text.bubble")
          .foregroundStyle(WorkspaceStyle.accent)
        Text("Teacher feedback")
          .font(.headline)
        Spacer(minLength: 4)
        if !readOnly {
          LiveReviewBadge(text: isFeedbackDirty ? "Local edits" : "No local edits")
        }
      }
      TextEditor(text: $feedbackDraft)
        .font(.callout)
        .frame(minHeight: 92)
        .padding(5)
        .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkspaceStyle.border, lineWidth: 1))
        .disabled(readOnly)
        .accessibilityLabel("Teacher feedback")
        .onChange(of: feedbackDraft) { _, _ in
          isFeedbackDirty = feedbackDraft != submission.feedback
        }
      HStack(alignment: .top, spacing: 8) {
        if let feedbackError {
          Text(feedbackError)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
        } else {
          Text("Feedback is teacher-authored and is included only in an approved export.")
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 4)
        Button("Save feedback") { saveFeedback() }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(readOnly || !isFeedbackDirty)
          .help(
            readOnly ? "Feedback editing is disabled in read-only review." : "Save teacher feedback"
          )
          .accessibilityLabel(
            readOnly ? "Save feedback, disabled in read-only review" : "Save feedback")
      }
    }
    .workspaceCard()
  }

  private var referencesCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 7) {
        Image(systemName: "books.vertical")
          .foregroundStyle(WorkspaceStyle.accent)
        Text("References")
          .font(.headline)
        Spacer(minLength: 4)
        LiveReviewBadge(text: "Assignment")
      }
      if assignment.parts.isEmpty {
        Text("Add an assignment part before attaching a reference.")
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
      } else {
        ForEach(assignment.parts) { part in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(part.title)
                .font(.caption.weight(.semibold))
              Spacer(minLength: 4)
              Button {
                onImportReference(part.id)
              } label: {
                Label("Import", systemImage: "square.and.arrow.down")
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .disabled(readOnly)
              .help(
                readOnly
                  ? "Reference import is disabled in read-only review."
                  : "Import a reference for \(part.title)"
              )
              .accessibilityLabel(
                readOnly
                  ? "Import reference for \(part.title), disabled"
                  : "Import reference for \(part.title)"
              )
            }
            let references = assignment.references.filter { $0.partID == part.id }
            if references.isEmpty {
              Text("No references attached to this part.")
                .font(.caption)
                .foregroundStyle(WorkspaceStyle.secondary)
            } else {
              ForEach(references) { reference in
                VStack(alignment: .leading, spacing: 3) {
                  Text(reference.title)
                    .font(.caption.weight(.medium))
                  if !reference.text.isEmpty {
                    Text(reference.text)
                      .font(.caption)
                      .foregroundStyle(WorkspaceStyle.secondary)
                      .lineLimit(3)
                  }
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                  WorkspaceStyle.inset.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
              }
            }
          }
          .padding(.top, 3)
        }
      }
      Text(
        readOnly
          ? "Reference changes are disabled in read-only review."
          : "Reference import is handled by the workspace and creates a new rubric revision."
      )
      .font(.caption)
      .foregroundStyle(WorkspaceStyle.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .workspaceCard()
  }

  private func historyCard(for submission: WorkSubmission) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 7) {
        Image(systemName: "clock.arrow.circlepath")
          .foregroundStyle(WorkspaceStyle.accent)
        Text("Revision history")
          .font(.headline)
        Spacer(minLength: 4)
        Text("\(submission.history.count) entries")
          .font(.caption.monospaced())
          .foregroundStyle(WorkspaceStyle.secondary)
      }
      if submission.history.isEmpty {
        Text("No review revisions yet.")
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
      } else {
        ForEach(submission.history.reversed()) { entry in
          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              LiveReviewStatusBadge(status: entry.status)
              Text(entry.reason)
                .font(.caption.weight(.medium))
              Spacer(minLength: 4)
              Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2.monospaced())
                .foregroundStyle(WorkspaceStyle.secondary)
            }
            Text(
              "Revision \(shortID(entry.reviewRevisionID)) · rubric \(shortID(entry.rubricRevisionID))"
            )
            .font(.caption2.monospaced())
            .foregroundStyle(WorkspaceStyle.secondary)
          }
          .padding(.vertical, 5)
          if entry.id != submission.history.first?.id { Divider() }
        }
      }
    }
    .workspaceCard()
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Revision history, \(submission.history.count) entries")
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label("No submission selected", systemImage: "doc.questionmark")
        .font(.headline)
      Text("Choose a candidate to review its scores, feedback, status, and revision history.")
        .font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .workspaceCard()
  }

  private func totalBadge(for submission: WorkSubmission) -> some View {
    let total = try? GradingEngine.total(submission: submission, assignment: assignment)
    return VStack(alignment: .trailing, spacing: 2) {
      Text("Total")
        .font(.caption2.weight(.medium))
        .foregroundStyle(WorkspaceStyle.secondary)
      Text(total.map(\.decimalString) ?? "—")
        .font(.title3.weight(.semibold))
      if let maximum = try? RubricEngine.maximum(for: assignment) {
        Text("/ \(maximum.decimalString)")
          .font(.caption2.monospaced())
          .foregroundStyle(WorkspaceStyle.secondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Grade total")
    .accessibilityValue(total.map { "\($0.decimalString) points" } ?? "Incomplete")
  }

  private func transitionButton(
    title: String,
    systemImage: String,
    to status: ReviewStatus,
    explanation: String
  ) -> some View {
    Button {
      transition(to: status)
    } label: {
      Label(title, systemImage: systemImage)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.small)
    .disabled(readOnly)
    .help(readOnly ? "\(title) is disabled in read-only review." : explanation)
    .accessibilityLabel(readOnly ? "\(title), disabled in read-only review" : title)
    .accessibilityHint(explanation)
  }

  private func revisionLine(title: String, value: String) -> some View {
    HStack(spacing: 6) {
      Text(title)
        .foregroundStyle(WorkspaceStyle.secondary)
      Spacer(minLength: 5)
      Text(value)
        .font(.caption2.monospaced())
        .foregroundStyle(WorkspaceStyle.ink)
    }
    .font(.caption2)
  }

  private func scoreBinding(for criterion: WorkCriterion) -> Binding<String> {
    Binding(
      get: { scoreDrafts[criterion.id] ?? "" },
      set: { newValue in
        scoreDrafts[criterion.id] = newValue
        scoreErrors[criterion.id] = nil
      }
    )
  }

  private func commitScore(for criterion: WorkCriterion) {
    guard !readOnly, let source = submission else { return }
    let text = scoreDrafts[criterion.id] ?? ""
    var next = source
    do {
      try GradingEngine.setScore(
        text,
        criterionID: criterion.id,
        submission: &next,
        assignment: assignment,
        expectedReviewRevisionID: source.reviewRevisionID
      )
      scoreErrors[criterion.id] = nil
      actionError = nil
      onSubmissionChange(next)
      syncTransientState(from: next)
    } catch {
      scoreErrors[criterion.id] = error.localizedDescription
    }
  }

  private func scoreNeedsSave(
    for criterion: WorkCriterion, submission: WorkSubmission
  ) -> Bool {
    let draft = (scoreDrafts[criterion.id] ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let entry = submission.scores[criterion.id] else {
      return !draft.isEmpty
    }
    if draft.isEmpty { return true }
    return draft != entry.value.decimalString || !entry.confirmed
  }

  private func confirmScore(for criterion: WorkCriterion) {
    guard !readOnly, let source = submission else { return }
    var next = source
    do {
      try GradingEngine.confirmScore(
        criterionID: criterion.id,
        submission: &next,
        assignment: assignment,
        expectedReviewRevisionID: source.reviewRevisionID
      )
      actionError = nil
      onSubmissionChange(next)
      syncTransientState(from: next)
    } catch {
      actionError = error.localizedDescription
    }
  }

  private func saveFeedback() {
    guard !readOnly, let source = submission else { return }
    var next = source
    do {
      try GradingEngine.setFeedback(
        feedbackDraft,
        submission: &next,
        assignment: assignment,
        expectedReviewRevisionID: source.reviewRevisionID
      )
      feedbackError = nil
      actionError = nil
      isFeedbackDirty = false
      onSubmissionChange(next)
      syncTransientState(from: next)
    } catch {
      feedbackError = error.localizedDescription
    }
  }

  private func transition(to status: ReviewStatus) {
    guard !readOnly, let source = submission else { return }
    var next = source
    do {
      try GradingEngine.transition(
        submission: &next,
        to: status,
        assignment: assignment,
        expectedReviewRevisionID: source.reviewRevisionID
      )
      actionError = nil
      onSubmissionChange(next)
      syncTransientState(from: next)
    } catch {
      actionError = error.localizedDescription
    }
  }

  private func scoreAccessibilityValue(
    for criterion: WorkCriterion, submission: WorkSubmission
  ) -> String {
    guard let entry = submission.scores[criterion.id] else { return "Missing score" }
    return
      "\(entry.value.decimalString) of \(criterion.maximum.decimalString) points, \(entry.confirmed ? "confirmed" : "carried forward")"
  }

  private func statusTitle(for status: ReviewStatus) -> String {
    switch status {
    case .draft: return "Draft grade"
    case .reviewed: return "Reviewed grade"
    case .approved: return "Approved grade"
    }
  }

  private func statusMessage(for status: ReviewStatus, submission: WorkSubmission) -> String {
    switch status {
    case .draft:
      return "Scores and feedback can be edited. Every score must be confirmed before review."
    case .reviewed:
      return "The grade has passed review and is ready for explicit teacher approval."
    case .approved:
      if submission.approvedReviewRevisionID == submission.reviewRevisionID {
        return "This revision is current and eligible for approved-only export."
      }
      return "This approval is out of date; edit or re-review before exporting."
    }
  }

  private func statusSymbol(for status: ReviewStatus) -> String {
    switch status {
    case .draft: return "pencil.circle"
    case .reviewed: return "checkmark.circle"
    case .approved: return "checkmark.seal.fill"
    }
  }

  private func statusColor(for status: ReviewStatus) -> Color {
    switch status {
    case .draft: return WorkspaceStyle.secondary
    case .reviewed: return .orange
    case .approved: return WorkspaceStyle.accent
    }
  }

  private func syncTransientState() {
    syncTransientState(from: submission)
  }

  private func syncTransientState(from value: WorkSubmission?) {
    scoreDrafts = Self.scoreTexts(for: assignment, submission: value)
    feedbackDraft = value?.feedback ?? ""
    scoreErrors = [:]
    feedbackError = nil
    isFeedbackDirty = false
  }

  private static func scoreTexts(
    for assignment: WorkAssignment, submission: WorkSubmission?
  ) -> [UUID: String] {
    Dictionary(
      uniqueKeysWithValues: assignment.criteria.map { criterion in
        let value = submission?.scores[criterion.id]?.value.decimalString ?? ""
        return (criterion.id, value)
      })
  }

  private func shortID(_ id: UUID) -> String {
    String(id.uuidString.prefix(8)).lowercased()
  }
}

private struct LiveReviewBadge: View {
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

private struct LiveReviewStatusBadge: View {
  let status: ReviewStatus

  var body: some View {
    Text(status.rawValue.capitalized)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(status == .approved ? WorkspaceStyle.accent : WorkspaceStyle.ink)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(WorkspaceStyle.inset, in: Capsule())
      .accessibilityLabel("Status")
      .accessibilityValue(status.rawValue)
  }
}

private struct LiveReviewMessage: View {
  let text: String
  let systemImage: String

  var body: some View {
    Label {
      Text(text)
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: systemImage)
    }
    .foregroundStyle(WorkspaceStyle.secondary)
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .combine)
  }
}
