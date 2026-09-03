import SwiftUI
import DuckKit
import StudioKit

/// Grab the duck by a joint and move it.
///
/// WHY THIS IS A SWIFTUI SIBLING AND NOT A REALITYKIT ENTITY. The stage already
/// owns three recognisers — pan to orbit, pinch to zoom, double-tap to reset —
/// and they are attached to the `ARView` itself. Handles built as entities and
/// hit-tested with `entity(at:)` would have to share those recognisers, which
/// means every one of them learns about handles and the orbit gesture starts
/// asking whether the finger landed on a joint. Drawn as a layer ABOVE the
/// stage in the same `ZStack`, a touch that lands on a handle never reaches the
/// ARView at all and a touch that misses one falls straight through to it,
/// because a `ZStack` does not hit-test its own empty space. Nothing in
/// `DuckStage` changed to make this work.
///
/// NOTHING HERE IS GEOMETRY. Every position on screen arrives already projected
/// (`StageProjections`, computed in the stage's frame callback from the one
/// legal conversion), every target that is drawn is chosen by
/// `JointHandles.place`, every drag becomes an angle in
/// `JointHandles.dragged`, and every sentence is a `JointHandles` string. What
/// this file decides is which pixels a finger can hit and what colour they are.
///
/// THE GAIN IS TAKEN ONCE AND HELD; THE DIRECTION FOLLOWS THE LEVER.
/// `JointHandles.grab` turns three projected points into a direction and a
/// gain, and both depend on where the camera is. Re-deriving the gain mid-drag
/// would make a joint accelerate under a thumb that is moving steadily, which
/// reads as the app fighting you, so the gain is captured on the first tick.
/// The direction is not: a joint that has swung a long way has its lever
/// pointing somewhere else on screen than when the finger came down, and a
/// drag that kept the first direction would stop tracking the thumb. Each
/// tick applies only its own movement, to the angle the joint is at now.
struct JointHandleOverlay: View {

    /// Every grabbable joint at the pose on screen, from the kit.
    let handles: [JointHandles.Handle]
    /// Where they landed this frame.
    let projections: StageProjections
    /// The joints of the group the chips row has chosen. Only these are drawn.
    let drawn: Set<Int>
    /// FALSE WHEN THE PLAYHEAD IS BETWEEN KEYFRAMES. The pose on screen is
    /// interpolated then, so there is nothing under the handle to write to.
    let editable: Bool
    /// The joint whose slider row is selected below.
    let focused: Int?
    /// Whether the floating label is drawn ON the duck.
    ///
    /// FALSE WHERE THE HOST HAS SOMEWHERE BETTER FOR IT. The pill is a card
    /// about 150 by 120 points and it is placed against the target, so on the
    /// Control tab — where the joints being posed are the head and the neck,
    /// at the top of a duck drawn small — it covered the very part somebody
    /// was moving. A screen that draws the name, the angle and a slider of its
    /// own passes false and gets a bare ring on the joint.
    var showsLabel = true

    /// The joint whose label a long press pinned up.
    @Binding var pinned: Int?
    /// The cluster target that has been opened out into a list.
    @Binding var opened: Int?
    /// Why the last drag was turned away, in the kit's own words.
    @Binding var refusal: String?
    /// The joints this frame's placement dropped, reported up so the screen can
    /// COUNT them. It used to drop them and say nothing: a joint whose box
    /// crossed the edge appeared in neither the drawn targets nor any cluster,
    /// and the only way to find out was to notice a handle you expected was not
    /// there.
    @Binding var offPicture: [Int]

    /// Select a joint: focus it and bring its slider into view.
    let select: (Int) -> Void
    /// Write an angle into the keyframe being edited.
    let write: (Int, Double) -> Void
    /// Put the playhead back on the keyframe being edited.
    let goToEditingKeyframe: () -> Void

    /// The joint under the finger and the law its drag is following.
    @State private var dragging: Dragging?

