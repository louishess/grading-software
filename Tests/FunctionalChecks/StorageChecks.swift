import CryptoKit
import Foundation
import WorkspaceKit

private struct StorageCheckFailure: Error, CustomStringConvertible {
  var description: String
}

private func storageExpect(
  _ condition: @autoclosure () throws -> Bool,
  _ message: String,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  guard try condition() else {
    throw StorageCheckFailure(description: "\(file):\(line): \(message)")
  }
}

@MainActor private func storageExpectThrows(
  _ message: String, operation: () async throws -> Void
) async throws {
  do {
    try await operation()
    throw StorageCheckFailure(description: message)
  } catch is StorageCheckFailure {
    throw StorageCheckFailure(description: message)
  } catch {}
}

public func runStorageChecks() async throws {
  try await simultaneousSaveCheck()
  try await repositoryRevisionAssetAndArchiveChecks()
  try await stagedAssetRecoveryChecks()
  try await stagedImportRecoveryCheck()
  try await archiveWriteFailureCheck()
  try await localAccessChecks()
}

private enum SaveRaceOutcome: Sendable {
  case saved(WorkspaceData)
  case stale
  case failed(String)
}

private func simultaneousSaveCheck() async throws {
  let testRoot = temporaryDirectory(label: "simultaneous-save")
  defer { try? FileManager.default.removeItem(at: testRoot) }
  try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
  let repositoryRoot = testRoot.appendingPathComponent("Repository")
  let firstRepository = try WorkspaceRepository(rootURL: repositoryRoot)
  let baseline = try await firstRepository.createWorkspace(title: "Concurrent baseline")
  let secondRepository = try WorkspaceRepository(rootURL: repositoryRoot)
  _ = try await secondRepository.loadWorkspace(containerID: baseline.containerID)

  var firstEdit = baseline
  firstEdit.title = "First concurrent edit"
  var secondEdit = baseline
  secondEdit.title = "Second concurrent edit"

  async let firstOutcome = attemptSave(
    firstEdit, expectedRevision: baseline.revisionID, repository: firstRepository)
  async let secondOutcome = attemptSave(
    secondEdit, expectedRevision: baseline.revisionID, repository: secondRepository)
  let outcomes = await [firstOutcome, secondOutcome]
  let saved = outcomes.compactMap { outcome -> WorkspaceData? in
    guard case .saved(let workspace) = outcome else { return nil }
    return workspace
  }
  let staleCount = outcomes.filter {
    if case .stale = $0 { return true }
    return false
  }.count
  let failures = outcomes.compactMap { outcome -> String? in
    guard case .failed(let message) = outcome else { return nil }
    return message
  }
  try storageExpect(
    saved.count == 1 && staleCount == 1 && failures.isEmpty,
    "Simultaneous saves did not produce exactly one winner and one stale revision: \(failures)")

  let current = try await firstRepository.loadWorkspace(containerID: baseline.containerID)
  try storageExpect(
    current.revisionID == saved[0].revisionID
      && current.parentRevisionID == baseline.revisionID
      && current.title == saved[0].title,
    "The simultaneous save lost or replaced the winning revision.")
}

private func attemptSave(
  _ workspace: WorkspaceData,
  expectedRevision: UUID,
  repository: WorkspaceRepository
) async -> SaveRaceOutcome {
  do {
    return .saved(
      try await repository.saveWorkspace(workspace, expectedRevision: expectedRevision))
  } catch let failure as WorkspaceFailure {
    if case .staleRevision = failure { return .stale }
    return .failed(failure.localizedDescription)
  } catch {
    return .failed(error.localizedDescription)
  }
}

