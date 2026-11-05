import SwiftUI
import StudioKit

/// The Duck sheet, from the duck pill on any tab (docs/plans/native-first-redesign.md, build 91).
///
/// ONE PLACE FOR THE DUCK. Which duck the controller drives, whether it answers (the live dot,
/// which is the old toolbar lens merged), its camera, its connection, its details, your room,
/// Siri, adding a duck, and the expert doors. The sections and their order are the kit's
/// (`DuckSheet.sections`), pinned by a Linux test to the target tree.
///
/// THE VENUE CHANGES ONLY ON A PICK HERE OR ON THE PILL. A row in "Drive on" asks Play through
/// the router with the cause `.duckSheet`; Play asks `VenueRule`, closes the stick gate and says
/// "Now driving ...". Nothing in this file writes a venue.
struct DuckSheetView: View {
    @ObservedObject var model: LibraryModel
    @ObservedObject var scenes: SceneStore
    @ObservedObject var drafts: DraftStore
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore
    @ObservedObject var detail: DetailStore
    @ObservedObject var machines: MachineStore
    @ObservedObject var remote: RemoteReachStore
    @ObservedObject var robot: BridgeLink
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// One address: empty means "the connection's host", which is what the camera uses.
    @AppStorage("robot.camera.address") private var cameraAddress = ""

    private var expert: Bool { detail.level == .full }

    private var phone: Bool {
#if os(iOS)
        true
#else
        false
#endif
    }

    var body: some View {
        List {
            ForEach(DuckSheet.sections(expert: expert, phone: phone)) { section in
                sectionView(section)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(DuckSheet.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(ControllerWords.done) { dismiss() }
            }
        }
    }

    @ViewBuilder private func sectionView(_ section: DuckSheet.Section) -> some View {
        switch section {
        case .yourDuck: yourDuck
        case .camera: camera
        case .pollen: pollen
        case .connection: connection
        case .details: details
        case .room: room
        case .siri: siri
        case .add: add
        case .expert: expertSection
        }
    }

    // MARK: - sections

    private var yourDuck: some View {
        Section {
            HStack(spacing: Theme.spacing(.snug)) {
                Circle().fill(dot).frame(width: 12, height: 12).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DuckPill.name(of: router.playVenue))
                        .font(.system(.headline, design: .rounded))
                    Text(liveWords).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            ForEach(DriveVenue.allCases) { venue in
                Button {
                    router.go(to: .play(.venue(venue, .duckSheet)))
                    dismiss()
                } label: {
                    HStack {
                        Text(DuckPill.name(of: venue)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if venue == router.playVenue {
                            Image(systemName: "checkmark").foregroundStyle(Theme.measured)
                        }
                    }
                    .frame(minHeight: DesignMetric.minimumTarget)
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(venue == router.playVenue ? .isSelected : [])
            }
        } header: {
            SectionHeading(text: ControllerWords.driveOn)
        } footer: {
            Text(DuckSheet.driveOnLine).foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    /// The live dot: the last thing asked was answered, or nothing is there. Never a heartbeat.
    private var dot: Color {
        if router.playVenue != .real { return Theme.success }
        return robot.isConnected ? Theme.success : Theme.textTertiary
    }

    private var liveWords: String {
        if router.playVenue != .real { return DuckSheet.liveAnswered }
        return robot.isConnected ? DuckSheet.liveAnswered : DuckSheet.liveNone
    }

    /// ONE ADDRESS FEEDS THE CAMERA. The field shows the connection's host until somebody types
    /// a different one; clearing it goes back to the connection.
    private var cameraBinding: Binding<String> {
        Binding(get: { cameraAddress.isEmpty ? robot.host : cameraAddress },
                set: { cameraAddress = $0 == robot.host ? "" : $0 })
    }

    private var camera: some View {
        Section {
            DuckCameraCard(address: cameraBinding, robot: robot, models: models)
        } header: {
            SectionHeading(text: DuckSheet.Section.camera.title)
        } footer: {
            if robot.isConnected, cameraAddress.isEmpty {
                Text(DuckSheet.cameraFromConnection).foregroundStyle(Theme.textSecondary)
            }
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var pollen: some View {
        Section {
            Button {
                openURL(Provenance.microduckPage.url)
            } label: {
                HubRow(DuckSheet.Section.pollen.title, DuckSheet.pollenLine, "arrow.up.right.square")
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var connection: some View {
        Section {
            NavigationLink { RobotBridgeView(library: model, robot: robot) } label: {
                HubRow(DuckSheet.connectRow, DuckSheet.connectRowLine, "cable.connector")
            }
            NavigationLink { FindDuckView() } label: {
                HubRow(DuckSheet.findRow, DuckSheet.findRowLine, "antenna.radiowaves.left.and.right")
            }
        } header: {
            SectionHeading(text: DuckSheet.Section.connection.title)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var details: some View {
        Section {
            NavigationLink {
                RobotView(benches: benches, models: models, library: model, robot: robot, detail: detail)
            } label: {
                HubRow(DuckSheet.Section.details.title, DuckSheet.detailsLine, "wrench.and.screwdriver")
            }
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    @ViewBuilder private var room: some View {
#if os(iOS)
        Section {
            NavigationLink { RoomCaptureView() } label: {
                HubRow(DuckSheet.Section.room.title, DuckSheet.roomLine, "square.split.bottomrightquarter")
            }
        }
        .listRowBackground(Theme.surfacePrimary)
#endif
    }

    private var siri: some View {
        Section {
            Text(DuckSheet.siriLine)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(Onboarding.makeItYoursTitle) {
                ForEach(Onboarding.makeItYoursSteps, id: \.self) { step in
                    Text(step).font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.footnote)
        } header: {
            SectionHeading(text: DuckSheet.Section.siri.title)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var add: some View {
        Section {
            Button {
                dismiss()
                router.welcomeAgain = Onboarding.addYourDuckStart
            } label: {
                HubRow(DuckSheet.Section.add.title, DuckSheet.addLine, "plus.circle")
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .listRowBackground(Theme.surfacePrimary)
    }

    private var expertSection: some View {
        Section {
            NavigationLink {
                MyMicroduckView(model: model, scenes: scenes, drafts: drafts,
                                models: models, benches: benches, detail: detail,
                                machines: machines, remote: remote, robot: robot)
            } label: {
                HubRow(DuckSheet.expertMachines, DuckSheet.expertMachinesLine, "server.rack")
            }
            NavigationLink { PairingSpikeView() } label: {
                HubRow(DuckSheet.expertDiagnostics, DuckSheet.expertDiagnosticsLine, "bolt.horizontal")
            }
            Button {
                dismiss()
                router.go(to: .studio(.measure))
            } label: {
                HubRow(DuckSheet.expertBenches, DuckSheet.expertBenchesLine, "cpu")
            }
            .foregroundStyle(Theme.textPrimary)
        } header: {
            SectionHeading(text: DuckSheet.Section.expert.title)
        }
        .listRowBackground(Theme.surfacePrimary)
    }
}
