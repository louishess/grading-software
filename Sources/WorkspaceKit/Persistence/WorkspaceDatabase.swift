import Foundation
import GRDB

final class WorkspaceDatabase: @unchecked Sendable {
  struct Metadata: Sendable {
    var workspaceID: UUID
    var containerID: UUID
    var title: String
    var headRevisionID: UUID
    var modifiedAt: Date
  }

  struct AssetOperation: Sendable {
    var id: UUID
    var stagingRelativePath: String
    var finalRelativePath: String
    var sha256: String
    var byteCount: Int64
    var typeIdentifier: String
  }

  struct RevisionSnapshot: Sendable {
    var data: WorkspaceData
    var createdAt: Date
  }

  let directory: URL
  let queue: DatabaseQueue

  init(directory: URL, createIfMissing: Bool) throws {
    self.directory = directory
    let databaseURL = StorageLayout.databaseURL(workspaceDirectory: directory)
    if !createIfMissing, !FileManager.default.fileExists(atPath: databaseURL.path) {
      throw WorkspaceFailure.unavailable("The workspace database is missing.")
    }
    var configuration = Configuration()
    configuration.label = "GradingWorkspace.\(directory.lastPathComponent)"
    configuration.busyMode = .timeout(5)
    configuration.prepareDatabase { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
      try db.execute(sql: "PRAGMA journal_mode = WAL")
      try db.execute(sql: "PRAGMA synchronous = FULL")
      try db.execute(sql: "PRAGMA trusted_schema = OFF")
    }
    queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
    try prepareSchema(createIfMissing: createIfMissing)
  }

  func seed(_ data: WorkspaceData, revisionHistory: [RevisionSnapshot]? = nil) throws {
    try WorkspaceValidation.validate(data, expectedContainerID: data.containerID)
    let revisions = revisionHistory ?? [RevisionSnapshot(data: data, createdAt: data.modifiedAt)]
    try validateRevisionHistory(revisions, head: data.revisionID)
    guard revisions.first(where: { $0.data.revisionID == data.revisionID })?.data == data else {
      throw WorkspaceFailure.invalid("The imported head does not match its current snapshot.")
    }
    try queue.writeWithoutTransaction { db in
      let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workspace_metadata") ?? 0
      guard count == 0 else { throw WorkspaceFailure.invalid("The workspace already exists.") }
      try db.inTransaction {
        try db.execute(
          sql: """
            INSERT INTO workspace_metadata
              (singleton, workspace_id, container_id, title, head_revision_id, modified_at)
            VALUES (1, ?, ?, ?, ?, ?)
            """,
          arguments: [
            data.id.uuidString, data.containerID.uuidString, data.title, data.revisionID.uuidString,
            data.modifiedAt.timeIntervalSince1970,
          ])
        for revision in revisions {
          let payload = try StorageCodec.snapshotPayload(revision.data)
          try db.execute(
            sql: """
              INSERT INTO workspace_revisions
                (revision_id, parent_revision_id, created_at, snapshot)
              VALUES (?, ?, ?, ?)
              """,
            arguments: [
              revision.data.revisionID.uuidString, revision.data.parentRevisionID?.uuidString,
              revision.createdAt.timeIntervalSince1970, payload,
            ])
          try insertRevisionIdentities(
            revision.data.identities, revisionID: revision.data.revisionID, in: db)
        }
        try replaceIdentities(data.identities, in: db)
        return .commit
      }
    }
  }

