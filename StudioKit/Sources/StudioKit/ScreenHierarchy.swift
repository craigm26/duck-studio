import Foundation

/// The app's screen tree as data: what ships today, and what build 91 builds.
///
/// docs/plans/native-first-redesign.md, "The screen hierarchy", asks for a
/// table a Linux test can pin. `today` is the tree read off the app at main
/// dfdf49a (DuckStudioApp.swift's five tabs and the top level of DriveView,
/// LearnView, PolicyListView, StudioHubView and MyMicroduckView). `target` is
/// the plan's tree. `shipped` names the one the app draws; build 91 flips it to
/// `target`, and the test that lists `differences(from: today, to: target)`
/// flips with it.
///
/// THE TREE IS A MAP, NOT THE NAVIGATION. Nothing routes through it. It
/// exists so that a screen moving is a diff a test can see.
public enum ScreenHierarchy {

    /// The plan's tags. A node of `today` carries none.
    public enum Change: String, Sendable, CaseIterable {
        case keep, merge, down, cut, new
    }

    public struct Node: Equatable, Sendable, Identifiable {
        /// Unique across the whole tree.
        public let id: String
        public let title: String
        public let change: Change?
        /// The app file the screen lives in today, where there is one.
        public let source: String?
        public let children: [Node]

        public init(_ id: String, _ title: String, _ change: Change? = nil,
                    source: String? = nil, _ children: [Node] = []) {
            self.id = id; self.title = title; self.change = change
            self.source = source; self.children = children
        }

        /// This node and every node under it, depth first.
        public var flattened: [Node] { [self] + children.flatMap(\.flattened) }
    }

    public struct Tab: Equatable, Sendable, Identifiable {
        /// The `AppTab` raw value, which is also what `-tab` accepts.
        public let id: String
        public let title: String
        /// Older `-tab` names that still reach this tab.
        public let aliases: [String]
        /// The app file that draws the tab's root.
        public let source: String?
        public let sections: [Node]

        public init(_ id: String, _ title: String, aliases: [String] = [], source: String? = nil,
                    _ sections: [Node]) {
            self.id = id; self.title = title; self.aliases = aliases
            self.source = source; self.sections = sections
        }
    }

    public struct Tree: Equatable, Sendable {
        public let name: String
        /// In tab-bar order; the index is the position.
        public let tabs: [Tab]
        /// The tab the app opens on.
        public let opensOn: String
        /// Sheets that are not inside one tab.
        public let sheets: [Node]

        public var allNodes: [Node] {
            tabs.flatMap { $0.sections.flatMap(\.flattened) } + sheets.flatMap(\.flattened)
        }

        /// Every app file the tree names, tabs included.
        public var sources: Set<String> {
            Set(tabs.compactMap(\.source) + allNodes.compactMap(\.source))
        }

        public func tab(_ name: String) -> Tab? {
            tabs.first { $0.id == name || $0.aliases.contains(name) }
        }
    }

    /// The tree the app draws. Build 91 flipped this from `today` to `target`.
    public static var shipped: Tree { target }

    // MARK: Launching on a tab

    /// What a `-tab` launch argument opens.
    public struct Launch: Equatable, Sendable {
        /// A tab id of the tree.
        public let tab: String
        /// `-tab duck` opens Play with the Duck sheet up.
        public let duckSheet: Bool
        /// A node id inside the tab to open on, or nil for the tab's top: `-tab learn` opens
        /// Studio on Learn, `-tab behaviours` on Behaviours (build 93).
        public var section: String? = nil
    }

    /// The old tab names that now live as a section of another tab, and the section's node id.
    public static let legacySections: [String: String] = [
        "learn": "studio.learn",
        "behaviours": "studio.behaviours",
    ]

    /// The five-tab layout's indices past the end of today's three, and the tab each now opens:
    /// 3 Moves, 4 Studio, so an old screenshot script lands somewhere real rather than on Play.
    public static let legacyIndices: [Int: String] = [3: "moves", 4: "studio"]

