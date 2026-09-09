import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
  import UIKit
#endif

public struct WorkspaceRootView: View {
  @State private var store = WorkspaceAccessSession.store
  @State private var access = WorkspaceAccessSession.controller
  @State private var unlockError: String?
  @Environment(\.scenePhase) private var scenePhase
  @State private var panel: InspectorPanel = .rubric
  @State private var sheet: WorkspaceSheet?
  @State private var importingDocuments = false
  @State private var importingArchive = false
  @State private var referencePartID: UUID?
  @State private var pendingURLs: [URL] = []
  @State private var showsImportPreview = false
  @State private var showsStatistics = false
  @State private var showsDemo = false
  @State private var compactTab = 0
  @State private var selectedReferenceID: UUID?
  @State private var exportFolder: WorkspaceExportFolder?
  @State private var showsGradeExporter = false
  @State private var archiveFile: WorkspaceArchiveFile?
  @State private var showsArchiveExporter = false

  public init() {}
  private var readOnly: Bool {
    #if os(iOS)
      UIDevice.current.userInterfaceIdiom == .phone
    #else
      false
    #endif
  }
  public var body: some View {
    Group {
      if access.isLocked {
        VStack(spacing: 18) {
          Image(systemName: "lock.fill").font(.largeTitle)
          Text("Workspace locked").font(.title2)
          Text("Unlock with this device’s owner authentication.").foregroundStyle(.secondary)
          Button("Unlock") {
            Task {
              do {
                try await access.unlock()
                unlockError = nil
              } catch { unlockError = error.localizedDescription }
            }
          }.buttonStyle(.borderedProminent).disabled(access.isAuthenticating)
          if let error = unlockError { Text(error).font(.caption) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        unlockedBody
      }
    }
    .background(WorkspaceActivityObserver(onActivity: { access.noteActivity() }))
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { access.applicationDidEnterBackground() }
    }
    .onChange(of: access.isLocked) { _, locked in
      if locked {
        unlockError = nil
        sheet = nil
        showsDemo = false
        showsImportPreview = false
        importingDocuments = false
        importingArchive = false
        showsGradeExporter = false
        showsArchiveExporter = false
      }
    }
  }
  private var unlockedBody: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      if store.workspace == nil {
        welcome
      } else {
        #if os(macOS)
          HSplitView {
            sidebar.frame(minWidth: 180, idealWidth: 215, maxWidth: 280)
            documentArea.frame(minWidth: 320)
            inspector.frame(minWidth: 280, idealWidth: 340, maxWidth: 540)
          }
        #else
          if readOnly {
            TabView(selection: $compactTab) {
              NavigationStack { sidebar.navigationTitle("Submissions") }.tabItem {
                Label("Work", systemImage: "list.bullet")
              }.tag(0)
              NavigationStack { documentArea.navigationTitle("Document") }.tabItem {
                Label("Document", systemImage: "doc")
              }.tag(1)
              NavigationStack { inspector.navigationTitle("Review") }.tabItem {
                Label("Review", systemImage: "list.clipboard")
              }.tag(2)
            }
          } else {
            NavigationSplitView {
              sidebar.navigationTitle("Assignments")
            } detail: {
              ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                  documentArea.frame(minWidth: 350)
                  Divider()
                  inspector.frame(width: 340)
                }
                VStack {
                  Picker("Panel", selection: $compactTab) {
                    Text("Document").tag(0)
                    Text("Review").tag(1)
                  }.pickerStyle(.segmented)
                  if compactTab == 0 { documentArea } else { inspector }
                }
              }
            }
          }
        #endif
        if showsStatistics, let assignment = store.assignment {
          Divider()
          LiveStatisticsPane(assignment: assignment).frame(maxHeight: 260)
        }
      }
      Divider()
      statusBar
    }
    .background(WorkspaceStyle.background).foregroundStyle(WorkspaceStyle.ink).tint(
      WorkspaceStyle.accent
    )
    .preferredColorScheme(
      store.appearance == .system ? nil : store.appearance == .dark ? .dark : .light
    )
    .task { await store.start() }
    .sheet(item: $sheet) { selected in sheetContent(selected) }
    .sheet(isPresented: $showsDemo) {
      VStack {
        HStack {
          Text("Synthetic interface demo").font(.headline)
          Spacer()
          Button("Close") { showsDemo = false }
        }.padding()
        ScrollView([.horizontal, .vertical]) { DemoWorkspaceRootView() }
      }
      #if os(macOS)
        .frame(width: 1200, height: 800)
      #endif
    }
    .fileImporter(
      isPresented: $importingDocuments, allowedContentTypes: [.pdf, .jpeg, .png, .heic],
      allowsMultipleSelection: true
    ) { result in
      do {
        pendingURLs = try result.get()
        showsImportPreview = !pendingURLs.isEmpty
      } catch { store.errorMessage = error.localizedDescription }
    }
    .fileImporter(
      isPresented: $importingArchive, allowedContentTypes: [.data], allowsMultipleSelection: false
    ) { result in
      do {
        if let url = try result.get().first { Task { await store.importArchive(from: url) } }
      } catch { store.errorMessage = error.localizedDescription }
    }
    .sheet(isPresented: $showsImportPreview) {
      DocumentImportPreview(
        urls: $pendingURLs,
        target: referencePartID == nil ? candidateTitle : "Assignment references"
      ) {
        let urls = pendingURLs
        let part = referencePartID
        showsImportPreview = false
        pendingURLs = []
        referencePartID = nil
        store.beginImportDocuments(urls, referencePartID: part)
      }
    }
    .fileExporter(
      isPresented: $showsGradeExporter, document: exportFolder, contentType: .folder,
      defaultFilename: "Grading export"
    ) { result in
      switch result {
      case .success: store.notice = "Approved export saved."
      case .failure(let error): store.errorMessage = error.localizedDescription
      }
      store.isExporting = false
      if let directory = exportFolder?.directory {
        try? FileManager.default.removeItem(at: directory)
      }
      exportFolder = nil
    }
    .fileExporter(
      isPresented: $showsArchiveExporter, document: archiveFile, contentType: .data,
      defaultFilename: "Workspace.gradingworkspace"
    ) { result in
      switch result {
      case .success:
        store.notice = "Workspace archive saved. It contains original documents and identities."
      case .failure(let error): store.errorMessage = error.localizedDescription
      }
      if let url = archiveFile?.url { try? FileManager.default.removeItem(at: url) }
      archiveFile = nil
    }
    .onChange(of: showsGradeExporter) { _, visible in if !visible { store.isExporting = false } }
    .alert(
      "Operation could not finish",
      isPresented: Binding(
        get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    ) {
      Button("OK") { store.errorMessage = nil }
    } message: {
      Text(store.errorMessage ?? "")
    }
  }
  private var candidateTitle: String {
    guard let submission = store.submission else { return "Select a candidate" }
    return store.masksEnabled
      ? submission.candidateAlias
      : store.candidateNames[submission.candidateID] ?? submission.candidateAlias
  }
  private var toolbar: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        Label("Grading Workspace", systemImage: "square.stack.3d.up.fill").font(.headline)
        workspaceMenu
        Spacer()
        toolbarActions
      }
      HStack {
        workspaceMenu
        Spacer()
        toolbarActions
      }
    }.padding(12).background(WorkspaceStyle.surface)
  }
  private var workspaceMenu: some View {
    Menu {
      if !readOnly { Button("New workspace") { sheet = .workspace } }
      Button("Import workspace copy") { importingArchive = true }
      Button("Workspace copies and backups") { sheet = .transfer }
      Divider()
      ForEach(store.summaries) { item in
        Button("\(item.title) · \(item.containerID.uuidString.prefix(6))") {
          Task { await store.selectWorkspace(item.containerID) }
        }
      }
      Divider()
      Button("View synthetic demo") { showsDemo = true }
    } label: {
      Label(store.workspace?.title ?? "Workspaces", systemImage: "folder")
    }
    .disabled(store.isBusy || store.isExporting)
  }
  private var toolbarActions: some View {
    HStack(spacing: 10) {
      if store.workspace != nil {
        Button {
          showsStatistics.toggle()
        } label: {
          Image(systemName: "chart.bar.xaxis")
        }.help("Assignment statistics").accessibilityLabel("Toggle statistics")
        Button {
          sheet = .privacy
        } label: {
          Image(systemName: store.masksEnabled ? "eye.slash" : "lock.shield")
        }.help("Privacy and local access").accessibilityLabel("Privacy and local access")
        if !readOnly {
          Button {
            sheet = .exports
          } label: {
            Image(systemName: "square.and.arrow.up")
          }.help("Export approved work").accessibilityLabel("Export approved work")
        }
      }
      Menu {
        ForEach(WorkspaceAppearance.allCases) { appearance in
          Button(appearance.rawValue) { store.appearance = appearance }
        }
      } label: {
        Image(systemName: "circle.lefthalf.filled")
      }.accessibilityLabel("Appearance")
    }
  }
  private var welcome: some View {
    VStack(spacing: 20) {
      Image(systemName: "doc.text.magnifyingglass").font(.system(size: 52)).foregroundStyle(
        WorkspaceStyle.accent)
      Text("Your work stays on this device").font(.title2.bold())
      Text(
        readOnly
          ? "Import a workspace copy to review documents, grades, and feedback."
          : "Create a workspace, add an assignment, and review submissions with your rubric."
      )
      .foregroundStyle(WorkspaceStyle.secondary).multilineTextAlignment(.center).frame(
        maxWidth: 500)
      if !readOnly {
        Button("Create workspace") { sheet = .workspace }.buttonStyle(.borderedProminent)
      }
      Button("Import workspace copy") { importingArchive = true }
      if !store.summaries.isEmpty {
        ForEach(store.summaries) { item in
          Button("Open \(item.title)") { Task { await store.selectWorkspace(item.containerID) } }
        }
      }
      Button("Explore synthetic demo") { showsDemo = true }.font(.callout)
      Text("Local processing · No generative AI · Teacher-approved grades").font(.caption)
        .foregroundStyle(WorkspaceStyle.secondary)
    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  private var sidebar: some View {
    List {
      Section("Assignments") {
        ForEach(store.workspace?.assignments ?? []) { assignment in
          Button {
            Task { await store.selectAssignment(assignment.id) }
          } label: {
            VStack(alignment: .leading) {
              Text(assignment.title).fontWeight(
                store.assignmentID == assignment.id ? .semibold : .regular)
              Text(assignment.course).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
            }
          }.buttonStyle(.plain).accessibilityAddTraits(
            store.assignmentID == assignment.id ? .isSelected : [])
        }
        if !readOnly { Button("Add assignment", systemImage: "plus") { sheet = .assignment } }
      }
      if let assignment = store.assignment {
        Section("Candidates") {
          ForEach(assignment.submissions) { submission in
            Button {
              Task {
                await store.selectSubmission(submission.id)
                if readOnly { compactTab = 1 }
              }
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(
                  store.masksEnabled
                    ? submission.candidateAlias
                    : store.candidateNames[submission.candidateID] ?? submission.candidateAlias)
                Text(submission.status.rawValue.capitalized).font(.caption).foregroundStyle(
                  WorkspaceStyle.secondary)
              }
            }.buttonStyle(.plain).accessibilityAddTraits(
              store.submissionID == submission.id ? .isSelected : [])
          }
          if !readOnly {
            Button("Add candidate", systemImage: "person.badge.plus") { sheet = .candidate }
          }
        }
      }
    }.disabled(store.isBusy || store.isExporting)
  }
  private var documentArea: some View {
    VStack(spacing: 0) {
      HStack {
        Text(candidateTitle).font(.headline).lineLimit(1)
        Spacer()
        if !readOnly {
          Button("Import", systemImage: "doc.badge.plus") {
            referencePartID = nil
            importingDocuments = true
          }.disabled(store.submission == nil || store.isBusy)
          Button {
            Task { await store.undoMark() }
          } label: {
            Image(systemName: "arrow.uturn.backward")
          }.disabled(!store.canUndoMark || store.isBusy).help("Undo annotation").accessibilityLabel(
            "Undo annotation")
        }
      }.padding(10)
      if store.inputs.count > 1 {
        Picker(
          "Document",
          selection: Binding(
            get: { store.documentID ?? store.inputs.first?.record.id },
            set: { store.documentID = $0 })
        ) {
          ForEach(Array(store.inputs.enumerated()), id: \.element.record.id) { index, input in
            Text(store.masksEnabled ? "Document \(index + 1)" : input.record.originalName).tag(
              Optional(input.record.id))
          }
        }.padding(.horizontal, 10)
      }
      if store.masksEnabled {
        Text("Display masking only. Original documents may still identify the student.").font(
          .caption
        ).foregroundStyle(.secondary).padding(8)
      }
      LiveDocumentPane(
        input: store.selectedInput, marks: store.submission?.marks ?? [],
        masked: store.masksEnabled, readOnly: readOnly || store.isBusy || store.isExporting,
        focusedRegion: store.focusedRegion,
        onAddMark: { mark in Task { await store.addMark(mark) } },
        onCrop: { region in Task { await store.addCrop(region) } },
        onRemoveMark: { id in Task { await store.removeMark(id) } })
    }
  }
  private var inspector: some View {
    VStack(spacing: 0) {
      Picker("Inspector", selection: $panel) {
        ForEach(InspectorPanel.allCases) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).padding(10)
      if let assignment = store.assignment {
        let renderedSubmission = store.submission
        switch panel {
        case .rubric:
          LiveReviewPane(
            assignment: assignment, submission: store.submission,
            readOnly: readOnly || store.isBusy || store.isExporting,
            saveError: store.errorMessage,
            onAssignmentChange: { updated in
              Task {
                await store.saveAssignment(
                  updated, expectedRubricRevision: assignment.rubricRevisionID)
              }
            },
            onSubmissionChange: { updated in
              let expected = renderedSubmission?.reviewRevisionID
              Task {
                if let expected {
                  await store.saveSubmission(updated, expectedReviewRevision: expected)
                }
              }
            },
            onImportReference: { partID in
              referencePartID = partID
              importingDocuments = true
            })
        case .ocr:
          VStack {
            if !readOnly {
              Picker(
                "Recognition language",
                selection: Binding(
                  get: { store.ocrLanguages.first ?? "en-US" },
                  set: { store.ocrLanguages = [$0] }
                )
              ) {
                ForEach(store.supportedOCRLanguages, id: \.self) { language in
                  Text(Locale.current.localizedString(forIdentifier: language) ?? language).tag(
                    language)
                }
              }.disabled(store.isRecognizing).padding(.horizontal, 8)
              HStack {
                Button(store.isRecognizing ? "Cancel recognition" : "Recognize text") {
                  if store.isRecognizing { store.cancelRecognition() } else { store.recognize() }
                }.disabled(store.inputs.isEmpty || store.isBusy)
                if store.isRecognizing { ProgressView().controlSize(.small) }
              }.padding(8)
            }
            LiveOCRPane(
              blocks: store.submission?.ocr.blocks ?? [], inputs: store.inputs,
              readOnly: readOnly || store.isBusy || store.isExporting, masked: store.masksEnabled,
              onBlocksChange: { blocks in
                if let expected = renderedSubmission?.reviewRevisionID {
                  Task { await store.saveBlocks(blocks, expectedReviewRevision: expected) }
                }
              },
              onFocus: {
                store.focus($0)
                if readOnly { compactTab = 1 }
              })
          }
        case .references:
          referencePanel
        }
      } else {
        ContentUnavailableView("Choose an assignment", systemImage: "list.clipboard")
      }
    }
  }
  private var referencePanel: some View {
    VStack {
      if store.referenceInputs.isEmpty {
        ContentUnavailableView(
          "Reference documents", systemImage: "books.vertical",
          description: Text("Add text references or import an answer key from the rubric editor."))
      } else {
        Picker("Reference", selection: $selectedReferenceID) {
          ForEach(store.referenceInputs, id: \.record.id) { input in
            Text(input.record.originalName).tag(Optional(input.record.id))
          }
        }.padding()
        LiveDocumentPane(
          input: store.referenceInputs.first { $0.record.id == selectedReferenceID }
            ?? store.referenceInputs.first,
          marks: [], masked: false, readOnly: true, focusedRegion: nil, onAddMark: { _ in },
          onCrop: { _ in }, onRemoveMark: { _ in })
      }
    }
  }
  private var statusBar: some View {
    HStack(spacing: 8) {
      if store.isBusy {
        ProgressView().controlSize(.small)
        Text(store.busyMessage)
        if store.isImporting { Button("Cancel import") { store.cancelImport() } }
      } else {
        Image(systemName: "internaldrive")
        Text(store.notice ?? (readOnly ? "Read-only review" : "Local workspace"))
      }
      Spacer()
      if let workspace = store.workspace {
        Text("Revision \(workspace.revisionID.uuidString.prefix(6))")
      }
    }.font(.caption).foregroundStyle(WorkspaceStyle.secondary).padding(.horizontal, 12).padding(
      .vertical, 7)
  }
  @ViewBuilder private func sheetContent(_ selected: WorkspaceSheet) -> some View {
    switch selected {
    case .workspace:
      SimpleEntrySheet(title: "New workspace", primaryLabel: "Workspace name", secondaryLabel: nil)
      { title, _ in Task { await store.createWorkspace(title) } }
    case .assignment:
      SimpleEntrySheet(
        title: "New assignment", primaryLabel: "Assignment title", secondaryLabel: "Course"
      ) { title, course in Task { await store.createAssignment(title: title, course: course) } }
    case .candidate:
      SimpleEntrySheet(
        title: "New candidate", primaryLabel: "Student name (optional)", secondaryLabel: nil,
        allowsEmpty: true
      ) { name, _ in Task { await store.createCandidate(name: name) } }
    case .privacy:
      PrivacyAccessView(
        accessController: access, masksEnabled: $store.masksEnabled, onDismiss: { sheet = nil })
    case .transfer:
      TransferWorkspaceView(
        workspaces: store.summaries, activeContainerID: store.workspace?.containerID,
        isBusy: store.isBusy, statusMessage: store.errorMessage ?? store.notice,
        onExport: { containerID in
          sheet = nil
          Task { await prepareArchive(containerID: containerID) }
        },
        onImport: {
          sheet = nil
          importingArchive = true
        },
        onActivate: { id in
          sheet = nil
          Task { await store.selectWorkspace(id) }
        },
        onDismiss: { sheet = nil })
    case .exports:
      VStack {
        HStack {
          Text("Export and backup").font(.title2.bold())
          Spacer()
          Button("Close") { sheet = nil }
        }.padding()
        if let assignment = store.assignment {
          GradeExportPanel(assignment: assignment, identities: store.candidateNames) {
            options, snapshot in
            sheet = nil
            Task {
              if let directory = await store.prepareGradeExport(
                options: options, snapshot: snapshot)
              {
                exportFolder = WorkspaceExportFolder(directory: directory)
                showsGradeExporter = true
              }
            }
          }
        }
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Text("Full workspace backup").font(.headline)
          Text(
            "Includes original documents, identity mappings, drafts, grades and history. This is not an anonymous copy."
          ).font(.caption).foregroundStyle(.secondary)
          Button("Create workspace archive") {
            sheet = nil
            Task { await prepareArchive() }
          }.disabled(store.workspace == nil || store.isBusy)
        }.padding()
      }.frame(idealWidth: 560)

    }
  }
  private func prepareArchive(containerID: UUID? = nil) async {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString).gradingworkspace")
    await store.exportArchive(containerID: containerID, to: url)
    if FileManager.default.fileExists(atPath: url.path), store.errorMessage == nil {
      archiveFile = WorkspaceArchiveFile(url: url)
      showsArchiveExporter = true
    }
  }
}
private enum InspectorPanel: String, CaseIterable, Identifiable {
  case rubric = "Rubric"
  case ocr = "OCR"
  case references = "References"
  var id: Self { self }
}
private enum WorkspaceSheet: String, Identifiable {
  case workspace, assignment, candidate, privacy, exports, transfer
  var id: Self { self }
}
private struct SimpleEntrySheet: View {
  @Environment(\.dismiss) private var dismiss
  let title: String
  let primaryLabel: String
  let secondaryLabel: String?
  var allowsEmpty = false
  let onSave: (String, String) -> Void
  @State private var primary = ""
  @State private var secondary = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(title).font(.title2.bold())
      TextField(primaryLabel, text: $primary).textFieldStyle(.roundedBorder)
      if let secondaryLabel {
        TextField(secondaryLabel, text: $secondary).textFieldStyle(.roundedBorder)
      }
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Create") {
          onSave(primary, secondary)
          dismiss()
        }.buttonStyle(.borderedProminent).disabled(
          !allowsEmpty && primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24).frame(idealWidth: 420)
  }
}
private struct DocumentImportPreview: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var urls: [URL]
  let target: String
  let onImport: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Import documents").font(.title2.bold())
      Text("Attach to: \(target)").font(.headline)
      Text(
        "Original files are copied into this workspace. Reorder or remove files before importing."
      ).font(.callout).foregroundStyle(.secondary)
      List {
        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
          HStack {
            Text(url.lastPathComponent).lineLimit(2)
            Spacer()
            Button {
              if index > 0 { urls.swapAt(index, index - 1) }
            } label: {
              Image(systemName: "arrow.up")
            }.disabled(index == 0).accessibilityLabel("Move document up")
            Button {
              if index + 1 < urls.count { urls.swapAt(index, index + 1) }
            } label: {
              Image(systemName: "arrow.down")
            }.disabled(index == urls.count - 1).accessibilityLabel("Move document down")
            Button {
              urls.remove(at: index)
            } label: {
              Image(systemName: "minus.circle")
            }.accessibilityLabel("Remove document from import")
          }.buttonStyle(.borderless)
        }
      }.frame(minHeight: 160, maxHeight: 350)
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Import \(urls.count) documents", action: onImport).buttonStyle(.borderedProminent)
          .disabled(urls.isEmpty)
      }
    }.padding(24).frame(idealWidth: 560)
  }
}

@MainActor private enum WorkspaceAccessSession {
  static let controller = LocalAccessController()
  static let store = LiveWorkspaceStore()
}