private func repositoryRevisionAssetAndArchiveChecks() async throws {
  let testRoot = temporaryDirectory(label: "repository")
  defer { try? FileManager.default.removeItem(at: testRoot) }
  try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
  let repositoryRoot = testRoot.appendingPathComponent("Repository")
  let sourceURL = testRoot.appendingPathComponent("synthetic.pdf")
  let originalBytes = Data("synthetic original submission".utf8)
  try originalBytes.write(to: sourceURL)

  let repository = try WorkspaceRepository(rootURL: repositoryRoot)
  var workspace = try await repository.createWorkspace(title: "Synthetic grading")
  let asset = try await repository.storeAsset(
    from: sourceURL, typeIdentifier: "com.adobe.pdf", containerID: workspace.containerID)
  var assignment = WorkAssignment(title: "Synthetic assignment")
  var submission = WorkSubmission(candidateAlias: "Candidate 014")
  submission.documents = [
    SourceDocumentRecord(
      originalName: "synthetic.pdf", asset: asset, pages: [storageSyntheticPage()])
  ]
  assignment.submissions = [submission]
  workspace.assignments = [assignment]
  workspace.identities = [
    CandidateIdentity(candidateID: submission.candidateID, displayName: "Synthetic Student")
  ]
  let firstRevision = try await repository.saveWorkspace(
    workspace, expectedRevision: workspace.revisionID)

  try Data("changed source file".utf8).write(to: sourceURL)
  let storedURL = try await repository.assetURL(asset, containerID: firstRevision.containerID)
  try storageExpect(
    try Data(contentsOf: storedURL) == originalBytes,
    "The immutable stored original changed when its source changed.")
  let permissions =
    try FileManager.default.attributesOfItem(atPath: storedURL.path)[.posixPermissions]
    as? NSNumber
  try storageExpect(
    (permissions?.intValue ?? 0) & 0o222 == 0,
    "The stored original remained writable after promotion.")

  var newer = firstRevision
  newer.title = "New local head"
  newer.identities[0].displayName = "Synthetic Learner"
  let replacementBytes = Data("changed source file".utf8)
  let replacementAsset = try await repository.storeAsset(
    from: sourceURL, typeIdentifier: "com.adobe.pdf", containerID: workspace.containerID)
  newer.assignments[0].submissions[0].documents[0].asset = replacementAsset
  let secondRevision = try await repository.saveWorkspace(
    newer, expectedRevision: firstRevision.revisionID)
  try storageExpect(
    secondRevision.parentRevisionID == firstRevision.revisionID
      && secondRevision.revisionID != firstRevision.revisionID,
    "Saving did not create the expected revision lineage.")
  try await storageExpectThrows("A stale save unexpectedly succeeded.") {
    _ = try await repository.saveWorkspace(newer, expectedRevision: firstRevision.revisionID)
  }

  var invalidPath = secondRevision
  invalidPath.assignments[0].submissions[0].documents[0].asset.relativePath = "../escape"
  try await storageExpectThrows("An escaping asset path unexpectedly saved.") {
    _ = try await repository.saveWorkspace(
      invalidPath, expectedRevision: secondRevision.revisionID)
  }

  let exportDirectory = testRoot.appendingPathComponent("Exports")
  try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
  let archiveURL = try await repository.exportWorkspace(
    containerID: secondRevision.containerID,
    destination: exportDirectory.appendingPathComponent("snapshot"))
  try storageExpect(
    archiveURL.pathExtension == "gradingworkspace"
      && FileManager.default.fileExists(atPath: archiveURL.path),
    "The workspace archive was not published.")

  let duplicate = try await repository.importWorkspace(from: archiveURL)
  try storageExpect(
    duplicate.wasDuplicate && !duplicate.isSeparateCopy
      && duplicate.workspace.containerID == secondRevision.containerID,
    "An identical logical workspace and head was not idempotent.")

  var divergent = secondRevision
  divergent.title = "Divergent local revision"
  _ = try await repository.saveWorkspace(
    divergent, expectedRevision: secondRevision.revisionID)
  let separate = try await repository.importWorkspace(from: archiveURL)
  try storageExpect(
    !separate.wasDuplicate && separate.isSeparateCopy
      && separate.workspace.id == secondRevision.id
      && separate.workspace.containerID != secondRevision.containerID
      && separate.workspace.revisionID == secondRevision.revisionID,
    "A differing head did not become a separate local container.")
  let importedAsset = separate.workspace.assignments[0].submissions[0].documents[0].asset
  let importedAssetURL = try await repository.assetURL(
    importedAsset, containerID: separate.workspace.containerID)
  try storageExpect(
    try Data(contentsOf: importedAssetURL) == replacementBytes,
    "The imported original did not round-trip exactly.")
  let historicalAssetURL = try await repository.assetURL(
    asset, containerID: separate.workspace.containerID)
  try storageExpect(
    try Data(contentsOf: historicalAssetURL) == originalBytes,
    "The archive omitted an asset referenced only by historical revisions.")

  let reexportURL = try await repository.exportWorkspace(
    containerID: separate.workspace.containerID,
    destination: exportDirectory.appendingPathComponent("reexported"))
  let secondTargetRoot = testRoot.appendingPathComponent("SecondTarget")
  let secondTarget = try WorkspaceRepository(rootURL: secondTargetRoot)
  let reimported = try await secondTarget.importWorkspace(from: reexportURL)
  let reimportedHistoricalURL = try await secondTarget.assetURL(
    asset, containerID: reimported.workspace.containerID)
  try storageExpect(
    try Data(contentsOf: reimportedHistoricalURL) == originalBytes,
    "An imported revision history lost its historical asset when re-exported.")

  let identityCorruptURL = exportDirectory.appendingPathComponent(
    "identity-corrupt.gradingworkspace")
  var identityCorruptBytes = try Data(contentsOf: archiveURL)
  try storageExpect(
    replaceFirstOccurrence(
      in: &identityCorruptBytes, original: Data("Synthetic Student".utf8),
      replacement: Data("Synthetic Studenx".utf8)),
    "The synthetic identity marker was absent from the archive fixture.")
  try identityCorruptBytes.write(to: identityCorruptURL)
  try await storageExpectThrows("A changed identity mapping unexpectedly imported.") {
    _ = try await repository.importWorkspace(from: identityCorruptURL)
  }

  let corruptURL = exportDirectory.appendingPathComponent("corrupt.gradingworkspace")
  var corruptBytes = try Data(contentsOf: archiveURL)
  corruptBytes.removeLast(min(64, corruptBytes.count))
  try corruptBytes.write(to: corruptURL)
  let countBeforeCorruptImport = try await repository.listWorkspaces().count
  try await storageExpectThrows("A truncated archive unexpectedly imported.") {
    _ = try await repository.importWorkspace(from: corruptURL)
  }
  let countAfterCorruptImport = try await repository.listWorkspaces().count
  try storageExpect(
    countAfterCorruptImport == countBeforeCorruptImport,
    "A corrupt archive changed the workspace catalog.")
}

