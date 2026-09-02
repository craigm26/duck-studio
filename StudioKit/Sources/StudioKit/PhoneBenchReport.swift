import Foundation

/// Every sentence a person reads about the bench that is this phone.
///
/// WHY THERE IS A FILE FOR THIS AT ALL. This app has said, in comments, in
/// documentation and in shipped copy, that an iPhone has no physics engine —
/// enough times that it reads like a fact about the hardware. It is a fact
/// about a BUILD. MuJoCo has a WebAssembly target, the app now carries it, and
/// the same ten endpoints the Pi answers are answered here by a WebView on a
/// loopback port. Reversing a claim the app has made in eleven places is
/// exactly the moment to put the replacement sentences somewhere `swift test`
/// runs on Linux, because the failure mode of getting this wrong is not a
/// crash: it is a confident, wrong sentence about where a saved measurement
/// came from, kept forever beside the measurement.
///
/// WHAT IS KNOWN AND WHAT IS NOT, SAID HERE RATHER THAN DISCOVERED LATER.
/// Everything below about the physics is measured. Nothing below is measured on
/// an iPhone. The bench core owner ran the shell in Chromium on a Raspberry Pi
/// 5 and got a 2.7 ms control tick against a 20 ms budget; that is a desktop
/// browser on the machine that built it. So the speed sentence says it does not
/// know, and points at the number `/health` measures on whatever is actually
/// running — which is the only honest way to write it before somebody has held
/// a phone.
public enum PhoneBenchReport {

    // MARK: - what it is called

    /// The name in the bench list. NOT "This phone": the app ships to iPad as
    /// well, and a name that is wrong on one of two devices is worse than a
    /// name that is specific — but the iPad case is the smaller wrong and this
    /// is the word people use. Held here rather than typed into
    /// `BenchEndpoint.thisPhone` so it is one string and not two.
    public static let name = "This iPhone"

    // MARK: - the premise this replaces

    /// The correction, in one sentence, for anywhere the old claim is quoted.
    public static let premiseWasAboutABuild =
        "\"An iPhone has no physics engine\" was a claim about a build and not about the "
      + "hardware. MuJoCo has a WebAssembly target, this app carries it, and this bench is it."

    // MARK: - what is the same, and what is not

    /// THE CLAIM, AND IT IS ABOUT THE INTEGRATOR AND THE PLANT. Both halves are
    /// checkable: the `.wasm` in the app is byte-identical to the build the
    /// desk bench imports, and the plant is the same `scene.mjb`, digest and
    /// all, which `/health` prints on both machines so the two can be read
    /// against each other rather than taken on trust.
    public static let samePhysics =
        "The same physics the bench runs. MuJoCo 3.1.16 — the same build, byte for byte, as "
      + "the one the desk bench steps — over the same scene.mjb, whose digest both benches "
      + "print. This is that integrator rather than a preview of it."

    /// Ticks of the drift measurement, so a caller can restate it without
    /// retyping it and getting it wrong.
    public static let driftTicks = 250
    /// Millimetres of trunk position the two benches are apart after
    /// `driftTicks` of closed loop.
    public static let driftMillimetres = 32
    /// How far apart onnxruntime and duckkit's own forward pass are on a single
    /// action, over 42,000 compared values.
    public static let actionAgreement = 3.5e-6

    /// THE UNCOMFORTABLE HALF, SAID IN THE SAME BREATH AS THE CLAIM. Same
    /// physics is not same trajectory. The desk runs the network through
    /// onnxruntime and this runs it through duckkit's own four matrix
    /// multiplies over the canonical parameter bytes; they agree to 3.5e-6 on
    /// an action, and a closed loop is a chaotic amplifier that turns that into
    /// 32 mm of trunk in 250 ticks. Anybody comparing two recordings needs this
    /// sentence before they conclude one of the benches is broken.
    public static let notTheSameTrajectory =
        "It is not the same trajectory. The network here is run over duckkit's own parameter "
      + "bytes rather than by onnxruntime, and the two agree to 3.5e-6 on an action — which a "
      + "closed loop amplifies into 32 mm of trunk after 250 ticks. Counting outcomes carries "
      + "between the two benches. Comparing recorded frames does not."

