import SwiftUI
import StudioKit
import DuckKit

/// "Measure my duck": the closed-loop cards on a connected real duck, as a test, with the tester's
/// tape-measured marks, into a duck-measure/0 report to share.
///
/// THIN ON PURPOSE. The rows, the runner, the report and the evaluation against docs/PACKS.md
/// "Acceptance" are `DuckMeasure` in StudioKit, tested on Linux; every sentence here is
/// `DuckMeasure.Words`. This draws them, holds the tester's numbers, and offers Run and Stop.
///
/// THE ONE SCREEN THAT RUNS MEASURED CARDS ON A ROBOT. Everywhere else a duck's Walk and Turn are
/// timed (`DuckCardLoop.spec.enabledOnRobot` is false); this says it is a test before anything else.
struct MeasureDuckView: View {
    var robot: BridgeLink? = nil
    var stopDriving: (() async -> Void)? = nil

    @State private var records: [String: DuckMeasure.RunRecord] = [:]
    @State private var marks: [String: [String]] = [:]       // run id -> forward, left, heading as typed
    @State private var running: String?
    @State private var task: Task<Void, Never>?
    @State private var line: String?
    @State private var outgoing: URL?
    @State private var still: DuckMeasure.StillRecord?
    @State private var stillMark = ""
    private static let stillID = "still"

    var body: some View {
        List {
            Section {
                Label(DuckMeasure.Words.thisIsATest, systemImage: "testtube.2")
                    .font(.footnote).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(DuckMeasure.Words.safety, systemImage: "hand.raised")
                    .font(.caption).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Text(DuckMeasure.Words.grid()).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { SectionHeading(text: DuckMeasure.Words.gridHeading) }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Text(DuckMeasure.Words.marks).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { SectionHeading(text: DuckMeasure.Words.marksHeading) }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Text(DuckMeasure.Words.still()).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    if running == Self.stillID {
                        Button(DuckMeasure.Words.stop) { task?.cancel() }
                            .buttonStyle(.primaryAction)
                    } else if running == nil, let robot, robot.isConnected {
                        Button(DuckMeasure.Words.run) { startStill(robot) }
                            .buttonStyle(.primaryActionMoves)
                    }
                }
                if let still {
                    Text(DuckMeasure.Words.stillResult(markedStill ?? still)).font(.footnote)
                        .foregroundStyle(Theme.measured).fixedSize(horizontal: false, vertical: true)
                    if still.ended == .finished || still.ended == .stopped {
                        TextField(DuckMeasure.Words.stillMark, text: $stillMark)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.body.monospacedDigit())
                            .accessibilityLabel(Text(DuckMeasure.Words.stillMark))
                    }
                }
            } header: { SectionHeading(text: DuckMeasure.Words.stillHeading) }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                if let line {
                    Text(line).font(.footnote).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if running != nil {
                    Button(DuckMeasure.Words.stop) { task?.cancel() }
                        .buttonStyle(.primaryAction)
                } else if robot?.isConnected != true {
                    Text(DuckMeasure.Words.needsDuck).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                ForEach(DuckMeasure.runs) { run in runRow(run) }
            } header: { SectionHeading(text: DuckMeasure.Words.runsHeading) }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                ForEach(report.evaluation.said, id: \.self) { said in
                    Text(said).font(.footnote).foregroundStyle(Theme.measured)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let outgoing {
                    ShareLink(item: outgoing) {
                        Label(DuckMeasure.Words.share, systemImage: "square.and.arrow.up")
                    }
                    .tint(Theme.actionSecondary)
                    .frame(minHeight: DesignMetric.minimumTarget)
                }
            } header: {
                SectionHeading(text: DuckMeasure.Words.reportHeading)
            } footer: {
                Text(DuckMeasure.Words.reportFooter).foregroundStyle(Theme.textSecondary)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(DuckMeasure.Words.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { task?.cancel() }
        .onChange(of: records) { _, _ in writeReport() }
        .onChange(of: marks) { _, _ in writeReport() }
        .onChange(of: still) { _, _ in writeReport() }
        .onChange(of: stillMark) { _, _ in writeReport() }
    }

    private func runRow(_ run: DuckMeasure.Run) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            HStack {
                Text(DuckMeasure.Words.runTitle(run)).font(.body).foregroundStyle(Theme.textPrimary)
                Spacer()
                if running == nil, let robot, robot.isConnected {
                    Button(DuckMeasure.Words.run) { start(run, robot) }
                        .buttonStyle(.primaryActionMoves)
                }
            }
            Text(DuckMeasure.Words.expect(run)).font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let record = records[run.id] {
                Text(DuckMeasure.Words.result(record)).font(.footnote).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let odometry = DuckMeasure.Words.odometry(record) {
                    Text(odometry).font(.caption.monospacedDigit()).foregroundStyle(Theme.measured)
                }
                if record.ended == .finished || record.ended == .stopped {
                    markField(run, 0, DuckMeasure.Words.forward)
                    markField(run, 1, DuckMeasure.Words.left)
                    markField(run, 2, DuckMeasure.Words.heading)
                }
            }
        }
        .padding(.vertical, Theme.spacing(.hairline))
    }

