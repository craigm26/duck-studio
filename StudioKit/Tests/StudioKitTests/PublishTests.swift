import XCTest
import DuckKit
@testable import StudioKit

/// Publishing: what gets built, and what must never be in it.
final class PublishTests: XCTestCase {

    /// The sentence every published move now has to carry.
    private static let whenToUse = "When somebody says hello and you want to greet them back."

    private func draft() -> IntentDraft {
        IntentDraft(name: "little bow", keys: [
            .init(time: 0, pose: DuckModel.homePose),
            .init(time: 0.6, pose: {
                var p = DuckModel.homePose
                p[DuckModel.jointIndex(of: "neck_pitch")!] += 0.4
                return p
            }()),
            .init(time: 1.2, pose: DuckModel.homePose),
        ], provenance: "Authored by hand in Duck Studio.")
    }

    // MARK: - the credential

    /// THE TEST THIS FILE EXISTS FOR. A write token in a URL ends up in logs
    /// and in the address this app prints on screen before asking permission.
    func testNoConstructedCallCanCarryTheToken() throws {
        let token = "hf_averysecrettokenvalue0000"
        let repository = try HuggingFacePublish.repository(namespace: "someone", name: "bow",
                                                           kind: .dataset)
        let calls = [
            HuggingFacePublish.whoami(),
            HuggingFacePublish.create(repository),
            try HuggingFacePublish.commit(repository, summary: "s",
                                          files: [.init(path: "a.txt",
                                                        contents: Data("hello".utf8), isText: true)]),
        ]
        for call in calls {
            XCTAssertFalse(call.displayURL.contains(token))
            XCTAssertFalse(call.displayURL.contains("hf_"))
            XCTAssertFalse(String(describing: call).contains(token))
            if let body = call.body {
                XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(token))
            }
        }
        // And the one place it IS attached puts it in a header, not the URL.
        let request = HuggingFacePublish.urlRequest(for: calls[0], token: token)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertFalse(request.url!.absoluteString.contains(token))
    }

    func testTheTokenIsTrimmedBecausePasteBringsWhitespace() {
        let request = HuggingFacePublish.urlRequest(for: HuggingFacePublish.whoami(),
                                                    token: "  hf_abc\n")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer hf_abc")
    }

    // MARK: - addresses and names

    func testTheAddressesMatchHuggingFacesAPI() throws {
        let repository = try HuggingFacePublish.repository(namespace: "someone", name: "little-bow",
                                                           kind: .dataset)
        XCTAssertEqual(HuggingFacePublish.whoami().displayURL,
                       "https://huggingface.co/api/whoami-v2")
        XCTAssertEqual(HuggingFacePublish.create(repository).displayURL,
                       "https://huggingface.co/api/repos/create")
        let commit = try HuggingFacePublish.commit(repository, summary: "s",
                                                   files: [.init(path: "a", contents: Data("x".utf8),
                                                                 isText: true)])
        XCTAssertEqual(commit.displayURL,
                       "https://huggingface.co/api/datasets/someone/little-bow/commit/main")
        XCTAssertEqual(repository.webURL, "https://huggingface.co/datasets/someone/little-bow")
    }

    /// Creating either kind is the SAME address — there is no
    /// `/api/datasets/create` — and only the body's `type` differs. Committing
    /// is the opposite: same body, different address.
    func testOnlyTheCommitAddressAndTheCreateBodyTellTheTwoKindsApart() throws {
        let asModel = try HuggingFacePublish.repository(namespace: "someone", name: "bow",
                                                        kind: .model)
        let asDataset = try HuggingFacePublish.repository(namespace: "someone", name: "bow",
                                                          kind: .dataset)
        XCTAssertEqual(HuggingFacePublish.create(asModel).displayURL,
                       HuggingFacePublish.create(asDataset).displayURL,
                       "one endpoint creates both kinds")
        func type(of repository: HuggingFacePublish.Repository) throws -> String? {
            let body = try XCTUnwrap(HuggingFacePublish.create(repository).body)
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            return json["type"] as? String
        }
        XCTAssertEqual(try type(of: asModel), "model")
        XCTAssertEqual(try type(of: asDataset), "dataset")

        let file = [HuggingFacePublish.File(path: "a", contents: Data("x".utf8), isText: true)]
        XCTAssertEqual(try HuggingFacePublish.commit(asModel, summary: "s", files: file).displayURL,
                       "https://huggingface.co/api/models/someone/bow/commit/main")
        XCTAssertEqual(try HuggingFacePublish.commit(asDataset, summary: "s", files: file).displayURL,
                       "https://huggingface.co/api/datasets/someone/bow/commit/main")
    }

    /// THE PREFIX IS NOT COSMETIC. `huggingface.co/<ns>/<name>` for a dataset
    /// does not 404 when a model of that name exists — it silently resolves to
    /// the model. An address shown to somebody after publishing a move would
    /// then open a real page describing a different artifact.
    func testADatasetsWebAddressCarriesTheDatasetsPrefix() throws {
        let asDataset = try HuggingFacePublish.repository(namespace: "someone", name: "bow",
                                                          kind: .dataset)
        let asModel = try HuggingFacePublish.repository(namespace: "someone", name: "bow",
                                                        kind: .model)
        XCTAssertEqual(asDataset.webURL, "https://huggingface.co/datasets/someone/bow")
        XCTAssertEqual(asModel.webURL, "https://huggingface.co/someone/bow")
        XCTAssertNotEqual(asDataset.webURL, asModel.webURL)
    }

    func testBadRepositoryNamesAreRefusedBeforeATokenIsSpent() {
        for (namespace, name, expected) in [
            ("someone", "", HuggingFacePublish.Refusal.emptyName),
            ("", "bow", .noNamespace),
            ("someone", "a bow", .badName("a bow")),
            ("someone", "bow!", .badName("bow!")),
            ("someone", "-bow", .badName("-bow")),
            ("someone", "bow.", .badName("bow.")),
            ("someone", String(repeating: "a", count: 97), .tooLong(String(repeating: "a", count: 97))),
        ] {
            XCTAssertThrowsError(try HuggingFacePublish.repository(namespace: namespace, name: name,
                                                                   kind: .dataset),
                                 "\(namespace)/\(name)") {
                XCTAssertEqual($0 as? HuggingFacePublish.Refusal, expected)
            }
        }
        XCTAssertNoThrow(try HuggingFacePublish.repository(namespace: "a", name: "micro_duck-bow.v2",
                                                           kind: .dataset))
    }

    /// A private repository is the default: a publish button's safe default is
    /// the one you can still change your mind about.
    func testItIsPrivateUnlessAsked() throws {
        let repository = try HuggingFacePublish.repository(namespace: "a", name: "b",
                                                           kind: .dataset)
        let body = try XCTUnwrap(HuggingFacePublish.create(repository).body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["private"] as? Bool, true)
        XCTAssertEqual(json["type"] as? String, "dataset")
        XCTAssertEqual(json["name"] as? String, "b")
        let open = try XCTUnwrap(HuggingFacePublish.create(repository, isPrivate: false).body)
        let openJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: open) as? [String: Any])
        XCTAssertEqual(openJSON["private"] as? Bool, false)
    }

    func testAnEmptyCommitIsRefused() throws {
        let repository = try HuggingFacePublish.repository(namespace: "a", name: "b",
                                                           kind: .dataset)
        XCTAssertThrowsError(try HuggingFacePublish.commit(repository, summary: "s", files: [])) {
            XCTAssertEqual($0 as? HuggingFacePublish.Refusal, .nothingToPublish)
        }
    }

    /// Text goes as utf-8 so the web diff is readable; anything else base64.
    func testTheCommitBodyEncodesEachFileTheRightWay() throws {
        let repository = try HuggingFacePublish.repository(namespace: "a", name: "b",
                                                           kind: .dataset)
        let binary = Data([0x00, 0xFF, 0x10])
        let call = try HuggingFacePublish.commit(repository, summary: "Add a motion", files: [
            .init(path: "README.md", contents: Data("# hi".utf8), isText: true),
            .init(path: "blob.bin", contents: binary, isText: false),
        ])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: call.body!) as? [String: Any])
        XCTAssertEqual(json["summary"] as? String, "Add a motion")
        let files = try XCTUnwrap(json["files"] as? [[String: Any]])
        XCTAssertEqual(files[0]["encoding"] as? String, "utf-8")
        XCTAssertEqual(files[0]["content"] as? String, "# hi")
        XCTAssertEqual(files[1]["encoding"] as? String, "base64")
        XCTAssertEqual(files[1]["content"] as? String, binary.base64EncodedString())
    }

    func testWhoamiIsRead() {
        let data = Data(#"{"name":"craigm26","fullname":"C"}"#.utf8)
        XCTAssertEqual(HuggingFacePublish.parseWhoami(data), "craigm26")
        XCTAssertNil(HuggingFacePublish.parseWhoami(Data("nope".utf8)))
    }

    // MARK: - what is published

    func testAMotionPublishesThreeFilesAndNoNetwork() throws {
        let publication = try MotionPublication(draft: draft(), whenToUse: Self.whenToUse)
        XCTAssertEqual(publication.files.map(\.path).sorted(),
                       ["README.md", "little-bow.json", "meta/manifest.json"])
        XCTAssertTrue(publication.files.allSatisfy(\.isText), "all three are readable text")
        XCTAssertGreaterThan(publication.totalBytes, 200)
        XCTAssertFalse(publication.files.contains { $0.path.hasSuffix(".onnx") },
                       "this app trains nothing and must never publish a network")
    }

    /// THE TEST FOR LOADABILITY. Pollen's `RecordedMoves.process()` globs
    /// `*.json` at the repository root and nothing else: a `.duckmove` is
    /// invisible to it however right the repository type and the tags are, and
    /// the name it shows is the file's own stem. So the move has to be
    /// `<slug>.json`, and it has to be the ONLY `.json` in the root — a
    /// `manifest.json` beside it would be loaded as a second move called
    /// "manifest" that cannot parse.
    func testTheMoveIsTheOnlyJSONAGlobbingLoaderWouldFindAndItCarriesTheName() throws {
        let publication = try MotionPublication(draft: draft(), whenToUse: Self.whenToUse)
        let rootJSON = publication.files.map(\.path)
            .filter { !$0.contains("/") && $0.hasSuffix(".json") }
        XCTAssertEqual(rootJSON, ["little-bow.json"],
                       "exactly one root .json, and it is the move")
        XCTAssertFalse(publication.files.contains { $0.path.hasSuffix(".duckmove") },
                       "a .duckmove is a file their loader cannot see")
        XCTAssertEqual(publication.slug, "little-bow")
        XCTAssertEqual(publication.movePath, "little-bow.json")

        // The rename is a rename: the bytes are still the duck-move file, and
        // still readable by the one reader of that format.
        let move = try XCTUnwrap(publication.files.first { $0.path == "little-bow.json" })
        let reread = try IntentDraft.decode(move.contents)
        XCTAssertEqual(reread.keys.count, 3)
    }

    /// A move's name on the other side is its filename, so the slug has to
    /// survive both being a filename and being a Hugging Face repository name.
    func testTheSlugIsAFilenameAndAlsoALegalRepositoryName() throws {
        XCTAssertEqual(MotionPublication.slug(for: "Little Bow"), "little-bow")
        XCTAssertEqual(MotionPublication.slug(for: "  a  slow!! bow  "), "a-slow-bow")
        // Nothing left to name it after: better a stated fallback than an
        // empty filename.
        XCTAssertEqual(MotionPublication.slug(for: "!!!"), "microduck-motion")
        // Non-ASCII is dropped rather than passed through — the same string is
        // offered as the repository name, and that validator refuses it.
        XCTAssertNoThrow(try HuggingFacePublish.repository(
            namespace: "a", name: MotionPublication.slug(for: "élan vital"), kind: .dataset))
    }

    /// A move with no "when to play it" is a filename in a list, so it is
    /// refused before a token is spent rather than published unfindable.
    func testAMoveWithoutAWhenToUseSentenceIsRefused() {
        for blank in ["", "   ", "\n"] {
            XCTAssertThrowsError(try MotionPublication(draft: draft(), whenToUse: blank)) {
                XCTAssertEqual($0 as? HuggingFacePublish.Refusal, .noWhenToUse)
            }
        }
    }

    /// The manifest must be impossible to mistake for a policy.
    func testTheManifestDeclaresItselfAMotion() throws {
        let publication = try MotionPublication(draft: draft(), whenToUse: Self.whenToUse)
        let manifest = try XCTUnwrap(publication.files.first { $0.path == "meta/manifest.json" })
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: manifest.contents) as? [String: Any])
        XCTAssertEqual(json["artifact"] as? String, "motion")
        XCTAssertNil(json["obs_len"], "a motion has no observation")
        XCTAssertNil(json["action_len"])
        let motion = try XCTUnwrap(json["motion"] as? [String: Any])
        XCTAssertEqual(motion["format"] as? String, DuckMoveFile.format)
        XCTAssertEqual(motion["joints"] as? [String], DuckModel.jointNames)
        XCTAssertEqual(motion["keyframes"] as? Int, 3)
        XCTAssertEqual(motion["file"] as? String, "little-bow.json",
                       "the manifest names the file a loader will actually pick up")
        // The browsable sentence is machine-readable too: Pollen key their
        // emotions library's metadata on exactly this field.
        XCTAssertEqual(json["when_to_use"] as? String, Self.whenToUse)
        // And our own policy reader refuses it rather than half-reading it.
        XCTAssertThrowsError(try PolicyManifest.decode(manifest.contents))
    }

    /// The card leads with what is NOT true of an authored motion.
    func testTheCardCarriesTheHonestCautions() throws {
        let publication = try MotionPublication(draft: draft(), whenToUse: Self.whenToUse)
        let readme = try XCTUnwrap(publication.files.first { $0.path == "README.md" })
        let card = String(decoding: readme.contents, as: UTF8.self)
        XCTAssertTrue(card.hasPrefix("---\n"), "Hugging Face needs front matter to tag it")
        XCTAssertTrue(card.contains("microduck_community_moves"))
        XCTAssertFalse(card.contains("microduck-policy"), "it is not a policy")
        XCTAssertTrue(card.contains("This is a motion, not a policy."))
        XCTAssertTrue(card.contains("40-60%"), "the authored-versus-achieved caveat")
        XCTAssertTrue(card.contains("Never run on hardware"))
        XCTAssertTrue(card.contains(DuckModel.jointNames.joined(separator: ", ")),
                      "the joint order IS the contract and belongs in the card")
        XCTAssertTrue(card.contains("Authored by hand in Duck Studio."))
        XCTAssertTrue(card.contains(Self.whenToUse), "the sentence that makes it browsable")
        XCTAssertTrue(card.contains("## When to play it"))
    }

    /// A DATASET CARD, NOT A MODEL CARD. The front matter's shape is copied
    /// from Pollen's community-moves convention, with our own tag; the two
    /// model-card fields and the audiofolder viewer config are absent, and
    /// their absence is the assertion.
    func testTheFrontMatterIsADatasetCardsAndSaysSoInPollensShape() throws {
        let publication = try MotionPublication(draft: draft(), whenToUse: Self.whenToUse)
        let readme = try XCTUnwrap(publication.files.first { $0.path == "README.md" })
        let card = String(decoding: readme.contents, as: UTF8.self)
        let parts = card.components(separatedBy: "---\n")
        XCTAssertGreaterThan(parts.count, 2, "front matter is fenced by --- lines")
        let front = parts[1]

        XCTAssertTrue(front.contains("license: apache-2.0"), front)
        XCTAssertTrue(front.contains("task_categories: [robotics]"), front)
        XCTAssertTrue(front.contains("language: [en]"), front)
        XCTAssertTrue(front.contains("tags: [microduck_community_moves]"), front)
        XCTAssertTrue(front.contains("pretty_name: \"little bow • Microduck Moves\""), front)

        // `library_name` and `pipeline_tag` are model-card fields: on a
        // dataset they announce that whoever wrote the card thought it was a
        // model, which is the exact mistake being fixed.
        XCTAssertFalse(front.contains("library_name"), front)
        XCTAssertFalse(front.contains("pipeline_tag"), front)
        // `configs:` is the audiofolder viewer's configuration. This ships no
        // audio, and a viewer pointed at files that do not exist renders as a
        // broken dataset preview.
        XCTAssertFalse(front.contains("configs"), front)
    }

    /// A quote in a move's name must not end the YAML scalar early: broken
    /// front matter on the Hub is not an error, it is an untagged repository.
    func testAQuotedNameCannotBreakTheFrontMatter() throws {
        var quoted = draft()
        quoted.name = "the \"big\" bow"
        let publication = try MotionPublication(draft: quoted, whenToUse: Self.whenToUse)
        let readme = try XCTUnwrap(publication.files.first { $0.path == "README.md" })
        let card = String(decoding: readme.contents, as: UTF8.self)
        XCTAssertTrue(card.contains(#"pretty_name: "the \"big\" bow • Microduck Moves""#), card)
        XCTAssertEqual(publication.slug, "the-big-bow")
    }

    /// The editor's verdicts travel with the file.
    func testTheDraftsOwnProblemsBecomeCautions() throws {
        var fast = draft()
        fast.keys = [.init(time: 0, pose: DuckModel.homePose),
                     .init(time: 0.02, pose: {
                         var p = DuckModel.homePose
                         p[DuckModel.jointIndex(of: "head_yaw")!] = 2.9
                         return p
                     }())]
        let cautions = MotionPublication.cautions(for: fast)
        XCTAssertGreaterThan(cautions.count, 3,
                             "an impossible rate should have added one: \(cautions)")
    }
}
