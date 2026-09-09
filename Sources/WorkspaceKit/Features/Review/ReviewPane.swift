import SwiftUI

struct ReviewPane: View {
  let assignment: AssignmentPreview
  let submission: SubmissionPreview?
  @Binding var selectedTab: InspectorTab

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      inspectorHeader
      Divider()
      Picker("Review section", selection: $selectedTab) {
        ForEach(InspectorTab.allCases) { tab in
          Text(tab.rawValue).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(WorkspaceStyle.surface)
      Divider()
      ScrollView {
        tabContent
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollIndicators(.visible)
      .id("\(submission?.id ?? assignment.id)-\(selectedTab.rawValue)")
    }
    .background(WorkspaceStyle.background)
  }

  private var inspectorHeader: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Review")
            .font(.system(size: 16, weight: .semibold))
          Text(assignment.title)
            .font(.system(size: 11))
            .foregroundStyle(WorkspaceStyle.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        PreviewBadge(text: "Sample")
      }
      if let submission {
        HStack(spacing: 7) {
          Image(systemName: "person.crop.circle")
            .foregroundStyle(WorkspaceStyle.accent)
          Text(submission.candidateLabel)
            .font(.system(size: 12, weight: .medium))
          Text("·")
            .foregroundStyle(WorkspaceStyle.secondary)
          Text(submission.status)
            .font(.system(size: 11))
            .foregroundStyle(WorkspaceStyle.secondary)
        }
      } else {
        Label("No sample submission selected", systemImage: "doc.questionmark")
          .font(.system(size: 11))
          .foregroundStyle(WorkspaceStyle.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(WorkspaceStyle.surface)
  }

  @ViewBuilder
  private var tabContent: some View {
    switch selectedTab {
    case .rubric:
      rubricContent
    case .references:
      referencesContent
    case .transcription:
      transcriptionContent
    }
  }

  private var rubricContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      scoreSummary
      sectionHeading(
        title: "Rubric",
        subtitle: "Read the sample score against each criterion."
      )
      if assignment.rubric.isEmpty {
        emptyState(
          title: "No rubric criteria",
          message: "This sample assignment does not include rubric criteria."
        )
      } else {
        ForEach(assignment.rubric) { criterion in
          criterionCard(criterion)
        }
      }
      feedbackCard
      actionGroup(
        title: "Scoring controls",
        actions: [
          ("Edit scores", "pencil", "Score editing is planned for a later milestone."),
          (
            "Edit feedback", "text.bubble", "Feedback editing is planned for a later milestone."
          ),
          (
            "Approve grade", "checkmark.circle",
            "Approval is unavailable while this is a sample preview."
          ),
        ]
      )
    }
  }

