import Foundation
import WorkspaceKit

@main
struct FunctionalCheckRunner {
  @MainActor static func main() async {
    var failed = 0
    let checks: [(String, @MainActor () async throws -> Void)] = [
      ("Storage integrity, archives, and recovery", { try await runStorageChecks() }),
      ("Grading, approval, statistics, and structured exports", { try runGradingChecks() }),
      ("Document geometry, OCR, and PDF exports", { try await runDocumentChecks() }),
      ("Complete local grading and transfer workflow", { try await runWorkflowChecks() }),
      ("Image formats, EXIF rotation, and crop alignment", { try await runImageWorkflowChecks() }),
    ]
    for (name, run) in checks {
      do {
        try await run()
        print("PASS \(name)")
      } catch {
        failed += 1
        print("FAIL \(name): \(error)")
      }
    }
    print("\(checks.count - failed)/\(checks.count) functional suites passed")
    if failed > 0 { exit(1) }
  }
}
