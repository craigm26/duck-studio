import SwiftUI
import StudioKit
import DuckEvidence

/// A sentence in, a chain of steps out, and the person decides each one.
///
/// THE CHAIN IS THE FLOW CHART, DRAWN AS ONE. A plan today is a sequence — each
/// step runs when the one before it finishes — so the honest drawing is nodes
/// joined top to bottom, not a canvas that suggests branches the runner cannot
/// take. Branching is where `DuckIntentPlan` is headed (a planner over skill
/// nodes); the node card is the unit that survives that change.
///
/// NOTHING MOVES UNTIL RUN IS PRESSED. Proposing, editing, reordering and
/// discarding are all edits to a value on this screen. Run resolves the kept
/// steps through `SequenceProposal` — every velocity re-derived against this
/// app's own limits — and hands the result to the same pilot a recorded take
/// plays through.
///
/// EVERY DECISION IS WRITTEN DOWN, ONCE, WHEN THE PLAN IS RUN OR KEPT. One
/// `route_correction` per clause, with the consent the person chose in
/// Settings (on the phone unless they said otherwise). A plan abandoned
/// half-edited records nothing: an unfinished edit is not an answer.
struct PlanEditorView: View {

    /// The drive desk, when this is opened from Control. Nil from Studio, where
    /// there is nothing to drive and a plan can only be kept.
    let desk: PadDesk?
    let venue: DriveVenue
    let engage: () -> Void
    /// The selected bench, whose machine is where the router is looked for
    /// when no address has been typed. Nil from Studio.
    var bench: BenchEndpoint? = nil
    /// The models chosen in Settings, for planning with a model rather than
    /// the router. Nil where no store was handed down; then only the router.
    var models: EndpointStore? = nil

