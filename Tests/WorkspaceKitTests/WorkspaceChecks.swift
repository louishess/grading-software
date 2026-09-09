import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
  let description: String
}

func expect(
  _ condition: @autoclosure () throws -> Bool,
  file: StaticString = #filePath, line: UInt = #line
) throws {
  guard try condition() else {
    throw CheckFailure(description: "\(file):\(line): expectation failed")
  }
}

func require<T>(
  _ value: T?, file: StaticString = #filePath, line: UInt = #line
) throws -> T {
  guard let value else {
    throw CheckFailure(description: "\(file):\(line): required value was nil")
  }
  return value
}

@main
struct WorkspaceChecks {
  @MainActor static func main() {
    let checks: [(String, @MainActor () throws -> Void)] = [
      ("Bundled examples contain both subjects", bundledExamplesContainBothSubjects),
      (
        "Assignment switch resets candidate and statistics",
        selectingAssignmentResetsSubmissionAndStatisticsTogether
      ),
      (
        "Invalid and cross-assignment selections are ignored",
        invalidAndCrossAssignmentSelectionsAreIgnored
      ),
      (
        "Reselecting an assignment preserves its selection",
        reselectingAssignmentPreservesItsCurrentSubmission
      ),
      ("Empty catalog handles selection safely", emptyCatalogRemainsSafeUnderSelection),
      (
        "Every part has rubric, references and statistics",
        allPartsHaveRubricReferencesAndStatistics
      ),
      (
        "Documents match selected sample and transcription",
        sampleDocumentsMatchSelectionAndTranscription
      ),
      (
        "Precomputed statistics match the distributions",
        precomputedStatisticsMatchTheirSampleDistributions
      ),
      ("Histogram bins cover each sample exactly once", histogramBinsCoverEverySampleExactlyOnce),
      ("Example scores agree across all panes", exampleScoresAgreeAcrossRubricAndStatistics),
    ]
    var failures = 0
    for (name, check) in checks {
      do {
        try check()
        print("PASS  \(name)")
      } catch {
        failures += 1
        print("FAIL  \(name): \(error)")
      }
    }
    print("\(checks.count - failures)/\(checks.count) checks passed")
    if failures > 0 { exit(1) }
  }
}
