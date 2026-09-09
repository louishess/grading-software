import Foundation
import GRDB

public actor WorkspaceRepository {
  let rootURL: URL
  let faultInjector: WorkspaceStorageFaultInjector
  var databases: [UUID: WorkspaceDatabase] = [:]

  public init(rootURL: URL) throws {
    try self.init(rootURL: rootURL, faultInjector: { _ in })
  }

  public init(rootURL: URL, faultInjector: @escaping WorkspaceStorageFaultInjector) throws {
    self.rootURL = rootURL.standardizedFileURL
    self.faultInjector = faultInjector
    try StorageFiles.ensureDirectory(self.rootURL)
    try StorageFiles.ensureDirectory(self.rootURL.appendingPathComponent("Workspaces"))
    try StorageFiles.ensureDirectory(self.rootURL.appendingPathComponent("Staging"))
    try StorageFiles.ensureDirectory(self.rootURL.appendingPathComponent("Recovery"))
    try Self.recoverRootOperations(rootURL: self.rootURL)
  }

  public func listWorkspaces() throws -> [WorkspaceSummary] {
    let workspacesURL = rootURL.appendingPathComponent("Workspaces", isDirectory: true)
    let urls = try FileManager.default.contentsOfDirectory(
      at: workspacesURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles])
    var summaries: [WorkspaceSummary] = []
    for url in urls {
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true,
        let containerID = UUID(uuidString: url.lastPathComponent)
      else { continue }
      let database = try database(for: containerID)
      let metadata = try database.metadata()
      guard metadata.containerID == containerID else {
        throw WorkspaceFailure.invalid("A workspace directory has the wrong container identifier.")
      }
      summaries.append(WorkspaceSummary(metadata: metadata))
    }
    return summaries.sorted {
      if $0.modifiedAt == $1.modifiedAt {
        return $0.containerID.uuidString < $1.containerID.uuidString
      }
      return $0.modifiedAt > $1.modifiedAt
    }
  }

  public func createWorkspace(title: String) throws -> WorkspaceData {
    var data = WorkspaceData(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
    try WorkspaceValidation.validate(data, expectedContainerID: data.containerID)
    let operationID = UUID()
    let stagingDirectory = rootURL.appendingPathComponent("Staging", isDirectory: true)
      .appendingPathComponent("create-\(operationID.uuidString.lowercased())", isDirectory: true)
    let finalDirectory = StorageLayout.workspaceDirectory(
      root: rootURL, containerID: data.containerID)
    guard !FileManager.default.fileExists(atPath: finalDirectory.path) else {
      throw WorkspaceFailure.unavailable("A workspace with this local identifier already exists.")
    }
    try StorageFiles.ensureDirectory(stagingDirectory)
    do {
      var stagedDatabase: WorkspaceDatabase? = try WorkspaceDatabase(
        directory: stagingDirectory, createIfMissing: true)
      try stagedDatabase?.seed(data)
      try stagedDatabase?.verifyIntegrity()
      try writeRootOperation(
        RootOperation(
          kind: .create, state: .ready,
          finalDirectoryName: data.containerID.uuidString.lowercased()),
        stagingDirectory: stagingDirectory)
      stagedDatabase = nil
      try FileManager.default.moveItem(at: stagingDirectory, to: finalDirectory)
      try? FileManager.default.removeItem(
        at: finalDirectory.appendingPathComponent(RootOperation.filename))
      databases[data.containerID] = try WorkspaceDatabase(
        directory: finalDirectory, createIfMissing: false)
      data = try databases[data.containerID]!.load()
      return data
    } catch {
      if FileManager.default.fileExists(atPath: stagingDirectory.path) {
        try? StorageFiles.moveToRecovery(stagingDirectory, root: rootURL, label: "failed-create")
      }
      throw error
    }
  }

  public func loadWorkspace(containerID: UUID) throws -> WorkspaceData {
    let database = try database(for: containerID)
    let data = try database.load()
    try verifyAssets(in: data, database: database)
    return data
  }

  public func saveWorkspace(_ data: WorkspaceData, expectedRevision: UUID) throws -> WorkspaceData {
    try WorkspaceValidation.validate(data, expectedContainerID: data.containerID)
    let database = try database(for: data.containerID)
    try verifyAssets(in: data, database: database)
    return try database.save(data, expectedRevision: expectedRevision)
  }

  public func storeAsset(
    from url: URL, typeIdentifier: String, containerID: UUID
  ) throws -> AssetReference {
    guard typeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
      throw WorkspaceFailure.invalid("An asset type identifier is required.")
    }
    let database = try database(for: containerID)
    let operationID = UUID()
    let stagingRelativePath = ".staging/\(operationID.uuidString.lowercased())"
    let stagingURL = try StorageFiles.containedURL(
      root: database.directory, relativePath: stagingRelativePath)
    let digest = try StorageFiles.copyAndDigest(from: url, to: stagingURL)
    try faultInjector(.afterAssetStaged)

    let finalRelativePath = try StorageLayout.assetRelativePath(sha256: digest.sha256)
    let operation = WorkspaceDatabase.AssetOperation(
      id: operationID, stagingRelativePath: stagingRelativePath,
      finalRelativePath: finalRelativePath, sha256: digest.sha256,
      byteCount: digest.byteCount, typeIdentifier: typeIdentifier)
    try database.beginAssetOperation(operation)
    try faultInjector(.afterAssetJournaled)
    try promoteAsset(operation, database: database)
    try faultInjector(.afterAssetPromoted)
    try database.finishAssetOperation(operation)
    return AssetReference(
      sha256: digest.sha256, byteCount: digest.byteCount, typeIdentifier: typeIdentifier,
      relativePath: finalRelativePath)
  }

  public func assetURL(_ asset: AssetReference, containerID: UUID) throws -> URL {
    let database = try database(for: containerID)
    return try verifiedAssetURL(asset, database: database)
  }

  public func exportWorkspace(containerID: UUID, destination: URL) throws -> URL {
    try exportArchive(containerID: containerID, destination: destination)
  }

  public func importWorkspace(from url: URL) throws -> WorkspaceImportResult {
    try importArchive(from: url)
  }

  func database(for containerID: UUID) throws -> WorkspaceDatabase {
    if let database = databases[containerID] {
      try recoverAssetOperations(database)
      return database
    }
    let directory = StorageLayout.workspaceDirectory(root: rootURL, containerID: containerID)
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw WorkspaceFailure.unavailable("The workspace is unavailable.")
    }
    let database = try WorkspaceDatabase(directory: directory, createIfMissing: false)
    try recoverAssetOperations(database)
    databases[containerID] = database
    return database
  }

  func verifiedAssetURL(_ asset: AssetReference, database: WorkspaceDatabase) throws -> URL {
    let expectedPath = try StorageLayout.assetRelativePath(sha256: asset.sha256)
    guard asset.relativePath == expectedPath, let stored = try database.asset(sha256: asset.sha256),
      stored == asset
    else { throw WorkspaceFailure.invalid("The asset is not registered in this workspace.") }
    let url = try StorageFiles.containedURL(
      root: database.directory, relativePath: asset.relativePath)
    try StorageFiles.rejectSymlink(url, description: "The stored asset")
    let resolvedRoot = database.directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
    guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(resolvedRoot) else {
      throw WorkspaceFailure.invalid("The stored asset escapes its workspace.")
    }
    let digest = try StorageFiles.digest(url: url)
    guard digest.sha256 == asset.sha256, digest.byteCount == asset.byteCount else {
      throw WorkspaceFailure.invalid("The stored asset no longer matches its recorded hash.")
    }
    return url
  }

  func verifyAssets(in data: WorkspaceData, database: WorkspaceDatabase) throws {
    for asset in data.assets { _ = try verifiedAssetURL(asset, database: database) }
  }

  func registerImportedAssets(_ assets: [AssetReference], database: WorkspaceDatabase) throws {
    try database.queue.writeWithoutTransaction { db in
      try db.inTransaction {
        for asset in assets { try database.recordAsset(asset, in: db) }
        return .commit
      }
    }
  }

  private func recoverAssetOperations(_ database: WorkspaceDatabase) throws {
    for operation in try database.assetOperations() {
      do {
        try promoteAsset(operation, database: database)
        try database.finishAssetOperation(operation)
      } catch {
        let staging = try StorageFiles.containedURL(
          root: database.directory, relativePath: operation.stagingRelativePath)
        if FileManager.default.fileExists(atPath: staging.path) {
          try? StorageFiles.moveToRecovery(staging, root: rootURL, label: "asset-operation")
        }
        try? database.removeAssetOperation(id: operation.id)
        throw WorkspaceFailure.invalid(
          "A staged asset could not be recovered: \(error.localizedDescription)")
      }
    }
    let stagingDirectory = database.directory.appendingPathComponent(".staging", isDirectory: true)
    guard FileManager.default.fileExists(atPath: stagingDirectory.path) else { return }
    let leftovers = try FileManager.default.contentsOfDirectory(
      at: stagingDirectory, includingPropertiesForKeys: nil)
    for leftover in leftovers {
      try StorageFiles.moveToRecovery(leftover, root: rootURL, label: "unrecorded-asset")
    }
  }

  private func promoteAsset(
    _ operation: WorkspaceDatabase.AssetOperation, database: WorkspaceDatabase
  ) throws {
    let staging = try StorageFiles.containedURL(
      root: database.directory, relativePath: operation.stagingRelativePath)
    let final = try StorageFiles.containedURL(
      root: database.directory, relativePath: operation.finalRelativePath)
    if FileManager.default.fileExists(atPath: final.path) {
      let existing = try StorageFiles.digest(url: final)
      guard existing.sha256 == operation.sha256, existing.byteCount == operation.byteCount else {
        throw WorkspaceFailure.invalid("An existing asset conflicts with staged bytes.")
      }
      if FileManager.default.fileExists(atPath: staging.path) {
        let staged = try StorageFiles.digest(url: staging)
        guard staged.sha256 == operation.sha256, staged.byteCount == operation.byteCount else {
          throw WorkspaceFailure.invalid("Staged asset bytes are corrupt.")
        }
        try FileManager.default.removeItem(at: staging)
      }
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o400)], ofItemAtPath: final.path)
      return
    }
    guard FileManager.default.fileExists(atPath: staging.path) else {
      throw WorkspaceFailure.invalid("Staged asset bytes are missing.")
    }
    let staged = try StorageFiles.digest(url: staging)
    guard staged.sha256 == operation.sha256, staged.byteCount == operation.byteCount else {
      throw WorkspaceFailure.invalid("Staged asset bytes are corrupt.")
    }
    try StorageFiles.ensureDirectory(final.deletingLastPathComponent())
    try FileManager.default.moveItem(at: staging, to: final)
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: 0o400)], ofItemAtPath: final.path)
  }

  private static func recoverRootOperations(rootURL: URL) throws {
    let stagingRoot = rootURL.appendingPathComponent("Staging", isDirectory: true)
    let entries = try FileManager.default.contentsOfDirectory(
      at: stagingRoot, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    for entry in entries {
      let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        try StorageFiles.moveToRecovery(entry, root: rootURL, label: "invalid-root-operation")
        continue
      }
      let recordURL = entry.appendingPathComponent(RootOperation.filename)
      guard
        let payload = try? Data(contentsOf: recordURL),
        let operation = try? StorageCodec.decoder().decode(RootOperation.self, from: payload),
        operation.state == .ready,
        let containerID = UUID(uuidString: operation.finalDirectoryName)
      else {
        try StorageFiles.moveToRecovery(entry, root: rootURL, label: "incomplete-root-operation")
        continue
      }
      let final = StorageLayout.workspaceDirectory(root: rootURL, containerID: containerID)
      guard !FileManager.default.fileExists(atPath: final.path) else {
        try StorageFiles.moveToRecovery(entry, root: rootURL, label: "conflicting-root-operation")
        continue
      }
      try FileManager.default.moveItem(at: entry, to: final)
      try? FileManager.default.removeItem(at: final.appendingPathComponent(RootOperation.filename))
    }
  }

  func writeRootOperation(_ operation: RootOperation, stagingDirectory: URL) throws {
    let payload = try StorageCodec.encoder().encode(operation)
    try payload.write(
      to: stagingDirectory.appendingPathComponent(RootOperation.filename), options: .atomic)
  }
}

struct RootOperation: Codable, Sendable {
  static let filename = ".root-operation.json"
  enum Kind: String, Codable, Sendable { case create, importWorkspace }
  enum State: String, Codable, Sendable { case ready }
  var kind: Kind
  var state: State
  var finalDirectoryName: String
}

extension WorkspaceSummary {
  fileprivate init(metadata: WorkspaceDatabase.Metadata) {
    workspaceID = metadata.workspaceID
    containerID = metadata.containerID
    title = metadata.title
    modifiedAt = metadata.modifiedAt
  }
}