    private struct Dragging {
        /// The joint under the finger.
        let joint: Int
        /// Where its pivot was when the finger came down. The drag ends if
        /// that moves: only the camera moves a pivot, and the finger did not
        /// aim from there.
        let pivot: JointHandles.ScreenPoint
        /// The law the last tick followed; its gain is kept, its direction
        /// refreshed from where the lever is now.
        var law: JointHandles.Grab
        /// The finger's translation at the last tick, so each tick applies
        /// only its own movement.
        var lastTranslation: CGSize
    }

    var body: some View {
        GeometryReader { proxy in
            let out = placed(in: proxy.size)
            let targets = out.kept
            ZStack(alignment: .topLeading) {
                // REPORTED FROM A `.task`, NOT FROM THE BODY. Writing state
                // while a view is being evaluated is the "Modifying state
                // during view update" warning and an undefined pass; an id'd
                // task runs after it, once per distinct answer.
                Color.clear
                    .frame(width: 0, height: 0)
                    .task(id: out.offPicture) { offPicture = out.offPicture }
                // A CLEAR SHEET UNDER AN OPENED LIST. A tap anywhere that is
                // not a name closes the list; without it the list stays up
                // until a name is chosen, over the targets it is hiding.
                if opened != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { opened = nil }
                }
                ForEach(targets) { target in
                    marker(target, in: proxy.size)
                        .position(x: CGFloat(target.at.x), y: CGFloat(target.at.y))
                }
                // DRAWN LAST SO IT IS ON TOP. An opened cluster is a menu over
                // the stage, and a menu that renders under the targets it is
                // offering is a menu nobody can use.
                if let opened, let target = targets.first(where: { $0.joint == opened }),
                   target.count > 1 {
                    spread(target)
                        .position(x: CGFloat(target.at.x), y: CGFloat(target.at.y))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // THE HANDLES GO INERT TOGETHER, not one at a time. Between keyframes
        // every one of them would be writing to a pose that is not stored
        // anywhere, so they are dimmed as a set and the notice below says why
        // and offers the one move that fixes it.
        .allowsHitTesting(editable)
        .opacity(editable ? 1 : OverlayMetric.betweenKeyframes)
        .overlay(alignment: .bottom) { notice }
        // THE REFUSAL FOLLOWS THE CAMERA. An edge-on handle is edge-on from
        // one viewpoint; once an orbit has given it a lever, the sentence that
        // said it had none is wrong and goes.
        .onChange(of: focusedIsEdgeOn) { _, edgeOn in
            if !edgeOn, refusal == JointHandles.edgeOnSaid { refusal = nil }
        }
    }

    // MARK: - which targets are drawn

    /// The targets, folded so no two are closer than a fingertip.
    ///
    /// THE FOCUSED JOINT GOES FIRST, WHICH IS HOW A FOLDED ONE IS REACHED.
    /// `place` gives the spot to whichever joint arrives first and folds the
    /// rest into it, so putting the selected joint at the head of the list
    /// makes it the one that is drawn and draggable — and choosing a joint out
    /// of an opened cluster is therefore the whole of "spread them".
    ///
    /// AND NOTHING IS DRAWN OFF THE PICTURE. A target whose centre is past
    /// the stage's edge is a target half of which cannot be hit; the kit
    /// keeps only those that sit whole inside it.
    private func placed(in size: CGSize)
        -> (kept: [JointHandles.Placed], offPicture: [Int]) {
        var seen = projections.handles.filter { drawn.contains($0.joint) }
        if let focused, let index = seen.firstIndex(where: { $0.joint == focused }) {
            seen.insert(seen.remove(at: index), at: 0)
        }
        return JointHandles.placed(
            seen.map { (joint: $0.joint, at: $0.grip, depth: $0.depth) },
            trunkDepth: projections.trunkDepth,
            minimumSeparation: Double(DesignMetric.minimumTarget),
            within: Double(size.width), Double(size.height),
            inset: Double(DesignMetric.minimumTarget / 2),
            // THE BAND THE CAMERA'S BUTTONS STAND IN. A handle under a button is
            // a handle nobody can press — the button takes the touch — so it is
            // named off the picture rather than drawn under one.
            reservingTrailing: StageViewport.Chrome.column.footprint)
    }

    /// The drag law a joint would follow from where the camera is now.
    private func law(for joint: Int) -> JointHandles.Grab? {
        guard let handle = handles.first(where: { $0.joint == joint }),
              let seen = projections.handles.first(where: { $0.joint == joint })
        else { return nil }
        return JointHandles.grab(handle: handle, pivot: seen.pivot,
                                 grip: seen.grip, swung: seen.swung)
    }

    private var focusedIsEdgeOn: Bool {
        guard let focused else { return false }
        return law(for: focused) == .edgeOn
    }

    @ViewBuilder private func marker(_ target: JointHandles.Placed,
                                     in glass: CGSize) -> some View {
        if target.count > 1 && target.joint != focused {
            cluster(target)
        } else {
            handle(target, in: glass)
        }
    }

    // MARK: - one joint

    @ViewBuilder private func handle(_ target: JointHandles.Placed,
                                     in glass: CGSize) -> some View {
        let width = Double(glass.width)
        let above = label(above: target, in: Double(glass.height))
        let control = JointControl(index: target.joint)
        let angle = handles.first { $0.joint == target.joint }?.angle ?? control.home
        let edgeOn = law(for: target.joint) == .edgeOn
        JointNode(load: atAStop(target.joint) ? 1 : 0, label: control.plainName)
            // THE NODE'S OWN VOICE IS TURNED OFF AND THE TARGET SPEAKS INSTEAD.
            // `JointNode` announces a LOAD, which is a fact about a robot that
            // is holding something up. Nothing is holding anything up here: this
            // is a pose being written, and what a person needs read back is the
            // joint's name and the angle it is at.
            .accessibilityHidden(true)
            .opacity(target.behind ? OverlayMetric.behind : 1)
            .frame(width: DesignMetric.minimumTarget, height: DesignMetric.minimumTarget)
            // EDGE-ON IS DRAWN, NOT DISCOVERED. A handle whose lever points at
            // the camera is marked before anybody drags it, so the drag that
            // would be refused is one nobody starts.
            .overlay { if edgeOn { edgeMark } }
            .overlay { if target.joint == focused { ring } }
            .contentShape(Circle())
            .overlay(alignment: above ? Alignment.top : Alignment.bottom) {
                if showsLabel,
                   pinned == target.joint || (pinned == nil && focused == target.joint) {
                    pill(control, angle: angle, folded: target)
                        .offset(x: pillShift(target, width: width),
                                y: above ? -OverlayMetric.labelStandoff
                                         : OverlayMetric.labelStandoff)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(control.plainName))
            .accessibilityValue(Text(control.spoken(at: angle)))
            .accessibilityAction(named: Text(JointHandles.homeActionSaid)) {
                snapHome(target.joint)
            }
            .onTapGesture {
                pinned = nil
                refusal = nil
                // A SECOND TAP ON A JOINT THAT IS SITTING ON OTHERS SPREADS
                // THEM. The pill's "4 joints here" line was the only way in,
                // and a host that draws no pill would have had none — the
                // folded joints would be unreachable without orbiting the
                // stage. The first tap still just selects.
                if focused == target.joint, target.count > 1 {
                    opened = target.joint
                } else {
                    opened = nil
                    select(target.joint)
                }
            }
            // SIMULTANEOUS, so a press that turns into a drag does both — the
            // label stays up while the joint moves, which is the one moment a
            // person most wants to read the degrees. `LongPressGesture` gives up
            // on its own once the finger has travelled, so a fast drag never
            // pins anything.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: OverlayMetric.pressToPin)
                    .onEnded { _ in
                        pinned = target.joint
                        select(target.joint)
                    })
            .gesture(drag(target))
    }

    /// The selection ring. A SHAPE AND NOT A HUE ALONE: which joint is selected
    /// is the fact this overlay is most often read for, and a target
    /// distinguished only by colour is one a colour-blind reader cannot find.
    ///
    /// AND A HALO UNDER IT. The ring sits over a live render, so on its own it
    /// has whatever contrast the frame behind it happens to have; the ground
    /// colour drawn a little wider underneath keeps it readable over a dark
    /// duck and a bright step alike.
    private var ring: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.surfacePrimary,
                              lineWidth: OverlayMetric.ringStroke + 2 * OverlayMetric.ringHalo)
                .padding(OverlayMetric.ringInset - OverlayMetric.ringHalo)
            Circle()
                .strokeBorder(Theme.focus, lineWidth: OverlayMetric.ringStroke)
                .padding(OverlayMetric.ringInset)
        }
    }

    /// A bar across the target: this lever is pointing at the camera, and a
    /// drag on it has nowhere to go until the stage is orbited.
    private var edgeMark: some View {
        Capsule()
            .fill(Theme.textSecondary)
            .frame(width: OverlayMetric.edgeMarkLength, height: OverlayMetric.edgeMarkStroke)
            .rotationEffect(.degrees(OverlayMetric.edgeMarkTilt))
            .allowsHitTesting(false)
    }

    /// How far the label slides sideways to stay on the stage. It is centred
    /// on its target, so a target near either edge would put half of it off
    /// the picture.
    private func pillShift(_ target: JointHandles.Placed, width: Double) -> CGFloat {
        let half = Double(OverlayMetric.pillWidth / 2)
        let inset = Double(DesignMetric.minimumTarget / 2)
        let left = target.at.x - half
        let right = target.at.x + half
        if left < inset { return CGFloat(inset - left) }
        if width > 0, right > width - inset { return CGFloat(width - inset - right) }
        return 0
    }

    private func drag(_ target: JointHandles.Placed) -> some Gesture {
        DragGesture(minimumDistance: OverlayMetric.dragBegins)
            .onChanged { move in
                // `@State` is not readable back in the pass that wrote it, so
                // the fresh state is used from the local rather than from
                // `dragging`.
                var live: Dragging
                if let dragging {
                    live = dragging
                } else if let started = begin(target) {
                    live = started
                } else {
                    return
                }
                guard let handle = handles.first(where: { $0.joint == live.joint }),
                      let seen = projections.handles.first(where: { $0.joint == live.joint })
                else {
                    dragging = nil
                    return
                }
                // THE DRAG ENDS WHEN THE PIVOT MOVES. The finger is still on
                // the glass, but the camera is no longer where it aimed from.
                guard !JointHandles.pivotMoved(from: live.pivot, to: seen.pivot) else {
                    dragging = nil
                    return
                }
                live.law = JointHandles.grab(handle: handle, pivot: seen.pivot,
                                             grip: seen.grip, swung: seen.swung,
                                             keepingGainOf: live.law)
                let dx = Double(move.translation.width - live.lastTranslation.width)
                let dy = Double(move.translation.height - live.lastTranslation.height)
                live.lastTranslation = move.translation
                dragging = live
                if case .draggable = live.law {
                    refusal = nil
                    write(live.joint, JointHandles.dragged(handle: handle, grab: live.law,
                                                           dx: dx, dy: dy))
                } else if refusal == nil {
                    refusal = JointHandles.edgeOnSaid
                }
            }
            .onEnded { _ in dragging = nil }
    }

    /// Take hold: work out the drag law from the three points this frame put on
    /// screen, and say so if the answer is that there is no honest one.
    private func begin(_ target: JointHandles.Placed) -> Dragging? {
        guard let handle = handles.first(where: { $0.joint == target.joint }),
              let seen = projections.handles.first(where: { $0.joint == target.joint })
        else { return nil }
        let law = JointHandles.grab(handle: handle, pivot: seen.pivot,
                                    grip: seen.grip, swung: seen.swung)
        select(target.joint)
        // A REFUSAL IS A SENTENCE, NOT A DEAD TARGET. The handle still selects,
        // the slider row below still moves the joint, and the sentence says
        // which camera move brings the handle back.
        if case .edgeOn = law { refusal = JointHandles.edgeOnSaid } else { refusal = nil }
        return Dragging(joint: target.joint, pivot: seen.pivot, law: law, lastTranslation: .zero)
    }

    private func snapHome(_ joint: Int) {
        select(joint)
        write(joint, JointControl(index: joint).home)
    }

    /// Whether this joint has run out of travel. A COMPARISON, NOT A FRACTION:
    /// the node's size says "this will not go further", which is the one thing
    /// about a joint's range a person cannot see on the duck.
    private func atAStop(_ joint: Int) -> Bool {
        guard let handle = handles.first(where: { $0.joint == joint }) else { return false }
        return handle.angle <= handle.lower || handle.angle >= handle.upper
    }

    // MARK: - the label

    /// The label goes ABOVE the target unless the target is near the top of the
    /// stage, where above is off the picture.
    private func label(above target: JointHandles.Placed, in height: Double) -> Bool {
        target.at.y > OverlayMetric.labelFlipsFraction * height
    }

    private func pill(_ control: JointControl, angle: Double,
                      folded target: JointHandles.Placed) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Text(control.plainName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(control.spoken(at: angle))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            // HOME IS A WORD ON THE LABEL, NOT A DOUBLE TAP. A double tap on a
            // target that also single-taps and drags is a gesture nobody
            // discovers and one SwiftUI resolves late; a word on the pill is
            // found the first time the pill is read.
            Button { snapHome(target.joint) } label: {
                Text(JointHandles.homeActionSaid)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.actionSecondary)
                    .frame(minHeight: DesignMetric.minimumTarget, alignment: .leading)
            }
            // THE WAY BACK TO THE JOINTS THIS ONE IS SITTING ON TOP OF. Once a
            // folded joint has been chosen it becomes the target and the others
            // disappear under it; without this line they would be unreachable
            // until somebody orbited the stage.
            if target.count > 1 {
                Button {
                    opened = target.joint
                } label: {
                    Text(JointHandles.clusterSaid(target.count))
                        .font(.caption2)
                        .foregroundStyle(Theme.actionSecondary)
                        .frame(minHeight: DesignMetric.minimumTarget, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, Theme.spacing(.tight))
        .padding(.vertical, Theme.spacing(.hairline))
        .background(card)
        .fixedSize()
        .accessibilityHidden(true)
    }

    // MARK: - several joints at one spot

    /// A target standing for a handful of joints that projected on top of each
    /// other. THE COUNT IS THE WHOLE LABEL: a sentence will not fit in a
    /// forty-four point circle, so the sentence is what VoiceOver reads and what
    /// the pill offers once one of them is chosen.
    private func cluster(_ target: JointHandles.Placed) -> some View {
        Button {
            pinned = nil
            refusal = nil
            opened = target.joint
        } label: {
            Text("\(target.count)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .frame(width: DesignMetric.minimumTarget, height: DesignMetric.minimumTarget)
                .background(Circle().fill(Theme.surfacePrimary))
                .overlay(Circle().strokeBorder(Theme.separator,
                                               lineWidth: DesignMetric.hairlineStroke))
                .opacity(target.behind ? OverlayMetric.behind : 1)
        }
        .accessibilityLabel(Text(JointHandles.clusterSaid(target.count)))
    }

    /// The folded joints, spread out as a list.
    ///
    /// A LIST AND NOT A FAN. Spreading targets apart on the picture means
    /// inventing screen positions for joints that are genuinely at the same
    /// place, and a fan of six circles round a hip is six targets none of which
    /// is where the joint is. Names in a column are unambiguous, hit the
    /// forty-four point floor without arithmetic, and read aloud.
    private func spread(_ target: JointHandles.Placed) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([target.joint] + target.clustered, id: \.self) { joint in
                Button {
                    opened = nil
                    select(joint)
                } label: {
                    Text(JointControl(index: joint).plainName)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.spacing(.tight))
                        .frame(minHeight: DesignMetric.minimumTarget)
                }
            }
        }
        .background(card)
        .fixedSize()
    }

    // MARK: - what the stage says when a handle cannot work

    @ViewBuilder private var notice: some View {
        if !editable {
            // A NOT-YET WITH THE MOVE THAT ENDS IT ON IT. The handles are inert
            // because the pose under them is interpolated, and the one thing
            // that fixes that is putting the playhead back on the keyframe being
            // edited — so the sentence is the button.
            Button { goToEditingKeyframe() } label: {
                Label(JointHandles.betweenKeyframesSaid, systemImage: "arrow.uturn.left")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.spacing(.tight))
                    .background(card)
            }
            .padding(Theme.spacing(.tight))
        } else if let refusal {
            Label(refusal, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Theme.warning)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.spacing(.tight))
                .background(card)
                .padding(Theme.spacing(.tight))
        }
        // THE OFF-PICTURE COUNT IS NOT A THIRD BRANCH HERE, AND THE PLAN ASKED
        // FOR ONE. §C.5 has it both in this notice and in the editor's group
        // capsule, which would draw one tested kit sentence twice on one stage —
        // the duplication this project's own rules exist to prevent. It is drawn
        // once, in the capsule, top-leading beside the caption that says which
        // group's handles these are: that is where somebody is already reading
        // about which handles exist, it is a small card rather than a full-width
        // one over the duck's feet, and it is visible even while the two
        // branches above are showing a refusal. Recorded in the build log.
    }

    /// The ground every floating piece of text on this overlay sits on.
    ///
    /// OPAQUE, FOR THE REASON THE LEGEND WAS. Words laid straight over a live
    /// render have whatever contrast happens to be behind them that frame — a
    /// bright floor tile, a dark duck, a yellow step lip. `Theme.surfacePrimary`
    /// is one of the four grounds the palette proves every ink against.
    private var card: some View {
        RoundedRectangle(cornerRadius: Theme.radius(OverlayMetric.card), style: .continuous)
            .fill(Theme.surfacePrimary)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius(OverlayMetric.card),
                                 style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: DesignMetric.hairlineStroke))
    }
}