    /// `-tab N` by index into the tree's tabs, or `-tab name` by id or old name, so
    /// `-tab control` and `-tab learn` keep working. Anything else opens the tab the app opens
    /// on: a screenshot run that shoots the first tab is better than one that fails.
    public static func launch(_ asked: String?, in tree: Tree = shipped) -> Launch {
        let home = Launch(tab: tree.opensOn, duckSheet: false)
        guard let asked = asked?.trimmingCharacters(in: .whitespaces), !asked.isEmpty else { return home }
        if let n = Int(asked) {
            if tree.tabs.indices.contains(n) { return Launch(tab: tree.tabs[n].id, duckSheet: false) }
            if let id = legacyIndices[n], tree.tab(id) != nil { return Launch(tab: id, duckSheet: false) }
            return home
        }
        guard let tab = tree.tab(asked) else { return home }
        let section = legacySections[asked].flatMap { id in
            tab.sections.flatMap(\.flattened).contains { $0.id == id } ? id : nil
        }
        return Launch(tab: tab.id, duckSheet: asked == "duck" && tab.id != "duck", section: section)
    }

    // MARK: Inventory

    /// Every feature the app has, and its one home in `target` (a node id). Bench's only home is
    /// Measure. A Swift dictionary cannot hold a feature twice, so "exactly one home" is the
    /// type's; the test checks each home exists.
    public static let inventory: [String: String] = [
        "Stop": "play.stop",
        "Link lens": "play.pill",
        "Venue choice": "duckSheet.yourDuck",
        "Sticks": "play.stick",
        "Face buttons": "play.buttons",
        "Head mode": "play.head",
        "Pose": "play.pose",
        "Talk to the duck": "play.tell.typed",
        "Plan from the controller": "play.tell.plan",
        "Watch for cards": "play.tell.cards",
        "Dream-1": "play.auto",
        "Phone driver": "play.auto",
        "Scene picker": "play.more.scene",
        "Record a sequence": "play.more.record",
        "Pad map": "play.more.padMap",
        "Stage camera": "play.more.camera",
        "Readout": "play.readout",
        "Imports": "moves.sequences",
        "Robot skills": "moves.skills",
        "Sound playback": "moves.sounds",
        "Saved sequences": "moves.sequences",
        "Saved plans": "moves.plans",
        "Cards and Packs": "moves.cards",
        "Games": "moves.games",
        "Goals": "moves.goals",
        "Expert tools switch": "studio.expert",
        "Motions": "studio.make.motions",
        "Plan editor": "studio.make.plan",
        "Draft with words": "studio.make.draft",
        "Scenes": "studio.make.scenes",
        "Sequence management": "studio.make.sequences",
        "Sound editor": "studio.make.sounds",
        "Mimic": "studio.make.mimic",
        "Behaviours library": "studio.behaviours.library",
        "Retrain": "studio.behaviours.library",
        "Catalogue": "studio.behaviours.catalogue",
        "Community": "studio.behaviours.community",
        "Blend": "studio.behaviours.blend",
        "Publish": "studio.behaviours.publish",
        "Hugging Face training": "studio.train.hub",
        "Compare": "studio.train.compare",
        "Train a duck to shoot": "studio.train.shoot",
        "Tune": "studio.train.tune",
        "Weight search": "studio.train.weights",
        "Move search": "studio.train.moves",
        "Drivers": "studio.train.drivers",
        "Challenges": "studio.measure.challenges",
        "Evaluations": "studio.measure.evaluations",
        "Bench": "studio.measure.benches",
        "Run on your network": "studio.measure.network",
        "Quick actions": "studio.measure.load",
        "Multi-duck": "studio.measure.multi",
        "Ghost duck": "studio.measure.ghost",
        "Lessons": "studio.learn",
        "Settings": "studio.settings",
        "Dream key": "studio.settings",
        "Model endpoints": "studio.settings",
        "Welcome": "welcome",
        "Find a duck": "welcome.find",
        "Camera": "duckSheet.camera",
        "Pollen's app": "duckSheet.pollen",
        "Bridge": "duckSheet.connection",
        "Robot details": "duckSheet.details",
        "Room capture": "duckSheet.room",
        "Siri and Shortcuts": "duckSheet.siri",
        "Machines": "duckSheet.expert",
        "Remote": "duckSheet.expert",
        "Diagnostics": "duckSheet.expert",
        "Moves sheet": "play.movesSheet",
        "More sheet": "play.more",
        "Second Stop": "play.secondStop",
        "Mode switch": "play.modes",
        "Local Network prompt": "welcome.find",
        "Say hi": "welcome.sayHi",
        "Stand up": "welcome.standUp",
        "Add your duck": "duckSheet.add",
        "Behaviour links out": "studio.behaviours.links",
    ]

