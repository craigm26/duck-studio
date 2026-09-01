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
///
/// TWO COLOURS AND NOTHING ELSE. The curve is `Theme.measured` because every
/// point on it was recorded off a bench, and the playhead is the app's orange
/// because it is the one mark in the picture the PERSON moves. A chart that
/// drew both in the same accent would be saying that where you are looking and
/// what the robot did are the same kind of claim. Everything else — grid,
/// reference line, axis numbers — is furniture in `separator` and
/// `textTertiary`, because a chart with three emphasised things has none.
///
/// `actionSecondary` AND NOT `actionPrimary`, WHICH IS A CONTRAST DECISION.
/// Duck Orange is 2.30:1 on Warm Cream — below even the 3:1 SC 1.4.11 asks of a
/// shape's edge — so a two-point rule in it is a playhead that is not there in
/// light mode. `actionSecondary` is the same hue at ink weight in light and
/// full Duck Orange in dark, which is exactly what the token exists for. It is
/// still orange, which matters beyond taste: `IntentListView` prints "The
/// orange line is the playhead" above these charts, and a picture that
/// contradicts the sentence beside it is worse than either alone.
///
/// NO FILL UNDER THE LINE, AND NO GRADIENT ANYWHERE. An area fill under a
/// trunk-height curve reads as a quantity accumulated, which is not what a
/// height is; a gradient under it reads as a quantity accumulated and fading,
/// which is not what anything is. The line is the reading.
///
/// THE LAST SAMPLE IS DRAWN AS A POINT. Where the recording ends is a fact the
/// line alone cannot state — a curve that stops mid-chart and a curve that runs
/// to the edge look identical when the axis is padded, and `Track.range` pads
/// it. One dot says "this is the last thing that was measured".
struct RunChart: View {
    let track: RunSeries.Track
    let playhead: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            // THE HEADER IS A TELEMETRY ROW BECAUSE IT IS ONE. A track's name
            // never changes and the value under the playhead changes on every
            // frame of a scrub, which is exactly the pair the component was
            // built for — and it is what stops the reading from being clipped
            // at an accessibility text size, where the old two-column HStack
            // gave the width to the name and truncated the number.
            TelemetryRow(label: track.name, value: reading, unit: track.unit)
            chart
            Text(track.detail)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                // A track's detail is two or three sentences. Without this it
                // is one line with a tail cut off it.
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chart: some View {
        Chart {
            if let reference = track.reference {
                // THE THRESHOLD, DASHED AND QUIET. It is not a measurement —
                // it is the height a standing robot sits at, or the tilt an
                // episode terminates past — so it is drawn in the furniture
                // grey rather than in the measured teal, and dashed, which is
                // how every chart convention says "this line was not sampled".
                RuleMark(y: .value(reference.label, reference.value))
                    .lineStyle(StrokeStyle(lineWidth: ChartMetric.hairlineStroke,
                                           dash: ChartMetric.referenceDash))
                    .foregroundStyle(Theme.textTertiary)
                    .annotation(position: .top, alignment: .leading) {
                        Text(reference.label)
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
            }
            ForEach(track.points) { point in
                LineMark(x: .value("t", point.time),
                         y: .value(track.name, point.value))
                    .foregroundStyle(Theme.measured)
                    // LINEAR, NOT CATMULL-ROM. A smoothed curve invents values
                    // between the ticks that were recorded, and the whole
                    // reason to look at this chart is to find the tick where
                    // something changed.
                    .interpolationMethod(.linear)
            }
            if let last = track.points.last {
                PointMark(x: .value("t", last.time),
                          y: .value(track.name, last.value))
                    .foregroundStyle(Theme.measured)
                    .symbolSize(ChartMetric.endpointArea)
            }
            RuleMark(x: .value("now", playhead))
                .lineStyle(StrokeStyle(lineWidth: ChartMetric.playheadStroke))
                .foregroundStyle(Theme.actionSecondary)
        }
        .chartYScale(domain: track.range)
        // ONE MARK TYPE PER COLOUR, SO THERE IS NOTHING FOR A LEGEND TO SAY.
        // Charts offers one the moment a second mark type appears, and a key
        // reading "Trunk height" beside the curve labelled "Trunk height" is a
        // second copy of the row above.
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: ChartMetric.timeMarks)) { value in
                grid
                AxisValueLabel {
                    if let t = value.as(Double.self) {
                        // Tabular figures because these numbers move: the axis
                        // is redrawn whenever a different track is shown, and
                        // proportional digits make the labels jog sideways.
                        Text(String(format: "%.1fs", t))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: ChartMetric.valueMarks)) { value in
                grid
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.0f", v))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .frame(height: ChartMetric.height)
        // THE PICTURE IS ONE ELEMENT AND IT SAYS THE ONE THING THE ROW ABOVE
        // DOES NOT. The reading under the playhead is already announced by the
        // `TelemetryRow`, and what the curve means is already announced by
        // `track.detail` — so all that is left in here is the threshold's own
        // word, which is drawn inside the plot and would otherwise be visible
        // only to somebody looking at it. The word is the kit's; this places it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(track.name))
        .accessibilityValue(Text(track.reference?.label ?? ""))
    }

    /// The faint grid. Drawn in `separator`, which `Palette` calls decoration
    /// in SC 1.4.11's exact sense: remove every gridline and the curve, the
    /// axis numbers and the reference line all still say what they said.
    private var grid: some AxisMark {
        AxisGridLine(stroke: StrokeStyle(lineWidth: ChartMetric.hairlineStroke))
            .foregroundStyle(Theme.separator)
    }

    /// The value under the playhead, so the number and the line always agree.
    ///
    /// AN EM DASH AND NOT A ZERO when there is nothing to read. A track with no
    /// points is a recording that carried none, and printing 0.0 for it would
    /// be this screen inventing a measurement.
    private var reading: String {
        guard let point = track.points.min(by: {
            abs($0.time - playhead) < abs($1.time - playhead)
        }) else { return "—" }
        return String(format: "%.1f", point.value)
    }
}

// MARK: - the numbers this chart writes down for itself

/// Dimensions that are decisions about how big to draw a picture, gathered so
/// the next person can see which ones are load-bearing. Nothing here is a
/// colour, a contrast or a quantity — those are facts and live in `Palette` and
/// `RunSeries`, where a test can run over them.
private enum ChartMetric {
    /// A hairline STROKE. One point, which on every device this ships to is one
    /// to three pixels. Named for the stroke rather than the scale because
    /// `Palette.Spacing` already has a `hairline` and it is four points.
    static let hairlineStroke: CGFloat = 1

    /// The playhead is drawn twice as heavy as the grid it crosses, because it
    /// is the one line in the plot a person is moving.
    static let playheadStroke: CGFloat = 2

    /// Three on, three off. Short enough to read as a rule rather than as a
    /// row of ticks at the widths a phone gives a chart.
    static let referenceDash: [CGFloat] = [3, 3]

    /// The last sample's dot, as an AREA — which is what `symbolSize` takes.
    /// Thirty-six square points is a six-point dot: bigger than the line is
    /// thick, smaller than the axis type.
    static let endpointArea: CGFloat = 36

    /// How tall a track is allowed to be. Small enough that several stack in a
    /// list without scrolling becoming the way you compare them, tall enough
    /// that a 45° threshold and a curve at 40° are two lines.
    static let height: CGFloat = 96

    /// Four times and three values. More labels on a chart this wide is a
    /// number every twenty points, which stops being an axis and becomes a rule.
    static let timeMarks = 4
    static let valueMarks = 3
}
