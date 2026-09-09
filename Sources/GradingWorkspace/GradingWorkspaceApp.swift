import SwiftUI
import WorkspaceKit

@main
struct GradingWorkspaceApp: App {
  var body: some Scene {
    WindowGroup("Grading Workspace") {
      WorkspaceRootView()
    }
    .defaultSize(width: 1360, height: 900)
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentMinSize)
  }
}
