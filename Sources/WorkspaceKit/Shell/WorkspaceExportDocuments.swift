import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.folder, .data] }
  let url: URL
  let isArchive: Bool
  var contentType: UTType { isArchive ? .data : .folder }
  init(url: URL, isArchive: Bool) {
    self.url = url
    self.isArchive = isArchive
  }
  init(configuration: ReadConfiguration) throws {
    throw WorkspaceFailure.invalid("Use workspace import to open grading data.")
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    try FileWrapper(url: url, options: [])
  }
}
