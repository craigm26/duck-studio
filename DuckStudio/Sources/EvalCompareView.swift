import SwiftUI
import StudioKit

/// Two evaluation logs, side by side, and the four cases where putting them
/// side by side would be the lie.
///
/// THE REFUSALS ARE THE FINDING AND THEY ARE SHOWN RATHER THAN HIDDEN. Two
/// numbers are comparable only when almost everything around them was the same,
/// and `EvalCompare.checked` decides that before this screen draws a row. A
/// screen that drew the rows first and warned second would be a screen where
/// the warning is the thing scrolled past, so the refusal takes the whole
/// screen and there is no table under it to scroll to.
///
/// THERE IS NO COMBINED NUMBER ANYWHERE HERE, and there is no way to add one:
/// the kit produces rows and a difference per row, and nothing in this file
/// touches two rows at once. A policy that travels twice as far and falls over
/// twice as often is a different trade rather than a better one, and any score
/// weighing the two would be a weighting nobody measured.
///
/// AN IMPORTED LOG IS ALLOWED ON EITHER SIDE. Comparing a run from this phone
/// with one somebody else published is the whole reason import exists. What is
/// refused is a comparison across worlds, never a comparison across machines.
struct EvalCompareView: View {
    @ObservedObject var evals: EvalStore

    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var leftName: String?
    @State private var rightName: String?

