import SwiftUI
import Charts
import StudioKit

/// One measured quantity over the run, with the playhead on it.
///
/// THE PLAYHEAD IS THE POINT. A chart beside a 3D view that do not agree about
/// where you are is two things to look at; a chart with the playhead drawn on
/// it is one thing, and scrubbing the transport moves both. That is what turns
/// "peak tilt 84°" into "it went over HERE, which is where the foot left the
/// step".
struct RunChart: View {
    let track: RunSeries.Track
    let playhead: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(track.name).font(.subheadline)
                Spacer()
                Text(current).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Chart {
                if let reference = track.reference {
                    RuleMark(y: .value(reference.label, reference.value))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text(reference.label).font(.caption2).foregroundStyle(.secondary)
                        }
                }
                ForEach(track.points) { point in
                    LineMark(x: .value("t", point.time), y: .value(track.name, point.value))
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.linear)
                }
                RuleMark(x: .value("now", playhead))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.orange)
            }
            .chartYScale(domain: track.range)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let t = value.as(Double.self) {
                            Text(String(format: "%.1fs", t)).font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.0f", v)).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 96)
            Text(track.detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The value under the playhead, so the number and the line always agree.
    private var current: String {
        guard let point = track.points.min(by: {
            abs($0.time - playhead) < abs($1.time - playhead)
        }) else { return "—" }
        return String(format: "%.1f %@", point.value, track.unit)
    }
}
