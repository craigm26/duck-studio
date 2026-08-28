import SwiftUI
import RealityKit
import DuckKit
import DuckRender
import StudioKit

/// The bench: a policy, an observation, and the robot it would command.
///
/// WHAT THIS SHOWS, AND WHAT IT DELIBERATELY DOES NOT. Feed the network an
/// observation and it answers with fourteen numbers; `DuckGait` turns those
/// into joint targets and `DuckKinematics` turns those into a robot. That whole
/// chain is exact, and it is what you see.
///
/// What you are NOT seeing is the robot walking. Closing the loop — feeding the
/// resulting pose back in as the next observation — does not work and cannot be
/// made to: the policy locks its gait phase to CONTACT, read through the gyro,
/// projected gravity and joint velocities, and on a bench all three are
/// whatever you last typed. Measured, that loop gives a 25 Hz flip-flop or a
/// slam into the travel stops. So this is a single honest step of the network,
/// held still and inspectable, rather than an animation that would imply
/// physics nobody ran.
struct BenchView: View {
    let entry: PolicyLibrary.Entry

    @State private var policy: DuckPolicy?
    @State private var observation = DuckObservation.zeroed
    @State private var actions: [Float] = Array(repeating: 0, count: DuckModel.policyJointCount)
    @State private var stages: DuckGait.Stages?
    @State private var preset: Preset = .standing
    @State private var failure: String?

    /// Observations worth starting from, built with `DuckObservation.build` so
    /// the app never assembles the 61 floats itself — that layout has exactly
    /// one home, and two places that know it are two places that disagree.
    enum Preset: String, CaseIterable, Identifiable {
        case standing = "Standing still"
        case walking = "Walking forward"
        case turning = "Turning left"
        case zeroed = "All zeros"
        var id: String { rawValue }

        var observation: DuckObservation {
            let level: [Double] = [0, 0, -1]        // upright: gravity straight down
            switch self {
            case .zeroed:
                // Not a robot state at all — an all-zero gravity vector
                // describes free fall, and it sits about 32 training standard
                // deviations off the mean. Kept because it is the warm-up input
                // the runtime itself uses, and seeing what the network does with
                // it is informative.
                return .zeroed
            case .standing:
                return .build(gyro: [0, 0, 0], gravity: level,
                              jointPositions: DuckModel.homePose,
                              jointVelocities: Array(repeating: 0, count: DuckModel.jointCount),
                              lastAction: Array(repeating: 0, count: DuckModel.policyJointCount),
                              command: DuckCommand(twist: (0, 0, 0)))
            case .walking:
                return .build(gyro: [0, 0, 0], gravity: level,
                              jointPositions: DuckModel.homePose,
                              jointVelocities: Array(repeating: 0, count: DuckModel.jointCount),
                              lastAction: Array(repeating: 0, count: DuckModel.policyJointCount),
                              command: DuckCommand(twist: (0.15, 0, 0)))
            case .turning:
                return .build(gyro: [0, 0, 0], gravity: level,
                              jointPositions: DuckModel.homePose,
                              jointVelocities: Array(repeating: 0, count: DuckModel.jointCount),
                              lastAction: Array(repeating: 0, count: DuckModel.policyJointCount),
                              command: DuckCommand(twist: (0, 0, 1.0)))
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DuckStage(jointAngles: jointAngles)
                .frame(maxHeight: 320)
                .background(Color(white: 0.08))

            List {
                if let failure {
                    Section { Text(failure).font(.footnote).foregroundStyle(.orange) }
                }
                Section("Observation") {
                    Picker("Preset", selection: $preset) {
                        ForEach(Preset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Text("The 61 floats the network is given. Assembled by DuckObservation.build, never here.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let stages {
                    Section("What the policy commands") {
                        // Walk the POLICY's fourteen slots and ask which joint
                        // each one drives, rather than walking the fifteen
                        // joints and hoping the mouth lines up. DuckModel owns
                        // that mapping in one direction used both ways.
                        ForEach(0..<DuckModel.policyJointCount, id: \.self) { slot in
                            let joint = DuckModel.jointOfPolicySlot(slot)
                            ActionRow(name: DuckModel.jointNames[joint],
                                      action: actions[slot],
                                      target: stages.clamped[joint],
                                      limited: stages.limitedBy.contains(DuckModel.jointNames[joint]))
                        }
                    }
                    if !stages.limitedBy.isEmpty {
                        Section("At the travel stops") {
                            Text(stages.limitedBy.joined(separator: ", "))
                                .font(.footnote.monospaced())
                            Text("These joints were asked for more than they have. The policy is not wrong to ask — the clamp is where the robot's limits enter.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bench")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: preset) { _, _ in run() }
    }

    /// The pose to draw: the policy's clamped targets, or the home stance while
    /// nothing has run.
    private var jointAngles: [Double] {
        stages?.clamped ?? DuckModel.homePose
    }

    private func load() {
        guard case .parameters = entry.identity else {
            failure = "This file does not load, so there is nothing to run."
            return
        }
        // The library holds the report, not the bytes — reload from wherever it
        // was persisted rather than keeping megabytes of policy in a view.
        guard let data = PolicyStore.data(for: entry) else {
            failure = "The policy file could not be re-read."
            return
        }
        do {
            policy = try DuckPolicy.load(from: data)
            run()
        } catch {
            failure = "\(error)"
        }
    }

    private func run() {
        guard let policy else { return }
        observation = preset.observation
        actions = policy.infer(observation)
        stages = DuckGait.stages(action: actions, previousTargets: nil)
    }
}

/// One joint's row: what the network asked for, and what the robot will do.
private struct ActionRow: View {
    let name: String
    let action: Float
    let target: Double
    let limited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.caption)
                if limited {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
                Text(String(format: "%+.3f rad", target))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(limited ? .orange : .secondary)
            }
            // Raw against clamped, drawn together: the gap between them IS the
            // travel limit, and a bar that showed only the final number would
            // hide every time the robot could not do what it was told.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(limited ? Color.orange : Color.accentColor)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
        }
    }

    /// The raw action, not the target. 1.5 rad is a generous full scale — the
    /// policies rarely exceed it, and a bar normalised to whatever the largest
    /// value happens to be would rescale every time the observation changed.
    private var fraction: CGFloat {
        CGFloat(min(abs(Double(action)) / 1.5, 1))
    }
}

/// A turntable view of the robot — not AR. The bench is a place to look at a
/// pose, and a camera feed behind it would be scenery.
private struct DuckStage: UIViewRepresentable {
    let jointAngles: [Double]

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.init(white: 0.08, alpha: 1))

        let duck = DuckGhostEntity()
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(duck)
        view.scene.addAnchor(anchor)
        context.coordinator.duck = duck

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 35
        // 0.45 m back and a little above the trunk: the robot is 25 cm tall, so
        // a default camera distance would put it in the middle distance.
        camera.look(at: SIMD3<Float>(0, 0.10, 0),
                    from: SIMD3<Float>(0.42, 0.20, 0.42),
                    relativeTo: nil)
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        view.scene.addAnchor(cameraAnchor)

        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.duck?.apply(jointAngles: jointAngles)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator { var duck: DuckGhostEntity? }
}
