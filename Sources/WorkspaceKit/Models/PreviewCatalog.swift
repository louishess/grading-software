import Foundation

package enum PreviewCatalog {
  // Prefer packaged resources; SwiftPM's fallback is for development runs only.
  private static func resourceBundle() throws -> Bundle {
    if Bundle.main.bundleURL.pathExtension == "app" {
      guard let root = Bundle.main.resourceURL,
        let bundle = Bundle(
          url: root.appendingPathComponent("GradingWorkspace_WorkspaceKit.bundle"))
      else { throw CocoaError(.fileNoSuchFile) }
      return bundle
    }
    return Bundle.module
  }

  package static func load() throws -> [AssignmentPreview] {
    let resources = try resourceBundle()
    guard
      let url = resources.url(
        forResource: "assignments", withExtension: "json", subdirectory: "Resources"
      )
    else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try JSONDecoder().decode([AssignmentPreview].self, from: Data(contentsOf: url))
  }
}