    /// Why the inventory is not one home per feature; empty when it is. Each home must be a
    /// node of `tree`, and no feature may be listed twice under names that differ only in case
    /// or spacing (a dictionary only stops exact repeats).
    public static func inventoryProblems(in tree: Tree = target) -> [String] {
        let ids = Set(tree.allNodes.map(\.id))
        var out: [String] = []
        var seen: [String: String] = [:]
        for (feature, home) in inventory.sorted(by: { $0.key < $1.key }) {
            if !ids.contains(home) { out.append("\(feature) -> \(home) is not a node") }
            let folded = feature.lowercased().filter { !$0.isWhitespace }
            if let other = seen[folded] { out.append("\(feature) and \(other) are one feature twice") }
            seen[folded] = feature
        }
        return out
    }

    // MARK: Tap counts

    /// One row of the plan's tap-count table, re-measured against the inventory.
    public struct TapCount: Equatable, Sendable {
        public let task: String
        public let today: String
        public let target: String
        /// The tree path the target is measured on, as node ids, first tap first. Empty for
        /// "0 taps".
        public let path: [String]

        public init(_ task: String, today: String, target: String, path: [String]) {
            self.task = task; self.today = today; self.target = target; self.path = path
        }

        /// The row as the plan writes it, so a test can find it in the checked-in document.
        public var markdownRow: String { "| \(task) | \(today) | \(target) |" }
    }

    /// The plan's table, checked in with it (docs/plans/native-first-redesign.md, "The screen
    /// hierarchy", exit check). The path is what a tap lands on in `target`.
    public static let tapCounts: [TapCount] = [
        TapCount("Drive the real duck", today: "4+ taps plus typing", target: "0 taps after onboarding",
                 path: []),
        TapCount("A game", today: "3 taps", target: "1 tap (Moves, then tile)",
                 path: ["moves.games"]),
        TapCount("Say it on the real duck", today: "impossible", target: "1 press",
                 path: ["play.buttons"]),
        TapCount("A skill on the real duck", today: "not offered", target: "1 tap",
                 path: ["moves.skills"]),
    ]

    // MARK: Today (main dfdf49a)