private func stagedAssetRecoveryChecks() async throws {
  for point in [
    WorkspaceStorageFaultPoint.afterAssetStaged,
    .afterAssetJournaled,
    .afterAssetPromoted,
  ] {
    let testRoot = temporaryDirectory(label: "asset-\(point.rawValue)")
    defer { try? FileManager.default.removeItem(at: testRoot) }
    try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    let repositoryRoot = testRoot.appendingPathComponent("Repository")
    let sourceURL = testRoot.appendingPathComponent("asset.bin")
    let bytes = Data("recoverable staged asset".utf8)
    try bytes.write(to: sourceURL)
    let setup = try WorkspaceRepository(rootURL: repositoryRoot)
    let workspace = try await setup.createWorkspace(title: "Recovery")

    let injector = OneShotFaultInjector(point: point)
    let faulting = try WorkspaceRepository(rootURL: repositoryRoot, faultInjector: injector.inject)
    try await storageExpectThrows("The requested asset fault was not injected.") {
      _ = try await faulting.storeAsset(
        from: sourceURL, typeIdentifier: "public.data", containerID: workspace.containerID)
    }

    let recovered = try WorkspaceRepository(rootURL: repositoryRoot)
    if point == .afterAssetStaged {
      let stored = try await recovered.storeAsset(
        from: sourceURL, typeIdentifier: "public.data", containerID: workspace.containerID)
      _ = try await recovered.assetURL(stored, containerID: workspace.containerID)
    } else {
      let sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
      let reference = AssetReference(
        sha256: sha256, byteCount: Int64(bytes.count), typeIdentifier: "public.data",
        relativePath: "Assets/\(sha256.prefix(2))/\(sha256)")
      let url = try await recovered.assetURL(reference, containerID: workspace.containerID)
      try storageExpect(
        try Data(contentsOf: url) == bytes,
        "A journaled asset did not recover at \(point.rawValue).")
    }
  }
}