    private func markField(_ run: DuckMeasure.Run, _ i: Int, _ label: String) -> some View {
        TextField(label, text: Binding(
            get: { marks[run.id]?[i] ?? "" },
            set: { typed in
                var three = marks[run.id] ?? ["", "", ""]
                three[i] = typed
                marks[run.id] = three
            }))
        .keyboardType(.numbersAndPunctuation)
        .font(.body.monospacedDigit())
        .accessibilityLabel(Text(label))
    }

    /// The records with the tester's marks folded in, as the report carries them.
    private var marked: [DuckMeasure.RunRecord] {
        DuckMeasure.runs.compactMap { run in
            guard var r = records[run.id] else { return nil }
            let n = (marks[run.id] ?? []).map { Double($0.replacingOccurrences(of: ",", with: ".")
                                                         .trimmingCharacters(in: .whitespaces)) }
            if n.count == 3, let f = n[0], let l = n[1], let h = n[2] {
                r.tester = .init(forwardCm: f, leftCm: l, headingDeg: h)
            }
            return r
        }
    }

    /// The stand-still record with the tester's tape heading folded in.
    private var markedStill: DuckMeasure.StillRecord? {
        guard var s = still else { return nil }
        s.testerHeadingDeg = Double(stillMark.replacingOccurrences(of: ",", with: ".")
                                             .trimmingCharacters(in: .whitespaces))
        return s
    }

    private var report: DuckMeasure.Report {
        DuckMeasure.report(marked, madeAt: Date(), app: AppVersion.said, bridge: robot?.greeting?.bridge,
                           robotd: nil, policy: robot?.lastState?.policy, still: markedStill)
    }

    private func writeReport() {
        guard !records.isEmpty || still != nil else { outgoing = nil; return }
        let r = report
        outgoing = try? ExportFile.write(try r.json(), named: r.fileName)
    }

    @MainActor private func startStill(_ robot: BridgeLink) {
        guard running == nil, let peer = robot.peer else { return }
        running = Self.stillID
        line = nil
        task = Task { @MainActor in
            defer { running = nil; task = nil }
            await stopDriving?()
            _ = try? await robot.subscribeToState()
            do {
                let record = try await DuckMeasure.standStill(
                    on: peer,
                    sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
                    state: { await MainActor.run { robot.lastState } })
                still = record
                stillMark = ""
                line = DuckMeasure.Words.stillResult(record)
            } catch let refusal as DuckMeasure.Refusal {
                line = refusal.message
            } catch let misuse as DuckCall.Misuse {
                line = misuse.message
            } catch {
                line = error.localizedDescription
            }
        }
    }

    @MainActor private func start(_ run: DuckMeasure.Run, _ robot: BridgeLink) {
        guard running == nil, let peer = robot.peer else { return }
        let interval = robot.interval
        running = run.id
        line = nil
        task = Task { @MainActor in
            defer { running = nil; task = nil }
            await stopDriving?()
            _ = try? await robot.subscribeToState()
            do {
                let record = try await DuckMeasure.run(
                    run, on: peer, interval: interval,
                    sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
                    state: { await MainActor.run { robot.lastState } },
                    said: { said in await MainActor.run { line = said } })
                records[run.id] = record
                line = DuckMeasure.Words.result(record)
            } catch let refusal as DuckMeasure.Refusal {
                line = refusal.message
            } catch let refusal as RobotPlanRunner.Refusal {
                line = refusal.message
            } catch let misuse as DuckCall.Misuse {
                line = misuse.message
            } catch {
                line = error.localizedDescription
            }
        }
    }
}