    public static let today = Tree(
        name: "today",
        tabs: [
            Tab("control", "Play", source: "DriveView.swift", [
                Node("control.venue", "Venue switch: Sim, Your floor, Robot", source: "DriveView.swift"),
                Node("control.stage", "Stage", source: "DriveView.swift", [
                    Node("control.stage.sim", "Sim stage", source: "DriveView.swift"),
                    Node("control.stage.floor", "Your floor", source: "ARDriveStage.swift"),
                    Node("control.stage.robot", "Robot venue list: camera, driving, head, console",
                         source: "DriveView.swift"),
                ]),
                Node("control.lens", "Link lens", source: "DriveView.swift"),
                Node("control.settings", "Settings", source: "SettingsView.swift"),
                Node("control.pad", "Sticks and face buttons", source: "PadChrome.swift"),
                Node("control.shelf", "Shelf chips: Pose, Scene, Mimic, Dream, Record, Sequences, Plan",
                     source: "ControlShelfChips.swift"),
                Node("control.talk", "Talk to the duck", source: "TalkToTheDuckView.swift"),
                Node("control.drawer", "Play drawer: layers, pad rest, Stop and Reset, pad map, controller",
                     source: "DriveView.swift"),
                Node("control.pose", "Pose bar", source: "DriveView.swift"),
                Node("control.mimic", "Mimic bar", source: "MimicChrome.swift"),
            ]),
            Tab("learn", "Learn", source: "LearnView.swift", [
                Node("learn.lessons", "Lessons", source: "LearnView.swift",
                     Learn.lessons.map { Node("learn.lessons.\($0.id)", $0.title) }),
            ]),
            Tab("behaviours", "Behaviours", source: "PolicyListView.swift", [
                Node("behaviours.installed", "Installed", source: "PolicyListView.swift"),
                Node("behaviours.retrain", "Retrain", source: "PolicyListView.swift"),
                Node("behaviours.discover", "Discover", source: "PolicyListView.swift", [
                    Node("behaviours.discover.catalogue", "Catalogue", source: "CatalogueView.swift"),
                    Node("behaviours.discover.community", "Community", source: "CommunityPoliciesView.swift"),
                ]),
                Node("behaviours.blend", "Blend", source: "PolicyBlendView.swift"),
                Node("behaviours.settings", "Settings", source: "SettingsView.swift"),
            ]),
            Tab("studio", "Studio", source: "StudioHubView.swift", [
                Node("studio.play", "Play", source: "StudioHubView.swift", [
                    Node("studio.play.shoot", "Train a duck to shoot", source: "ShootLabView.swift"),
                    Node("studio.play.lab", "Lab modes (games and Ghost duck)", source: "StudioHubView.swift"),
                ]),
                Node("studio.make", "Make", source: "StudioHubView.swift", [
                    Node("studio.make.motions", "Motions", source: "IntentListView.swift"),
                    Node("studio.make.scenes", "Scenes", source: "SceneEditorView.swift"),
                    Node("studio.make.draft", "Draft with words", source: "AutomationChatView.swift"),
                    Node("studio.make.plan", "Plan with words", source: "PlanEditorView.swift"),
                    Node("studio.make.mimic", "Mimic a person", source: "PoseCaptureView.swift"),
                    Node("studio.make.compare", "Compare", source: "CompareViews.swift"),
                ]),
                Node("studio.train", "Train and measure", source: "StudioHubView.swift", [
                    Node("studio.train.network", "Run on your network", source: "RemoteRunView.swift"),
                    Node("studio.train.tune", "Tune it", source: "TuneView.swift"),
                    Node("studio.train.weights", "Search its weights", source: "WeightSearchView.swift"),
                    Node("studio.train.hub", "Train a network on Hugging Face", source: "HubTrainingView.swift"),
                    Node("studio.train.moves", "Search a move's keyframes", source: "MoveSearchView.swift"),
                    Node("studio.train.challenges", "Challenges", source: "ChallengeListView.swift"),
                    Node("studio.train.evaluations", "Run a formal evaluation", source: "EvalListView.swift"),
                    Node("studio.train.multi", "Compare on two ducks", source: "MultiDuckView.swift"),
                ]),
                Node("studio.tools", "Tools row (Simple), sends to Learn", source: "StudioHubView.swift"),
                Node("studio.settings", "Settings", source: "SettingsView.swift"),
            ]),
            Tab("duck", "My Microduck", source: "MyMicroduckView.swift", [
                Node("duck.banner", "Banner", source: "MyMicroduckView.swift"),
                Node("duck.device", "Duck", source: "MyMicroduckView.swift"),
                Node("duck.quick", "Quick actions", source: "MyMicroduckView.swift"),
                Node("duck.robot", "Robot", source: "MyMicroduckView.swift", [
                    Node("duck.robot.bridge", "Bridge", source: "RobotBridgeView.swift"),
                    Node("duck.robot.find", "Find a duck", source: "FindDuckView.swift"),
                    Node("duck.robot.details", "Robot details", source: "RobotView.swift"),
                ]),
                Node("duck.machines", "Machines", source: "MyMicroduckView.swift"),
                Node("duck.remote", "Remote", source: "MyMicroduckView.swift"),
                Node("duck.bench", "Bench", source: "BenchSettingsView.swift"),
                Node("duck.camera", "Camera", source: "DuckCameraView.swift"),
                Node("duck.connection", "Connection", source: "PairingSpikeView.swift"),
                Node("duck.settings", "Settings", source: "SettingsView.swift"),
            ]),
        ],
        opensOn: "control",
        sheets: [
            Node("firstRun", "First run: three cards", source: "FirstRunView.swift"),
        ])

    // MARK: Target (build 91)

