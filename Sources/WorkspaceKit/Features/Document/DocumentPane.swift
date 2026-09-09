import SwiftUI

struct DocumentPane: View {
  let assignment: AssignmentPreview
  let submission: SubmissionPreview?

  var body: some View {
    VStack(spacing: 0) {
      documentHeader
      Divider()
      annotationToolbar
      Divider()
      documentContent
    }
    .background(WorkspaceStyle.background)
  }

  private var documentHeader: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "doc.text")
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(WorkspaceStyle.accent)
        .frame(width: 24, height: 24)

      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text("Document")
            .font(.system(size: 16, weight: .semibold))
          PreviewBadge(text: "Document layout preview")
        }

        Text(assignment.title)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(WorkspaceStyle.ink)
          .lineLimit(2)

        HStack(spacing: 6) {
          Text(assignment.course)
          Circle()
            .fill(WorkspaceStyle.secondary)
            .frame(width: 3, height: 3)
          if let submission {
            Text(submission.candidateLabel)
              .fontWeight(.medium)
          } else {
            Text("No candidate selected")
          }
        }
        .font(.system(size: 10))
        .foregroundStyle(WorkspaceStyle.secondary)
        .lineLimit(1)
      }

      Spacer(minLength: 10)

      VStack(alignment: .trailing, spacing: 5) {
        PreviewBadge(text: submission?.status ?? "No submission")
        Text(submission == nil ? "Select a sample submission" : "Sample document")
          .font(.system(size: 10))
          .foregroundStyle(WorkspaceStyle.secondary)
          .multilineTextAlignment(.trailing)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 15)
    .frame(minHeight: 76)
    .background(WorkspaceStyle.surface)
  }

  private var annotationToolbar: some View {
    HStack(spacing: 6) {
      PlannedButton(title: "Highlight", systemImage: "highlighter")
        .buttonStyle(.bordered)
        .controlSize(.small)
      PlannedButton(title: "Note", systemImage: "note.text.badge.plus")
        .buttonStyle(.bordered)
        .controlSize(.small)
      PlannedButton(title: "Draw", systemImage: "pencil.tip")
        .buttonStyle(.bordered)
        .controlSize(.small)
      PlannedButton(title: "Feedback", systemImage: "text.bubble")
        .buttonStyle(.bordered)
        .controlSize(.small)

      Spacer(minLength: 8)

      Label("Annotation tools are planned for a later milestone.", systemImage: "info.circle")
        .font(.system(size: 10))
        .foregroundStyle(WorkspaceStyle.secondary)
        .lineLimit(2)
        .multilineTextAlignment(.trailing)
        .help("Annotation tools are planned for a later milestone.")
        .accessibilityLabel("Annotation tools are planned for a later milestone")
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 9)
    .frame(minHeight: 48)
    .background(WorkspaceStyle.surface)
  }

  @ViewBuilder
  private var documentContent: some View {
    if let submission {
      if submission.document.sections.isEmpty {
        emptyState(
          title: "No document sections",
          message:
            "This sample submission does not include content for the document layout preview.",
          badge: "Sample content unavailable"
        )
      } else {
        ScrollView(.vertical) {
          DocumentPaper(document: submission.document)
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
        }
        .accessibilityLabel("Scrollable sample document preview")
        .id(submission.id)
      }
    } else {
      emptyState(
        title: "Choose a sample submission",
        message: "Select a candidate from the submissions list to preview its document layout.",
        badge: "No submission selected"
      )
    }
  }

  private func emptyState(title: String, message: String, badge: String) -> some View {
    VStack(spacing: 14) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 30, weight: .light))
        .foregroundStyle(WorkspaceStyle.accent)
      Text(title)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(WorkspaceStyle.ink)
      Text(message)
        .font(.system(size: 12))
        .foregroundStyle(WorkspaceStyle.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
      PreviewBadge(text: badge)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(32)
    .accessibilityElement(children: .combine)
  }
}

private struct DocumentPaper: View {
  let document: DocumentPreview

  var body: some View {
    VStack(alignment: .leading, spacing: 27) {
      paperHeader

      ForEach(document.sections) { section in
        DocumentSectionPreview(section: section)
      }

      HStack(spacing: 7) {
        Image(systemName: "checkmark.seal")
        Text("Sample content supplied for layout review")
      }
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(DocumentPalette.muted)
      .padding(.top, 3)
    }
    .padding(30)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 3))
    .overlay(
      RoundedRectangle(cornerRadius: 3)
        .stroke(DocumentPalette.rule, lineWidth: 1)
    )
    .compositingGroup()
    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Paper-like sample document")
  }

  private var paperHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 5) {
          Text(document.title)
            .font(.system(size: 25, weight: .semibold, design: .serif))
            .foregroundStyle(DocumentPalette.ink)
            .fixedSize(horizontal: false, vertical: true)
          Text(document.subtitle)
            .font(.system(size: 13))
            .foregroundStyle(DocumentPalette.muted)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 12)

        Text("SAMPLE")
          .font(.system(size: 9, weight: .bold))
          .tracking(1.4)
          .foregroundStyle(DocumentPalette.accent)
          .padding(.horizontal, 9)
          .padding(.vertical, 6)
          .overlay(
            Capsule().stroke(DocumentPalette.accent.opacity(0.45), lineWidth: 1)
          )
      }

      Rectangle()
        .fill(DocumentPalette.rule)
        .frame(height: 1)
    }
  }
}

private struct DocumentSectionPreview: View {
  let section: DocumentSection

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      Text(section.heading.isEmpty ? "Untitled section" : section.heading)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(DocumentPalette.ink)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 6) {
        Text("Prompt")
          .font(.system(size: 10, weight: .bold))
          .tracking(0.8)
          .foregroundStyle(DocumentPalette.muted)
        Text(section.prompt.isEmpty ? "Prompt not supplied in this sample." : section.prompt)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(DocumentPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("Response")
          .font(.system(size: 10, weight: .bold))
          .tracking(0.8)
          .foregroundStyle(DocumentPalette.muted)

        HStack(alignment: .top, spacing: 11) {
          RoundedRectangle(cornerRadius: 2)
            .fill(DocumentPalette.accent)
            .frame(width: 3)
          Text(
            section.response.isEmpty
              ? "No response supplied in this sample."
              : section.response
          )
          .font(.system(size: 14))
          .foregroundStyle(DocumentPalette.ink)
          .lineSpacing(5)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DocumentPalette.responseSurface, in: RoundedRectangle(cornerRadius: 5))
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(section.heading.isEmpty ? "Document section" : section.heading)
  }
}

private enum DocumentPalette {
  static let accent = Color(red: 0.08, green: 0.48, blue: 0.46)
  static let ink = Color(red: 0.11, green: 0.19, blue: 0.27)
  static let muted = Color(red: 0.31, green: 0.38, blue: 0.43)
  static let rule = Color(red: 0.85, green: 0.87, blue: 0.86)
  static let responseSurface = Color(red: 0.96, green: 0.97, blue: 0.95)
}
