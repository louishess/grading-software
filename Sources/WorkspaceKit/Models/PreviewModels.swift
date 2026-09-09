import Foundation

package struct AssignmentPreview: Codable, Identifiable, Sendable {
  package let id: String
  package let title: String
  package let course: String
  package let subtitle: String
  package let maximumScore: Int
  package let parts: [AssignmentPart]
  package let submissions: [SubmissionPreview]
  package let rubric: [RubricCriterion]
  package let answerKey: [ReferencePreview]
  package let exemplars: [ReferencePreview]
  package let statistics: [StatisticsPreview]
}

package struct AssignmentPart: Codable, Identifiable, Sendable {
  package let id: String
  package let title: String
  package let maximumScore: Int
}

package struct SubmissionPreview: Codable, Identifiable, Sendable {
  package let id: String
  package let candidateLabel: String
  package let document: DocumentPreview
  package let status: String
  package let exampleScore: Int
  package let criterionScores: [String: Int]
  package let feedback: String
  package let transcription: String
}

package struct DocumentPreview: Codable, Sendable {
  package let title: String
  package let subtitle: String
  package let sections: [DocumentSection]
}

package struct DocumentSection: Codable, Identifiable, Sendable {
  package let id: String
  package let heading: String
  package let prompt: String
  package let response: String
}

package struct RubricCriterion: Codable, Identifiable, Sendable {
  package let id: String
  package let partID: String
  package let title: String
  package let description: String
  package let maximumScore: Int
  package let performanceDescription: String
}

package struct ReferencePreview: Codable, Identifiable, Sendable {
  package let id: String
  package let partID: String
  package let title: String
  package let body: String
}

package struct HistogramBin: Codable, Identifiable, Sendable {
  package let id: String
  package let label: String
  package let lowerBound: Double
  package let upperBound: Double
  package let count: Int
}

package struct StatisticsPreview: Codable, Identifiable, Sendable {
  package let id: String
  package let title: String
  package let maximumScore: Int
  package let scores: [Int]
  package let mean: Double
  package let median: Double
  package let modes: [Int]
  package let minimum: Int
  package let maximum: Int
  package let range: Int
  package let populationStandardDeviation: Double
  package let bins: [HistogramBin]
}

package enum InspectorTab: String, CaseIterable, Identifiable {
  case rubric = "Rubric"
  case references = "References"
  case transcription = "OCR"
  package var id: String { rawValue }
}

package enum WorkspaceAppearance: String, CaseIterable, Identifiable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"
  package var id: String { rawValue }
}
