import CryptoKit
import Foundation

public enum WorkspaceStorageFaultPoint: String, Sendable {
  case afterAssetStaged
  case afterAssetJournaled
  case afterAssetPromoted
  case afterArchiveCreated
  case duringArchiveAssetWrite
  case afterImportPrepared
}

public typealias WorkspaceStorageFaultInjector =
  @Sendable (WorkspaceStorageFaultPoint) throws -> Void

enum StorageLayout {
  static let liveSchemaVersion = 2
  static let archiveFormatVersion = 1
  static let domainSchemaVersion = 1
  static let chunkSize = 1_048_576
  static let maximumAssetBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
  static let maximumArchiveBytes: Int64 = 20 * 1_024 * 1_024 * 1_024

  static func workspaceDirectory(root: URL, containerID: UUID) -> URL {
    root.appendingPathComponent("Workspaces", isDirectory: true)
      .appendingPathComponent(containerID.uuidString.lowercased(), isDirectory: true)
  }

  static func databaseURL(workspaceDirectory: URL) -> URL {
    workspaceDirectory.appendingPathComponent("workspace.sqlite", isDirectory: false)
  }

  static func assetRelativePath(sha256: String) throws -> String {
    guard isSHA256(sha256) else { throw WorkspaceFailure.invalid("The asset hash is invalid.") }
    return "Assets/\(sha256.prefix(2))/\(sha256)"
  }

  static func isSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

struct StoredSnapshot: Sendable {
  var data: WorkspaceData
  var payload: Data
}

enum StorageCodec {
  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }

  static func snapshotPayload(_ data: WorkspaceData) throws -> Data {
    var separated = data
    separated.identities = []
    return try encoder().encode(separated)
  }

  static func decodeSnapshot(_ payload: Data, identities: [CandidateIdentity]) throws
    -> WorkspaceData
  {
    var data = try decoder().decode(WorkspaceData.self, from: payload)
    data.identities = identities
    return data
  }
}

struct FileDigest: Sendable {
  var sha256: String
  var byteCount: Int64
}

enum StorageFiles {
  static func ensureDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  static func rejectSymlink(_ url: URL, description: String) throws {
    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
    guard values.isSymbolicLink != true else {
      throw WorkspaceFailure.invalid("\(description) cannot be a symbolic link.")
    }
    guard values.isRegularFile == true else {
      throw WorkspaceFailure.invalid("\(description) must be a regular file.")
    }
  }

  static func containedURL(root: URL, relativePath: String) throws -> URL {
    guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
      throw WorkspaceFailure.invalid("An asset path is invalid.")
    }
    let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw WorkspaceFailure.invalid("An asset path escapes its workspace.")
    }
    let standardizedRoot = root.standardizedFileURL
    let candidate = standardizedRoot.appendingPathComponent(relativePath).standardizedFileURL
    let prefix =
      standardizedRoot.path.hasSuffix("/") ? standardizedRoot.path : standardizedRoot.path + "/"
    guard candidate.path.hasPrefix(prefix) else {
      throw WorkspaceFailure.invalid("An asset path escapes its workspace.")
    }
    return candidate
  }

  static func digest(url: URL, maximumBytes: Int64 = StorageLayout.maximumAssetBytes) throws
    -> FileDigest
  {
    try rejectSymlink(url, description: "The file")
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    var total: Int64 = 0
    while let chunk = try handle.read(upToCount: StorageLayout.chunkSize), !chunk.isEmpty {
      total += Int64(chunk.count)
      guard total <= maximumBytes else {
        throw WorkspaceFailure.invalid("The file is larger than the supported limit.")
      }
      hasher.update(data: chunk)
    }
    return FileDigest(sha256: hasher.finalize().hexString, byteCount: total)
  }

  static func copyAndDigest(
    from source: URL, to destination: URL,
    maximumBytes: Int64 = StorageLayout.maximumAssetBytes
  ) throws -> FileDigest {
    try rejectSymlink(source, description: "The source file")
    try ensureDirectory(destination.deletingLastPathComponent())
    guard FileManager.default.fileExists(atPath: destination.path) == false else {
      throw WorkspaceFailure.unavailable("A staged file already exists.")
    }
    guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
      throw WorkspaceFailure.unavailable("The staged file could not be created.")
    }
    let input = try FileHandle(forReadingFrom: source)
    let output = try FileHandle(forWritingTo: destination)
    do {
      defer {
        try? input.close()
        try? output.close()
      }
      var hasher = SHA256()
      var total: Int64 = 0
      while let chunk = try input.read(upToCount: StorageLayout.chunkSize), !chunk.isEmpty {
        total += Int64(chunk.count)
        guard total <= maximumBytes else {
          throw WorkspaceFailure.invalid("The file is larger than the supported limit.")
        }
        hasher.update(data: chunk)
        try output.write(contentsOf: chunk)
      }
      try output.synchronize()
      return FileDigest(sha256: hasher.finalize().hexString, byteCount: total)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }

  static func moveToRecovery(_ url: URL, root: URL, label: String) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let recovery = root.appendingPathComponent("Recovery", isDirectory: true)
    try ensureDirectory(recovery)
    let target = recovery.appendingPathComponent(
      "\(label)-\(UUID().uuidString.lowercased())", isDirectory: true)
    try FileManager.default.moveItem(at: url, to: target)
  }
}

