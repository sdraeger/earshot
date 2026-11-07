import AppKit
import SwiftUI

/// Surfaces aggregate counts from `recognition_log.jsonl` so the user can
/// verify whether `SpeakerMatcher` quality drifts over time. The JSONL file
/// remains the source of truth; this view is read-only.
struct RecognitionStatsView: View {
    @State private var aggregate: RecognitionStats.Aggregate?
    @State private var windowDays: StatsWindowChoice = .thirty

    private let log: RecognitionStatsLog

    init(log: RecognitionStatsLog) {
        self.log = log
    }

    var body: some View {
        Section("Recognition stats") {
            Picker("Window", selection: $windowDays) {
                ForEach(StatsWindowChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            if let aggregate {
                if aggregate.total > 0 {
                    statsBody(aggregate)
                } else {
                    Text("No data yet — confirm a meeting to start collecting.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, alignment: .center)
            }

            HStack {
                Button("Open log folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([RecognitionStatsLog.defaultPath])
                }
                Spacer()
                Button("Reload") {
                    Task { await reload() }
                }
            }
        }
        .task(id: windowDays) { await reload() }
    }

    @ViewBuilder
    private func statsBody(_ agg: RecognitionStats.Aggregate) -> some View {
        LabeledContent("Total confirmations", value: "\(agg.total)")
        ForEach(RecognitionAction.allCases, id: \.self) { action in
            statRow(action, count: agg.counts[action] ?? 0, total: agg.total)
        }
    }

    private func statRow(_ action: RecognitionAction, count: Int, total: Int) -> some View {
        let pct = Int((Double(count) / Double(total) * 100).rounded())
        return LabeledContent(action.rawValue.capitalized) {
            HStack(spacing: 8) {
                Text("\(count)")
                pctLabel(pct)
                progressBar(count: count, total: total)
            }
        }
    }

    private func pctLabel(_ pct: Int) -> some View {
        Text("(\(pct)%)")
            .foregroundStyle(.secondary)
            .font(.callout)
    }

    private func progressBar(count: Int, total: Int) -> some View {
        ProgressView(value: Double(count), total: Double(total))
            .frame(width: 80)
    }

    private func reload() async {
        let now = Date()
        let interval = TimeInterval(windowDays.rawValue * 86400)
        let events = await log.loadRecent(within: interval, now: now)
        aggregate = RecognitionStats.aggregate(
            events: events,
            from: now.addingTimeInterval(-interval),
            to: now,
        )
    }
}
