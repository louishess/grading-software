// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "GradingWorkspace",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "GradingWorkspace", targets: ["GradingWorkspace"])],
  targets: [
    .target(name: "WorkspaceKit", resources: [.copy("Resources")]),
    .executableTarget(name: "GradingWorkspace", dependencies: ["WorkspaceKit"]),
    .executableTarget(
      name: "WorkspaceChecks", dependencies: ["WorkspaceKit"], path: "Tests/WorkspaceKitTests"
    ),
  ]
)
