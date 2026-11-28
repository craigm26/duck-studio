import SwiftUI
import StudioKit

/// Monocular Ground-Segmentation Autonomous Building Mapping, Segmented Frontier Search,
/// and Conversational Exploration Skill view (native iOS 17+ and macOS 14+).
///
/// Follows DuckStudio's house rules:
/// - StudioKit computes (`MonocularGroundMapper`, `ConversationalExplorationSkill`,
///   `MonocularMappingSimPreset`); this view only draws and binds state.
/// - Every sheet carries `.stopPill()` so Stop is always reachable.
/// - Uses Pond Day `.primaryAction` / `.secondaryAction` / `.raisedAction` / `.pondChip`
///   styles and `SectionHeading` headers.
/// - Software HOLD pairs with — and NEVER replaces — hardwired power / ISO 13850 kill switches.
struct AutonomousMappingSkillView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var sim = MonocularMappingSimPreset()
    @State private var demoMode: DualDemoMode = .simulation
    @State private var trustTier: MappingTrustTier = .observe
    @State private var softwareHoldEngaged = false
    @State private var showGroundMaskOverlay = true
    @State private var dualRecordingEnabled = true

    // Interactive fault-injection toggles for Safe Sim Preview safety verification.
    @State private var simulateLowBattery = false
    @State private var simulateHighTilt = false
    @State private var simulateStaleCamera = false

    @State private var commandText = ""
    @State private var lastOutcome: ExplorationGoalOutcome?
    @State private var latestPlan: FrontierPlanResult?
    @State private var receiptChain = MappingReceiptChain(
        sessionId: "duckstudio-sim-preview",
        manifest: .forSimulation()
    )
    @State private var pulsePhase = false
    @State private var showInfoSheet = false
    @State private var showReceiptSheet = false

    private var currentTelemetry: BipedHealthTelemetry {
        BipedHealthTelemetry(
            batteryV: simulateLowBattery ? 6.65 : 7.85,
            imuRollDeg: simulateHighTilt ? 25.4 : 1.4,
            imuPitchDeg: -0.9,
            cameraAgeS: simulateStaleCamera ? 2.10 : 0.12,
            humanDistanceM: 2.2,
            servoMaxTempC: 36.5,
            estopOk: true
        )
    }

    private var healthVerdict: BipedHealthVerdict {
        checkBipedHealth(currentTelemetry)
    }

    private var segmentation: ZoneSegmentationResult {
        sim.mapper.segmentZones()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing(.standard)) {
                headerProvenanceBar
                mainVisualGrid
                holdAndSafetyCard
                conversationalGoalCard
                trustAndRecordingCard
                zoneSummaryCard
            }
            .padding(Theme.spacing(.standard))
        }
        .background(Theme.backgroundSecondary)
        .navigationTitle(AutonomousMappingWords.screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showInfoSheet = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .accessibilityLabel(Text(AutonomousMappingWords.infoSheetTitle))
                }
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            NavigationStack {
                infoSheetContent
            }
            .stopPill()
        }
        .sheet(isPresented: $showReceiptSheet) {
            NavigationStack {
                receiptSheetContent
            }
            .stopPill()
        }
        .onAppear {
            refreshPlanAndRecord(event: "skill_opened")
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulsePhase = true
                }
            }
        }
        .onChange(of: demoMode) { _, newMode in
            let manifest: EnvironmentFactorManifest = (newMode == .simulation)
                ? .forSimulation()
                : .forPhysicalHardware()
            receiptChain = MappingReceiptChain(
                sessionId: "duckstudio-\(newMode.rawValue)",
                manifest: manifest
            )
            // Switching to physical hardware always drops back to L0_OBSERVE fail-closed.
            if newMode == .physicalHardware {
                trustTier = .observe
            }
            refreshPlanAndRecord(event: "provenance_mode_changed")
        }
    }

    // MARK: - Provenance & Health Header

    private var headerProvenanceBar: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            HStack(spacing: Theme.spacing(.tight)) {
                StateBadge(
                    text: demoMode.badgeTitle,
                    state: demoMode == .simulation ? .scanning : .active,
                    ground: .render
                )
                StateBadge(
                    text: softwareHoldEngaged ? "HOLD LATCHED" : (healthVerdict.ok ? "BIPED OK" : "INTERLOCK HOLD"),
                    state: (softwareHoldEngaged || !healthVerdict.ok) ? .offline : .idle,
                    ground: .render
                )
                Spacer()
                Text(String(format: "%.1f%% mapped", segmentation.globalCoveragePct))
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.measured)
            }

            Picker("Provenance Mode", selection: $demoMode) {
                ForEach(DualDemoMode.allCases) { mode in
                    Text(mode.pickerLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: Theme.spacing(.standard)) {
                telemetryMetric("Battery", String(format: "%.2f V", currentTelemetry.batteryV), ok: currentTelemetry.batteryV >= MonocularMappingConstants.defaultMinBatteryV)
                telemetryMetric("IMU Roll", String(format: "%+.1f°", currentTelemetry.imuRollDeg), ok: abs(currentTelemetry.imuRollDeg) <= MonocularMappingConstants.defaultMaxTiltDeg)
                telemetryMetric("Cam Age", String(format: "%.2f s", currentTelemetry.cameraAgeS), ok: currentTelemetry.cameraAgeS <= MonocularMappingConstants.defaultMaxCameraAgeS)
                telemetryMetric("Zones", "\(segmentation.zones.count)", ok: true)
            }
        }
        .padding(Theme.spacing(.standard))
        .pondPanel()
    }

    private func telemetryMetric(_ label: String, _ value: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(ok ? Theme.textPrimary : Theme.refused)
        }
    }

    // MARK: - Split Camera + 2D Segmented Map Grid

    @ViewBuilder
    private var mainVisualGrid: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: Theme.spacing(.standard)) {
                cameraPanelCard
                buildingMapCard
            }
        } else {
            VStack(spacing: Theme.spacing(.standard)) {
                cameraPanelCard
                buildingMapCard
            }
        }
    }

    private var cameraPanelCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            HStack {
                Label("Onboard Camera", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Toggle("Ground Mask", isOn: $showGroundMaskOverlay)
                    .labelsHidden()
                    .tint(Theme.actionPrimary)
                    .accessibilityLabel(Text("Toggle monocular ground-plane segmentation mask"))
            }

            Text(AutonomousMappingWords.cameraBadge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.measured)

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    drawSimulatedCameraFrame(ctx: &ctx, size: size)
                }
                .frame(height: 196)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius(.card), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius(.card), style: .continuous)
                        .strokeBorder(Theme.outline.opacity(0.3), lineWidth: DesignMetric.hairlineStroke)
                )

                HStack(spacing: Theme.spacing(.hairline)) {
                    Text(demoMode.badgeTitle)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.surfacePrimary.opacity(0.92), in: Capsule())
                        .foregroundStyle(Theme.textPrimary)
                    if showGroundMaskOverlay {
                        Text("z=0 mask ON")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.success.opacity(0.22), in: Capsule())
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .padding(8)
            }

            HStack(spacing: Theme.spacing(.snug)) {
                legendDot(Theme.success, "Floor (z=0)")
                legendDot(Theme.warning, "Frontier")
                legendDot(Theme.stop, "Keep-out")
            }
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.spacing(.standard))
        .pondPanel()
    }

    private func drawSimulatedCameraFrame(ctx: inout GraphicsContext, size: CGSize) {
        // Sky / upper room wall gradient
        let upper = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.48)
        ctx.fill(Path(upper), with: .color(Color.gray.opacity(0.22)))
        // Floor perspective trapezoid
        let lower = CGRect(x: 0, y: size.height * 0.48, width: size.width, height: size.height * 0.52)
        ctx.fill(Path(lower), with: .color(Color.gray.opacity(0.36)))

        // Perspective hallway lines
        var guide = Path()
        guide.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.44))
        guide.addLine(to: CGPoint(x: size.width * 0.05, y: size.height))
        guide.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.44))
        guide.addLine(to: CGPoint(x: size.width * 0.95, y: size.height))
        ctx.stroke(guide, with: .color(Color.white.opacity(0.35)), lineWidth: 1)

        if showGroundMaskOverlay {
            let patches = sim.cameraOverlayPatches(plan: latestPlan)
            for patch in patches {
                let rect = CGRect(
                    x: patch.minX * size.width,
                    y: patch.minY * size.height,
                    width: patch.width * size.width,
                    height: patch.height * size.height
                )
                let tint: Color
                switch patch.label {
                case .floor: tint = Theme.success
                case .keepout: tint = Theme.stop
                case .obstacle: tint = Theme.critical
                case .unknown: tint = Theme.warning
                }
                let rounded = Path(roundedRect: rect, cornerRadius: 8)
                ctx.fill(rounded, with: .color(tint.opacity(0.36)))
                ctx.stroke(rounded, with: .color(tint.opacity(0.90)), lineWidth: 1.5)
                ctx.draw(
                    Text(patch.caption)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            }
        }
    }

    private var buildingMapCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            HStack {
                Label("2D Segmented Building Map", systemImage: "map")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Step \(sim.stepIndex)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }

            Canvas { ctx, size in
                drawOccupancyMap(ctx: &ctx, size: size)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius(.card), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius(.card), style: .continuous)
                    .strokeBorder(Theme.outline.opacity(0.3), lineWidth: DesignMetric.hairlineStroke)
            )

            HStack(spacing: Theme.spacing(.tight)) {
                Button("Step Sim") {
                    stepSafeSimOnce()
                }
                .buttonStyle(.secondaryAction)
                .disabled(softwareHoldEngaged || !healthVerdict.ok || trustTier == .observe)

                Button("Reset Sim") {
                    sim = MonocularMappingSimPreset()
                    softwareHoldEngaged = false
                    lastOutcome = nil
                    refreshPlanAndRecord(event: "sim_reset")
                }
                .buttonStyle(.raisedAction)
            }
        }
        .padding(Theme.spacing(.standard))
        .pondPanel()
    }

    private func drawOccupancyMap(ctx: inout GraphicsContext, size: CGSize) {
        let m = sim.mapper
        let seg = segmentation
        let display = m.displayCells()
        let cw = size.width / CGFloat(max(1, m.cols))
        let ch = size.height / CGFloat(max(1, m.rows))

        let zonePalette: [Color] = [
            Theme.brandPrimary.opacity(0.38),
            Theme.actionTeal.opacity(0.45),
            Theme.actionLavender.opacity(0.45),
            Theme.success.opacity(0.38),
        ]

        // 1. Occupancy & per-zone cells
        for r in 0..<m.rows {
            for c in 0..<m.cols {
                let state = display[r * m.cols + c]
                let rect = CGRect(
                    x: CGFloat(c) * cw,
                    y: size.height - CGFloat(r + 1) * ch,
                    width: cw + 0.5,
                    height: ch + 0.5
                )
                switch state {
                case .unknown:
                    ctx.fill(Path(rect), with: .color(Color.gray.opacity(0.18)))
                case .free:
                    let zid = seg.cellToZone[GridCell(col: c, row: r)] ?? "zone_01"
                    let idx = max(0, (Int(zid.suffix(2)) ?? 1) - 1) % zonePalette.count
                    ctx.fill(Path(rect), with: .color(zonePalette[idx]))
                case .obstacle:
                    ctx.fill(Path(rect), with: .color(Theme.textPrimary.opacity(0.75)))
                case .keepout:
                    ctx.fill(Path(rect), with: .color(Theme.stop.opacity(0.38)))
                    var hatch = Path()
                    hatch.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                    hatch.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                    ctx.stroke(hatch, with: .color(Theme.stop.opacity(0.85)), lineWidth: 1)
                case .frontier:
                    let alpha = reduceMotion ? 0.80 : (pulsePhase ? 0.92 : 0.45)
                    ctx.fill(Path(rect), with: .color(Theme.warning.opacity(alpha)))
                }
            }
        }

        func toCanvas(_ p: Point2D) -> CGPoint {
            let nx = (p.x - m.origin.x) / (Double(m.cols) * m.resolutionM)
            let ny = (p.y - m.origin.y) / (Double(m.rows) * m.resolutionM)
            return CGPoint(x: nx * size.width, y: (1.0 - ny) * size.height)
        }

        // 2. Keep-out zone borders & labels
        for kz in m.keepoutZones {
            let p0 = toCanvas(Point2D(x: kz.minX, y: kz.maxY))
            let p1 = toCanvas(Point2D(x: kz.maxX, y: kz.minY))
            let box = CGRect(x: p0.x, y: p0.y, width: p1.x - p0.x, height: p1.y - p0.y)
            ctx.stroke(Path(box), with: .color(Theme.stop), lineWidth: 2)
            ctx.draw(
                Text("KEEPOUT")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(Theme.stop),
                at: CGPoint(x: box.midX, y: box.midY)
            )
        }

        // 3. Active swept path preview (green if ALLOW, dashed crimson if DENY)
        let activePath = lastOutcome?.sweptPath.isEmpty == false
            ? (lastOutcome?.sweptPath ?? [])
            : (latestPlan?.selectedFrontier?.sweptPath ?? [])
        if activePath.count >= 2 {
            var line = Path()
            line.move(to: toCanvas(activePath[0]))
            for pt in activePath.dropFirst() {
                line.addLine(to: toCanvas(pt))
            }
            let denied = lastOutcome?.decision == .deny || latestPlan?.decision == .deny
            let style = StrokeStyle(lineWidth: 2.5, dash: denied ? [5, 4] : [])
            ctx.stroke(line, with: .color(denied ? Theme.stop : Theme.success), style: style)
        }

        // 4. Zone labels
        for zone in seg.zones {
            let center = toCanvas(zone.centroid)
            ctx.draw(
                Text("\(zone.roomLabel) \(Int(zone.coveragePct))%")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(Theme.textPrimary),
                at: center
            )
        }

        // 5. MicroDuck pose + monocular FOV cone
        let duckPt = toCanvas(Point2D(x: sim.pose.x, y: sim.pose.y))
        let fovLen: Double = 1.15
        let halfCone: Double = 0.45
        let leftTip = toCanvas(Point2D(
            x: sim.pose.x + fovLen * cos(sim.pose.theta + halfCone),
            y: sim.pose.y + fovLen * sin(sim.pose.theta + halfCone)
        ))
        let rightTip = toCanvas(Point2D(
            x: sim.pose.x + fovLen * cos(sim.pose.theta - halfCone),
            y: sim.pose.y + fovLen * sin(sim.pose.theta - halfCone)
        ))
        var cone = Path()
        cone.move(to: duckPt)
        cone.addLine(to: leftTip)
        cone.addLine(to: rightTip)
        cone.closeSubpath()
        ctx.fill(cone, with: .color(Theme.actionPrimary.opacity(0.24)))
        ctx.stroke(cone, with: .color(Theme.actionPrimary), lineWidth: 1)

        let dotRect = CGRect(x: duckPt.x - 6, y: duckPt.y - 6, width: 12, height: 12)
        ctx.fill(Path(ellipseIn: dotRect), with: .color(Theme.actionPrimary))
        ctx.stroke(Path(ellipseIn: dotRect), with: .color(Theme.outline), lineWidth: 2)
    }

    // MARK: - Software HOLD & Safety Interlock Card

    private var holdAndSafetyCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Button {
                engageSoftwareHold(reason: "Operator pressed SOFTWARE HOLD button")
            } label: {
                Label(AutonomousMappingWords.holdButtonTitle, systemImage: "hand.raised.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: DesignMetric.movingTarget)
                    .background(Theme.stop, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: DesignMetric.outlineStroke))
            }
            .buttonStyle(.plain)

            if softwareHoldEngaged {
                Button(AutonomousMappingWords.holdReleaseTitle) {
                    softwareHoldEngaged = false
                    refreshPlanAndRecord(event: "software_hold_released")
                }
                .buttonStyle(.raisedAction)
            }

            Text(AutonomousMappingWords.holdSafetyNotice)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !healthVerdict.ok {
                Text(healthVerdict.reasons.joined(separator: " • "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.spacing(.standard))
        .pondPanel()
    }

    // MARK: - Conversational Goal Bar

    private var conversationalGoalCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Label("Conversational Exploration Goal", systemImage: "text.bubble.fill")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: Theme.spacing(.tight)) {
                TextField(AutonomousMappingWords.goalPlaceholder, text: $commandText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitCommand(commandText) }

                Button("Run") {
                    submitCommand(commandText)
                }
                .buttonStyle(.primaryActionInline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacing(.tight)) {
                    ForEach(AutonomousMappingWords.exampleCommands, id: \.self) { phrase in
                        Button {
                            commandText = phrase
                            submitCommand(phrase)
                        } label: {
                            Label(phrase, systemImage: phrase.lowercased().contains("stop") ? "stop.circle" : "sparkles")
                        }
                        .buttonStyle(.pondChip)
                    }
                }
            }

            if let outcome = lastOutcome {
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    HStack {
                        Text("Verdict: \(outcome.decision.rawValue)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(verdictColor(outcome.decision))
                        if let violator = outcome.gateViolator {
                            Text("(\(violator))")
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.refused)
                        }
                    }
                    Text(outcome.summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if outcome.requiresHumanApproval && trustTier == .atomic && !softwareHoldEngaged {
                        Button("Approve Bounded L1 Step") {
                            approveAtomicStep(for: outcome.rawCommand)
                        }
                        .buttonStyle(.primaryAction)
                    }
                }
                .padding(Theme.spacing(.snug))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: Theme.radius(.card), style: .continuous))
            }
        }
        .padding(Theme.spacing(.standard))
        .pondPanel()
    }

    // MARK: - Trust Ladder, Fault Test Toggles & Dual Recording

    private var trustAndRecordingCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Label("Trust Ladder & Dual Recording", systemImage: "shield.lefthalf.filled")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Picker("Trust Tier", selection: $trustTier) {
                ForEach(MappingTrustTier.allCases) { tier in
                    Text(tier.shortLabel).tag(tier)
                }
            }
            .pickerStyle(.segmented)

            Text(trustTier.plainEnglishDescription)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle("Dual Sim / Real SHA-256 Hash-Chained Recording", isOn: $dualRecordingEnabled)
                .tint(Theme.actionPrimary)

            HStack {
                Text("Receipts: \(receiptChain.records.count) · Head: \(String(receiptChain.headHash.prefix(12)))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.measured)
                Spacer()
                Button("Inspect Receipt") {
                    showReceiptSheet = true
                }
                .buttonStyle(.raisedAction)
            }

            if demoMode == .simulation {
                Divider()
                Text("Safe Sim Safety-Interlock Fault Drills")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: Theme.spacing(.tight)) {
                    Toggle("Batt < 7V", isOn: $simulateLowBattery)
                    Toggle("Tilt > 22°", isOn: $simulateHighTilt)
                    Toggle("Cam > 1.5s", isOn: $simulateStaleCamera)
                }
                .font(.caption)
                .toggleStyle(.switch)
                .tint(Theme.stop)
            }
        }
        .padding(Theme.spacing(.standard))
        .pondPanel()
    }

    // MARK: - Segmented Zones Summary

    private var zoneSummaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            Label("Segmented Rooms & Keep-Outs", systemImage: "square.split.2x2")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            ForEach(segmentation.zones) { zone in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(zone.roomLabel) (\(zone.zoneId))")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(String(format: "%.2f m² · %d frontier cells", zone.areaM2, zone.frontierCells))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text(String(format: "%.0f%%", zone.coveragePct))
                        .font(.footnote.monospacedDigit().weight(.bold))
                        .foregroundStyle(Theme.measured)
                }
                .padding(.vertical, 2)
            }

            ForEach(sim.mapper.keepoutZones) { kz in
                HStack {
                    Label("Keep-out: \(kz.name)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.refused)
                    Spacer()
                    Text("Envelope 0.2 DENY")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.refused)
                }
            }
        }
        .padding(Theme.spacing(.standard))
        .pondPanel()
    }

    // MARK: - Sheets (each wrapped with `.stopPill()`)

    private var infoSheetContent: some View {
        List {
            ForEach(Array(AutonomousMappingWords.infoSections.enumerated()), id: \.offset) { _, section in
                Section {
                    Text(section.body)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    SectionHeading(text: section.title)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(AutonomousMappingWords.infoSheetTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { showInfoSheet = false }
            }
        }
    }

    private var receiptSheetContent: some View {
        let bundle = receiptChain.exportBundle()
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                Text("Provenance: \(bundle.mode.badgeTitle)")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Chain Verified: \(bundle.chainVerified ? "PASS" : "FAIL") · Records: \(bundle.recordCount)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(bundle.chainVerified ? Theme.success : Theme.refused)
                Text("Bundle SHA-256:\n\(bundle.bundleSHA256)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.measured)
                Text(receiptChain.exportBundleJSON())
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }
            .padding(Theme.spacing(.standard))
        }
        .background(Theme.backgroundSecondary)
        .navigationTitle("SHA-256 Receipt Export")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { showReceiptSheet = false }
            }
        }
    }

    // MARK: - Actions

    private func engageSoftwareHold(reason: String) {
        softwareHoldEngaged = true
        DuckRuns.shared.stop()
        recordEvent(event: "software_hold", decision: .hold, gateViolator: "SOFTWARE_HOLD", details: ["reason": reason])
    }

    private func submitCommand(_ raw: String) {
        let outcome = ConversationalExplorationSkill.evaluate(
            command: raw,
            mapper: sim.mapper,
            pose: sim.pose,
            trustTier: trustTier,
            softwareHoldEngaged: softwareHoldEngaged,
            health: currentTelemetry,
            nowS: nil,
            humanApprovedAtomicStep: false
        )
        if case .hold = outcome.intent {
            softwareHoldEngaged = true
            DuckRuns.shared.stop()
        }
        lastOutcome = outcome
        if let plan = outcome.frontierPlan {
            latestPlan = plan
        }
        if outcome.motionPermitted, let target = outcome.targetPoint, demoMode == .simulation {
            sim.stepToward(target)
            latestPlan = sim.mapper.planNextFrontier(pose: sim.pose, health: currentTelemetry)
        }
        recordEvent(
            event: "conversational_goal",
            decision: outcome.decision,
            gateViolator: outcome.gateViolator,
            details: ["command": raw]
        )
    }

    private func approveAtomicStep(for raw: String) {
        let outcome = ConversationalExplorationSkill.evaluate(
            command: raw,
            mapper: sim.mapper,
            pose: sim.pose,
            trustTier: .atomic,
            softwareHoldEngaged: softwareHoldEngaged,
            health: currentTelemetry,
            nowS: nil,
            humanApprovedAtomicStep: true
        )
        lastOutcome = outcome
        if outcome.motionPermitted, let target = outcome.targetPoint, demoMode == .simulation {
            sim.stepToward(target)
            latestPlan = sim.mapper.planNextFrontier(pose: sim.pose, health: currentTelemetry)
        }
        recordEvent(
            event: "l1_atomic_approved_step",
            decision: outcome.decision,
            gateViolator: outcome.gateViolator,
            details: ["command": raw]
        )
    }

    private func stepSafeSimOnce() {
        let plan = sim.mapper.planNextFrontier(pose: sim.pose, health: currentTelemetry)
        latestPlan = plan
        if plan.decision == .allow, let target = plan.selectedFrontier?.target {
            sim.stepToward(target)
            latestPlan = sim.mapper.planNextFrontier(pose: sim.pose, health: currentTelemetry)
        }
        recordEvent(
            event: "sim_frontier_step",
            decision: plan.decision,
            gateViolator: plan.rejectedCandidates.first?.gateViolator
        )
    }

    private func refreshPlanAndRecord(event: String) {
        let plan = sim.mapper.planNextFrontier(pose: sim.pose, health: currentTelemetry)
        latestPlan = plan
        recordEvent(event: event, decision: plan.decision, gateViolator: plan.rejectedCandidates.first?.gateViolator)
    }

    private func recordEvent(
        event: String,
        decision: MappingDecision,
        gateViolator: String?,
        details: [String: String] = [:]
    ) {
        guard dualRecordingEnabled else { return }
        let iso = ISO8601DateFormatter().string(from: Date())
        receiptChain.append(
            event: event,
            decision: decision,
            pose: sim.pose,
            trustTier: trustTier,
            activeZoneId: latestPlan?.activeZoneId,
            coveragePct: segmentation.globalCoveragePct,
            telemetry: currentTelemetry,
            gateViolator: gateViolator,
            details: details,
            timestampISO: iso
        )
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }

    private func verdictColor(_ decision: MappingDecision) -> Color {
        switch decision {
        case .allow, .complete: return Theme.success
        case .deny: return Theme.stop
        case .hold: return Theme.warning
        }
    }
}

#Preview {
    NavigationStack {
        AutonomousMappingSkillView()
    }
}
