import SwiftUI
import StudioKit

/// What somebody sees the first time they open Microduck Studio.
///
/// IT OPENS BY ADMITTING THERE IS NO ROBOT. Pollen's first deliveries are
/// around Christmas 2026, so an app that starts with "pair your Microduck"
/// fails for every person who has it today. The first card says so and then
/// says what works anyway — which is nearly everything, because every motion
/// here was recorded in physics on a bigger machine and replays without
/// hardware.
///
/// IT ENDS BY ASKING HOW MUCH TO SHOW, ONCE. The app was built for people who
/// train these networks and grew into one for people who own the robot, and
/// neither is the right default for the other. Skipping is allowed and lands on
/// Everything, which is what the app has always been.
struct FirstRunView: View {
    @ObservedObject var detail: DetailStore
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    @State private var chosen: DetailLevel?

    private var cards: Int { FirstRun.steps.count + 1 }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(Array(FirstRun.steps.enumerated()), id: \.element.id) { index, step in
                    stepCard(step).tag(index)
                }
                detailCard.tag(FirstRun.steps.count)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // SKIPPING IS ALLOWED. Somebody who wants to look around
                    // first should not have to read five cards to be let in.
                    Button("Skip") { finish(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if page == cards - 1 {
                        Button("Start") { finish(chosen) }.fontWeight(.semibold)
                    } else {
                        Button("Next") { withAnimation { page += 1 } }
                    }
                }
            }
        }
        .interactiveDismissDisabled(false)
    }

    private func stepCard(_ step: FirstRun.Step) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            if let tab = step.tab {
                Text(tab.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            Text(step.title).font(.title2.weight(.semibold))
            Text(step.body).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 0)
            Text(FirstRun.detailQuestion).font(.title2.weight(.semibold))
            Text(FirstRun.detailWhy).font(.footnote).foregroundStyle(.secondary)
            ForEach(DetailLevel.allCases) { level in
                Button {
                    chosen = level
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: chosen == level
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(level.name).font(.headline)
                            Text(level.blurb).font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Text("Settings → Detail changes it any time.")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    private func finish(_ level: DetailLevel?) {
        detail.finishFirstRun(choosing: level)
        dismiss()
    }
}