private func stagedImportRecoveryCheck() async throws {
  let testRoot = temporaryDirectory(label: "import-recovery")
  defer { try? FileManager.default.removeItem(at: testRoot) }
  try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
  let sourceRoot = testRoot.appendingPathComponent("Source")
  let source = try WorkspaceRepository(rootURL: sourceRoot)
  let workspace = try await source.createWorkspace(title: "Portable synthetic workspace")
  let archive = try await source.exportWorkspace(
    containerID: workspace.containerID,
    destination: testRoot.appendingPathComponent("portable.gradingworkspace"))

  let targetRoot = testRoot.appendingPathComponent("Target")
  let injector = OneShotFaultInjector(point: .afterImportPrepared)
  let faulting = try WorkspaceRepository(rootURL: targetRoot, faultInjector: injector.inject)
  try await storageExpectThrows("The prepared-import fault was not injected.") {
    _ = try await faulting.importWorkspace(from: archive)
  }
  let recovered = try WorkspaceRepository(rootURL: targetRoot)
  let summaries = try await recovered.listWorkspaces()
  try storageExpect(
    summaries.count == 1 && summaries[0].workspaceID == workspace.id,
    "A fully prepared import did not recover after interruption.")
}

private func archiveWriteFailureCheck() async throws {
  let testRoot = temporaryDirectory(label: "archive-fault")
  defer { try? FileManager.default.removeItem(at: testRoot) }
  try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
  let repositoryRoot = testRoot.appendingPathComponent("Repository")
  let sourceURL = testRoot.appendingPathComponent("asset.bin")
  try Data("archive fault bytes".utf8).write(to: sourceURL)
  let setup = try WorkspaceRepository(rootURL: repositoryRoot)
  var workspace = try await setup.createWorkspace(title: "Archive fault")
  let asset = try await setup.storeAsset(
    from: sourceURL, typeIdentifier: "public.data", containerID: workspace.containerID)
  var assignment = WorkAssignment(title: "Synthetic")
  var submission = WorkSubmission(candidateAlias: "Candidate 001")
  submission.documents = [
    SourceDocumentRecord(originalName: "asset.bin", asset: asset, pages: [storageSyntheticPage()])
  ]
  assignment.submissions = [submission]
  workspace.assignments = [assignment]
  workspace = try await setup.saveWorkspace(workspace, expectedRevision: workspace.revisionID)

  let destination = testRoot.appendingPathComponent("failed.gradingworkspace")
  let injector = OneShotFaultInjector(point: .duringArchiveAssetWrite)
  let faulting = try WorkspaceRepository(rootURL: repositoryRoot, faultInjector: injector.inject)
  try await storageExpectThrows("The archive-write fault was not injected.") {
    _ = try await faulting.exportWorkspace(
      containerID: workspace.containerID, destination: destination)
  }
  try storageExpect(
    !FileManager.default.fileExists(atPath: destination.path),
    "A failed export published a destination archive.")
}

