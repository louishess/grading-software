import SwiftUI

public struct TransferWorkspaceView: View {
  private let workspaces: [WorkspaceSummary]
  private let activeContainerID: UUID?
  private let isBusy: Bool
  private let statusMessage: String?
  private let onExport: (UUID) -> Void
  private let onImport: () -> Void
  private let onActivate: (UUID) -> Void
  private let onDismiss: () -> Void

  @State private var selectedContainerID: UUID?

  public init(
    workspaces: [WorkspaceSummary],
    activeContainerID: UUID?,
    isBusy: Bool,
    statusMessage: String?,
    onExport: @escaping (UUID) -> Void,
    onImport: @escaping () -> Void,
    onActivate: @escaping (UUID) -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.workspaces = workspaces
    self.activeContainerID = activeContainerID
    self.isBusy = isBusy
    self.statusMessage = statusMessage
    self.onExport = onExport
    self.onImport = onImport
    self.onActivate = onActivate
    self.onDismiss = onDismiss
    _selectedContainerID = State(initialValue: activeContainerID ?? workspaces.first?.containerID)
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        workspaceSection
        transferActions
        transferNotes
        statusArea
      }
      .frame(maxWidth: 760, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.vertical, 24)
      .frame(maxWidth: .infinity, alignment: .center)
    }
    .background(WorkspaceStyle.background)
    .foregroundStyle(WorkspaceStyle.ink)
    .tint(WorkspaceStyle.accent)
    .onChange(of: activeContainerID) { _, newValue in
      if let newValue, workspaces.contains(where: { $0.containerID == newValue }) {
        selectedContainerID = newValue
      }
    }
    .onChange(of: workspaces) { _, newValue in
      normalizeSelection(in: newValue, preferred: activeContainerID)
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "arrow.triangle.2.circlepath")
        .font(.system(size: 27, weight: .semibold))
        .foregroundStyle(WorkspaceStyle.accent)
        .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 5) {
        Text("Workspace transfer")
          .font(.system(size: 23, weight: .semibold))
        Text("Move a local workspace with an explicit, reviewable archive.")
          .font(.system(size: 13))
          .foregroundStyle(WorkspaceStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 12)

      Button("Done", action: onDismiss)
        .buttonStyle(.bordered)
        .accessibilityHint("Closes workspace transfer")
    }
  }

  private var workspaceSection: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Local workspaces")
            .font(.system(size: 14, weight: .semibold))
          Text("Choose which local copy to export or activate.")
            .font(.system(size: 11))
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 8)
        Text("\(workspaces.count)")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(WorkspaceStyle.secondary)
          .accessibilityLabel("\(workspaces.count) local workspaces")
      }

      if workspaces.isEmpty {
        VStack(alignment: .leading, spacing: 9) {
          Label("No local workspaces yet", systemImage: "tray")
            .font(.system(size: 13, weight: .semibold))
          Text(
            "Import a workspace archive to add a local copy. Nothing is synchronized automatically."
          )
          .font(.system(size: 11))
          .foregroundStyle(WorkspaceStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 9))
      } else {
        LazyVStack(spacing: 9) {
          ForEach(workspaces) { workspace in
            workspaceRow(workspace)
          }
        }
      }
    }
    .workspaceCard()
  }

  private var transferActions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) {
        actionButton(
          title: "Export full archive", systemImage: "arrow.up.doc", prominent: true,
          action: exportSelected
        )
        actionButton(
          title: "Import archive", systemImage: "arrow.down.doc", prominent: false,
          action: onImport
        )
        activateButton
      }
      VStack(alignment: .leading, spacing: 10) {
        actionButton(
          title: "Export full archive", systemImage: "arrow.up.doc", prominent: true,
          action: exportSelected
        )
        actionButton(
          title: "Import archive", systemImage: "arrow.down.doc", prominent: false,
          action: onImport
        )
        activateButton
      }
    }
  }

  private var activateButton: some View {
    Button(action: activateSelected) {
      Label("Use selected workspace", systemImage: "checkmark.circle")
    }
    .buttonStyle(.bordered)
    .disabled(isBusy || selectedWorkspace == nil || selectedContainerID == activeContainerID)
    .accessibilityHint("Makes the selected local copy active")
  }

  private var transferNotes: some View {
    VStack(alignment: .leading, spacing: 12) {
      note(
        title: "Full archive privacy",
        systemImage: "lock.doc",
        text:
          "Full archives contain original files and identity mappings. Device-owner authentication state is excluded; configure local access again on the destination device."
      )
      Divider()
      note(
        title: "Copies stay separate",
        systemImage: "square.on.square",
        text:
          "An import with the same revision head is shown as a duplicate. Different heads become a separate copy with explicit active selection. The app does not merge, replace, or sync workspaces."
      )
    }
    .workspaceCard()
  }

  @ViewBuilder
  private var statusArea: some View {
    if isBusy {
      HStack(spacing: 9) {
        ProgressView()
          .controlSize(.small)
        Text(statusMessage ?? "Workspace transfer in progress…")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(WorkspaceStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Workspace transfer in progress")
    } else if let statusMessage, !statusMessage.isEmpty {
      Label(statusMessage, systemImage: "info.circle")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(WorkspaceStyle.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isStaticText)
    }
  }

  private var selectedWorkspace: WorkspaceSummary? {
    guard let selectedContainerID else { return nil }
    return workspaces.first { $0.containerID == selectedContainerID }
  }

  private func workspaceRow(_ workspace: WorkspaceSummary) -> some View {
    let isSelected = workspace.containerID == selectedContainerID
    let isActive = workspace.containerID == activeContainerID
    return Button {
      selectedContainerID = workspace.containerID
    } label: {
      HStack(alignment: .top, spacing: 11) {
        Image(systemName: isActive ? "checkmark.circle.fill" : "square.stack.3d.up")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(isActive ? WorkspaceStyle.accent : WorkspaceStyle.secondary)
          .frame(width: 22, height: 22)

        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(workspace.title.isEmpty ? "Untitled workspace" : workspace.title)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(WorkspaceStyle.ink)
              .lineLimit(2)
            if isActive {
              PreviewBadge(text: "Active")
            }
          }
          Text("Updated \(workspace.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.system(size: 10))
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 8)
        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(WorkspaceStyle.accent)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isSelected ? WorkspaceStyle.accent.opacity(0.12) : WorkspaceStyle.inset,
        in: RoundedRectangle(cornerRadius: 9)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 9)
          .stroke(isSelected ? WorkspaceStyle.accent.opacity(0.45) : Color.clear, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityLabel(workspaceAccessibilityLabel(workspace, isActive: isActive))
    .accessibilityHint("Selects this workspace for transfer or activation")
  }

  @ViewBuilder
  private func actionButton(
    title: String,
    systemImage: String,
    prominent: Bool,
    action: @escaping () -> Void
  ) -> some View {
    if prominent {
      Button(action: action) {
        Label(title, systemImage: systemImage)
      }
      .buttonStyle(.borderedProminent)
      .disabled(isBusy || selectedWorkspace == nil)
      .accessibilityHint("Exports the selected workspace as a full archive")
    } else {
      Button(action: action) {
        Label(title, systemImage: systemImage)
      }
      .buttonStyle(.bordered)
      .disabled(isBusy)
      .accessibilityHint("Opens a file chooser for a workspace archive")
    }
  }

  private func note(title: String, systemImage: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(WorkspaceStyle.accent)
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
        Text(text)
          .font(.system(size: 11))
          .foregroundStyle(WorkspaceStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func workspaceAccessibilityLabel(_ workspace: WorkspaceSummary, isActive: Bool) -> String
  {
    let title = workspace.title.isEmpty ? "Untitled workspace" : workspace.title
    let activeText = isActive ? ", active" : ""
    return
      "\(title)\(activeText), updated \(workspace.modifiedAt.formatted(date: .abbreviated, time: .shortened))"
  }

  private func exportSelected() {
    guard let selectedContainerID else { return }
    onExport(selectedContainerID)
  }

  private func activateSelected() {
    guard let selectedContainerID else { return }
    onActivate(selectedContainerID)
  }

  private func normalizeSelection(in values: [WorkspaceSummary], preferred: UUID?) {
    if let preferred, values.contains(where: { $0.containerID == preferred }) {
      selectedContainerID = preferred
    } else if let selectedContainerID,
      values.contains(where: { $0.containerID == selectedContainerID })
    {
      return
    } else {
      selectedContainerID = values.first?.containerID
    }
  }
}
