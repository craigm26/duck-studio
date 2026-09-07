import SwiftUI
import AVFoundation
import StudioKit

/// The Control tab's Mimic bar: what replaces the pose bar while the duck on
/// the picture is standing the way the person in front of the camera stands.
///
/// THE CAMERA IS THE ONLY SOURCE HERE, ON PURPOSE. A video or a YouTube clip
/// needs a player on the screen, and this screen's whole subject is the duck
/// being driven; a player over it would be the build-41 overlay again, with a
/// video in it. The bar says where the other two sources are and opens
/// Studio to them. What it keeps is a thumbnail — small enough to confirm the
/// camera can see you, not big enough to be the picture.
///
/// EVERY DOOR OUT OF IT IS A DOOR THE POSE SHELF ALREADY HAD. Hold it on the
/// bench is `holdThePose`; keep is `keepThePose` for a single stance or the
/// recorded track for a run; run it here is `runMotion` on the draft that was
/// just kept. Nothing new is sent to a bench by this bar, and `mimicSaid` says
/// so beside the thumbnail.
struct MimicBar: View {
    @ObservedObject var engine: PoseCaptureEngine
    let door: CameraAvailability
    let benchIsHere: Bool
    let busy: Bool
    /// The name of the draft the last recording was kept as, when it was.
    let keptName: String?
    let note: String?

    let flip: () -> Void
    let hold: () -> Void
    let keep: () -> Void
    let runIt: () -> Void
    let openStudio: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
            HStack(alignment: .top, spacing: Theme.spacing(.snug)) {
                if door.canOffer(.mimic) {
                    CameraPreview(session: engine.cameraSession)
                        // The thumbnail is decoration for a screen reader;
                        // the status line beside it says what it shows.
                        .accessibilityHidden(true)
                        .frame(width: MimicMetric.thumbWidth, height: MimicMetric.thumbHeight)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius(MimicMetric.thumb),
                                                    style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Button(action: flip) {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.caption)
                                    .padding(Theme.spacing(.hairline))
                                    .background(Theme.surfacePrimary, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(Theme.spacing(.hairline))
                            .accessibilityLabel(Text(Mimic.flipCamera))
                        }
                }
                VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                    HStack(spacing: Theme.spacing(.tight)) {
                        Circle()
                            .fill(engine.personInView ? Theme.robotActive : Theme.robotOffline)
                            .frame(width: Theme.spacing(.tight), height: Theme.spacing(.tight))
                            .accessibilityHidden(true)
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button(Mimic.done, action: done)
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.actionSecondary)
                            .frame(minHeight: DesignMetric.minimumTarget)
                    }
                    if let refusal = door.refusal(for: .mimic) {
                        Text(refusal)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let reading = engine.reading {
                        Text(PoseRetarget.readingLine(reading))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(ControlShelf.mimicSaid)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            controls
            Text(Mimic.videoAndYouTubeAreInStudio)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spacing(.snug))
    }

    private var status: String {
        if let note { return note }
        if engine.isRecording {
            return MimicTrack.recordingSaid(seconds: engine.track.seconds, keys: engine.track.keyCount)
        }
        if engine.stoppedAtCap { return MimicTrack.stoppedAtTheCap }
        if engine.personInView { return Mimic.tracking(posesPerSecond: engine.posesPerSecond) }
        guard door.canOffer(.mimic) else { return CameraAvailability.Dependent.mimic.title }
        if engine.framesPerSecond == 0 { return Mimic.noFramesYet(.camera) }
        if engine.personSeen { return Mimic.personSeenNotRead }
        return Mimic.noPersonYet
    }

    /// Record, hold, keep, run — in a row that wraps at accessibility sizes.
    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacing(.tight)) {
                if door.canOffer(.mimic) {
                    if engine.isRecording {
                        Button(Mimic.stop) { engine.stopRecording() }
                            .buttonStyle(.primaryAction)
                    } else {
                        Button(engine.track.isEmpty ? Mimic.record : Mimic.recordAgain) {
                            engine.startRecording()
                        }
                        .buttonStyle(.primaryAction)
                        .disabled(engine.duckPose == nil)
                    }
                    Button(ControlShelf.holdIt, action: hold)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.actionSecondary)
                        .frame(minHeight: DesignMetric.minimumTarget)
                        .disabled(busy || !benchIsHere || engine.isRecording)
                    if keptName == nil {
                        Button(ControlShelf.keepItAsAMotion, action: keep)
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.actionSecondary)
                            .frame(minHeight: DesignMetric.minimumTarget)
                            .disabled(engine.isRecording || engine.duckPose == nil)
                    } else {
                        Button(ControlShelf.runItHere, action: runIt)
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.actionSecondary)
                            .frame(minHeight: DesignMetric.minimumTarget)
                            .disabled(busy || !benchIsHere)
                    }
                }
                Button(Mimic.openStudio, action: openStudio)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.actionSecondary)
                    .frame(minHeight: DesignMetric.minimumTarget)
            }
        }
    }
}

private enum MimicMetric {
    /// The thumbnail: a portrait card the size of two rows, which is enough to
    /// see that a whole person is in shot and not enough to be the picture.
    static let thumbWidth: CGFloat = 72
    static let thumbHeight: CGFloat = 96
    static let thumb = Palette.Radius.control
}
