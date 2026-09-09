import CryptoKit
import Foundation
import GRDB

extension WorkspaceRepository {
  func exportArchive(containerID: UUID, destination: URL) throws -> URL {
    let database = try database(for: containerID)
    let data = try database.load()
    let revisions = try database.revisions()
    for revision in revisions { try verifyAssets(in: revision.data, database: database) }

    let finalURL =
      destination.pathExtension.lowercased() == "gradingworkspace"
      ? destination : destination.appendingPathExtension("gradingworkspace")
    guard !FileManager.default.fileExists(atPath: finalURL.path) else {
      throw WorkspaceFailure.unavailable("A file already exists at the backup destination.")
    }
    try StorageFiles.ensureDirectory(finalURL.deletingLastPathComponent())

    let operationID = UUID()
    let stagingDirectory = rootURL.appendingPathComponent("Staging", isDirectory: true)
      .appendingPathComponent("export-\(operationID.uuidString.lowercased())", isDirectory: true)
    let archiveURL = stagingDirectory.appendingPathComponent("workspace.gradingworkspace")
    try StorageFiles.ensureDirectory(stagingDirectory)
    do {
      try WorkspaceArchive.create(
        at: archiveURL, workspace: data, revisions: revisions,
        assetURL: { asset in try self.verifiedAssetURL(asset, database: database) },
        faultInjector: faultInjector)
      try faultInjector(.afterArchiveCreated)
      try WorkspaceArchive.validate(at: archiveURL)

      let destinationStage = finalURL.deletingLastPathComponent().appendingPathComponent(
        ".\(finalURL.lastPathComponent).\(operationID.uuidString.lowercased()).partial")
      guard !FileManager.default.fileExists(atPath: destinationStage.path) else {
        throw WorkspaceFailure.unavailable("A temporary backup destination already exists.")
      }
      do {
        let sourceDigest = try StorageFiles.digest(
          url: archiveURL, maximumBytes: StorageLayout.maximumArchiveBytes)
        let copiedDigest = try StorageFiles.copyAndDigest(
          from: archiveURL, to: destinationStage,
          maximumBytes: StorageLayout.maximumArchiveBytes)
        guard sourceDigest.sha256 == copiedDigest.sha256,
          sourceDigest.byteCount == copiedDigest.byteCount
        else { throw WorkspaceFailure.invalid("The copied backup failed verification.") }
        try FileManager.default.moveItem(at: destinationStage, to: finalURL)
      } catch {
        try? FileManager.default.removeItem(at: destinationStage)
        throw error
      }
      try FileManager.default.removeItem(at: stagingDirectory)
      return finalURL
    } catch {
      if FileManager.default.fileExists(atPath: stagingDirectory.path) {
        try? StorageFiles.moveToRecovery(stagingDirectory, root: rootURL, label: "failed-export")
      }
      throw error
    }
  }

