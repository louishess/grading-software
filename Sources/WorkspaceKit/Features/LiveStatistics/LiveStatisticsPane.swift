import Charts
import SwiftUI

/// Statistics for current approved grades or the explicitly selected draft and
/// reviewed cohort.
public struct LiveStatisticsPane: View {
  public let assignment: WorkAssignment

  @State private var selectedScopeID = "overall"
  @State private var selectedCohort: GradeStatisticsCohort = .approved
  @State private var showsDataTable = false

  public init(assignment: WorkAssignment) {
    self.assignment = assignment
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        header
        if let statistics {
          summary(for: statistics)
          if statistics.includedCount == 0 {
            emptyState(for: statistics)
          } else {
            metricsAndChart(for: statistics)
          }
        } else {
          unavailableState
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(WorkspaceStyle.background)
    .onAppear {
      ensureScopeIsAvailable()
    }
    .onChange(of: assignment.parts.map(\.id)) { _, _ in
      ensureScopeIsAvailable()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Assignment statistics")
            .font(.title3.weight(.semibold))
          Text("Statistics are calculated from the selected local review cohort.")
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 8)
        LiveStatisticsBadge(text: "No AI")
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          scopePicker
          cohortPicker
        }
        VStack(alignment: .leading, spacing: 8) {
          scopePicker
          cohortPicker
        }
      }
    }
    .workspaceCard()
  }

  private var scopePicker: some View {
    Picker("Statistics scope", selection: $selectedScopeID) {
      Text("Whole assignment").tag("overall")
      ForEach(assignment.parts) { part in
        Text(part.title.isEmpty ? "Untitled part" : part.title)
          .tag(part.id.uuidString)
      }
    }
    .pickerStyle(.menu)
    .accessibilityLabel("Statistics scope")
    .help("Choose the whole assignment or an assignment part")
  }

  private var cohortPicker: some View {
    Picker("Cohort", selection: $selectedCohort) {
      ForEach(GradeStatisticsCohort.allCases, id: \.self) { cohort in
        Text(cohort.title).tag(cohort)
      }
    }
    .pickerStyle(.menu)
    .accessibilityLabel("Statistics cohort")
    .help("Approved is the official cohort. Draft and reviewed is a separate exploratory cohort.")
  }

  private var selectedScope: GradeStatisticsScope {
    guard selectedScopeID != "overall",
      let id = UUID(uuidString: selectedScopeID),
      assignment.parts.contains(where: { $0.id == id })
    else {
      return .overall
    }
    return .part(id)
  }

  private var statistics: GradeStatisticsSnapshot? {
    try? StatisticsEngine.snapshot(
      assignment: assignment,
      scope: selectedScope,
      cohort: selectedCohort
    )
  }

  private func summary(for statistics: GradeStatisticsSnapshot) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(scopeTitle(statistics.scope))
          .font(.headline)
        Text(statistics.cohort.title)
          .font(.caption.weight(.medium))
          .foregroundStyle(WorkspaceStyle.secondary)
      }
      Spacer(minLength: 8)
      LiveStatisticsBadge(text: "n = \(statistics.includedCount)")
      if statistics.excludedCount > 0 {
        Text("\(statistics.excludedCount) excluded")
          .font(.caption.monospaced())
          .foregroundStyle(WorkspaceStyle.secondary)
      }
    }
    .padding(.horizontal, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(scopeTitle(statistics.scope)), \(statistics.cohort.title), \(statistics.includedCount) included"
    )
    .accessibilityValue(
      statistics.excludedCount == 0
        ? "No exclusions"
        : "\(statistics.excludedCount) excluded"
    )
  }

  private func metricsAndChart(for statistics: GradeStatisticsSnapshot) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 16) {
        metrics(for: statistics)
          .frame(minWidth: 290, maxWidth: 360, alignment: .topLeading)
        chartCard(for: statistics)
          .frame(minWidth: 420, maxWidth: .infinity, alignment: .topLeading)
      }
      VStack(alignment: .leading, spacing: 14) {
        metrics(for: statistics)
        chartCard(for: statistics)
      }
    }
  }

  private func metrics(for statistics: GradeStatisticsSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Summary")
        .font(.headline)
      LazyVGrid(
        columns: [
          GridItem(.flexible(minimum: 110), spacing: 8),
          GridItem(.flexible(minimum: 110), spacing: 8),
        ],
        alignment: .leading,
        spacing: 8
      ) {
        LiveStatisticsMetric(title: "Mean", value: decimal(statistics.mean))
        LiveStatisticsMetric(title: "Median", value: decimal(statistics.median))
        LiveStatisticsMetric(title: "Modes", value: modes(statistics.modes))
        LiveStatisticsMetric(title: "Range", value: point(statistics.range))
        LiveStatisticsMetric(
          title: "Population SD", value: decimal(statistics.populationStandardDeviation)
        )
        LiveStatisticsMetric(
          title: "Minimum / maximum",
          value: "\(point(statistics.scores.first)) / \(point(statistics.scores.last))"
        )
      }
      exclusionList(for: statistics)
    }
    .workspaceCard()
  }

  private func exclusionList(for statistics: GradeStatisticsSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Excluded from \(statistics.cohort.title.lowercased()) statistics")
        .font(.caption.weight(.semibold))
        .foregroundStyle(WorkspaceStyle.secondary)
      if statistics.excludedCounts.isEmpty {
        Text("None")
          .font(.caption)
          .foregroundStyle(WorkspaceStyle.secondary)
      } else {
        ForEach(GradeStatisticsExclusion.allCases, id: \.self) { exclusion in
          if let count = statistics.excludedCounts[exclusion], count > 0 {
            HStack(spacing: 6) {
              Text(exclusion.title)
              Spacer(minLength: 5)
              Text(String(count))
                .font(.caption.monospaced())
            }
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
          }
        }
      }
    }
    .padding(.top, 4)
    .accessibilityElement(children: .contain)
  }

  private func chartCard(for statistics: GradeStatisticsSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Score distribution")
            .font(.headline)
          Text("Ten equal-width bins; the final bin includes the maximum score.")
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 6)
        Text("out of \(statistics.maximum.decimalString)")
          .font(.caption.monospaced())
          .foregroundStyle(WorkspaceStyle.secondary)
      }
      Chart(statistics.bins) { bin in
        BarMark(
          x: .value("Score range", bin.label),
          y: .value("Count", bin.count)
        )
        .foregroundStyle(WorkspaceStyle.accent)
        .accessibilityLabel(bin.label)
        .accessibilityValue("\(bin.count) \(bin.count == 1 ? "score" : "scores")")
      }
      .chartXAxis {
        AxisMarks { _ in
          AxisGridLine()
          AxisTick()
          AxisValueLabel(orientation: .vertical)
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading) { _ in
          AxisGridLine()
          AxisTick()
          AxisValueLabel()
        }
      }
      .chartXAxisLabel("Score range")
      .chartYAxisLabel("Count")
      .chartYScale(domain: 0...max(1, statistics.bins.map(\.count).max() ?? 1))
      .frame(minHeight: 205)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Score distribution chart for \(scopeTitle(statistics.scope))")
      .accessibilityHint("Each bar reports the number of scores in its range.")

      DisclosureGroup("Accessible data table", isExpanded: $showsDataTable) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(statistics.bins) { bin in
            HStack(spacing: 8) {
              Text(bin.label)
                .frame(maxWidth: .infinity, alignment: .leading)
              Text("\(bin.count) \(bin.count == 1 ? "score" : "scores")")
                .font(.caption.monospaced())
            }
            .font(.caption)
            .padding(.vertical, 5)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(bin.label) score range")
            .accessibilityValue("\(bin.count) \(bin.count == 1 ? "score" : "scores")")
            if bin.id < statistics.bins.count - 1 {
              Divider()
            }
          }
        }
        .padding(.top, 5)
      }
      .font(.caption.weight(.medium))
      .accessibilityLabel("Accessible score distribution table")
    }
    .workspaceCard()
  }

  private func emptyState(for statistics: GradeStatisticsSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        statistics.cohort == .approved
          ? "No approved grades yet" : "No complete draft or reviewed grades",
        systemImage: "chart.bar.xaxis"
      )
      .font(.headline)
      Text(
        statistics.cohort == .approved
          ? "Approve a complete grade before it enters official statistics. Missing or unreadable work is excluded rather than scored zero."
          : "This cohort includes only submissions with a complete, confirmed score set. Choose another cohort or scope when available."
      )
      .font(.caption)
      .foregroundStyle(WorkspaceStyle.secondary)
      .fixedSize(horizontal: false, vertical: true)
      exclusionList(for: statistics)
    }
    .workspaceCard()
    .accessibilityElement(children: .contain)
  }

  private var unavailableState: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Statistics unavailable", systemImage: "exclamationmark.triangle")
        .font(.headline)
      Text(
        "The selected scope cannot produce a summary until the rubric is valid and its parts still exist."
      )
      .font(.caption)
      .foregroundStyle(WorkspaceStyle.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .workspaceCard()
  }

  private func ensureScopeIsAvailable() {
    guard selectedScopeID != "overall" else { return }
    guard let id = UUID(uuidString: selectedScopeID),
      assignment.parts.contains(where: { $0.id == id })
    else {
      selectedScopeID = "overall"
      return
    }
  }

  private func scopeTitle(_ scope: GradeStatisticsScope) -> String {
    switch scope {
    case .overall:
      return "Whole assignment"
    case .part(let id):
      return assignment.parts.first(where: { $0.id == id })?.title ?? "Assignment part"
    }
  }

  private func point(_ value: PointValue?) -> String {
    value?.decimalString ?? "—"
  }

  private func decimal(_ value: Double?) -> String {
    guard let value else { return "—" }
    return value.formatted(.number.precision(.fractionLength(0...2)))
  }

  private func modes(_ values: [PointValue]) -> String {
    values.isEmpty ? "No mode" : values.map(\.decimalString).joined(separator: ", ")
  }
}

private struct LiveStatisticsMetric: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption.weight(.medium))
        .foregroundStyle(WorkspaceStyle.secondary)
      Text(value)
        .font(.headline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(WorkspaceStyle.border, lineWidth: 1))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue(value)
  }
}

private struct LiveStatisticsBadge: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(WorkspaceStyle.secondary)
      .padding(.horizontal, 7)
      .padding(.vertical, 4)
      .background(WorkspaceStyle.inset, in: Capsule())
  }
}
