import Observation

@MainActor @Observable
package final class WorkspaceStore {
  package let assignments: [AssignmentPreview]
  package private(set) var selectedAssignmentID: String?
  package private(set) var selectedSubmissionID: String?
  package private(set) var selectedScopeID = "overall"
  package var inspectorTab: InspectorTab = .rubric
  package var showsStatistics = true
  package var showsAccount = false
  package var appearance: WorkspaceAppearance = .system

  package init(assignments: [AssignmentPreview]) {
    self.assignments = assignments
    selectedAssignmentID = assignments.first?.id
    selectedSubmissionID = assignments.first?.submissions.first?.id
  }

  package var assignment: AssignmentPreview? {
    assignments.first { $0.id == selectedAssignmentID }
  }

  package var submission: SubmissionPreview? {
    assignment?.submissions.first { $0.id == selectedSubmissionID }
  }

  package func selectAssignment(_ id: String) {
    guard let next = assignments.first(where: { $0.id == id }) else { return }
    guard id != selectedAssignmentID else { return }
    selectedAssignmentID = next.id
    selectedSubmissionID = next.submissions.first?.id
    selectedScopeID = "overall"
  }

  package func selectSubmission(_ id: String) {
    guard assignment?.submissions.contains(where: { $0.id == id }) == true else { return }
    selectedSubmissionID = id
  }

  package func selectScope(_ id: String) {
    guard assignment?.statistics.contains(where: { $0.id == id }) == true else { return }
    selectedScopeID = id
  }
}