    var body: some View {
        List {
            pickers
            switch outcome {
            case .ready(let comparison): rows(comparison)
            case .refused(let refusal): refused(refusal)
            case .notChosen: EmptyView()
            }
            footnotes
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(EvalScreen.sideBySideTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: settle)
    }

    // MARK: - which two

    /// The two pickers, over the whole shelf.
    ///
    /// EVERY LOG IS OFFERED ON BOTH SIDES, including the one already chosen on
    /// the other. Filtering it out would answer one of the four refusals by
    /// making it unreachable, and `EvalCompare.Refusal.sameLog` is a sentence
    /// worth reading once: a log compared with itself agrees with itself.
    private var pickers: some View {
        Section {
            Picker(selection: $leftName) {
                ForEach(evals.comparable) { file in
                    Text(name(file)).tag(String?.some(file.name))
                }
            } label: {
                Text(EvalScreen.leftSaid)
            }
            Picker(selection: $rightName) {
                ForEach(evals.comparable) { file in
                    Text(name(file)).tag(String?.some(file.name))
                }
            } label: {
                Text(EvalScreen.rightSaid)
            }
        } header: {
            SectionHeading(text: EvalScreen.whichTwoHeading)
        } footer: {
            Text(EvalCompare.whatCanBeComparedSaid)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// A file on a picker row: the task it ran, and the name on the shelf under
    /// it, because two runs of one task differ only by those eight hex.
    private func name(_ file: EvalLogFile) -> String {
        "\(EvalText.foreign(file.log.eval.task)) \(EvalText.foreign(file.name))"
    }

    // MARK: - the refusal

    private func refused(_ refusal: String) -> some View {
        Section {
            Text(refusal)
                .font(.footnote)
                .foregroundStyle(Theme.refused)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeading(text: EvalScreen.notSideBySideHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - the rows

    /// One scorer, two numbers, the difference, and which side that scorer
    /// prefers when this app knows the scorer at all.
    ///
    /// A BLANK IS NOT A ZERO, and the row says so rather than drawing one. A
    /// scorer only one side measured is a fact about the two runs, and filling
    /// the other cell with a zero would turn it into a result.
    private func rows(_ comparison: EvalCompare) -> some View {
        Section {
            // HOW MUCH OF EACH RUN THERE IS, BEFORE ANY OF ITS NUMBERS. A run
            // somebody stopped is filed with the scenes that finished and none
            // of the ones that never started, so one of these columns can be a
            // mean over one scene and the other a mean over twelve, and the
            // screen said which nowhere: not in the picker, which shows a task
            // and a file name, and not in the rows, which colour a winner.
            TelemetryRow(label: EvalScreen.leftSaid,
                         value: comparison.statusSaid(comparison.left))
            TelemetryRow(label: EvalScreen.rightSaid,
                         value: comparison.statusSaid(comparison.right))
            if let partial = comparison.partialSideSaid() {
                Text(partial)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(comparison.rows) { row in
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    Text(EvalText.foreign(row.name))
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.textPrimary)
                    if typeSize.isAccessibilitySize {
                        // THE SENTENCE RATHER THAN THE COLUMNS at a size where
                        // two numbers and a difference cannot share the width
                        // of a card, which is the branch the epoch grid on the
                        // detail screen already takes. It is the same sentence
                        // a screen reader hears at every size, so the two
                        // layouts cannot come to say different things.
                        Text(comparison.spoken(row))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(spacing: Theme.spacing(.snug)) {
                            value(row.left, isBetter: row.better == .left)
                            value(row.right, isBetter: row.better == .right)
                            Spacer(minLength: Theme.spacing(.tight))
                            Text(differenceSaid(row))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    if let said = row.said {
                        Text(said)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, Theme.spacing(.hairline))
                // THE FINDING OF THIS SCREEN, OUT LOUD. Combined, the row read
                // as three unlabelled numbers with no sides and no direction,
                // and which side a scorer prefers was carried by a colour on
                // one of them. The kit knows `higherIsBetter`, so it says the
                // whole row and this draws it.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(EvalText.foreign(row.name)))
                .accessibilityValue(Text(comparison.spoken(row)))
            }
            if !comparison.oneSidedRows.isEmpty {
                Text(EvalCompare.oneSidedSaid)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: EvalScreen.bothScorerByScorerHeading)
        } footer: {
            Text(EvalCompare.differenceIsNotAScoreSaid)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// One side's number, or an empty cell where that side has none.
    ///
    /// BETTER IS A WORD AS WELL AS A COLOUR. It marks which side this one
    /// scorer prefers, which the kit only answers for a scorer this app knows;
    /// a name out of somebody else's task gets no direction at all, because a
    /// direction guessed would be an opinion about their measurement. The hue
    /// alone was the whole finding of this screen carried in a colour, on the
    /// one row a person acts on, which is what `IntentListView`'s clamp row
    /// already refuses to do.
    private func value(_ number: Double?, isBetter: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(number.map { EvalReport.number($0) } ?? "")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(isBetter ? Theme.measured : Theme.textPrimary)
            if isBetter {
                Text(EvalCompare.betterMark)
                    .font(.caption2)
                    .foregroundStyle(Theme.measured)
            }
        }
        .frame(width: column, alignment: .trailing)
    }

    /// `@ScaledMetric` for the reason `IntentListView.angleColumn` is one: a
    /// hard 88 points holds a four character value at Large and nothing at all
    /// by the top of the ordinary sizes, and the numbers here are the whole
    /// row. Above the accessibility sizes the columns are gone entirely.
    @ScaledMetric(relativeTo: .footnote) private var column: CGFloat = 88

    private func differenceSaid(_ row: EvalCompare.Row) -> String {
        row.difference.map { EvalReport.number($0) } ?? ""
    }

    // MARK: - the sentences that are always true

    private var footnotes: some View {
        Section {
            Text(EvalCompare.neverCombinedSaid)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(EvalLogFile.aLogIsFinished)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - what the kit answers

    /// The two chosen files, or nothing while the shelf is shorter than two.
    private var chosen: (left: EvalLogFile, right: EvalLogFile)? {
        guard let left = evals.comparable.first(where: { $0.name == leftName }),
              let right = evals.comparable.first(where: { $0.name == rightName })
        else { return nil }
        return (left, right)
    }

    /// What the kit made of the two: a comparison, a refusal in its own words,
    /// or nothing to say yet.
    ///
    /// ONE ANSWER AND NOT TWO PROPERTIES. A `comparison` beside a `refusal`
    /// would ask `EvalCompare.checked` the same question twice per pass, and
    /// the failure mode of two answers to one question is a screen that draws
    /// both: a table of rows under a sentence saying they cannot be compared.
    private enum Outcome {
        case ready(EvalCompare)
        case refused(String)
        case notChosen
    }

    /// THE KIT DECIDES, INSIDE A `do`/`catch` AND NOT IN A PROPERTY THAT
    /// THROWS. `EvalCompare.checked` is the only way to build one, and a `View`
    /// property that called a throwing factory without catching would be a
    /// screen that cannot be built.
    private var outcome: Outcome {
        guard let chosen else { return .notChosen }
        do {
            return .ready(try EvalCompare.checked(chosen.left, chosen.right))
        } catch {
            return .refused(EvalMessage.of(error))
        }
    }

    /// The first two on the shelf, so the screen opens on something rather than
    /// on two empty pickers. Newest first is the store's order, so this is the
    /// two most recent runs, which is what somebody arriving here usually meant.
    private func settle() {
        if leftName == nil { leftName = evals.comparable.first?.name }
        if rightName == nil {
            rightName = evals.comparable.dropFirst().first?.name ?? evals.comparable.first?.name
        }
    }
}
