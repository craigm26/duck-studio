import SwiftUI
import StudioKit

/// The Learn tab: the path from driving the duck to changing how it moves.
///
/// THE LESSONS ARE THE KIT'S (`Learn.lessons`, pinned by `swift test`); this
/// screen only draws them and sends each button somewhere real. A lesson is
/// marked done when its button is pressed, or by hand for the one that is only
/// reading, and the marks live on this phone.
struct LearnView: View {
    @ObservedObject var detail: DetailStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var progress = LearnProgress()

    var body: some View {
        List {
            Section {
                ForEach(Array(Learn.lessons.enumerated()), id: \.element.id) { index, lesson in
                    row(lesson, number: index + 1)
                }
            } header: {
                SectionHeading(text: Learn.intro)
            } footer: {
                Text(Learn.progress(done: progress.done.count))
                    .foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(Learn.title)
        .navigationBarTitleDisplayMode(.large)
    }

    private func row(_ lesson: Learn.Lesson, number: Int) -> some View {
        let done = progress.done.contains(lesson.id)
        return VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
                Image(systemName: done ? "checkmark.circle.fill" : lesson.symbol)
                    .foregroundStyle(done ? Theme.measured : Theme.actionSecondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text("\(number). \(lesson.title)")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(lesson.body)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let button = lesson.button, let go = lesson.go {
                Button(button) {
                    progress.mark(lesson.id)
                    open(go)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, Theme.spacing(.hairline))
            } else if !done {
                Button("Got it") { progress.mark(lesson.id) }
                    .buttonStyle(.bordered)
                    .padding(.top, Theme.spacing(.hairline))
            }
        }
        .padding(.vertical, Theme.spacing(.tight))
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(done ? "Done" : ""))
    }

    private func open(_ go: Learn.Go) {
        switch go {
        case .play: router.go(to: .control)
        case .behaviours: router.go(to: .behaviours)
        case .preference: router.go(to: .studio, then: .preference)
        case .motions: router.go(to: .studio, then: .motions)
        case .challenges: router.go(to: .studio, then: .challenges)
        case .tune: router.go(to: .studio, then: .tune)
        case .everything:
            detail.level = .full
            router.go(to: .studio)
        }
    }
}

/// Which lessons somebody has done, on this phone only.
@MainActor final class LearnProgress: ObservableObject {
    @Published private(set) var done: Set<String>
    private static let key = "duckstudio.learnDone"

    init() {
        done = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    func mark(_ id: String) {
        guard !done.contains(id) else { return }
        done.insert(id)
        UserDefaults.standard.set(Array(done), forKey: Self.key)
    }
}