  func metadata() throws -> Metadata {
    try queue.read { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql: """
            SELECT workspace_id, container_id, title, head_revision_id, modified_at
            FROM workspace_metadata WHERE singleton = 1
            """)
      else { throw WorkspaceFailure.invalid("The workspace metadata is missing.") }
      return try Metadata(
        workspaceID: parseUUID(row["workspace_id"], label: "workspace"),
        containerID: parseUUID(row["container_id"], label: "container"),
        title: row["title"],
        headRevisionID: parseUUID(row["head_revision_id"], label: "revision"),
        modifiedAt: Date(timeIntervalSince1970: row["modified_at"]))
    }
  }

  func load() throws -> WorkspaceData {
    try queue.read { db in
      guard
        let metadata = try Row.fetchOne(
          db,
          sql: """
            SELECT workspace_id, container_id, title, head_revision_id, modified_at
            FROM workspace_metadata WHERE singleton = 1
            """),
        let payload = try Data.fetchOne(
          db, sql: "SELECT snapshot FROM workspace_revisions WHERE revision_id = ?",
          arguments: [metadata["head_revision_id"] as String])
      else { throw WorkspaceFailure.invalid("The workspace snapshot is missing.") }
      let identities = try identityRows(in: db)
      let data = try StorageCodec.decodeSnapshot(payload, identities: identities)
      guard
        data.id.uuidString == metadata["workspace_id"],
        data.containerID.uuidString == metadata["container_id"],
        data.revisionID.uuidString == metadata["head_revision_id"]
      else { throw WorkspaceFailure.invalid("The workspace metadata and snapshot disagree.") }
      try WorkspaceValidation.validate(data, expectedContainerID: data.containerID)
      return data
    }
  }

  func save(_ data: WorkspaceData, expectedRevision: UUID) throws -> WorkspaceData {
    guard data.revisionID == expectedRevision else { throw WorkspaceFailure.staleRevision }
    var saved = data
    saved.parentRevisionID = expectedRevision
    saved.revisionID = UUID()
    saved.modifiedAt = Date()
    try WorkspaceValidation.validate(saved, expectedContainerID: data.containerID)
    let payload = try StorageCodec.snapshotPayload(saved)

    return try queue.write { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql:
            "SELECT workspace_id, container_id, head_revision_id FROM workspace_metadata WHERE singleton = 1"
        )
      else { throw WorkspaceFailure.invalid("The workspace metadata is missing.") }
      guard row["workspace_id"] as String == data.id.uuidString,
        row["container_id"] as String == data.containerID.uuidString
      else { throw WorkspaceFailure.invalid("The workspace identity cannot be changed.") }
      guard row["head_revision_id"] as String == expectedRevision.uuidString else {
        throw WorkspaceFailure.staleRevision
      }

      try db.execute(
        sql: """
          INSERT INTO workspace_revisions
            (revision_id, parent_revision_id, created_at, snapshot)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          saved.revisionID.uuidString, expectedRevision.uuidString,
          saved.modifiedAt.timeIntervalSince1970, payload,
        ])
      try insertRevisionIdentities(saved.identities, revisionID: saved.revisionID, in: db)
      try replaceIdentities(saved.identities, in: db)
      try db.execute(
        sql: """
          UPDATE workspace_metadata
          SET title = ?, head_revision_id = ?, modified_at = ?
          WHERE singleton = 1
          """,
        arguments: [
          saved.title, saved.revisionID.uuidString, saved.modifiedAt.timeIntervalSince1970,
        ])
      return saved
    }
  }

  func revisions() throws -> [RevisionSnapshot] {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT revision_id, parent_revision_id, created_at, snapshot
          FROM workspace_revisions ORDER BY created_at, revision_id
          """
      ).map { row in
        let revisionID = try parseUUID(row["revision_id"], label: "revision")
        let identities = try revisionIdentityRows(revisionID: revisionID, in: db)
        let payload: Data = row["snapshot"]
        let data = try StorageCodec.decodeSnapshot(payload, identities: identities)
        guard data.revisionID == revisionID,
          data.parentRevisionID?.uuidString == row["parent_revision_id"] as String?
        else { throw WorkspaceFailure.invalid("A saved revision is inconsistent.") }
        try WorkspaceValidation.validate(data, expectedContainerID: data.containerID)
        return RevisionSnapshot(
          data: data, createdAt: Date(timeIntervalSince1970: row["created_at"]))
      }
    }
  }

  func recordAsset(_ asset: AssetReference, in db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO asset_records (sha256, byte_count, type_identifier, relative_path)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(sha256) DO UPDATE SET
          byte_count = excluded.byte_count,
          type_identifier = excluded.type_identifier,
          relative_path = excluded.relative_path
        """,
      arguments: [asset.sha256, asset.byteCount, asset.typeIdentifier, asset.relativePath])
  }

  func asset(sha256: String) throws -> AssetReference? {
    try queue.read { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql: """
            SELECT sha256, byte_count, type_identifier, relative_path
            FROM asset_records WHERE sha256 = ?
            """, arguments: [sha256])
      else { return nil }
      return AssetReference(
        sha256: row["sha256"], byteCount: row["byte_count"],
        typeIdentifier: row["type_identifier"], relativePath: row["relative_path"])
    }
  }

  func beginAssetOperation(_ operation: AssetOperation) throws {
    try queue.write { db in
      try db.execute(
        sql: """
          INSERT INTO file_operations
            (operation_id, kind, state, staging_path, final_path, sha256, byte_count,
             type_identifier, created_at)
          VALUES (?, 'asset', 'staged', ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          operation.id.uuidString, operation.stagingRelativePath, operation.finalRelativePath,
          operation.sha256, operation.byteCount, operation.typeIdentifier,
          Date().timeIntervalSince1970,
        ])
    }
  }

  func finishAssetOperation(_ operation: AssetOperation) throws {
    let asset = AssetReference(
      sha256: operation.sha256, byteCount: operation.byteCount,
      typeIdentifier: operation.typeIdentifier, relativePath: operation.finalRelativePath)
    try queue.writeWithoutTransaction { db in
      try db.inTransaction {
        try recordAsset(asset, in: db)
        try db.execute(
          sql: "DELETE FROM file_operations WHERE operation_id = ?",
          arguments: [operation.id.uuidString])
        return .commit
      }
    }
  }

  func assetOperations() throws -> [AssetOperation] {
    try queue.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT operation_id, staging_path, final_path, sha256, byte_count, type_identifier
          FROM file_operations WHERE kind = 'asset' ORDER BY created_at, operation_id
          """
      ).map { row in
        try AssetOperation(
          id: parseUUID(row["operation_id"], label: "operation"),
          stagingRelativePath: row["staging_path"], finalRelativePath: row["final_path"],
          sha256: row["sha256"], byteCount: row["byte_count"],
          typeIdentifier: row["type_identifier"])
      }
    }
  }

  func removeAssetOperation(id: UUID) throws {
    try queue.write { db in
      try db.execute(
        sql: "DELETE FROM file_operations WHERE operation_id = ?", arguments: [id.uuidString])
    }
  }

  func verifyIntegrity() throws {
    try queue.read { db in
      let result = try String.fetchOne(db, sql: "PRAGMA integrity_check")
      guard result == "ok" else {
        throw WorkspaceFailure.invalid("The workspace database failed its integrity check.")
      }
      let foreignKeyFailures = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
      guard foreignKeyFailures.isEmpty else {
        throw WorkspaceFailure.invalid("The workspace database contains invalid references.")
      }
    }
  }

  private func prepareSchema(createIfMissing: Bool) throws {
    let version = try queue.read { db in try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0 }
    guard version <= StorageLayout.liveSchemaVersion else {
      throw WorkspaceFailure.invalid("This workspace requires a newer app version.")
    }
    if version > 0, version < StorageLayout.liveSchemaVersion {
      try createPreMigrationSnapshot(fromVersion: version)
    }
    if version == 0 {
      guard createIfMissing else {
        throw WorkspaceFailure.invalid("The workspace database has no recognized schema.")
      }
      try queue.writeWithoutTransaction { db in
        try db.inTransaction {
          try db.execute(
            sql: """
              CREATE TABLE workspace_metadata (
                singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                workspace_id TEXT NOT NULL,
                container_id TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                head_revision_id TEXT NOT NULL,
                modified_at REAL NOT NULL
              );
              CREATE TABLE workspace_revisions (
                revision_id TEXT PRIMARY KEY,
                parent_revision_id TEXT,
                created_at REAL NOT NULL,
                snapshot BLOB NOT NULL
              );
              CREATE TABLE candidate_identities (
                candidate_id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL
              );
              CREATE TABLE candidate_identity_revisions (
                revision_id TEXT NOT NULL REFERENCES workspace_revisions(revision_id) ON DELETE CASCADE,
                candidate_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                PRIMARY KEY (revision_id, candidate_id)
              );
              CREATE TABLE asset_records (
                sha256 TEXT PRIMARY KEY,
                byte_count INTEGER NOT NULL CHECK (byte_count >= 0),
                type_identifier TEXT NOT NULL,
                relative_path TEXT NOT NULL
              );
              CREATE TABLE file_operations (
                operation_id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                state TEXT NOT NULL,
                staging_path TEXT NOT NULL,
                final_path TEXT NOT NULL,
                sha256 TEXT NOT NULL,
                byte_count INTEGER NOT NULL,
                type_identifier TEXT NOT NULL,
                created_at REAL NOT NULL
              );
              PRAGMA user_version = 2;
              """)
          return .commit
        }
      }
    }
    if version == 1 {
      try queue.writeWithoutTransaction { db in
        try db.inTransaction {
          try db.execute(
            sql: """
              CREATE TABLE candidate_identity_revisions (
                revision_id TEXT NOT NULL REFERENCES workspace_revisions(revision_id) ON DELETE CASCADE,
                candidate_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                PRIMARY KEY (revision_id, candidate_id)
              );
              INSERT INTO candidate_identity_revisions (revision_id, candidate_id, display_name)
              SELECT workspace_metadata.head_revision_id, candidate_id, display_name
              FROM candidate_identities CROSS JOIN workspace_metadata
              WHERE workspace_metadata.singleton = 1;
              PRAGMA user_version = 2;
              """)
          return .commit
        }
      }
    }
  }

  private func createPreMigrationSnapshot(fromVersion: Int) throws {
    let backupDirectory = directory.appendingPathComponent("SafetyBackups", isDirectory: true)
    try StorageFiles.ensureDirectory(backupDirectory)
    let destination = backupDirectory.appendingPathComponent(
      "pre-migration-v\(fromVersion)-\(UUID().uuidString.lowercased()).sqlite")
    try queue.writeWithoutTransaction { db in
      try db.execute(sql: "VACUUM INTO ?", arguments: [destination.path])
    }
  }

  private func validateRevisionHistory(_ revisions: [RevisionSnapshot], head: UUID) throws {
    guard !revisions.isEmpty, revisions.contains(where: { $0.data.revisionID == head }) else {
      throw WorkspaceFailure.invalid("The imported revision history has no current head.")
    }
    let identifiers = revisions.map { $0.data.revisionID }
    guard Set(identifiers).count == identifiers.count else {
      throw WorkspaceFailure.invalid("The imported revision history has duplicate revisions.")
    }
    let known = Set(identifiers)
    for revision in revisions {
      try WorkspaceValidation.validate(
        revision.data, expectedContainerID: revision.data.containerID)
      if let parent = revision.data.parentRevisionID, !known.contains(parent) {
        throw WorkspaceFailure.invalid("The imported revision history is incomplete.")
      }
    }
    var visited: Set<UUID> = []
    var cursor: UUID? = head
    let byID = Dictionary(uniqueKeysWithValues: revisions.map { ($0.data.revisionID, $0.data) })
    while let revisionID = cursor {
      guard visited.insert(revisionID).inserted, let revision = byID[revisionID] else {
        throw WorkspaceFailure.invalid("The imported revision lineage contains a cycle.")
      }
      cursor = revision.parentRevisionID
    }
    guard visited.count == revisions.count else {
      throw WorkspaceFailure.invalid("The imported revision history contains unrelated revisions.")
    }
  }
}

private func parseUUID(_ string: String, label: String) throws -> UUID {
  guard let value = UUID(uuidString: string) else {
    throw WorkspaceFailure.invalid("The \(label) identifier is invalid.")
  }
  return value
}

private func identityRows(in db: Database) throws -> [CandidateIdentity] {
  try Row.fetchAll(
    db,
    sql: "SELECT candidate_id, display_name FROM candidate_identities ORDER BY candidate_id"
  ).map { row in
    CandidateIdentity(
      candidateID: try parseUUID(row["candidate_id"], label: "candidate"),
      displayName: row["display_name"])
  }
}

private func replaceIdentities(_ identities: [CandidateIdentity], in db: Database) throws {
  try db.execute(sql: "DELETE FROM candidate_identities")
  for identity in identities {
    try db.execute(
      sql: "INSERT INTO candidate_identities (candidate_id, display_name) VALUES (?, ?)",
      arguments: [identity.candidateID.uuidString, identity.displayName])
  }
}

private func insertRevisionIdentities(
  _ identities: [CandidateIdentity], revisionID: UUID, in db: Database
) throws {
  for identity in identities {
    try db.execute(
      sql: """
        INSERT INTO candidate_identity_revisions (revision_id, candidate_id, display_name)
        VALUES (?, ?, ?)
        """,
      arguments: [revisionID.uuidString, identity.candidateID.uuidString, identity.displayName])
  }
}

private func revisionIdentityRows(revisionID: UUID, in db: Database) throws
  -> [CandidateIdentity]
{
  try Row.fetchAll(
    db,
    sql: """
      SELECT candidate_id, display_name FROM candidate_identity_revisions
      WHERE revision_id = ? ORDER BY candidate_id
      """, arguments: [revisionID.uuidString]
  ).map { row in
    CandidateIdentity(
      candidateID: try parseUUID(row["candidate_id"], label: "candidate"),
      displayName: row["display_name"])
  }
}