// MARK: - the numbers this layer picks for itself

/// Judgements about a phone, not facts about a robot — the split `StageMetric`
/// and `AuthoringMetric` already make, in the same shape.
private enum OverlayMetric {
    /// A joint further from the camera than the trunk. Dimmed, still tappable —
    /// there is no occlusion test here and there should not be one: the duck is
    /// not opaque enough for it to be worth a frame, and a handle you can see
    /// through the body is a handle you can still aim at.
    static let behind = 0.45

    /// The whole layer, while the playhead is between keyframes.
    static let betweenKeyframes = 0.5

    /// How far a finger has to travel before it is a drag rather than a tap.
    /// Six points is under the long press's own ten, so a press that slides a
    /// little still pins the label instead of being lost between the two.
    static let dragBegins: CGFloat = 6

    /// How long a press has to be held to pin the label up.
    static let pressToPin = 0.4

    /// The selection ring, and the ground-coloured halo drawn under it.
    static let ringStroke: CGFloat = 2
    static let ringInset: CGFloat = 3
    static let ringHalo: CGFloat = 1.5

    /// The bar across an edge-on target.
    static let edgeMarkLength: CGFloat = 22
    static let edgeMarkStroke: CGFloat = 3
    static let edgeMarkTilt = -45.0

    /// How wide the label is taken to be when it is kept on the stage.
    ///
    /// AN UPPER BOUND, NOT THE WIDTH. The label sizes itself from a name, a
    /// reading and up to two buttons; this is what `pillShift` assumes when it
    /// slides one back onto the picture, and `pillShift` clamps against the
    /// stage's real width, so a label narrower than this is shifted no further
    /// than it needs. The old comment called it "the width a name and a reading
    /// fill", which reads as a measurement of something and is not one.
    static let pillWidth: CGFloat = 150

    /// How far the label sits off its target.
    static let labelStandoff: CGFloat = 8

    /// How far down the stage the label flips from below its target to above it,
    /// AS A FRACTION OF THE STAGE.
    ///
    /// IT WAS AN ABSOLUTE EIGHTY POINTS, and eighty points meant "the top
    /// quarter or so" only while every stage in this app was three hundred tall.
    /// On the editor's grown picture — 534 points, and more on an iPad — eighty
    /// points is the top seventh, so a handle a fifth of the way down got a
    /// label above it that ran off the picture the rule exists to keep it on.
    /// Written as the fraction the number always meant.
    static let labelFlipsFraction = 80.0 / 300.0

    /// The floating card's corner. A card over a render, so `.card` — the same
    /// radius the legend's panel took when it was there.
    static let card = Palette.Radius.card
}
