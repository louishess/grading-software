// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "GradingWorkspace",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "WorkspaceKit", targets: ["WorkspaceKit"]),
    .executable(name: "GradingWorkspace", targets: ["GradingWorkspace"]),
  ],
  dependencies: [.package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")],
  targets: [
    .target(
      name: "WorkspaceKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
      resources: [.copy("Resources")]),
    .executableTarget(name: "GradingWorkspace", dependencies: ["WorkspaceKit"]),
    .executableTarget(
      name: "FunctionalChecks", dependencies: ["WorkspaceKit"], path: "Tests/FunctionalChecks"),
    .executableTarget(
      name: "WorkspaceChecks", dependencies: ["WorkspaceKit"], path: "Tests/WorkspaceKitTests"
    ),
  ]
)
