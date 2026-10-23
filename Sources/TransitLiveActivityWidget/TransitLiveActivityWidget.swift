import ActivityKit
import SwiftUI
import WidgetKit
import TransitLiveActivityShared

@main
struct TransitLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        TransitLiveActivityWidget()
    }
}

struct TransitLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TransitActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.06))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    lineBadge(context.attributes.line)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    arrivalView(context.state, compact: false, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Vehicul \(context.attributes.vehicleNumber)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        nextStopView(context.state, isStale: context.isStale)
                        stopTimeline(context.state)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "bus.fill")
                    Text(context.attributes.line)
                        .lineLimit(1)
                }
                .font(.caption2.bold())
            } compactTrailing: {
                arrivalView(context.state, compact: true, isStale: context.isStale)
            } minimal: {
                Image(systemName: "bus.fill")
            }
            .keylineTint(.blue)
        }
    }

    private func lockScreenView(context: ActivityViewContext<TransitActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                lineBadge(context.attributes.line)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vehicul \(context.attributes.vehicleNumber)")
                        .font(.headline)
                    Text("Urmărire în timp real")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            nextStopView(context.state, isStale: context.isStale)
            stopTimeline(context.state)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineBadge(_ line: String) -> some View {
        Text(line)
            .font(.headline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.blue, in: RoundedRectangle(cornerRadius: 12))
    }

    private func nextStopView(
        _ state: TransitActivityAttributes.ContentState,
        isStale: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isStale ? "DATE NEACTUALIZATE" : state.stops.isEmpty ? "URMĂRIRE ACTIVĂ" : "URMĂTOAREA STAȚIE")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(isStale ? "Deschide aplicația pentru date noi" : nextStopName(state))
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            Spacer()
            if !isStale, let arrival = state.arrivalEstimate, arrival > .now {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("ESTIMAT")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(timerInterval: .now...arrival, countsDown: true)
                        .font(.subheadline.monospacedDigit().bold())
                        .multilineTextAlignment(.trailing)
                }
            } else if !isStale, state.arrivalEstimate != nil {
                Text("00:00")
                    .font(.subheadline.monospacedDigit().bold())
            } else {
                Text(isStale ? "—" : state.stops.isEmpty ? "Se încarcă traseul" : "Timp indisponibil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stopTimeline(_ state: TransitActivityAttributes.ContentState) -> some View {
        HStack(spacing: 2) {
            ForEach(state.stops.indices, id: \.self) { index in
                Circle()
                    .fill(isPassed(index, state: state) ? Color.blue : Color.secondary.opacity(0.35))
                    .frame(width: 5, height: 5)
                if index < state.stops.count - 1 {
                    Rectangle()
                        .fill(index < (state.nextStopIndex ?? -1) ? Color.blue : Color.secondary.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .frame(height: 2)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func nextStopName(_ state: TransitActivityAttributes.ContentState) -> String {
        guard let index = state.nextStopIndex, state.stops.indices.contains(index) else {
            return state.stops.isEmpty ? "Vehicul urmărit" : "Stație indisponibilă"
        }
        return state.stops[index].name
    }

    @ViewBuilder
    private func arrivalView(
        _ state: TransitActivityAttributes.ContentState,
        compact: Bool,
        isStale: Bool
    ) -> some View {
        if isStale {
            if compact {
                Image(systemName: "arrow.clockwise")
            } else {
                Text("Date vechi")
                    .font(.caption)
            }
        } else if let arrival = state.arrivalEstimate, arrival > .now {
            Text(timerInterval: .now...arrival, countsDown: true)
                .font(compact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
                .frame(maxWidth: compact ? 42 : 76)
        } else if state.arrivalEstimate != nil {
            Text("00:00")
                .font(compact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
                .frame(maxWidth: compact ? 42 : 76)
        } else if compact {
            Image(systemName: "bus.fill")
        } else {
            Text(progressText(state))
                .font(.caption.monospacedDigit())
        }
    }

    private func progressText(_ state: TransitActivityAttributes.ContentState) -> String {
        guard let index = state.nextStopIndex else { return "— / \(state.stops.count)" }
        return "\(index + 1) / \(state.stops.count)"
    }

    private func isPassed(_ index: Int, state: TransitActivityAttributes.ContentState) -> Bool {
        guard let nextStopIndex = state.nextStopIndex else { return false }
        return index < nextStopIndex
    }
}