@MainActor private func localAccessChecks() async throws {
  let preferences = MemoryAccessPreferences(enabled: false)
  let success = ImmediateAuthenticator(outcome: .success)
  let controller = LocalAccessController(
    authenticator: success, preferences: preferences, inactivityDuration: .milliseconds(20))
  try storageExpect(!controller.isEnabled && !controller.isLocked, "The lock did not default off.")
  try await controller.setEnabled(true)
  try storageExpect(controller.isEnabled && !controller.isLocked, "The lock did not enable.")
  try await Task.sleep(for: .milliseconds(60))
  try storageExpect(controller.isLocked, "Inactivity did not relock the workspace.")

  let restored = LocalAccessController(authenticator: success, preferences: preferences)
  try storageExpect(
    restored.isEnabled && restored.isLocked,
    "A persisted lock preference did not restore in a locked state.")
  restored.applicationDidEnterBackground()
  try await restored.setEnabled(false)
  try storageExpect(
    !restored.isEnabled && !preferences.lockIsEnabled(), "The lock did not disable.")

  let cancelledPreferences = MemoryAccessPreferences(enabled: true)
  let cancelled = LocalAccessController(
    authenticator: ImmediateAuthenticator(outcome: .cancelled),
    preferences: cancelledPreferences)
  try await storageExpectThrows("Cancelled authentication unexpectedly unlocked.") {
    try await cancelled.unlock()
  }
  try storageExpect(cancelled.isLocked, "Cancellation did not fail closed.")

  let deferredAuthenticator = DeferredAuthenticator()
  let deferred = LocalAccessController(
    authenticator: deferredAuthenticator,
    preferences: MemoryAccessPreferences(enabled: true))
  let unlock = Task { @MainActor in try await deferred.unlock() }
  while !(await deferredAuthenticator.hasStarted()) { await Task.yield() }
  deferred.applicationDidEnterBackground()
  await deferredAuthenticator.complete(success: true)
  try await storageExpectThrows("A late authentication result unlocked after backgrounding.") {
    try await unlock.value
  }
  try storageExpect(deferred.isLocked, "A backgrounded workspace did not remain locked.")
}

private func temporaryDirectory(label: String) -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "grading-storage-\(label)-\(UUID().uuidString.lowercased())", isDirectory: true)
}

private func replaceFirstOccurrence(
  in data: inout Data, original: Data, replacement: Data
) -> Bool {
  guard original.count == replacement.count, let range = data.range(of: original) else {
    return false
  }
  data.replaceSubrange(range, with: replacement)
  return true
}

private struct InjectedStorageFault: Error {}

private final class OneShotFaultInjector: @unchecked Sendable {
  private let lock = NSLock()
  private let point: WorkspaceStorageFaultPoint
  private var fired = false

  init(point: WorkspaceStorageFaultPoint) { self.point = point }

  func inject(_ candidate: WorkspaceStorageFaultPoint) throws {
    lock.lock()
    defer { lock.unlock() }
    guard candidate == point, !fired else { return }
    fired = true
    throw InjectedStorageFault()
  }
}

private final class MemoryAccessPreferences: LocalAccessPreferenceStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var enabled: Bool

  init(enabled: Bool) { self.enabled = enabled }

  func lockIsEnabled() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return enabled
  }

  func setLockEnabled(_ enabled: Bool) {
    lock.lock()
    defer { lock.unlock() }
    self.enabled = enabled
  }
}

private enum ImmediateAuthenticationOutcome: Sendable {
  case success
  case denied
  case cancelled
}

private actor ImmediateAuthenticator: DeviceOwnerAuthenticating {
  let outcome: ImmediateAuthenticationOutcome

  init(outcome: ImmediateAuthenticationOutcome) { self.outcome = outcome }

  func isAvailable() async -> Bool { true }

  func authenticate(reason: String) async throws -> Bool {
    switch outcome {
    case .success: return true
    case .denied: return false
    case .cancelled: throw CancellationError()
    }
  }
}

private actor DeferredAuthenticator: DeviceOwnerAuthenticating {
  private var started = false
  private var continuation: CheckedContinuation<Bool, Never>?

  func isAvailable() async -> Bool { true }

  func authenticate(reason: String) async throws -> Bool {
    started = true
    return await withCheckedContinuation { continuation = $0 }
  }

  func hasStarted() -> Bool { started }

  func complete(success: Bool) {
    continuation?.resume(returning: success)
    continuation = nil
  }
}

private func storageSyntheticPage() -> DocumentPageRecord {
  let bounds = PageRectangle(x: 0, y: 0, width: 100, height: 100)
  return DocumentPageRecord(index: 0, mediaBox: bounds, cropBox: bounds)
}
