import SwiftUI
import WorkspaceKit

@main
struct GradingWorkspaceApp: App {
  var body: some Scene {
    #if os(macOS)
    WindowGroup("Grading Workspace") {
      WorkspaceRootView()
    }
    .defaultSize(width: 1360, height: 900)
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentMinSize)
    #else
    WindowGroup("Grading Workspace") { WorkspaceRootView() }
    #endif
  }
}