    /// A typed address wins; otherwise the router on the bench's own machine.
    private var routerBase: URL? {
        feedback.routerURL ?? bench.flatMap(DuckMachine.routerURL(for:))
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var feedback = FeedbackStore()
    @StateObject private var ownShelf = SequenceStore()

    @State private var typed = ""
    @State private var plan: DuckIntentPlan?
    @State private var took: Double?
    @State private var refusal: String?
    @State private var thinking = false
    @State private var kept: String?
    /// Who plans: the bench's router, or the model chosen in Settings.
    @State private var useModel = false
    /// Who planned the plan on screen, for its provenance and its records.
    @State private var plannedBy: DuckIntentPlan.RouterIdentity = .decide
    @State private var checkProgress: String?
    @State private var checkResult: String?

    var body: some View {
        List {
                askSection
                if let plan {
                    stepsSection(plan)
                    runSection(plan)
                }
                if let refusal {
                    Section {
                        Label(refusal, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
                if let kept {
                    Section {
                        Text(kept).font(.footnote).foregroundStyle(Theme.textSecondary)
                        Text(PlanEditorWords.recorded).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }
                sourceSection
                if !useModel { routerSection }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .navigationTitle(PlanEditorWords.title)
            .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - asking

    private var askSection: some View {
        Section {
            Text(PlanEditorWords.intro)
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(PlanEditorWords.askPlaceholder, text: $typed, axis: .vertical)
                .lineLimit(1...4)
                .submitLabel(.go)
                .onSubmit { Task { await propose() } }
            Button {
                Task { await propose() }
            } label: {
                if thinking {
                    Label(PlanEditorWords.proposing, systemImage: "hourglass")
                } else {
                    Label(PlanEditorWords.proposeButton, systemImage: "arrow.triangle.branch")
                }
            }
            .buttonStyle(.primaryAction)
            .disabled(thinking || typed.trimmingCharacters(in: .whitespaces).isEmpty)
            .frame(minHeight: DesignMetric.minimumTarget)
        } header: {
            SectionHeading(text: PlanEditorWords.askHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var routerSection: some View {
        Section {
            TextField(PlanEditorWords.routerPlaceholder, text: $feedback.routerAddress)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            SectionHeading(text: PlanEditorWords.routerHeading)
        } footer: {
            if feedback.routerURL == nil, let bench, let url = DuckMachine.routerURL(for: bench) {
                Text(DuckMachine.usingRouter(on: bench.name, url)).foregroundStyle(Theme.textSecondary)
            } else {
                Text(PlanEditorWords.routerFooter).foregroundStyle(Theme.textSecondary)
            }
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - who plans

    private var sourceSection: some View {
        Section {
            if models != nil {
                Picker(PlanEditorWords.sourceHeading, selection: $useModel) {
                    Text(PlanEditorWords.sourceRouter).tag(false)
                    Text(PlanEditorWords.sourceModel).tag(true)
                }
                .pickerStyle(.segmented)
            }
            if useModel, let models {
                Text(PlanEditorWords.usingModel(models.selected.name))
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await check() }
                } label: {
                    Label(checkProgress ?? PlanEditorWords.checkButton, systemImage: "checklist")
                }
                .disabled(thinking || checkProgress != nil)
                .frame(minHeight: DesignMetric.minimumTarget)
                if let checkResult {
                    Text(checkResult).font(.footnote.monospacedDigit()).foregroundStyle(Theme.measured)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(PlanEditorWords.routerSourceFooter)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: PlanEditorWords.sourceHeading)
        } footer: {
            if useModel { Text(PlanEditorWords.checkFooter).foregroundStyle(Theme.textSecondary) }
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// The chosen model as a planner. `DraftEngine.ask` is the one door every
    /// model goes through, so Apple's, a downloaded one and a server all plan
    /// with the same prompt and are read by the same reader.
    private func modelPlanner(_ models: EndpointStore) -> ModelIntentPlanner {
        let endpoint = models.armed(models.selected)
        let name = endpoint.model.isEmpty ? endpoint.name : endpoint.model
        return ModelIntentPlanner(
            identity: .init(model: name, revision: ModelIntentPlanner.promptSource),
            ask: { instructions, prompt in
                try await DraftEngine.ask(endpoint, kind: .motion, prompt: prompt, knownIntents: [],
                                          instructions: instructions).json
            })
    }

    /// p002 on this phone, one request at a time — a phone holds one model and
    /// one answer at a time, and the time per answer is part of the result.
    @MainActor private func check() async {
        guard let models, checkProgress == nil else { return }
        let planner = modelPlanner(models)
        let requests = PlannerCheck.requests
        var rows: [PlannerCheck.Row] = []
        checkResult = nil
        defer { checkProgress = nil }
        for request in requests {
            checkProgress = PlanEditorWords.checking(rows.count, of: requests.count)
            let started = Date()
            do {
                let plan = try await planner.plan(for: request.text)
                rows.append(PlannerCheck.score(request, plan: plan,
                                               seconds: Date().timeIntervalSince(started)))
            } catch let error as ModelIntentPlanner.ReadError {
                rows.append(PlannerCheck.score(request, plan: nil, unreadable: error.message,
                                               seconds: Date().timeIntervalSince(started)))
            } catch {
                // THE MODEL COULD NOT BE ASKED AT ALL — not loaded, too big, no
                // Apple Intelligence. That is not a score, so say why and stop.
                refusal = error.localizedDescription
                return
            }
        }
        checkResult = PlanEditorWords.checked(planner.identity.model,
                                              PlannerCheck.summarise(rows).line)
    }

    @MainActor private func propose() async {
        let asked = typed.trimmingCharacters(in: .whitespaces)
        guard !asked.isEmpty, !thinking else { return }
        refusal = nil; kept = nil
        if useModel, let models {
            thinking = true
            defer { thinking = false }
            let planner = modelPlanner(models)
            let started = Date()
            do {
                plan = try await planner.plan(for: asked)
                plannedBy = planner.identity
                took = Date().timeIntervalSince(started)
            } catch let error as ModelIntentPlanner.ReadError {
                refusal = error.message
            } catch {
                refusal = error.localizedDescription
            }
            return
        }
        let typed = feedback.routerAddress.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty, feedback.routerURL == nil {
            refusal = PlanEditorWords.notAnAddress(feedback.routerAddress)
            return
        }
        guard let base = routerBase else {
            refusal = PlanEditorWords.noRouter
            return
        }
        thinking = true
        defer { thinking = false }
        let router = HTTPIntentRouter(base: base) { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            return data
        }
        let started = Date()
        do {
            plan = try await router.plan(for: asked)
            plannedBy = router.identity
            took = Date().timeIntervalSince(started)
        } catch let error as DuckIntentPlan.ReadError {
            refusal = error.message
        } catch {
            refusal = PlanEditorWords.routerFailed(error.localizedDescription)
        }
    }

    // MARK: - the chain

    private func stepsSection(_ plan: DuckIntentPlan) -> some View {
        Section {
            Text(PlanEditorWords.proposedBy(plan.model, seconds: took))
                .font(.caption).foregroundStyle(Theme.textSecondary)
            ForEach(Array(plan.nodes.enumerated()), id: \.element.id) { index, node in
                PlanNodeCard(node: node, number: index + 1,
                             isFirst: index == 0, isLast: index == plan.nodes.count - 1,
                             change: { changed in self.plan?.update(changed) },
                             moveUp: { self.plan?.move(from: index, to: index - 1) },
                             moveDown: { self.plan?.move(from: index, to: index + 2) })
            }
        } header: {
            SectionHeading(text: PlanEditorWords.stepsHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    // MARK: - running

    private func runSection(_ plan: DuckIntentPlan) -> some View {
        Section {
            switch Result(catching: { try plan.run() }) {
            case .success(let run):
                ForEach(Array(run.moves.enumerated()), id: \.offset) { _, move in
                    Text(SequenceProposal.spelled(move))
                        .font(.footnote.monospacedDigit()).foregroundStyle(Theme.measured)
                }
                if let slot = run.thenLoading {
                    Text(PlanEditorWords.thenSkill(slot.title))
                        .font(.footnote).foregroundStyle(Theme.measured)
                }
                ForEach(run.notSent, id: \.self) { line in
                    Label(line, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if plan.flaggedCount > 0 {
                    Label(PlanEditorWords.flaggedLeft(plan.flaggedCount),
                          systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
                if desk != nil, venue != .real {
                    Button(PlanEditorWords.runButton) { go(plan, run: run, play: true) }
                        .buttonStyle(.primaryActionMoves)
                } else {
                    Text(PlanEditorWords.runNeedsBench)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(PlanEditorWords.keepButton) { go(plan, run: run, play: false) }
                    .frame(minHeight: DesignMetric.minimumTarget)
            case .failure(let error):
                Label((error as? DuckIntentPlan.RunRefusal)?.message ?? error.localizedDescription,
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeading(text: PlanEditorWords.runHeading)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// Resolve, keep, record, and — from Control — play.
    private func go(_ plan: DuckIntentPlan, run: DuckIntentPlan.Run, play: Bool) {
        do {
            let sequence = try SequenceProposal(name: plan.request, moves: run.moves)
                .resolve(named: plan.request,
                         provenance: .drafted(model: plannedBy.model,
                                              asked: plan.request),
                         venue: venue, at: Date())
            if let desk {
                desk.add(sequence)
                if play {
                    desk.pilot.play(sequence, thenLoading: run.thenLoading)
                    engage()
                }
            } else {
                ownShelf.save(sequence)
            }
            feedback.append((try? plan.corrections(router: plannedBy, share: feedback.share,
                                                   client: FeedbackStore.client)) ?? [])
            if play { dismiss() } else { kept = PlanEditorWords.kept(sequence.name) }
        } catch let error as SequenceProposal.Unresolvable {
            refusal = error.message
        } catch let error as DuckSequence.Refusal {
            refusal = error.message
        } catch {
            refusal = error.localizedDescription
        }
    }
}

/// One node of the chain: the clause, a picker per head that matters, the
/// router's doubts, and the controls that reorder or drop it.
///
/// THE CONNECTOR IS PART OF THE CARD, so a reordered chain redraws its own
/// lines and there is no second list of edges to keep in step with the nodes.
private struct PlanNodeCard: View {
    let node: DuckIntentPlan.Node
    let number: Int
    let isFirst: Bool
    let isLast: Bool
    let change: (DuckIntentPlan.Node) -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing(.snug)) {
            connector
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                HStack {
                    Text(PlanEditorWords.stepNumber(number))
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button { moveUp() } label: {
                        Label(PlanEditorWords.moveUp, systemImage: "chevron.up").labelStyle(.iconOnly)
                    }
                    .disabled(isFirst)
                    Button { moveDown() } label: {
                        Label(PlanEditorWords.moveDown, systemImage: "chevron.down").labelStyle(.iconOnly)
                    }
                    .disabled(isLast)
                }
                .buttonStyle(.borderless)
                Text(node.clause)
                    .font(.body.italic())
                    .foregroundStyle(node.discarded ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(node.discarded)
                if node.discarded {
                    Text(PlanEditorWords.discarded).font(.caption).foregroundStyle(Theme.textSecondary)
                } else {
                    if node.isRefusal {
                        Label(PlanEditorWords.refusal, systemImage: "hand.raised")
                            .font(.caption).foregroundStyle(Theme.warning)
                    }
                    ForEach(node.heads, id: \.self) { head in picker(head) }
                    ForEach(node.flagged, id: \.self) { head in
                        Label(PlanEditorWords.unsure(head, confidence: node.confidence[head.rawValue] ?? 0),
                              systemImage: "questionmark.circle")
                            .font(.caption).foregroundStyle(Theme.warning)
                    }
                    if node.isMovement {
                        Stepper(PlanEditorWords.holdFor(node.seconds),
                                value: Binding(get: { node.seconds },
                                               set: { var n = node; n.seconds = $0; change(n) }),
                                in: DuckDrive.holdSeconds...DuckSequence.maximumMoveSeconds,
                                step: 0.5)
                            .font(.footnote)
                    }
                    if node.outcome == .edited {
                        Text(PlanEditorWords.edited).font(.caption).foregroundStyle(Theme.measured)
                    }
                }
                Button(node.discarded ? PlanEditorWords.restore : PlanEditorWords.discard) {
                    var n = node; n.discarded.toggle(); change(n)
                }
                .buttonStyle(.borderless)
                .font(.footnote)
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    private func picker(_ head: DuckIntentPlan.Head) -> some View {
        Picker(PlanEditorWords.headName(head),
               selection: Binding(get: { node.labels[head.rawValue] ?? "" },
                                  set: { label in
                                      var n = node
                                      try? n.set(head, to: label)
                                      change(n)
                                  })) {
            ForEach(DuckIntentPlan.Vocabulary.labels(for: head), id: \.self) { label in
                Text(DuckIntentPlan.Vocabulary.words(label)).tag(label)
            }
        }
        .pickerStyle(.menu)
        .font(.footnote)
    }

    /// The line into this node and out of it, with a dot for the node.
    private var connector: some View {
        VStack(spacing: 0) {
            Rectangle().fill(isFirst ? Color.clear : Theme.separator)
                .frame(width: DesignMetric.hairlineStroke * 2, height: Theme.spacing(.snug))
            Circle()
                .fill(node.discarded ? Theme.separator : (node.flagged.isEmpty ? Theme.actionPrimary : Theme.warning))
                .frame(width: 10, height: 10)
            Rectangle().fill(isLast ? Color.clear : Theme.separator)
                .frame(width: DesignMetric.hairlineStroke * 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }
}