  private var scoreSummary: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Sample total")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WorkspaceStyle.secondary)
          if let submission {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
              Text("\(submission.exampleScore)")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(WorkspaceStyle.ink)
              Text("/ \(assignment.maximumScore)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WorkspaceStyle.secondary)
            }
          } else {
            Text("— / \(assignment.maximumScore)")
              .font(.system(size: 24, weight: .semibold))
              .foregroundStyle(WorkspaceStyle.secondary)
          }
        }
        Spacer(minLength: 8)
        PreviewBadge(text: "Read only")
      }
      if let submission {
        ProgressView(
          value: Double(submission.exampleScore),
          total: Double(max(assignment.maximumScore, 1))
        )
        .tint(WorkspaceStyle.accent)
        .accessibilityLabel(
          "Sample total, \(submission.exampleScore) of \(assignment.maximumScore) points"
        )
      }
      Text("Precomputed sample score for interface review; no grade is being calculated.")
        .font(.system(size: 10))
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .workspaceCard()
  }

  private func criterionCard(_ criterion: RubricCriterion) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 5) {
          Text(partTitle(for: criterion.partID))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(WorkspaceStyle.accent)
          Text(criterion.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WorkspaceStyle.ink)
        }
        Spacer(minLength: 8)
        criterionScore(criterion)
      }
      Divider()
      Text(criterion.description)
        .font(.system(size: 12))
        .foregroundStyle(WorkspaceStyle.ink)
        .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 5) {
        Label("Performance guidance", systemImage: "checkmark.seal")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(WorkspaceStyle.secondary)
        Text(criterion.performanceDescription)
          .font(.system(size: 11))
          .foregroundStyle(WorkspaceStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .workspaceCard()
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      "\(criterion.title), \(scoreAccessibilityText(for: criterion)), \(criterion.description)"
    )
  }

  private func criterionScore(_ criterion: RubricCriterion) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 2) {
      if let score = submission?.criterionScores[criterion.id] {
        Text("\(score)")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(WorkspaceStyle.ink)
      } else {
        Text("—")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(WorkspaceStyle.secondary)
      }
      Text("/ \(criterion.maximumScore)")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(WorkspaceStyle.secondary)
    }
    .accessibilityLabel(scoreAccessibilityText(for: criterion))
  }

  private var feedbackCard: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 7) {
        Image(systemName: "text.bubble")
          .foregroundStyle(WorkspaceStyle.accent)
        Text("Read-only feedback")
          .font(.system(size: 12, weight: .semibold))
        Spacer(minLength: 6)
        PreviewBadge(text: "Sample")
      }
      Text(
        submission?.feedback
          ?? "Feedback preview is unavailable until a sample submission is selected."
      )
      .font(.system(size: 12))
      .foregroundStyle(submission == nil ? WorkspaceStyle.secondary : WorkspaceStyle.ink)
      .fixedSize(horizontal: false, vertical: true)
    }
    .workspaceCard()
  }

  private var referencesContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeading(
        title: "References",
        subtitle: "Sample guidance connected to each assignment part."
      )
      actionGroup(
        title: "Reference library",
        actions: [
          (
            "Import references", "square.and.arrow.down",
            "Reference import is planned for a later milestone."
          )
        ]
      )
      referenceSection(
        title: "Answer key",
        subtitle: "Expected results and essential reasoning.",
        systemImage: "checkmark.seal",
        references: assignment.answerKey
      )
      referenceSection(
        title: "Exemplars",
        subtitle: "Useful moves to look for in a strong response.",
        systemImage: "star",
        references: assignment.exemplars
      )
    }
  }

  private func referenceSection(
    title: String,
    subtitle: String,
    systemImage: String,
    references: [ReferencePreview]
  ) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        Image(systemName: systemImage)
          .foregroundStyle(WorkspaceStyle.accent)
        Text(title)
          .font(.system(size: 13, weight: .semibold))
        Spacer(minLength: 4)
        PreviewBadge(text: "Sample")
      }
      Text(subtitle)
        .font(.system(size: 11))
        .foregroundStyle(WorkspaceStyle.secondary)
      if references.isEmpty {
        emptyState(
          title: "No \(title.lowercased())",
          message: "This sample assignment does not include reference material."
        )
      } else {
        ForEach(references) { reference in
          referenceCard(reference)
        }
      }
    }
  }

  private func referenceCard(_ reference: ReferencePreview) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(partTitle(for: reference.partID))
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(WorkspaceStyle.accent)
      Text(reference.title)
        .font(.system(size: 12, weight: .semibold))
      Text(reference.body)
        .font(.system(size: 12))
        .foregroundStyle(WorkspaceStyle.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
    .workspaceCard()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(reference.title), for \(partTitle(for: reference.partID)). \(reference.body)"
    )
  }

  private var transcriptionContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeading(
        title: "OCR preview",
        subtitle: "Review the supplied text alongside the document layout."
      )
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 7) {
          Image(systemName: "text.viewfinder")
            .foregroundStyle(WorkspaceStyle.accent)
          Text("Manually supplied transcription")
            .font(.system(size: 12, weight: .semibold))
          Spacer(minLength: 4)
          PreviewBadge(text: "Preview text")
        }
        Text(
          submission?.transcription
            ?? "No sample transcription is available until a sample submission is selected."
        )
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(submission == nil ? WorkspaceStyle.secondary : WorkspaceStyle.ink)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
      }
      .workspaceCard()
      Text("This text was supplied with the synthetic fixture. Recognition has not been performed.")
        .font(.system(size: 10))
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
      actionGroup(
        title: "Transcription controls",
        actions: [
          (
            "Run recognition", "text.viewfinder",
            "Recognition is planned for a later milestone."
          ),
          (
            "Correct transcription", "pencil.and.outline",
            "Transcription correction is planned for a later milestone."
          ),
        ]
      )
    }
  }

  private func sectionHeading(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
      Text(subtitle)
        .font(.system(size: 11))
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func actionGroup(
    title: String,
    actions: [(String, String, String)]
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(WorkspaceStyle.secondary)
      ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
        VStack(alignment: .leading, spacing: 3) {
          PlannedButton(title: action.0, systemImage: action.1)
          Text(action.2)
            .font(.system(size: 10))
            .foregroundStyle(WorkspaceStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(13)
    .background(WorkspaceStyle.inset.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(WorkspaceStyle.border, lineWidth: 1))
  }

  private func emptyState(title: String, message: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(title, systemImage: "tray")
        .font(.system(size: 12, weight: .semibold))
      Text(message)
        .font(.system(size: 11))
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 9))
  }

  private func partTitle(for partID: String) -> String {
    assignment.parts.first(where: { $0.id == partID })?.title ?? "Assignment part"
  }

  private func scoreAccessibilityText(for criterion: RubricCriterion) -> String {
    guard let score = submission?.criterionScores[criterion.id] else {
      return "No sample score of \(criterion.maximumScore) points"
    }
    return "Sample score \(score) of \(criterion.maximumScore) points"
  }
}