  func importArchive(from sourceURL: URL) throws -> WorkspaceImportResult {
    try StorageFiles.rejectSymlink(sourceURL, description: "The workspace archive")
    let fileSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
    guard fileSize > 0, Int64(fileSize) <= StorageLayout.maximumArchiveBytes else {
      throw WorkspaceFailure.invalid("The workspace archive size is invalid.")
    }

    let operationID = UUID()
    let stagingDirectory = rootURL.appendingPathComponent("Staging", isDirectory: true)
      .appendingPathComponent("import-\(operationID.uuidString.lowercased())", isDirectory: true)
    let stagedArchive = stagingDirectory.appendingPathComponent("incoming.gradingworkspace")
    try StorageFiles.ensureDirectory(stagingDirectory)
    do {
      _ = try StorageFiles.copyAndDigest(
        from: sourceURL, to: stagedArchive, maximumBytes: StorageLayout.maximumArchiveBytes)
      let contents = try WorkspaceArchive.read(at: stagedArchive)
      try WorkspaceValidation.validate(contents.workspace)

      for summary in try listWorkspaces() where summary.workspaceID == contents.workspace.id {
        let existingDatabase = try database(for: summary.containerID)
        let metadata = try existingDatabase.metadata()
        if metadata.headRevisionID == contents.workspace.revisionID {
          let existing = try existingDatabase.load()
          try verifyAssets(in: existing, database: existingDatabase)
          try FileManager.default.removeItem(at: stagingDirectory)
          return WorkspaceImportResult(
            workspace: existing, wasDuplicate: true, isSeparateCopy: false)
        }
      }

      var imported = contents.workspace
      imported.containerID = UUID()
      let importedHistory = contents.revisions.map { revision in
        var adjusted = revision.data
        adjusted.containerID = imported.containerID
        return WorkspaceDatabase.RevisionSnapshot(data: adjusted, createdAt: revision.createdAt)
      }
      let finalDirectory = StorageLayout.workspaceDirectory(
        root: rootURL, containerID: imported.containerID)
      guard !FileManager.default.fileExists(atPath: finalDirectory.path) else {
        throw WorkspaceFailure.unavailable("The imported workspace identifier already exists.")
      }

      try WorkspaceArchive.extractAssets(
        contents.assets, from: stagedArchive, to: stagingDirectory)
      try FileManager.default.removeItem(at: stagedArchive)
      var importedDatabase: WorkspaceDatabase? = try WorkspaceDatabase(
        directory: stagingDirectory, createIfMissing: true)
      try importedDatabase?.seed(imported, revisionHistory: importedHistory)
      guard importedDatabase != nil else {
        throw WorkspaceFailure.unavailable("The imported workspace database is unavailable.")
      }
      try registerImportedAssets(contents.assets, database: importedDatabase!)
      try verifyAssets(in: imported, database: importedDatabase!)
      try importedDatabase?.verifyIntegrity()
      try writeRootOperation(
        RootOperation(
          kind: .importWorkspace, state: .ready,
          finalDirectoryName: imported.containerID.uuidString.lowercased()),
        stagingDirectory: stagingDirectory)
      try faultInjector(.afterImportPrepared)
      importedDatabase = nil
      try FileManager.default.moveItem(at: stagingDirectory, to: finalDirectory)
      try? FileManager.default.removeItem(
        at: finalDirectory.appendingPathComponent(RootOperation.filename))
      let finalDatabase = try WorkspaceDatabase(directory: finalDirectory, createIfMissing: false)
      databases[imported.containerID] = finalDatabase
      return WorkspaceImportResult(
        workspace: try finalDatabase.load(), wasDuplicate: false, isSeparateCopy: true)
    } catch {
      if FileManager.default.fileExists(atPath: stagingDirectory.path) {
        let operationRecord = stagingDirectory.appendingPathComponent(RootOperation.filename)
        if !FileManager.default.fileExists(atPath: operationRecord.path) {
          try? StorageFiles.moveToRecovery(stagingDirectory, root: rootURL, label: "failed-import")
        }
      }
      throw error
    }
  }
}

private enum WorkspaceArchive {
  struct AssetEntry: Codable, Hashable, Sendable {
    var sha256: String
    var byteCount: Int64
    var typeIdentifier: String
    var relativePath: String
    var chunkCount: Int

    var reference: AssetReference {
      AssetReference(
        sha256: sha256, byteCount: byteCount, typeIdentifier: typeIdentifier,
        relativePath: relativePath)
    }
  }

  struct DigestManifest: Codable, Sendable {
    var formatVersion: Int
    var workspaceID: UUID
    var sourceContainerID: UUID
    var headRevisionID: UUID
    var parentRevisionID: UUID?
    var domainSchemaVersion: Int
    var title: String
    var modifiedAt: Date
    var snapshotSHA256: String
    var identitiesSHA256: String
    var revisions: [RevisionEntry]
    var assets: [AssetEntry]
  }

  struct RevisionEntry: Codable, Hashable, Sendable {
    var revisionID: UUID
    var parentRevisionID: UUID?
    var createdAt: Date
    var snapshotSHA256: String
    var identitiesSHA256: String
  }

  struct Contents: Sendable {
    var workspace: WorkspaceData
    var assets: [AssetReference]
    var revisions: [WorkspaceDatabase.RevisionSnapshot]
  }

