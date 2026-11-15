import SwiftUI
import StudioKit

/// A `StageLine` on the picture: one line, at most `StageLine.collapsedMaxHeight` points, and the
/// whole sentence on a tap, scrolled inside a quarter of the stage so it never reaches the pad.
///
/// EVERY LINE PLAY FLOATS OVER THE PICTURE GOES THROUGH HERE. Build 96 drew a run's report in full
/// twice, once across the top half and once as a card over the sticks; see `StageLine`.
struct StageLineView: View {
    let line: StageLine
    /// The stage's height, for the expanded cap.
    let stageHeight: CGFloat
    var font: Font = .system(.footnote, design: .rounded)
    var colour: Color = Theme.textPrimary

    @State private var expanded = false

    var body: some View {
        Button {
            guard line.hasMore else { return }
            expanded.toggle()
        } label: {
            Group {
                if expanded {
                    ScrollView(.vertical) {
                        Text(line.full)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: CGFloat(StageLine.expandedMaxHeight(stage: Double(stageHeight))))
                } else {
                    HStack(spacing: Theme.spacing(.hairline)) {
                        Text(line.short).lineLimit(1).truncationMode(.tail)
                        if line.hasMore {
                            Image(systemName: "chevron.down").imageScale(.small)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxHeight: CGFloat(StageLine.collapsedMaxHeight))
                }
            }
            .font(font)
            .foregroundStyle(colour)
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        // A NEW LINE STARTS FOLDED, whatever the last one was left as.
        .onChange(of: line) { _, _ in expanded = false }
        .accessibilityLabel(Text(line.full))
        .accessibilityHint(Text(line.hasMore ? (expanded ? StageLine.collapseHint : StageLine.expandHint) : ""))
    }
}
