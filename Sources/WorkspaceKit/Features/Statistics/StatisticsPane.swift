import SwiftUI

struct StatisticsPane: View {
  let assignment: AssignmentPreview
  @Binding var selectedScopeID: String

  private var scopeOptions: [StatisticsScopeOption] {
    var options = [
      StatisticsScopeOption(
        id: "overall",
        title: assignment.statistics.first(where: { $0.id == "overall" })?.title
          ?? "Whole assignment"
      )
    ]

    options.append(
      contentsOf: assignment.parts.map { part in
        StatisticsScopeOption(
          id: part.id,
          title: assignment.statistics.first(where: { $0.id == part.id })?.title ?? part.title
        )
      })
    return options
  }

  private var selectedStatistics: StatisticsPreview? {
    assignment.statistics.first { $0.id == selectedScopeID }
  }

  var body: some View {
    VStack(spacing: 0) {
      scopeHeader
      Divider()
      content
    }
    .background(WorkspaceStyle.background)
    .foregroundStyle(WorkspaceStyle.ink)
  }

  private var scopeHeader: some View {
    HStack(spacing: 9) {
      Image(systemName: "chart.bar.xaxis")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(WorkspaceStyle.accent)
      Text("Scope")
        .font(.system(size: 11, weight: .semibold))

      Picker("Statistics scope", selection: $selectedScopeID) {
        ForEach(scopeOptions) { option in
          Text(option.title).tag(option.id)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .frame(minWidth: 190, alignment: .leading)
      .accessibilityLabel("Statistics scope")
      .help("Choose the whole assignment or an assignment part")

      Spacer(minLength: 12)
      PreviewBadge(text: "Sample")
      Text(sampleSizeLabel)
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(WorkspaceStyle.secondary)
        .accessibilityLabel(sampleSizeAccessibilityLabel)
    }
    .padding(.horizontal, 20)
    .frame(height: 38)
    .background(WorkspaceStyle.surface)
  }

  private var sampleSizeLabel: String {
    guard let selectedStatistics else { return "n = —" }
    return "n = \(selectedStatistics.scores.count)"
  }

  private var sampleSizeAccessibilityLabel: String {
    guard let selectedStatistics else { return "No sample size available" }
    let count = selectedStatistics.scores.count
    return "Sample size, \(count) \(count == 1 ? "score" : "scores")"
  }

  @ViewBuilder
  private var content: some View {
    if let selectedStatistics {
      if selectedStatistics.scores.isEmpty {
        emptyScoresState(for: selectedStatistics)
      } else {
        HStack(alignment: .top, spacing: 18) {
          metrics(for: selectedStatistics)
          Divider()
          HistogramView(statistics: selectedStatistics)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    } else {
      missingScopeState
    }
  }

  private func metrics(for statistics: StatisticsPreview) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(statistics.title)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Spacer(minLength: 0)
        Text("max \(statistics.maximumScore)")
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(WorkspaceStyle.secondary)
      }

      Text("Precomputed summary for the sample scores")
        .font(.system(size: 10))
        .foregroundStyle(WorkspaceStyle.secondary)
        .lineLimit(1)

      LazyVGrid(
        columns: [
          GridItem(.flexible(minimum: 132), spacing: 8),
          GridItem(.flexible(minimum: 132), spacing: 8),
        ],
        alignment: .leading,
        spacing: 6
      ) {
        StatisticsMetricCell(title: "Mean", value: decimalString(statistics.mean))
        StatisticsMetricCell(title: "Median", value: decimalString(statistics.median))
        StatisticsMetricCell(title: "Modes", value: modesString(statistics.modes))
        StatisticsMetricCell(title: "Range", value: String(statistics.range))
        StatisticsMetricCell(
          title: "Population standard deviation",
          value: decimalString(statistics.populationStandardDeviation)
        )
        StatisticsMetricCell(
          title: "Minimum / maximum",
          value: "\(statistics.minimum) / \(statistics.maximum)"
        )
      }
    }
    .frame(minWidth: 338, maxWidth: 380, alignment: .topLeading)
  }

  private var missingScopeState: some View {
    StatisticsEmptyState(
      title: "Statistics unavailable",
      message:
        "This scope has no precomputed summary. Choose another assignment scope to continue.",
      systemImage: "chart.bar.xaxis"
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 20)
  }

  private func emptyScoresState(for statistics: StatisticsPreview) -> some View {
    StatisticsEmptyState(
      title: "No sample scores",
      message:
        "\(statistics.title) has no precomputed scores yet. Choose another scope to view its distribution.",
      systemImage: "chart.bar.xaxis"
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 20)
  }

  private func modesString(_ modes: [Int]) -> String {
    modes.isEmpty ? "None" : modes.map(String.init).joined(separator: ", ")
  }

  private func decimalString(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
  }
}

private struct StatisticsScopeOption: Identifiable {
  let id: String
  let title: String
}

private struct StatisticsMetricCell: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(WorkspaceStyle.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(value)
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(WorkspaceStyle.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    .padding(.horizontal, 9)
    .padding(.vertical, 4)
    .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(WorkspaceStyle.border, lineWidth: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(value)
  }
}

private struct HistogramView: View {
  let statistics: StatisticsPreview

  private var maximumCount: Int {
    statistics.bins.map(\.count).max() ?? 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          Text("Score distribution")
            .font(.system(size: 12, weight: .semibold))
          Text("Supplied histogram bins")
            .font(.system(size: 10))
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        Spacer(minLength: 0)
        Text("out of \(statistics.maximumScore)")
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(WorkspaceStyle.secondary)
      }

      if statistics.bins.isEmpty {
        VStack(spacing: 5) {
          Image(systemName: "chart.bar.xaxis")
            .font(.system(size: 18))
            .foregroundStyle(WorkspaceStyle.secondary)
          Text("Histogram unavailable")
            .font(.system(size: 11, weight: .semibold))
          Text("No precomputed bins were supplied for this scope.")
            .font(.system(size: 10))
            .foregroundStyle(WorkspaceStyle.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112)
        .accessibilityElement(children: .combine)
      } else {
        HStack(alignment: .bottom, spacing: 5) {
          Text("Count")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(WorkspaceStyle.secondary)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: 18, height: 84)
            .accessibilityLabel("Vertical axis, count")

          VStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 7) {
              ForEach(statistics.bins) { bin in
                HistogramBar(bin: bin, maximumCount: maximumCount)
                  .frame(maxWidth: .infinity)
              }
            }
            .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .bottom)
            .padding(.horizontal, 2)
            .overlay(alignment: .bottom) {
              Rectangle()
                .fill(WorkspaceStyle.border)
                .frame(height: 1)
                .padding(.horizontal, 1)
            }

            HStack(alignment: .top, spacing: 7) {
              ForEach(statistics.bins) { bin in
                Text(bin.label)
                  .font(.system(size: 9, weight: .medium, design: .monospaced))
                  .foregroundStyle(WorkspaceStyle.secondary)
                  .lineLimit(1)
                  .minimumScaleFactor(0.65)
                  .frame(maxWidth: .infinity)
              }
            }
            .accessibilityHidden(true)

            Text("Score range")
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(WorkspaceStyle.secondary)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Score distribution histogram")
        .accessibilityHint("Horizontal axis is score range. Vertical axis is count.")
      }
    }
    .frame(minWidth: 410, maxWidth: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .contain)
  }
}

