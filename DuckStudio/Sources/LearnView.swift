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
    /// Finished lessons somebody tapped open again, for this visit only.
    @State private var expanded: Set<String> = []

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

    /// The first lesson not yet done: the only one whose button is prominent,
    /// so the path has one obvious next step.
    private var nextLessonID: String? {
        Learn.lessons.first { !progress.done.contains($0.id) }?.id
    }

    private func row(_ lesson: Learn.Lesson, number: Int) -> some View {
        let done = progress.done.contains(lesson.id)
        // A FINISHED LESSON FOLDS TO ITS TITLE. Tapping the title reopens it.
        let showsBody = !done || expanded.contains(lesson.id)
        return VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            // ONLY A FINISHED LESSON'S TITLE IS A BUTTON: an open lesson has
            // nothing to fold, and VoiceOver should not announce one.
            if done {
                Button {
                    if expanded.contains(lesson.id) {
                        expanded.remove(lesson.id)
                    } else {
                        expanded.insert(lesson.id)
                    }
                } label: {
                    heading(lesson, number: number, done: true, open: showsBody)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(showsBody ? "Folds this lesson" : "Opens this lesson again"))
            } else {
                heading(lesson, number: number, done: false, open: true)
            }
            if showsBody {
                Text(lesson.body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let how = lesson.howItWorks, detail.shows(.notes) {
                    DisclosureGroup("How it works") {
                        Text(how)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                }
                action(for: lesson, done: done)
                    .padding(.top, Theme.spacing(.hairline))
            }
        }
        .padding(.vertical, Theme.spacing(.tight))
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(done ? "Done" : ""))
    }

    private func heading(_ lesson: Learn.Lesson, number: Int, done: Bool, open: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing(.tight)) {
            Image(systemName: done ? "checkmark.circle.fill" : lesson.symbol)
                .foregroundStyle(done ? Theme.measured : Theme.actionSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text("\(number). \(lesson.title)")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if done {
                Spacer()
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func action(for lesson: Learn.Lesson, done: Bool) -> some View {
        if lesson.go == .everything, detail.level == .full {
            // Nothing new to turn on: say so instead of a button that does nothing.
            Label(Learn.everythingOn, systemImage: "checkmark")
                .font(.subheadline)
                .foregroundStyle(Theme.measured)
                .onAppear { progress.mark(lesson.id) }
        } else if let button = lesson.button, let go = lesson.go {
            let press = {
                progress.mark(lesson.id)
                open(go)
            }
            if lesson.id == nextLessonID {
                Button(button, action: press).buttonStyle(.borderedProminent)
            } else {
                Button(button, action: press).buttonStyle(.bordered)
            }
        } else if !done {
            if lesson.id == nextLessonID {
                Button("Got it") { progress.mark(lesson.id) }.buttonStyle(.borderedProminent)
            } else {
                Button("Got it") { progress.mark(lesson.id) }.buttonStyle(.bordered)
            }
        }
    }

    private func open(_ go: Learn.Go) {
        switch go {
        case .play: router.go(to: .control)
        case .behaviours: router.go(to: .behaviours)
        case .preference: router.go(to: .studio, then: .preference)
        case .motions: router.go(to: .studio, then: .motions)
        case .challenges: router.go(to: .studio, then: .challenges)
        case .tune: router.go(to: .studio, then: .tune)
        case .shoot: router.go(to: .studio, then: .shoot)
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
