# Mimic — a person's pose on the duck

Studio > Author > **Mimic a person**, and the **Mimic** chip on the Control tab.

## What it does

A body-pose model on the phone reads a person as seventeen 3D joints. StudioKit
turns those into the five things the duck can act on and writes them as offsets
from the duck's home stance. The duck on the picture stands the way the person
stands; Record turns a run of poses into a motion draft like any other.

| Person                          | Duck joint(s)                         | Note |
|---------------------------------|---------------------------------------|------|
| thigh swung forward             | `*_hip_pitch`                         | gain 0.7 |
| knee bent                       | `*_knee`, and `*_ankle` = knee − hip  | ankle keeps the foot level |
| leg out to the side             | `*_hip_roll`                          | gain 0.7, outward on each side |
| head nod / turn / tilt          | `head_pitch` / `head_yaw` / `head_roll` | gain 1.0, neck stays home |
| higher hand above the shoulder  | `mouth`                               | the duck has no arms; 0 at shoulder height, 1 straight up |

Every sign was measured with `DuckKinematics` (foot and head sites read back
after moving one joint 0.3 rad from home) and is re-measured by
`PoseRetargetTests`, so it cannot drift from the robot model.

The person's own frame is built from their hips and spine — `left`, `up`,
`forward = left × up` — so the camera angle and the phone's orientation do not
matter. Handedness cannot be derived, which is what the **Mirror** switch is
for; it is on by default because a person facing a phone expects a mirror.

## Sources

- **Camera** — `AVCaptureSession`, upright and mirrored on the front camera.
  Needs the camera permission; does NOT need ARKit world tracking
  (`CameraAvailability.Dependent.mimic`).
- **A video** — Photos picker or Files; plays in an `AVPlayerViewController`
  with a video output read on a display link, so the frame read is the frame
  shown. Portrait recordings are read through the track's preferred transform.
- **YouTube** — the clip plays in YouTube's inline embed (`youtube-nocookie`)
  in a `WKWebView`; the phone reads its own screen with ReplayKit's in-app
  capture, cropped to the player's rectangle so the rendered duck below it is
  never read as a second person. iOS asks once. Nothing is downloaded.

Vision's `VNDetectHumanBodyPose3DRequest` runs one frame at a time on its own
queue and drops frames while busy; the rate it manages is printed.

## Recording

`MimicTrack`: one keyframe every 0.1 s, smoothed by half against the previous
keyframe, every joint slewed under 80 % of `IntentDraft.observedPeakJointRate`,
capped at 30 s (one batch `/perform` on a bench). The draft's provenance names
the source ("Mimicked from a YouTube clip").

## What is not built

- No live streaming of a pose to a robot. The live lane carries a twist;
  `robot.head` exists in `DuckMethod` but no bench answers it and no robot
  transport is wired. A mimicked pose reaches a bench the way every pose does:
  as a batch `/perform`.
- No ARKit `ARBodyTrackingConfiguration` path. Vision's 3D request covers all
  three sources with one pipeline and runs on every iOS 17 device.
- Nothing here has run on a device yet: Vision's coordinate handedness, the
  ReplayKit prompt flow, and the front-camera mirror are all compile-verified
  and kit-tested, not phone-tested. The first thing to check on a phone is
  that a raised RIGHT hand opens the beak while the duck's right side (screen
  right, mirrored) is the one that moves for a lifted right knee.