    public static let target = Tree(
        name: "target",
        tabs: [
            Tab("play", "Play", aliases: ["control", "duck"], source: "DriveView.swift", [
                Node("play.stage", "Stage", .keep, source: "DriveView.swift", [
                    Node("play.stage.sim", "Sim stage", .keep),
                    Node("play.stage.floor", "Your floor", .keep, source: "ARDriveStage.swift"),
                    Node("play.stage.real", "Real duck picture", .merge, source: "DuckCameraView.swift"),
                    Node("play.stage.poster", "No picture yet", .new),
                ]),
                Node("play.pill", "Duck pill", .new, source: "ControllerView.swift"),
                Node("play.modes", "Mode switch: Drive, Tell, Auto", .new, source: "ControllerView.swift"),
                Node("play.stop", "Stop", .new, source: "StopPill.swift"),
                Node("play.stick", "Stick", .keep, source: "PadChrome.swift"),
                Node("play.buttons", "Move buttons and mic", .new),
                Node("play.head", "Head drag", .merge),
                Node("play.secondStop", "Take over while Auto runs", .new),
                Node("play.readout", "Readout chip", .new),
                Node("play.movesSheet", "Moves sheet", .new),
                Node("play.pose", "Pose", .keep, source: "JointHandleOverlay.swift"),
                Node("play.tell", "Tell", .keep, [
                    Node("play.tell.typed", "Typed field", .keep, source: "TalkToTheDuckView.swift"),
                    Node("play.tell.plan", "Plan", .keep, source: "PlanEditorView.swift"),
                    Node("play.tell.cards", "Watch for cards", .merge, source: "DuckCardsViews.swift"),
                ]),
                Node("play.auto", "Auto: Ask the duck, other helpers beside it", .merge, source: "ControllerView.swift"),
                Node("play.more", "More", .new, [
                    Node("play.more.scene", "Scene", .down),
                    Node("play.more.record", "Record a sequence", .down, source: "SequenceKeepSheet.swift"),
                    Node("play.more.padMap", "Pad map", .down, source: "PadMapSection.swift"),
                    Node("play.more.camera", "Camera view", .down),
                ]),
            ]),
            Tab("moves", "Moves", source: "MovesView.swift", [
                Node("moves.skills", "Skills", .new),
                Node("moves.sounds", "Sounds", .merge, source: "DuckSoundsView.swift"),
                Node("moves.sequences", "My sequences", .merge, source: "SequenceListView.swift"),
                Node("moves.plans", "My plans", .merge),
                Node("moves.cards", "Cards and Packs", .merge, source: "DuckPacksViews.swift"),
                Node("moves.games", "Games", .merge, source: "GhostDuckView.swift"),
                Node("moves.goals", "Goals", .new),
            ]),
            Tab("studio", "Studio", aliases: ["learn", "behaviours"], source: "StudioHubView.swift", [
                Node("studio.expert", "Show expert tools", .new),
                Node("studio.make", "Make", .keep, [
                    Node("studio.make.motions", "Motions", .keep, source: "IntentListView.swift"),
                    Node("studio.make.plan", "Plan editor", .keep, source: "PlanEditorView.swift"),
                    Node("studio.make.draft", "Draft with words", .keep, source: "AutomationChatView.swift"),
                    Node("studio.make.scenes", "Scenes", .keep, source: "SceneEditorView.swift"),
                    Node("studio.make.sequences", "Sequences", .keep, source: "SequenceListView.swift"),
                    Node("studio.make.sounds", "Duck sounds", .keep, source: "DuckSoundsView.swift"),
                    Node("studio.make.mimic", "Mimic, Mac only", .keep, source: "PoseCaptureView.swift"),
                ]),
                Node("studio.behaviours", "Behaviours", .down, source: "PolicyListView.swift", [
                    Node("studio.behaviours.library", "Library", .down),
                    Node("studio.behaviours.catalogue", "Catalogue", .down, source: "CatalogueView.swift"),
                    Node("studio.behaviours.community", "Community", .down, source: "CommunityPoliciesView.swift"),
                    Node("studio.behaviours.blend", "Blend", .down, source: "PolicyBlendView.swift"),
                    Node("studio.behaviours.publish", "Publish and Share", .down, source: "PublishPolicyView.swift"),
                    Node("studio.behaviours.links", "Links out", .new),
                ]),
                Node("studio.train", "Train", .down, [
                    Node("studio.train.hub", "Hugging Face training", .down, source: "HubTrainingView.swift"),
                    Node("studio.train.compare", "Compare", .down, source: "CompareViews.swift"),
                    Node("studio.train.shoot", "Train a duck to shoot", .down, source: "ShootLabView.swift"),
                    Node("studio.train.tune", "Tune", .down, source: "TuneView.swift"),
                    Node("studio.train.weights", "Weight search", .down, source: "WeightSearchView.swift"),
                    Node("studio.train.moves", "Move search", .down, source: "MoveSearchView.swift"),
                    Node("studio.train.drivers", "Drivers", .new),
                ]),
                Node("studio.measure", "Measure", .down, [
                    Node("studio.measure.challenges", "Challenges", .down, source: "ChallengeListView.swift"),
                    Node("studio.measure.evaluations", "Evaluations", .down, source: "EvalListView.swift"),
                    Node("studio.measure.benches", "Benches", .down, source: "BenchSettingsView.swift"),
                    Node("studio.measure.network", "Run on your network", .down, source: "RemoteRunView.swift"),
                    Node("studio.measure.load", "Load a behaviour on a bench", .down),
                    Node("studio.measure.multi", "Multi-duck", .down, source: "MultiDuckView.swift"),
                    Node("studio.measure.ghost", "Ghost duck", .down, source: "GhostDuckView.swift"),
                ]),
                Node("studio.learn", "Learn", .down, source: "LearnView.swift"),
                Node("studio.settings", "Settings", .keep, source: "SettingsView.swift"),
            ]),
        ],
        opensOn: "play",
        sheets: [
            Node("welcome", "Welcome", .new, [
                Node("welcome.haveDuck", "Do you have a Microduck?", .new),
                Node("welcome.wifi", "Is it on your Wi-Fi?", .new),
                Node("welcome.find", "Find it", .merge, source: "FindDuckView.swift"),
                Node("welcome.sayHi", "Say hi", .new),
                Node("welcome.standUp", "Stand up", .new),
            ]),
            Node("duckSheet", "Duck sheet", .new, [
                Node("duckSheet.yourDuck", "Your duck", .merge, source: "MyMicroduckView.swift"),
                Node("duckSheet.camera", "Camera", .merge, source: "DuckCameraView.swift"),
                Node("duckSheet.pollen", "Open Pollen's app", .new),
                Node("duckSheet.connection", "Connection", .merge, source: "RobotBridgeView.swift"),
                Node("duckSheet.details", "Robot details", .merge, source: "RobotView.swift"),
                Node("duckSheet.room", "Your room", .down, source: "RoomCaptureView.swift"),
                Node("duckSheet.siri", "Siri and Shortcuts", .new),
                Node("duckSheet.add", "Add your duck", .new),
                Node("duckSheet.expert", "Expert", .down, source: "PairingSpikeView.swift"),
            ]),
        ])