  static func create(
    at url: URL, workspace: WorkspaceData,
    revisions: [WorkspaceDatabase.RevisionSnapshot],
    assetURL: (AssetReference) throws -> URL,
    faultInjector: WorkspaceStorageFaultInjector
  ) throws {
    let payload = try StorageCodec.snapshotPayload(workspace)
    let snapshotHash = SHA256.hash(data: payload).hexString
    let currentIdentitiesPayload = try identityPayload(workspace.identities)
    let currentIdentitiesHash = SHA256.hash(data: currentIdentitiesPayload).hexString
    let sortedRevisions = revisions.sorted {
      if $0.createdAt == $1.createdAt {
        return $0.data.revisionID.uuidString < $1.data.revisionID.uuidString
      }
      return $0.createdAt < $1.createdAt
    }
    guard
      sortedRevisions.first(where: { $0.data.revisionID == workspace.revisionID })?.data
        == workspace
    else { throw WorkspaceFailure.invalid("The current snapshot is absent from revision history.") }
    let revisionEntries = try sortedRevisions.map { revision in
      let revisionPayload = try StorageCodec.snapshotPayload(revision.data)
      let identities = try identityPayload(revision.data.identities)
      return RevisionEntry(
        revisionID: revision.data.revisionID,
        parentRevisionID: revision.data.parentRevisionID,
        createdAt: revision.createdAt,
        snapshotSHA256: SHA256.hash(data: revisionPayload).hexString,
        identitiesSHA256: SHA256.hash(data: identities).hexString)
    }
    var assetsByHash: [String: AssetReference] = [:]
    for revision in sortedRevisions {
      for asset in revision.data.assets {
        if let existing = assetsByHash[asset.sha256], existing != asset {
          throw WorkspaceFailure.invalid("Saved revisions contain conflicting asset references.")
        }
        assetsByHash[asset.sha256] = asset
      }
    }
    let sortedAssets = assetsByHash.values.sorted { $0.sha256 < $1.sha256 }
    var entries: [AssetEntry] = []
    for asset in sortedAssets {
      entries.append(
        AssetEntry(
          sha256: asset.sha256, byteCount: asset.byteCount,
          typeIdentifier: asset.typeIdentifier, relativePath: asset.relativePath,
          chunkCount: Int(
            (asset.byteCount + Int64(StorageLayout.chunkSize) - 1)
              / Int64(StorageLayout.chunkSize))))
    }
    let digestManifest = DigestManifest(
      formatVersion: StorageLayout.archiveFormatVersion, workspaceID: workspace.id,
      sourceContainerID: workspace.containerID, headRevisionID: workspace.revisionID,
      parentRevisionID: workspace.parentRevisionID,
      domainSchemaVersion: workspace.schemaVersion, title: workspace.title,
      modifiedAt: workspace.modifiedAt, snapshotSHA256: snapshotHash,
      identitiesSHA256: currentIdentitiesHash, revisions: revisionEntries, assets: entries)
    let manifestPayload = try StorageCodec.encoder().encode(digestManifest)
    let manifestHash = SHA256.hash(data: manifestPayload).hexString

    var configuration = Configuration()
    configuration.prepareDatabase { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
      try db.execute(sql: "PRAGMA journal_mode = DELETE")
      try db.execute(sql: "PRAGMA synchronous = FULL")
      try db.execute(sql: "PRAGMA trusted_schema = OFF")
    }
    let queue = try DatabaseQueue(path: url.path, configuration: configuration)
    try queue.write { db in
      try db.execute(
        sql: """
          CREATE TABLE archive_manifest (
            singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
            format_version INTEGER NOT NULL,
            workspace_id TEXT NOT NULL,
            source_container_id TEXT NOT NULL,
            head_revision_id TEXT NOT NULL,
            parent_revision_id TEXT,
            domain_schema_version INTEGER NOT NULL,
            title TEXT NOT NULL,
            modified_at REAL NOT NULL,
            exported_at REAL NOT NULL,
            snapshot_sha256 TEXT NOT NULL,
            manifest_sha256 TEXT NOT NULL,
            manifest_payload BLOB NOT NULL
          );
          CREATE TABLE workspace_snapshot (
            singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
            payload BLOB NOT NULL
          );
          CREATE TABLE candidate_identities (
            candidate_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL
          );
          CREATE TABLE archive_revisions (
            revision_id TEXT PRIMARY KEY,
            parent_revision_id TEXT,
            created_at REAL NOT NULL,
            snapshot BLOB NOT NULL,
            snapshot_sha256 TEXT NOT NULL,
            identities BLOB NOT NULL,
            identities_sha256 TEXT NOT NULL
          );
          CREATE TABLE archive_assets (
            sha256 TEXT PRIMARY KEY,
            byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
            type_identifier TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            chunk_count INTEGER NOT NULL CHECK (chunk_count >= 0)
          );
          CREATE TABLE archive_asset_chunks (
            sha256 TEXT NOT NULL REFERENCES archive_assets(sha256) ON DELETE CASCADE,
            chunk_index INTEGER NOT NULL CHECK (chunk_index >= 0),
            payload BLOB NOT NULL,
            PRIMARY KEY (sha256, chunk_index)
          );
          """)
      try db.execute(
        sql: """
          INSERT INTO archive_manifest
            (singleton, format_version, workspace_id, source_container_id, head_revision_id,
             parent_revision_id, domain_schema_version, title, modified_at, exported_at,
             snapshot_sha256, manifest_sha256, manifest_payload)
          VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          digestManifest.formatVersion, digestManifest.workspaceID.uuidString,
          digestManifest.sourceContainerID.uuidString, digestManifest.headRevisionID.uuidString,
          digestManifest.parentRevisionID?.uuidString, digestManifest.domainSchemaVersion,
          digestManifest.title, digestManifest.modifiedAt.timeIntervalSince1970,
          Date().timeIntervalSince1970, snapshotHash, manifestHash, manifestPayload,
        ])
      try db.execute(
        sql: "INSERT INTO workspace_snapshot (singleton, payload) VALUES (1, ?)",
        arguments: [payload])
      for identity in workspace.identities {
        try db.execute(
          sql: "INSERT INTO candidate_identities (candidate_id, display_name) VALUES (?, ?)",
          arguments: [identity.candidateID.uuidString, identity.displayName])
      }
      for revision in sortedRevisions {
        let revisionPayload = try StorageCodec.snapshotPayload(revision.data)
        let identities = try identityPayload(revision.data.identities)
        try db.execute(
          sql: """
            INSERT INTO archive_revisions
              (revision_id, parent_revision_id, created_at, snapshot, snapshot_sha256,
               identities, identities_sha256)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            revision.data.revisionID.uuidString, revision.data.parentRevisionID?.uuidString,
            revision.createdAt.timeIntervalSince1970, revisionPayload,
            SHA256.hash(data: revisionPayload).hexString, identities,
            SHA256.hash(data: identities).hexString,
          ])
      }
      for entry in entries {
        try db.execute(
          sql: """
            INSERT INTO archive_assets
              (sha256, byte_count, type_identifier, relative_path, chunk_count)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            entry.sha256, entry.byteCount, entry.typeIdentifier, entry.relativePath,
            entry.chunkCount,
          ])
      }
    }

    for asset in sortedAssets {
      let source = try assetURL(asset)
      var index = 0
      do {
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: StorageLayout.chunkSize), !chunk.isEmpty {
          try queue.write { db in
            try db.execute(
              sql: """
                INSERT INTO archive_asset_chunks (sha256, chunk_index, payload)
                VALUES (?, ?, ?)
                """, arguments: [asset.sha256, index, chunk])
          }
          index += 1
          try faultInjector(.duringArchiveAssetWrite)
        }
      }
      guard index == entries.first(where: { $0.sha256 == asset.sha256 })?.chunkCount else {
        throw WorkspaceFailure.invalid("An asset changed while its backup was being created.")
      }
    }
    try queue.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
    }
  }

  static func validate(at url: URL) throws {
    _ = try read(at: url)
  }

  static func read(at url: URL) throws -> Contents {
    let queue = try readOnlyQueue(at: url)
    return try queue.read { db in
      guard try String.fetchOne(db, sql: "PRAGMA integrity_check") == "ok" else {
        throw WorkspaceFailure.invalid("The workspace archive is corrupt.")
      }
      guard try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else {
        throw WorkspaceFailure.invalid("The workspace archive contains invalid references.")
      }
      guard
        let manifest = try Row.fetchOne(
          db, sql: "SELECT * FROM archive_manifest WHERE singleton = 1"),
        let payload = try Data.fetchOne(
          db, sql: "SELECT payload FROM workspace_snapshot WHERE singleton = 1")
      else { throw WorkspaceFailure.invalid("The workspace archive manifest is missing.") }

      let formatVersion: Int = manifest["format_version"]
      guard formatVersion == StorageLayout.archiveFormatVersion else {
        throw WorkspaceFailure.invalid("This workspace archive version is unsupported.")
      }
      let domainVersion: Int = manifest["domain_schema_version"]
      guard domainVersion <= StorageLayout.domainSchemaVersion else {
        throw WorkspaceFailure.invalid("This archive requires a newer app version.")
      }
      let manifestPayload: Data = manifest["manifest_payload"]
      let manifestHash: String = manifest["manifest_sha256"]
      guard SHA256.hash(data: manifestPayload).hexString == manifestHash else {
        throw WorkspaceFailure.invalid("The workspace archive manifest hash does not match.")
      }
      let decodedManifest = try StorageCodec.decoder().decode(
        DigestManifest.self, from: manifestPayload)
      guard decodedManifest.formatVersion == formatVersion,
        decodedManifest.domainSchemaVersion == domainVersion,
        decodedManifest.workspaceID.uuidString == manifest["workspace_id"],
        decodedManifest.sourceContainerID.uuidString == manifest["source_container_id"],
        decodedManifest.headRevisionID.uuidString == manifest["head_revision_id"],
        decodedManifest.snapshotSHA256 == manifest["snapshot_sha256"],
        decodedManifest.title == manifest["title"]
      else { throw WorkspaceFailure.invalid("The workspace archive manifest is inconsistent.") }
      guard SHA256.hash(data: payload).hexString == decodedManifest.snapshotSHA256 else {
        throw WorkspaceFailure.invalid("The workspace snapshot hash does not match.")
      }

      let identities = try Row.fetchAll(
        db,
        sql: "SELECT candidate_id, display_name FROM candidate_identities ORDER BY candidate_id"
      ).map { row -> CandidateIdentity in
        guard let id = UUID(uuidString: row["candidate_id"] as String) else {
          throw WorkspaceFailure.invalid("The archive contains an invalid candidate identifier.")
        }
        return CandidateIdentity(candidateID: id, displayName: row["display_name"])
      }
      let identitiesPayload = try identityPayload(identities)
      guard SHA256.hash(data: identitiesPayload).hexString == decodedManifest.identitiesSHA256
      else {
        throw WorkspaceFailure.invalid("The archive identity mapping hash does not match.")
      }
      let workspace = try StorageCodec.decodeSnapshot(payload, identities: identities)
      guard workspace.id == decodedManifest.workspaceID,
        workspace.containerID == decodedManifest.sourceContainerID,
        workspace.revisionID == decodedManifest.headRevisionID,
        workspace.parentRevisionID == decodedManifest.parentRevisionID,
        workspace.schemaVersion == decodedManifest.domainSchemaVersion,
        workspace.title == decodedManifest.title,
        workspace.modifiedAt == decodedManifest.modifiedAt
      else { throw WorkspaceFailure.invalid("The archive snapshot and manifest disagree.") }

      let revisionRows = try Row.fetchAll(
        db,
        sql: """
          SELECT revision_id, parent_revision_id, created_at, snapshot, snapshot_sha256,
                 identities, identities_sha256
          FROM archive_revisions ORDER BY created_at, revision_id
          """)
      var revisions: [WorkspaceDatabase.RevisionSnapshot] = []
      var revisionEntries: [RevisionEntry] = []
      for row in revisionRows {
        guard let revisionID = UUID(uuidString: row["revision_id"] as String) else {
          throw WorkspaceFailure.invalid("The archive contains an invalid revision identifier.")
        }
        let parentString: String? = row["parent_revision_id"]
        let parentID: UUID?
        if let parentString {
          guard let parsed = UUID(uuidString: parentString) else {
            throw WorkspaceFailure.invalid("The archive contains an invalid parent revision.")
          }
          parentID = parsed
        } else {
          parentID = nil
        }
        let revisionPayload: Data = row["snapshot"]
        let revisionHash: String = row["snapshot_sha256"]
        let revisionIdentitiesPayload: Data = row["identities"]
        let revisionIdentitiesHash: String = row["identities_sha256"]
        guard SHA256.hash(data: revisionPayload).hexString == revisionHash,
          SHA256.hash(data: revisionIdentitiesPayload).hexString == revisionIdentitiesHash
        else { throw WorkspaceFailure.invalid("A saved revision failed hash verification.") }
        let revisionIdentities = try StorageCodec.decoder().decode(
          [CandidateIdentity].self, from: revisionIdentitiesPayload)
        let revisionData = try StorageCodec.decodeSnapshot(
          revisionPayload, identities: revisionIdentities)
        guard revisionData.id == workspace.id, revisionData.revisionID == revisionID,
          revisionData.parentRevisionID == parentID,
          revisionData.modifiedAt == Date(timeIntervalSince1970: row["created_at"])
        else { throw WorkspaceFailure.invalid("A saved revision is inconsistent.") }
        try WorkspaceValidation.validate(revisionData)
        let createdAt = Date(timeIntervalSince1970: row["created_at"])
        revisions.append(
          WorkspaceDatabase.RevisionSnapshot(data: revisionData, createdAt: createdAt))
        revisionEntries.append(
          RevisionEntry(
            revisionID: revisionID, parentRevisionID: parentID, createdAt: createdAt,
            snapshotSHA256: revisionHash, identitiesSHA256: revisionIdentitiesHash))
      }
      guard revisionEntries == decodedManifest.revisions,
        revisions.first(where: { $0.data.revisionID == workspace.revisionID })?.data == workspace
      else { throw WorkspaceFailure.invalid("The archive revision history is incomplete.") }
      try validateLineage(revisions, head: workspace.revisionID)

      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT sha256, byte_count, type_identifier, relative_path, chunk_count
          FROM archive_assets ORDER BY sha256
          """)
      let entries = rows.map { row in
        AssetEntry(
          sha256: row["sha256"], byteCount: row["byte_count"],
          typeIdentifier: row["type_identifier"], relativePath: row["relative_path"],
          chunkCount: row["chunk_count"])
      }
      guard entries == decodedManifest.assets else {
        throw WorkspaceFailure.invalid("The archive asset manifest is inconsistent.")
      }
      var historicalAssets: [String: AssetReference] = [:]
      for revision in revisions {
        for asset in revision.data.assets {
          if let existing = historicalAssets[asset.sha256], existing != asset {
            throw WorkspaceFailure.invalid("Archive revisions contain conflicting assets.")
          }
          historicalAssets[asset.sha256] = asset
        }
      }
      guard
        entries.map(\.reference) == historicalAssets.values.sorted(by: { $0.sha256 < $1.sha256 })
      else {
        throw WorkspaceFailure.invalid("The archive assets do not match the workspace snapshot.")
      }
      for entry in entries {
        try validate(entry: entry, in: db)
      }
      return Contents(
        workspace: workspace, assets: entries.map(\.reference), revisions: revisions)
    }
  }

  static func extractAssets(
    _ assets: [AssetReference], from archiveURL: URL, to workspaceDirectory: URL
  ) throws {
    let queue = try readOnlyQueue(at: archiveURL)
    for asset in assets {
      let expectedRelativePath = try StorageLayout.assetRelativePath(sha256: asset.sha256)
      guard asset.relativePath == expectedRelativePath else {
        throw WorkspaceFailure.invalid("An archive asset path is invalid.")
      }
      let destination = try StorageFiles.containedURL(
        root: workspaceDirectory, relativePath: expectedRelativePath)
      try StorageFiles.ensureDirectory(destination.deletingLastPathComponent())
      guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
        throw WorkspaceFailure.unavailable("An imported asset could not be created.")
      }
      let output = try FileHandle(forWritingTo: destination)
      do {
        defer { try? output.close() }
        try queue.read { db in
          let cursor = try Row.fetchCursor(
            db,
            sql: """
              SELECT chunk_index, payload FROM archive_asset_chunks
              WHERE sha256 = ? ORDER BY chunk_index
              """, arguments: [asset.sha256])
          var expectedIndex = 0
          while let row = try cursor.next() {
            guard row["chunk_index"] as Int == expectedIndex else {
              throw WorkspaceFailure.invalid("An archive asset has missing chunks.")
            }
            try output.write(contentsOf: row["payload"] as Data)
            expectedIndex += 1
          }
        }
        try output.synchronize()
      } catch {
        try? FileManager.default.removeItem(at: destination)
        throw error
      }
      let digest = try StorageFiles.digest(url: destination)
      guard digest.sha256 == asset.sha256, digest.byteCount == asset.byteCount else {
        try? FileManager.default.removeItem(at: destination)
        throw WorkspaceFailure.invalid("An imported asset failed hash verification.")
      }
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o400)], ofItemAtPath: destination.path)
    }
  }

  private static func validate(entry: AssetEntry, in db: Database) throws {
    guard entry.byteCount >= 0, entry.byteCount <= StorageLayout.maximumAssetBytes,
      entry.relativePath == (try StorageLayout.assetRelativePath(sha256: entry.sha256)),
      entry.chunkCount
        == Int(
          (entry.byteCount + Int64(StorageLayout.chunkSize) - 1) / Int64(StorageLayout.chunkSize))
    else { throw WorkspaceFailure.invalid("An archive asset record is invalid.") }
    let cursor = try Row.fetchCursor(
      db,
      sql: """
        SELECT chunk_index, payload FROM archive_asset_chunks
        WHERE sha256 = ? ORDER BY chunk_index
        """, arguments: [entry.sha256])
    var hasher = SHA256()
    var byteCount: Int64 = 0
    var expectedIndex = 0
    while let row = try cursor.next() {
      let index: Int = row["chunk_index"]
      let payload: Data = row["payload"]
      guard index == expectedIndex,
        payload.count == StorageLayout.chunkSize || expectedIndex == entry.chunkCount - 1
      else { throw WorkspaceFailure.invalid("An archive asset has invalid chunks.") }
      byteCount += Int64(payload.count)
      hasher.update(data: payload)
      expectedIndex += 1
    }
    guard expectedIndex == entry.chunkCount else {
      throw WorkspaceFailure.invalid("An archive asset has missing chunks.")
    }
    guard byteCount == entry.byteCount, hasher.finalize().hexString == entry.sha256 else {
      throw WorkspaceFailure.invalid("An archive asset failed hash verification.")
    }
  }

  private static func readOnlyQueue(at url: URL) throws -> DatabaseQueue {
    try StorageFiles.rejectSymlink(url, description: "The workspace archive")
    var configuration = Configuration()
    configuration.readonly = true
    configuration.prepareDatabase { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
      try db.execute(sql: "PRAGMA trusted_schema = OFF")
      try db.execute(sql: "PRAGMA query_only = ON")
    }
    return try DatabaseQueue(path: url.path, configuration: configuration)
  }

  private static func identityPayload(_ identities: [CandidateIdentity]) throws -> Data {
    try StorageCodec.encoder().encode(
      identities.sorted { $0.candidateID.uuidString < $1.candidateID.uuidString })
  }

  private static func validateLineage(
    _ revisions: [WorkspaceDatabase.RevisionSnapshot], head: UUID
  ) throws {
    let identifiers = revisions.map { $0.data.revisionID }
    guard Set(identifiers).count == identifiers.count else {
      throw WorkspaceFailure.invalid("The archive contains duplicate revisions.")
    }
    let byID = Dictionary(uniqueKeysWithValues: revisions.map { ($0.data.revisionID, $0.data) })
    var visited: Set<UUID> = []
    var cursor: UUID? = head
    while let revisionID = cursor {
      guard visited.insert(revisionID).inserted, let revision = byID[revisionID] else {
        throw WorkspaceFailure.invalid("The archive revision lineage is invalid.")
      }
      cursor = revision.parentRevisionID
    }
    guard visited.count == revisions.count else {
      throw WorkspaceFailure.invalid("The archive contains unrelated revision history.")
    }
  }
}