private struct HistogramBar: View {
  let bin: HistogramBin
  let maximumCount: Int

  private var barHeight: CGFloat {
    guard maximumCount > 0, bin.count > 0 else { return 2 }
    return max(4, 62 * CGFloat(bin.count) / CGFloat(maximumCount))
  }

  private var countDescription: String {
    "\(bin.count) sample \(bin.count == 1 ? "score" : "scores")"
  }

  var body: some View {
    VStack(spacing: 3) {
      Text(String(bin.count))
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(WorkspaceStyle.ink)
        .frame(height: 14)
      Spacer(minLength: 0)
      RoundedRectangle(cornerRadius: 3)
        .fill(bin.count == 0 ? WorkspaceStyle.inset : WorkspaceStyle.accent)
        .frame(height: barHeight)
        .overlay {
          if bin.count == 0 {
            RoundedRectangle(cornerRadius: 3)
              .stroke(WorkspaceStyle.border, lineWidth: 1)
          }
        }
    }
    .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .bottom)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(bin.label) score range")
    .accessibilityValue(countDescription)
    .help("\(bin.label) score range: \(countDescription)")
  }
}

private struct StatisticsEmptyState: View {
  let title: String
  let message: String
  let systemImage: String

  var body: some View {
    VStack(spacing: 7) {
      Image(systemName: systemImage)
        .font(.system(size: 20))
        .foregroundStyle(WorkspaceStyle.secondary)
      Text(title)
        .font(.system(size: 12, weight: .semibold))
      Text(message)
        .font(.system(size: 10))
        .foregroundStyle(WorkspaceStyle.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
    }
    .accessibilityElement(children: .combine)
  }
}
