import XCTest
import DuckKit
@testable import StudioKit

/// Publishing: what gets built, and what must never be in it.
final class PublishTests: XCTestCase {

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
        let repository = try HuggingFacePublish.repository(namespace: "someone", name: "bow")
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
        let repository = try HuggingFacePublish.repository(namespace: "someone", name: "little-bow")
        XCTAssertEqual(HuggingFacePublish.whoami().displayURL,
                       "https://huggingface.co/api/whoami-v2")
        XCTAssertEqual(HuggingFacePublish.create(repository).displayURL,
                       "https://huggingface.co/api/repos/create")
        let commit = try HuggingFacePublish.commit(repository, summary: "s",
                                                   files: [.init(path: "a", contents: Data("x".utf8),
                                                                 isText: true)])
        XCTAssertEqual(commit.displayURL,
                       "https://huggingface.co/api/models/someone/little-bow/commit/main")
        XCTAssertEqual(repository.webURL, "https://huggingface.co/someone/little-bow")
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
            XCTAssertThrowsError(try HuggingFacePublish.repository(namespace: namespace, name: name),
                                 "\(namespace)/\(name)") {
                XCTAssertEqual($0 as? HuggingFacePublish.Refusal, expected)
            }
        }
        XCTAssertNoThrow(try HuggingFacePublish.repository(namespace: "a", name: "micro_duck-bow.v2"))
    }

    /// A private repository is the default: a publish button's safe default is
    /// the one you can still change your mind about.
    func testItIsPrivateUnlessAsked() throws {
        let repository = try HuggingFacePublish.repository(namespace: "a", name: "b")
        let body = try XCTUnwrap(HuggingFacePublish.create(repository).body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["private"] as? Bool, true)
        XCTAssertEqual(json["type"] as? String, "model")
        XCTAssertEqual(json["name"] as? String, "b")
        let open = try XCTUnwrap(HuggingFacePublish.create(repository, isPrivate: false).body)
        let openJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: open) as? [String: Any])
        XCTAssertEqual(openJSON["private"] as? Bool, false)
    }

    func testAnEmptyCommitIsRefused() throws {
        let repository = try HuggingFacePublish.repository(namespace: "a", name: "b")
        XCTAssertThrowsError(try HuggingFacePublish.commit(repository, summary: "s", files: [])) {
            XCTAssertEqual($0 as? HuggingFacePublish.Refusal, .nothingToPublish)
        }
    }

    /// Text goes as utf-8 so the web diff is readable; anything else base64.
    func testTheCommitBodyEncodesEachFileTheRightWay() throws {
        let repository = try HuggingFacePublish.repository(namespace: "a", name: "b")
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
        let publication = try MotionPublication(draft: draft())
        XCTAssertEqual(publication.files.map(\.path).sorted(),
                       ["README.md", "manifest.json", "motion.duckmove"])
        XCTAssertTrue(publication.files.allSatisfy(\.isText), "all three are readable text")
        XCTAssertGreaterThan(publication.totalBytes, 200)
        XCTAssertFalse(publication.files.contains { $0.path.hasSuffix(".onnx") },
                       "this app trains nothing and must never publish a network")
    }

    /// The manifest must be impossible to mistake for a policy.
    func testTheManifestDeclaresItselfAMotion() throws {
        let publication = try MotionPublication(draft: draft())
        let manifest = try XCTUnwrap(publication.files.first { $0.path == "manifest.json" })
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: manifest.contents) as? [String: Any])
        XCTAssertEqual(json["artifact"] as? String, "motion")
        XCTAssertNil(json["obs_len"], "a motion has no observation")
        XCTAssertNil(json["action_len"])
        let motion = try XCTUnwrap(json["motion"] as? [String: Any])
        XCTAssertEqual(motion["format"] as? String, DuckMoveFile.format)
        XCTAssertEqual(motion["joints"] as? [String], DuckModel.jointNames)
        XCTAssertEqual(motion["keyframes"] as? Int, 3)
        // And our own policy reader refuses it rather than half-reading it.
        XCTAssertThrowsError(try PolicyManifest.decode(manifest.contents))
    }

    /// The card leads with what is NOT true of an authored motion.
    func testTheCardCarriesTheHonestCautions() throws {
        let publication = try MotionPublication(draft: draft())
        let readme = try XCTUnwrap(publication.files.first { $0.path == "README.md" })
        let card = String(decoding: readme.contents, as: UTF8.self)
        XCTAssertTrue(card.hasPrefix("---\n"), "Hugging Face needs front matter to tag it")
        XCTAssertTrue(card.contains("microduck-motion"))
        XCTAssertFalse(card.contains("microduck-policy"), "it is not a policy")
        XCTAssertTrue(card.contains("This is a motion, not a policy."))
        XCTAssertTrue(card.contains("40-60%"), "the authored-versus-achieved caveat")
        XCTAssertTrue(card.contains("Never run on hardware"))
        XCTAssertTrue(card.contains(DuckModel.jointNames.joined(separator: ", ")),
                      "the joint order IS the contract and belongs in the card")
        XCTAssertTrue(card.contains("Authored by hand in Duck Studio."))
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
