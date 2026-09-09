import SwiftUI

public struct WorkspaceRootView: View {
  @State private var store: WorkspaceStore
  private let loadError: Bool

  public init() {
    do {
      _store = State(initialValue: WorkspaceStore(assignments: try PreviewCatalog.load()))
      loadError = false
    } catch {
      _store = State(initialValue: WorkspaceStore(assignments: []))
      loadError = true
    }
  }

  public var body: some View {
    @Bindable var store = store
    VStack(spacing: 0) {
      header
      Divider()
      if let assignment = store.assignment {
        HStack(spacing: 0) {
          AssignmentSidebar(store: store).frame(width: 226)
          Divider()
          VStack(spacing: 0) {
            HStack(spacing: 0) {
              DocumentPane(assignment: assignment, submission: store.submission)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
              Divider()
              ReviewPane(
                assignment: assignment, submission: store.submission,
                selectedTab: $store.inspectorTab
              )
              .frame(width: 330)
            }
            Divider()
            statisticsHeader
            if store.showsStatistics {
              StatisticsPane(
                assignment: assignment,
                selectedScopeID: Binding(
                  get: { store.selectedScopeID }, set: { store.selectScope($0) }
                )
              )
              .frame(height: 222)
            }
          }
        }
      } else {
        ContentUnavailableView(
          loadError ? "Sample data unavailable" : "No sample assignments",
          systemImage: "doc.questionmark",
          description: Text("Rebuild the app to restore its bundled sample resources.")
        ).frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      footer
    }
    .frame(minWidth: 1120, minHeight: 720)
    .background(WorkspaceStyle.background)
    .foregroundStyle(WorkspaceStyle.ink)
    .tint(WorkspaceStyle.accent)
    .preferredColorScheme(
      store.appearance == .system ? nil : store.appearance == .dark ? .dark : .light
    )
    .sheet(isPresented: $store.showsAccount) { AccountPreview() }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "square.stack.3d.up.fill")
        .font(.system(size: 21)).foregroundStyle(WorkspaceStyle.accent)
      VStack(alignment: .leading, spacing: 2) {
        Text("Grading Workspace").font(.system(size: 17, weight: .semibold))
        Text("A clearer view of every assignment")
          .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
      }
      Spacer()
      Label("Interface preview · Sample data", systemImage: "sparkle")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(WorkspaceStyle.secondary)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(WorkspaceStyle.inset, in: Capsule())
      Menu {
        ForEach(WorkspaceAppearance.allCases) { appearance in
          Button {
            store.appearance = appearance
          } label: {
            if store.appearance == appearance {
              Label(appearance.rawValue, systemImage: "checkmark")
            } else {
              Text(appearance.rawValue)
            }
          }
        }
      } label: {
        Image(systemName: "circle.lefthalf.filled").frame(width: 22, height: 22)
      }
      .menuStyle(.borderlessButton).fixedSize()
      .accessibilityLabel("Appearance").help("Choose light, dark, or system appearance")
      Button {
        store.showsAccount = true
      } label: {
        Label("Grader access", systemImage: "person.crop.circle")
      }
      .buttonStyle(.bordered)
      .help("Preview grader access; authentication is not connected")
    }
    .padding(.leading, 82).padding(.trailing, 20).frame(height: 70)
    .background(WorkspaceStyle.surface)
  }

  private var statisticsHeader: some View {
    HStack {
      Button {
        store.showsStatistics.toggle()
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "chart.bar.xaxis")
          Text("Assignment insights").fontWeight(.semibold)
          Image(systemName: store.showsStatistics ? "chevron.down" : "chevron.up")
            .font(.system(size: 10, weight: .semibold))
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        store.showsStatistics ? "Collapse assignment insights" : "Expand assignment insights"
      )
      .keyboardShortcut("i", modifiers: [.command, .option])
      Spacer()
      Text("Precomputed sample statistics")
        .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
    }
    .padding(.horizontal, 20).frame(height: 40)
    .background(WorkspaceStyle.surface)
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Circle().fill(WorkspaceStyle.accent).frame(width: 5, height: 5)
      Text("Synthetic examples only")
      Spacer()
      Text("Document reader and supporting software to be selected")
    }
    .font(.system(size: 10)).foregroundStyle(WorkspaceStyle.secondary)
    .padding(.horizontal, 18).frame(height: 26)
    .background(WorkspaceStyle.surface)
  }
}