    /// Today's screens with no home in `target`, and why. Everything else
    /// `today` names keeps a place.
    public static let retired: [String: String] = [
        "ControlShelfChips.swift": "The mode switch replaces the shelf chips.",
        "MimicChrome.swift": "Mimic leaves the phone; on a Mac it stays in Studio, Make.",
        "FirstRunView.swift": "The welcome sheet replaces the three cards.",
    ]

    // MARK: Checks

    /// Why `tree` is not well formed; empty when it is.
    public static func problems(_ tree: Tree) -> [String] {
        var out: [String] = []
        let tagged = tree.name != "today"
        if tree.tabs.isEmpty { out.append("no tabs") }
        if tree.tab(tree.opensOn)?.id != tree.opensOn { out.append("opens on \(tree.opensOn), not a tab") }
        var names = Set<String>()
        for tab in tree.tabs {
            for name in [tab.id] + tab.aliases where !names.insert(name).inserted {
                out.append("tab name \(name) used twice")
            }
            if tab.title.isEmpty { out.append("tab \(tab.id) has no title") }
            if tab.sections.isEmpty { out.append("tab \(tab.id) has no sections") }
        }
        var ids = Set<String>()
        for node in tree.allNodes {
            if !ids.insert(node.id).inserted { out.append("node \(node.id) used twice") }
            if node.title.trimmingCharacters(in: .whitespaces).isEmpty { out.append("node \(node.id) has no title") }
            if node.title.contains("\u{2014}") { out.append("node \(node.id) has an em-dash") }
            if tagged && node.change == nil { out.append("node \(node.id) has no tag") }
            if !tagged && node.change != nil { out.append("node \(node.id) is tagged in today's tree") }
            if node.change == .cut { out.append("node \(node.id) is cut but still in the tree") }
            if let s = node.source, !s.hasSuffix(".swift") { out.append("node \(node.id) source \(s)") }
        }
        return out
    }

