import SwiftUI
import StudioKit

/// Kid-friendly Worlds picker on Play: 6 colorful sky/floor palettes (`StageTheme`) and
/// 6 interactive physics playgrounds (`PlayWorld.Playground`), plus access to all saved scenes.
struct PlayWorldsSheet: View {
    @Binding var selectedBackdrop: PlayWorld.Backdrop
    let activeWorldName: String?
    let busy: Bool
    let choosePlayground: (PlayWorld.Playground) -> Void
    let openAllScenes: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let backdropColumns = [GridItem(.adaptive(minimum: 96), spacing: Theme.spacing(.tight))]
    private let playgroundColumns = [GridItem(.adaptive(minimum: 148), spacing: Theme.spacing(.tight))]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing(.standard)) {
                    VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                        SectionHeading(text: PlayWorld.Words.backdrops)
                        LazyVGrid(columns: backdropColumns, spacing: Theme.spacing(.tight)) {
                            ForEach(PlayWorld.Backdrop.allCases) { backdrop in
                                backdropTile(backdrop)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                        SectionHeading(text: PlayWorld.Words.playgrounds)
                        LazyVGrid(columns: playgroundColumns, spacing: Theme.spacing(.tight)) {
                            ForEach(PlayWorld.Playground.allCases) { playground in
                                playgroundTile(playground)
                            }
                        }
                    }

                    Button {
                        dismiss()
                        openAllScenes()
                    } label: {
                        HStack(spacing: Theme.spacing(.tight)) {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundStyle(Theme.actionInk)
                            Text(PlayWorld.Words.moreScenes)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, Theme.spacing(.standard))
                        .frame(minHeight: DesignMetric.minimumTarget)
                        .pondPanel(.control)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Theme.spacing(.standard))
            }
            .background(Theme.backgroundSecondary)
            .navigationTitle(PlayWorld.Words.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ControllerWords.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func backdropTile(_ backdrop: PlayWorld.Backdrop) -> some View {
        let theme = backdrop.stageTheme
        let selected = selectedBackdrop == backdrop
        let shape = RoundedRectangle(cornerRadius: Theme.radius(.control), style: .continuous)
        return Button {
            selectedBackdrop = backdrop
        } label: {
            VStack(spacing: Theme.spacing(.hairline)) {
                ZStack {
                    VStack(spacing: 0) {
                        Color(uiColor: theme.sky)
                        Color(uiColor: theme.floor)
                    }
                    Image(systemName: backdrop.symbol)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(uiColor: theme.accent))
                        .shadow(color: PondShadow.colour, radius: 4, y: 1)
                }
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius(.control) - 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius(.control) - 4, style: .continuous)
                        .strokeBorder(Theme.outline.opacity(0.3), lineWidth: 1)
                )

                Text(backdrop.title)
                    .font(.system(.footnote, design: .rounded).weight(selected ? .bold : .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(Theme.spacing(.tight))
            .frame(maxWidth: .infinity, minHeight: DesignMetric.movingTarget)
            .background(selected ? Theme.actionYellow.opacity(0.35) : Theme.surfacePrimary, in: shape)
            .overlay(shape.strokeBorder(selected ? Theme.outline : Theme.outline.opacity(0.25),
                                        lineWidth: selected ? DesignMetric.outlineStroke : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func playgroundTile(_ playground: PlayWorld.Playground) -> some View {
        let active = activeWorldName == playground.title
        let shape = RoundedRectangle(cornerRadius: Theme.radius(.control), style: .continuous)
        return Button {
            choosePlayground(playground)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                HStack(spacing: Theme.spacing(.tight)) {
                    Image(systemName: playground.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.actionInk)
                        .frame(width: 28, height: 28)
                    Text(playground.title)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                    }
                }
                Text(playground.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.spacing(.snug))
            .frame(maxWidth: .infinity, minHeight: DesignMetric.movingTarget, alignment: .leading)
            .background(active ? Theme.actionTeal.opacity(0.22) : Theme.surfacePrimary, in: shape)
            .overlay(shape.strokeBorder(active ? Theme.outline : Theme.outline.opacity(0.25),
                                        lineWidth: active ? DesignMetric.outlineStroke : 1))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

extension PlayWorld.Backdrop {
    /// Maps each StudioKit backdrop choice to DuckStudio's existing `StageTheme` palette.
    var stageTheme: StageTheme {
        switch self {
        case .pond: return .pond
        case .meadow: return .meadow
        case .snow: return .alpine
        case .arcade: return .arcade
        case .dusk: return .dusk
        case .park: return .park
        }
    }
}
