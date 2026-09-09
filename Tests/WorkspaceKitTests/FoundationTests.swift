import Foundation
import WorkspaceKit

func bundledExamplesContainBothSubjects() throws {
  let assignments = try PreviewCatalog.load()
  try expect(assignments.map(\.id) == ["math", "writing"])
  try expect(assignments.allSatisfy { $0.submissions.count == 6 && $0.parts.count == 3 })
}

@MainActor func selectingAssignmentResetsSubmissionAndStatisticsTogether() throws {
  let assignments = try PreviewCatalog.load()
  let store = WorkspaceStore(assignments: assignments)
  store.selectSubmission(assignments[0].submissions[3].id)
  store.selectScope(assignments[0].parts[1].id)
  store.selectAssignment(assignments[1].id)
  try expect(store.assignment?.id == assignments[1].id)
  try expect(store.submission?.id == assignments[1].submissions[0].id)
  try expect(store.selectedScopeID == "overall")
}

@MainActor func invalidAndCrossAssignmentSelectionsAreIgnored() throws {
  let assignments = try PreviewCatalog.load()
  let store = WorkspaceStore(assignments: assignments)
  store.selectAssignment("missing")
  store.selectSubmission(assignments[1].submissions[0].id)
  store.selectScope(assignments[1].parts[0].id)
  try expect(store.assignment?.id == assignments[0].id)
  try expect(store.submission?.id == assignments[0].submissions[0].id)
  try expect(store.selectedScopeID == "overall")
}

@MainActor func reselectingAssignmentPreservesItsCurrentSubmission() throws {
  let assignments = try PreviewCatalog.load()
  let store = WorkspaceStore(assignments: assignments)
  store.selectSubmission(assignments[0].submissions[2].id)
  store.selectScope(assignments[0].parts[2].id)
  store.selectAssignment(assignments[0].id)
  try expect(store.submission?.id == assignments[0].submissions[2].id)
  try expect(store.selectedScopeID == assignments[0].parts[2].id)
}

@MainActor func emptyCatalogRemainsSafeUnderSelection() throws {
  let store = WorkspaceStore(assignments: [])
  store.selectAssignment("math")
  store.selectSubmission("math-s1")
  store.selectScope("math-p1")
  try expect(store.assignment == nil)
  try expect(store.submission == nil)
  try expect(store.selectedScopeID == "overall")
}

func allPartsHaveRubricReferencesAndStatistics() throws {
  for assignment in try PreviewCatalog.load() {
    let parts = Set(assignment.parts.map(\.id))
    try expect(Set(assignment.rubric.map(\.partID)) == parts)
    try expect(Set(assignment.answerKey.map(\.partID)) == parts)
    try expect(Set(assignment.exemplars.map(\.partID)) == parts)
    try expect(Set(assignment.statistics.map(\.id)) == parts.union(["overall"]))
    try expect(assignment.answerKey.allSatisfy { !$0.body.isEmpty })
    try expect(assignment.exemplars.allSatisfy { !$0.body.isEmpty })
  }
}

func sampleDocumentsMatchSelectionAndTranscription() throws {
  for assignment in try PreviewCatalog.load() {
    try expect(Set(assignment.submissions.map(\.id)).count == assignment.submissions.count)
    for submission in assignment.submissions {
      try expect(submission.candidateLabel.hasPrefix("Candidate "))
      try expect(submission.status == "Sample draft")
      try expect(submission.document.title == assignment.title)
      try expect(submission.document.sections.map(\.id) == assignment.parts.map(\.id))
      try expect(
        submission.document.sections.allSatisfy { !$0.response.isEmpty && !$0.prompt.isEmpty })
      for section in submission.document.sections {
        try expect(submission.transcription.contains(section.response))
      }
    }
  }
}

func precomputedStatisticsMatchTheirSampleDistributions() throws {
  for assignment in try PreviewCatalog.load() {
    for summary in assignment.statistics {
      let values = summary.scores.map(Double.init)
      let mean = values.reduce(0, +) / Double(values.count)
      let sorted = values.sorted()
      let median = (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
      let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
      let frequencies = Dictionary(grouping: summary.scores, by: { $0 }).mapValues(\.count)
      let highest = frequencies.values.max()!
      let modes = highest > 1 ? frequencies.filter { $0.value == highest }.keys.sorted() : []
      try expect(abs(summary.mean - mean) < 0.000_001)
      try expect(abs(summary.median - median) < 0.000_001)
      try expect(abs(summary.populationStandardDeviation - sqrt(variance)) < 0.000_001)
      try expect(summary.modes == modes)
      try expect(summary.minimum == summary.scores.min())
      try expect(summary.maximum == summary.scores.max())
      try expect(summary.range == summary.maximum - summary.minimum)
    }
  }
}

func histogramBinsCoverEverySampleExactlyOnce() throws {
  for assignment in try PreviewCatalog.load() {
    for summary in assignment.statistics {
      try expect(summary.bins.reduce(0) { $0 + $1.count } == summary.scores.count)
      for score in summary.scores {
        let containing = summary.bins.filter {
          Double(score) >= $0.lowerBound && Double(score) < $0.upperBound
        }
        try expect(containing.count == 1)
      }
      for bin in summary.bins {
        let count = summary.scores.filter {
          Double($0) >= bin.lowerBound && Double($0) < bin.upperBound
        }.count
        try expect(count == bin.count)
      }
    }
  }
}

func exampleScoresAgreeAcrossRubricAndStatistics() throws {
  for assignment in try PreviewCatalog.load() {
    try expect(assignment.maximumScore == assignment.parts.reduce(0) { $0 + $1.maximumScore })
    try expect(assignment.statistics[0].scores == assignment.submissions.map(\.exampleScore))
    for (partIndex, part) in assignment.parts.enumerated() {
      let criterion = assignment.rubric[partIndex]
      let summary = assignment.statistics.first { $0.id == part.id }!
      try expect(summary.maximumScore == part.maximumScore)
      try expect(summary.scores == assignment.submissions.map { $0.criterionScores[criterion.id]! })
    }
    for submission in assignment.submissions {
      try expect(submission.exampleScore == submission.criterionScores.values.reduce(0, +))
      for criterion in assignment.rubric {
        let score = try require(submission.criterionScores[criterion.id])
        try expect((0...criterion.maximumScore).contains(score))
      }
    }
  }
}