    // MARK: Differences

    public enum Difference: Equatable, Sendable, CustomStringConvertible {
        case tabAdded(String)
        case tabRemoved(String)
        /// The old id is an alias of the new tab.
        case tabRenamed(from: String, to: String)
        case tabMoved(String, from: Int, to: Int)
        case opensOn(from: String, to: String)
        case sectionAdded(tab: String, String)
        case sectionRemoved(tab: String, String)
        case sheetAdded(String)
        case sheetRemoved(String)

        public var description: String {
            switch self {
            case .tabAdded(let t): return "+tab \(t)"
            case .tabRemoved(let t): return "-tab \(t)"
            case .tabRenamed(let a, let b): return "tab \(a) -> \(b)"
            case .tabMoved(let t, let a, let b): return "tab \(t) \(a) -> \(b)"
            case .opensOn(let a, let b): return "opens on \(a) -> \(b)"
            case .sectionAdded(let t, let s): return "+\(t): \(s)"
            case .sectionRemoved(let t, let s): return "-\(t): \(s)"
            case .sheetAdded(let s): return "+sheet \(s)"
            case .sheetRemoved(let s): return "-sheet \(s)"
            }
        }
    }

    /// What changes from `old` to `new`, at the level of tabs, their
    /// top-level sections (by title) and sheets. A tab whose old id is an
    /// alias of a new tab is the same tab, renamed.
    public static func differences(from old: Tree, to new: Tree) -> [Difference] {
        var out: [Difference] = []
        let oldOpens = old.tab(old.opensOn)?.id ?? old.opensOn
        if new.tab(oldOpens)?.id != new.opensOn {
            out.append(.opensOn(from: old.opensOn, to: new.opensOn))
        }
        // Same id first, then an alias, each new tab taken once: an old tab
        // folded into a new tab that already has its own old self is removed,
        // not renamed.
        var pair: [String: Tab] = [:]
        var matched = Set<String>()
        for was in old.tabs {
            if let now = new.tabs.first(where: { $0.id == was.id }) {
                pair[was.id] = now; matched.insert(now.id)
            }
        }
        for was in old.tabs where pair[was.id] == nil {
            if let now = new.tabs.first(where: { $0.aliases.contains(was.id) && !matched.contains($0.id) }) {
                pair[was.id] = now; matched.insert(now.id)
            }
        }
        for (i, was) in old.tabs.enumerated() {
            guard let now = pair[was.id] else { out.append(.tabRemoved(was.id)); continue }
            if now.id != was.id { out.append(.tabRenamed(from: was.id, to: now.id)) }
            let j = new.tabs.firstIndex(of: now)!
            if i != j { out.append(.tabMoved(now.id, from: i, to: j)) }
            let before = was.sections.map(\.title), after = now.sections.map(\.title)
            out += before.filter { !after.contains($0) }.map { .sectionRemoved(tab: now.id, $0) }
            out += after.filter { !before.contains($0) }.map { .sectionAdded(tab: now.id, $0) }
        }
        out += new.tabs.filter { !matched.contains($0.id) }.map { .tabAdded($0.id) }
        let oldSheets = old.sheets.map(\.id), newSheets = new.sheets.map(\.id)
        out += oldSheets.filter { !newSheets.contains($0) }.map { .sheetRemoved($0) }
        out += newSheets.filter { !oldSheets.contains($0) }.map { .sheetAdded($0) }
        return out
    }
}
