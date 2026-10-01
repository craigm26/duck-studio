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
/// THREE CARDS AND NO QUESTION. A new install starts Simple and the Learn tab
/// is the way to everything else, so nothing needs deciding before the duck
/// can be driven.
struct FirstRunView: View {
    @ObservedObject var detail: DetailStore
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0

    private var cards: Int { FirstRun.steps.count }

    var body: some View {
        NavigationStack {
            pages
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // SKIPPING IS ALLOWED. Somebody who wants to look around
                    // first should not have to read five cards to be let in.
                    Button("Skip") { finish(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if page == cards - 1 {
                        Button("Start") { finish(nil) }.fontWeight(.semibold)
                    } else {
                        Button("Next") { withAnimation { page += 1 } }
                    }
                }
            }
        }
        .interactiveDismissDisabled(false)
    }

    /// SWIPED ON A PHONE, STEPPED ON A MAC. macOS has no paging `TabView`; the
    /// Next button in the toolbar already moves through the cards, so a Mac
    /// shows the current one and lets that button do the work.
    @ViewBuilder private var pages: some View {
#if os(iOS)
        TabView(selection: $page) {
            ForEach(Array(FirstRun.steps.enumerated()), id: \.element.id) { index, step in
                stepCard(step).tag(index)
            }
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
#else
        stepCard(FirstRun.steps[page])
            .id(page)
            .transition(.opacity)
            .frame(minWidth: 420, minHeight: 360)
#endif
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
            // POLLEN'S OWN PAGES UNDER THE CARD THAT SAYS THIS IS NOT THEIR APP,
            // for the person who opened it looking for them.
            if step.id == "not-official" {
                ProvenanceLinks()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finish(_ level: DetailLevel?) {
        detail.finishFirstRun(choosing: level)
        dismiss()
    }
}

/// Pollen Robotics' pages for the robot and the company, as tappable rows.
///
/// ONE VIEW, THREE PLACES — the first-run card, Settings → About and the foot
/// of Behaviours — so the addresses are the kit's (`Provenance.links`, pinned
/// by `swift test`) and no screen can quietly point somewhere else.
struct ProvenanceLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Provenance.links) { link in
                Link(destination: link.url) {
                    Label(link.title, systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }
}
