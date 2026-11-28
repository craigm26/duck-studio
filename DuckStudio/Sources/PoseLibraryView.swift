import SwiftUI
import DuckKit
import StudioKit

/// The picture's height: the kit's standard, as `MoveSearchMetric` takes it.
private enum PoseMetric { static let viewportHeight = CGFloat(StageViewport.standardHeight) }

/// Moves > My poses: the saved poses, each one openable, and a composer that
/// strings them into a motion.
///
/// NOTHING HERE MOVES A DUCK. A pose is shown on the picture and kept; a
/// motion made from poses goes into Studio as an ordinary draft, and running
/// it is the motion door's job, with its Stop and its practice-duck default.
/// Every sentence is `PoseLibrary.Words`; every number is `DuckPose`'s.
struct PoseLibraryView: View {
    @EnvironmentObject private var poses: PoseStore
    @ObservedObject var drafts: DraftStore
    @State private var composing = false

    var body: some View {
        List {
            Section {
                Text(PoseLibrary.Words.chatSaid)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                if poses.poses.isEmpty {
                    Text(PoseLibrary.Words.none)
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(poses.poses) { pose in
                    NavigationLink {
                        PoseDetailView(pose: pose)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pose.name).foregroundStyle(Theme.textPrimary)
                            Text(pose.about.isEmpty ? pose.summary : pose.about)
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                        .frame(minHeight: DesignMetric.minimumTarget, alignment: .leading)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { poses.delete(poses.poses[index]) }
                }
            } header: {
                SectionHeading(text: PoseLibrary.Words.heading)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .navigationTitle(PoseLibrary.Words.heading)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(PoseLibrary.Words.makeMotion) { composing = true }
                    .disabled(poses.poses.isEmpty)
            }
        }
        .sheet(isPresented: $composing) {
            NavigationStack { PoseMotionComposer(drafts: drafts) }
                .environmentObject(poses)
                .stopPill()
        }
    }
}

/// One pose: the duck standing in it, its name and description, and what can
/// be made from it.
struct PoseDetailView: View {
    @EnvironmentObject private var poses: PoseStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let pose: DuckPose
    @State private var name = ""
    @State private var about = ""
    @State private var orbit = OrbitState()
    @State private var note: String?

    var body: some View {
        Form {
            Section {
                DuckStage(pose: StagePose(jointAngles: pose.angles, root: StagePose.home.root),
                          environment: .bareFloor, orbit: $orbit)
                    .frame(maxHeight: typeSize.isAccessibilitySize ? nil : PoseMetric.viewportHeight)
                    .listRowInsets(EdgeInsets())
                Text(pose.summary).font(.footnote).foregroundStyle(Theme.textSecondary)
                Text(pose.sourceSentence).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Section {
                TextField(PoseLibrary.Words.name, text: $name)
                TextField(PoseLibrary.Words.aboutPrompt, text: $about)
            } header: {
                SectionHeading(text: PoseLibrary.Words.about)
            } footer: {
                Text(PoseLibrary.Words.aboutSaid)
            }
            Section {
                Button(PoseLibrary.Words.mirror) {
                    if let kept = poses.keep(pose.mirrored()) {
                        note = ControlShelf.keptAsAPose(kept.name)
                    }
                }
                if let url = poses.exportURL(for: pose) {
                    ShareLink(item: url) { Text(PoseLibrary.Words.share) }
                }
                Button(PoseLibrary.Words.delete, role: .destructive) {
                    poses.delete(pose)
                    dismiss()
                }
                if let note {
                    Text(note).font(.footnote).foregroundStyle(Theme.measured)
                }
            }
        }
        .navigationTitle(pose.name)
        .onAppear { name = pose.name; about = pose.about }
        .onDisappear {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard poses.poses.contains(where: { $0.id == pose.id }),
                  !trimmed.isEmpty, trimmed != pose.name || about != pose.about else { return }
            poses.edit(pose, name: trimmed, about: about)
        }
    }
}

/// Pick poses in order, set the timing, keep the motion.
struct PoseMotionComposer: View {
    @EnvironmentObject private var poses: PoseStore
    @ObservedObject var drafts: DraftStore
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [DuckPose] = []
    @State private var seconds = 0.8
    @State private var hold = 0.0
    @State private var name = ""
    @State private var refusal: String?

    var body: some View {
        Form {
            Section {
                Text(PoseLibrary.Words.composerSaid)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                ForEach(poses.poses) { pose in
                    Button { picked.append(pose) } label: {
                        Label(pose.name, systemImage: "plus.circle")
                    }
                }
            } header: {
                SectionHeading(text: PoseLibrary.Words.pickPoses)
            }
            Section {
                if picked.isEmpty {
                    Text(PoseLibrary.Words.nothingPicked).foregroundStyle(Theme.textSecondary)
                }
                ForEach(Array(picked.enumerated()), id: \.offset) { index, pose in
                    Text("\(index + 1). \(pose.name)")
                }
                .onDelete { picked.remove(atOffsets: $0) }
                .onMove { picked.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                SectionHeading(text: PoseLibrary.Words.order)
            }
            Section {
                Stepper(value: $seconds, in: 0.2...3, step: 0.1) {
                    TelemetryRow(label: PoseLibrary.Words.secondsBetween,
                                 value: String(format: "%.1f", seconds), unit: "s")
                }
                Stepper(value: $hold, in: 0...3, step: 0.1) {
                    TelemetryRow(label: PoseLibrary.Words.holdEach,
                                 value: String(format: "%.1f", hold), unit: "s")
                }
                TextField(PoseLibrary.Words.motionName, text: $name)
            }
            Section {
                Button(PoseLibrary.Words.keepMotion) { keep() }
                    .buttonStyle(.primaryAction)
                    .disabled(picked.isEmpty)
                if let refusal {
                    Text(refusal).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .navigationTitle(PoseLibrary.Words.makeMotion)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func keep() {
        let steps = picked.map {
            PoseLibrary.Step(pose: $0.name, moveSeconds: seconds, holdSeconds: hold)
        }
        do {
            let draft = try PoseLibrary.motion(named: name, steps: steps, from: poses.poses)
            if let broken = draft.problems.first(where: { $0.severity == .broken }) {
                refusal = broken.text
                return
            }
            drafts.save(draft)
            refusal = PoseLibrary.Words.keptMotion(draft.name)
            picked = []
        } catch let error as PoseLibrary.Refusal {
            refusal = error.message
        } catch {
            refusal = error.localizedDescription
        }
    }
}
