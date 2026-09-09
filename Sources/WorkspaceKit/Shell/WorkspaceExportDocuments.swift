import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceExportFolder: FileDocument {
  static var readableContentTypes: [UTType] { [.folder] }
  let directory: URL
  init(directory: URL) { self.directory = directory }
  init(configuration: ReadConfiguration) throws {
    throw WorkspaceFailure.invalid("Use workspace import to open grading data.")
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    try FileWrapper(url: directory, options: [])
  }
}

struct WorkspaceArchiveFile: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  let url: URL
  init(url: URL) { self.url = url }
  init(configuration: ReadConfiguration) throws {
    throw WorkspaceFailure.invalid("Use workspace import to open this archive.")
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    try FileWrapper(url: url, options: [])
  }
}