private struct AssignmentSidebar: View {
  let store: WorkspaceStore

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("YOUR WORKSPACE")
        .font(.system(size: 10, weight: .bold)).tracking(1.4)
        .foregroundStyle(WorkspaceStyle.secondary)
        .padding(.top, 24).padding(.bottom, 12)
      ForEach(store.assignments) { assignment in
        Button {
          store.selectAssignment(assignment.id)
        } label: {
          HStack(alignment: .top, spacing: 9) {
            Image(systemName: assignment.id == "math" ? "function" : "text.alignleft")
              .font(.system(size: 14, weight: .semibold)).frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
              Text(assignment.title).font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.leading)
              Text(assignment.course).font(.system(size: 10))
                .foregroundStyle(WorkspaceStyle.secondary)
            }
            Spacer(minLength: 0)
          }
          .padding(12).frame(maxWidth: .infinity, alignment: .leading)
          .background(
            store.selectedAssignmentID == assignment.id ? WorkspaceStyle.surface : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
          )
          .overlay(alignment: .leading) {
            if store.selectedAssignmentID == assignment.id {
              RoundedRectangle(cornerRadius: 2).fill(WorkspaceStyle.accent)
                .frame(width: 3).padding(.vertical, 10)
            }
          }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(store.selectedAssignmentID == assignment.id ? .isSelected : [])
        .padding(.bottom, 4)
      }
      HStack {
        Text("SUBMISSIONS").font(.system(size: 10, weight: .bold)).tracking(1.4)
        Spacer()
        Text("\(store.assignment?.submissions.count ?? 0)")
          .font(.system(size: 11, weight: .semibold))
      }
      .foregroundStyle(WorkspaceStyle.secondary)
      .padding(.top, 25).padding(.bottom, 10)
      ScrollView {
        VStack(spacing: 5) {
          ForEach(store.assignment?.submissions ?? []) { submission in
            Button {
              store.selectSubmission(submission.id)
            } label: {
              HStack(spacing: 10) {
                Image(systemName: "doc.text")
                  .font(.system(size: 14)).foregroundStyle(WorkspaceStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                  Text(submission.candidateLabel).font(.system(size: 12, weight: .medium))
                  Text(submission.status).font(.system(size: 10))
                    .foregroundStyle(WorkspaceStyle.secondary)
                }
                Spacer()
                if store.selectedSubmissionID == submission.id {
                  Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
              }
              .padding(11).frame(maxWidth: .infinity, alignment: .leading)
              .background(
                store.selectedSubmissionID == submission.id
                  ? WorkspaceStyle.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
              )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(store.selectedSubmissionID == submission.id ? .isSelected : [])
          }
        }
      }
      Spacer(minLength: 12)
      VStack(alignment: .leading, spacing: 10) {
        Label("Review progress", systemImage: "circle.dashed")
          .font(.system(size: 12, weight: .semibold))
        Text("0 of \(store.assignment?.submissions.count ?? 0) approved · Preview")
          .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
        Capsule().fill(WorkspaceStyle.border).frame(height: 4)
        Text("Grading and approval arrive in a later milestone.")
          .font(.system(size: 10)).foregroundStyle(WorkspaceStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(13)
      .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 10))
      .padding(.bottom, 16)
      VStack(alignment: .leading, spacing: 8) {
        PlannedButton(title: "Anonymity mode", systemImage: "eye.slash")
        Text("Automatic name redaction is planned.")
          .font(.system(size: 10)).foregroundStyle(WorkspaceStyle.secondary)
        PlannedButton(title: "Import assignment", systemImage: "square.and.arrow.down")
      }.padding(.bottom, 20)
    }
    .padding(.horizontal, 14)
    .background(WorkspaceStyle.background)
  }
}

private struct AccountPreview: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Image(systemName: "person.crop.circle.badge.checkmark")
          .font(.system(size: 32)).foregroundStyle(WorkspaceStyle.accent)
        Spacer()
        PreviewBadge(text: "Layout preview")
      }
      Text("Grader access").font(.system(size: 25, weight: .semibold))
      Text("A place for approved graders")
        .font(.system(size: 14, weight: .medium))
      Text(
        "Sign-in and grader approval will appear here. Authentication and authorization are not connected."
      )
      .font(.system(size: 13)).foregroundStyle(WorkspaceStyle.secondary)
      VStack(alignment: .leading, spacing: 14) {
        Label("Sign in with an approved account", systemImage: "person.crop.circle")
        Divider()
        Label("Confirm assignment permissions", systemImage: "checkmark.shield")
      }.font(.system(size: 13)).workspaceCard()
      HStack {
        PlannedButton(title: "Sign in", systemImage: "arrow.right.circle")
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(28).frame(width: 440)
    .background(WorkspaceStyle.background)
  }
}