    /// Said where a success rate is about to be compared with one from
    /// somewhere else.
    public static let measureTransfers =
        "A success rate measured here can be read against one from a bench on your network: "
      + "both count outcomes over randomised drops, and 32 mm of drift does not change whether "
      + "the duck was on its feet at the end."

    /// Said where a recording made here is about to be kept.
    public static let recordDoesNotTransfer =
        "A clip recorded here is this phone's run and not the desk bench's. The two are "
      + "identical for the first fifty ticks, 2 mm apart by a hundred and 32 mm apart by two "
      + "hundred and fifty — so this is a second run rather than a second copy of one, and "
      + "putting the two side by side compares two runs."

    // MARK: - what it cannot do

    /// WHAT THIS BENCH REFUSES IS A FILE, NOT A NETWORK — AND THE FIRST
    /// VERSION OF THIS SENTENCE GOT THAT WRONG.
    ///
    /// It read "This bench cannot be handed a network", which is what the
    /// shell's own comment says about `/upload` and is a fair description of
    /// the endpoint's intent. It is not what the endpoint does. `makeSession`
    /// in `duckbench-web.mjs` checks one thing — that the body is exactly
    /// `FLOAT_COUNT * 4` bytes — and hands everything that passes to
    /// `policyforward.mjs`, which reads `DuckPolicy.canonicalParameterBytes`.
    /// That is the same layout `DuckEvidence` fingerprints a policy by and the
    /// same layout this app already exports to serve the shell its nine
    /// bundled networks. So a network this app can LOAD, it can put on this
    /// bench; what it cannot put there is a file, because there is no ONNX
    /// reader and deliberately so.
    ///
    /// MEASURED, not reasoned: against the shipped `site/phonebench` build,
    /// a 791,584-byte canonical-bytes body was accepted as
    /// `uploaded-27b1f53d1f26`, `/policy` swapped to it, and `/measure` ran
    /// three six-second rollouts on it. An ONNX body to the same endpoint came
    /// back refused. The claim this app had been making was one experiment
    /// away from being checked, and had not been checked.
    ///
    /// WHY THE DISTINCTION IS WORTH A PARAGRAPH RATHER THAN A SHRUG. It is the
    /// difference between a phone that can only replay what shipped with it and
    /// one that can run something it just made — a blend, or a tuned fold. The
    /// old sentence closed a door that was open.
    public static let uploadNotWired =
        "This bench will not take a policy FILE. It has no ONNX reader of its own — a second "
      + "reader would be a second opinion about what is in a policy — so an .onnx has to go to "
      + "a bench on your network. A network this app has already loaded is a different matter: "
      + "it runs the same parameter bytes the fingerprint is taken over, and those it accepts."

    /// Said where a network made ON this phone is about to be run on it.
    public static let parametersAreWhatItTakes =
        "A policy this app made — a blend, or a tuned fold — goes onto this bench as the "
      + "parameter bytes its fingerprint is taken over, not as a file. That is the same "
      + "arrangement the nine bundled networks already use, so what runs here is exactly what "
      + "the library screen inspected."

    /// WHAT IS NOT KNOWN, IN THE PLACE SOMEBODY WOULD OTHERWISE ASSUME IT. A
    /// number measured in Chromium on a Raspberry Pi is not a claim about
    /// Safari on a phone, and quoting it as though it were is the exact kind of
    /// inherited prose this file exists to stop.
    ///
    /// A RANGE AND NOT A FIGURE, BECAUSE THERE ARE TWO MEASUREMENTS AND THEY
    /// DISAGREE. The bench core owner measured 2.7 ms in headed Chromium on a
    /// Raspberry Pi 5; serving this app's own bundled folder to headless
    /// Chromium on the same machine measured 3.50 ms. Two runs of the same
    /// browser on the same hardware are 30% apart, which is the strongest
    /// available argument that neither of them is a fact about an iPhone.
    public static let speedIsUnmeasuredOnAPhone =
        "How fast this is on this phone has not been measured. A desktop browser on the machine "
      + "that built it does a control tick in 2.7 to 3.5 ms against a 20 ms budget, and two runs "
      + "on that one machine are a third apart — which is Chromium on a Raspberry Pi either way, "
      + "not Safari on an iPhone. The bench times its own tick when it starts and reports it; "
      + "that number is the one to read."