extension Digest {
  var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}

enum WorkspaceValidation {
  static func validate(_ data: WorkspaceData, expectedContainerID: UUID? = nil) throws {
    try WorkspaceIntegrity.validate(data)
    guard data.schemaVersion == StorageLayout.domainSchemaVersion else {
      throw WorkspaceFailure.invalid("The workspace data version is unsupported.")
    }
    guard data.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
      throw WorkspaceFailure.invalid("A workspace title is required.")
    }
    if let expectedContainerID, data.containerID != expectedContainerID {
      throw WorkspaceFailure.invalid("The workspace belongs to a different local container.")
    }
    try requireUnique(data.assignments.map(\.id), label: "assignment")
    let submissions = data.assignments.flatMap(\.submissions)
    try requireUnique(submissions.map(\.id), label: "submission")
    for assignment in data.assignments {
      try requireUnique(assignment.submissions.map(\.candidateID), label: "assignment candidate")
    }
    try requireUnique(data.identities.map(\.candidateID), label: "candidate identity")

    let candidates = Set(submissions.map(\.candidateID))
    guard data.identities.allSatisfy({ candidates.contains($0.candidateID) }) else {
      throw WorkspaceFailure.invalid("An identity does not match a workspace candidate.")
    }
    for identity in data.identities {
      guard identity.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      else {
        throw WorkspaceFailure.invalid("Candidate names cannot be empty.")
      }
    }
    var assetsByHash: [String: AssetReference] = [:]
    let allAssets = data.assignments.flatMap { assignment in
      assignment.references.compactMap { $0.document?.asset }
        + assignment.submissions.flatMap { submission in
          submission.documents.map(\.asset) + submission.ocr.blocks.compactMap(\.cropAsset)
        }
    }
    for asset in allAssets {
      let expectedPath = try StorageLayout.assetRelativePath(sha256: asset.sha256)
      guard asset.byteCount >= 0, asset.byteCount <= StorageLayout.maximumAssetBytes,
        asset.relativePath == expectedPath
      else { throw WorkspaceFailure.invalid("An asset reference is invalid.") }
      if let existing = assetsByHash[asset.sha256], existing != asset {
        throw WorkspaceFailure.invalid("Conflicting references use the same asset hash.")
      }
      assetsByHash[asset.sha256] = asset
    }
  }

  private static func requireUnique<T: Hashable>(_ values: [T], label: String) throws {
    guard Set(values).count == values.count else {
      throw WorkspaceFailure.invalid("The workspace contains a duplicate \(label) identifier.")
    }
  }
}