    // MARK: - when it is not there

    /// Before the listener has a port.
    ///
    /// A REAL STATE AND NOT AN ERROR. The bench is a WebView the app brings up
    /// at launch, and the port comes from the kernel at bind time, so there is
    /// a moment after opening the app when there is genuinely nothing to talk
    /// to. Saying that is better than an empty list, and much better than the
    /// address parser's "127.0.0.1:0 is not on your network".
    public static let notListening =
        "This phone's bench is still coming up. It runs inside the app and answers on a port "
      + "the system hands out at launch, so there is a moment after opening where there is "
      + "nothing yet to ask. It arrives on its own."

    /// The WebView's content process was killed under it.
    ///
    /// THE SENTENCE THAT MUST NOT BE OPTIMISTIC. iOS ends that process when it
    /// wants the memory, and everything in it goes: the duck's pose, the loaded
    /// policy, and any rollouts that were part-way through. An app that quietly
    /// reloaded and carried on would hand somebody a half-finished measurement
    /// as though it were a result — which is the failure this whole project is
    /// built against. So the loss is stated, the in-flight work is called not a
    /// result, and the rebuild is mentioned last.
    public static let worldLost =
        "This phone's bench lost its world. iOS ended the process the physics was running in — "
      + "usually to take back memory — so the duck's pose, the loaded policy and anything "
      + "part-way through are gone. Whatever was being measured did not finish and is not a "
      + "result. The bench is being rebuilt now."

    // MARK: - the list it sits at the top of

    /// The bench list's own explanation, replacing the empty state that used to
    /// say a phone cannot run anything.
    public static let alwaysOneBench =
        "There is always one bench: this phone. It is first in the list, it cannot be edited "
      + "or deleted, and it wants no token — there is nothing to type, because the physics "
      + "runs inside the app. Add a machine on your network for a second bench that can be "
      + "handed a network of its own — how the two compare in speed has not been measured."

    /// Under the phone's row.
    public static let phoneRowNote =
        "Runs inside the app. Nothing to set up and nothing saved — the port it answers on is "
      + "different every launch."

    // MARK: - what a bench says about the machine it is

    /// Said when a bench will not name its machine.
    public static let unstatedHost =
        "This bench does not say which machine ran the physics, so a result kept from it names "
      + "no hardware."

    /// Where the physics ran, as the bench itself reported it.
    ///
    /// EVERY BRANCH NAMES SOMETHING THE BENCH SAID. `kind` is the only field
    /// worth branching on and it is Optional, because a bench is allowed to
    /// answer with a third word — and a third word must read as "this app does
    /// not know that one" rather than be rounded to whichever case is nearer.
    /// The device and engine strings are never interpreted, only quoted: they
    /// are a user agent and a library list, and this file has no business
    /// deciding what they mean.
    public static func ranOn(_ host: DuckBench.Health.Host?) -> String {
        guard let host else { return unstatedHost }
        let machine: String
        switch host.kind {
        case .phone: machine = "on this phone"
        case .desk:  machine = "on a machine across the network"
        case nil:
            machine = host.kindSaid.isEmpty
                ? "on a machine it did not name"
                : "on something it calls \"\(host.kindSaid)\", which this app has no word for"
        }
        let device = host.device.isEmpty ? "an unnamed device" : host.device
        let engine = host.engine.isEmpty ? "an unnamed engine" : host.engine
        let tick = host.tickMillis.map { "One control tick cost \(milliseconds($0)) there, "
                                       + "measured when it started." }
            ?? "It did not measure what a tick costs there."
        return "Ran \(machine): \(device), \(engine). \(tick)"
    }

    /// A duration in milliseconds, to two figures after the point.
    ///
    /// FORMATTED IN ONE PLACE because it appears in a sentence a person keeps.
    /// Two decimals is what separates 2.70 ms from 27.0 ms at a glance, and
    /// the unit is spelled out rather than left to a suffix somebody has to
    /// infer.
    static func milliseconds(_ value: Double) -> String {
        String(format: "%.2f ms", value)
    }
}
