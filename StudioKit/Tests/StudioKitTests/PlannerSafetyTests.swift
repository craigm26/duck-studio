import XCTest
@testable import StudioKit

/// The five things that must hold before any planner is offered (PlannerSafety.swift): the AI
/// label on each step, the local disclosure, camera consent, face blur that fails closed, and the
/// adult's recorded agreement.
final class PlannerSafetyTests: XCTestCase {
    typealias H = HostedFixtures
    typealias L = LocalFixtures

    // Every planner kind the kit has, by its info: hosted, network (plain, tailnet, encrypted),
    // forwarded, internet, and on this phone.
    static func everyPlanner() throws -> [(String, PlannerInfo)] {
        var out: [(String, PlannerInfo)] = HostedVendor.allCases.map { ($0.name, $0.info()) }
        for base in ["http://mac.local:11434/v1", "http://100.101.102.103:11434/v1", "https://mac.local:11434/v1",
                     "https://models.example.com/v1"] {
            out.append((base, try LANPlanner(endpoint: L.endpoint(base), version: L.pinned, http: StubLocalHTTP(json: "{}")).info))
        }
        out.append(("relay", try LANPlanner(endpoint: L.endpoint("http://pi.local:8080/v1", relay: true),
                                            version: L.pinned, http: StubLocalHTTP(json: "{}")).info))
        out.append(("phone", PhoneMLXPlanner(repository: PhoneMLXPlannerTests.repo, version: PhoneMLXPlannerTests.version,
                                             runner: StubRunner { _ in "" }).info))
        return out
    }

    func settings(agreed: Bool = true) -> PlannerSafetySettings {
        let s = PlannerSafetySettings(storage: MemoryPlannerSettingsStorage())
        if agreed { s.agree(on: Date(timeIntervalSince1970: 1_794_614_400), appVersion: "2.0 (96)") }
        return s
    }

    // MARK: 1. the label on each step

    func testEveryPlannerKindGetsALabelNamingProviderAndModel() throws {
        let planners = try Self.everyPlanner()
        XCTAssertEqual(planners.count, 8)
        for (name, info) in planners {
            let decided = Decided(decision: .walk(forwardM: 0.3, sideM: 0), why: "ahead", provider: info, latency: .milliseconds(5))
            let label = try XCTUnwrap(decided.aiLabel, "\(name) chose a step and must be labelled")
            XCTAssertEqual(label.headline, "Chosen by an AI model, not a person")
            XCTAssertTrue(label.line.contains("not a person"), name)
            XCTAssertFalse(label.provider.isEmpty, name)
            XCTAssertFalse(label.model.isEmpty, name)
        }
        let anthropic = try XCTUnwrap(PlannerDisclosure.stepLabel(for: HostedVendor.anthropic.info()))
        XCTAssertEqual(anthropic.line, "Chosen by an AI model, not a person: Anthropic, claude-haiku-5-5.")
        XCTAssertEqual(PlannerDisclosure.stepLabel(for: HostedVendor.openai.info(model: "gpt-6-luna-0101"))?.line,
                       "Chosen by an AI model, not a person: OpenAI, gpt-6-luna-0101.")
        let lan = try LANPlanner(endpoint: L.endpoint(), version: L.pinned, http: StubLocalHTTP(json: "{}")).info
        XCTAssertEqual(PlannerDisclosure.stepLabel(for: lan, device: .phone)?.line,
                       "Chosen by an AI model, not a person: Your computer, qwen3.5:4b.")
        let phone = PhoneMLXPlanner(repository: PhoneMLXPlannerTests.repo, version: PhoneMLXPlannerTests.version,
                                    runner: StubRunner { _ in "" }).info
        XCTAssertEqual(PlannerDisclosure.stepLabel(for: phone, device: .phone)?.line,
                       "Chosen by an AI model, not a person: This phone, mlx-community/Qwen3-1.7B-4bit.")
        XCTAssertEqual(PlannerDisclosure.stepLabel(for: phone, device: .mac)?.provider, "This Mac")
    }

    func testTheLabelNamesTheModelThatActuallyAnswered() async throws {
        let stub = StubPlannerHTTP(json: H.anthropicToolUse("walk", #"{"forward_m":0.3,"side_m":0,"why":"ahead"}"#,
                                                            model: "claude-haiku-5-5-20261201"))
        let d = try await AnthropicPlanner(key: H.anthropicKey, http: stub).decide(H.ask())
        XCTAssertEqual(d.aiLabel?.model, "claude-haiku-5-5-20261201")
    }

    func testDuckTalkAndNoPlannerGetNoLabel() {
        // The deterministic reader's steps, each with its own provider: no label.
        let converted = DecisionAdapter.from(DuckTalk.read("walk forward then turn left"))
        XCTAssertFalse(converted.decisions.isEmpty, "the check below must have steps to look at")
        for decision in converted.decisions {
            let d = Decided(decision: decision, why: "", provider: .duckTalk, latency: .milliseconds(1))
            XCTAssertNil(d.aiLabel, "\(decision)")
        }
        XCTAssertNil(PlannerDisclosure.stepLabel(for: Decided?.none))
        XCTAssertNil(PlannerDisclosure.stepLabel(for: PlannerInfo?.none))
        XCTAssertNil(PlannerDisclosure.stepLabel(for: PlannerInfo.duckTalk))
        XCTAssertFalse(PlannerDisclosure.isModel(.duckTalk))
    }

    func testASavedEndpointShowsTheLabelItWillCarry() {
        XCTAssertEqual(PlannerDisclosure.stepLabel(for: L.endpoint(), device: .phone).line,
                       "Chosen by an AI model, not a person: Your computer, qwen3.5:4b.")
        let mlx = ModelEndpoint(name: "Qwen", kind: .downloadedMLX, baseURL: "", model: "mlx-community/Qwen3-0.6B-4bit")
        XCTAssertEqual(PlannerDisclosure.stepLabel(for: mlx, device: .mac).line,
                       "Chosen by an AI model, not a person: This Mac, mlx-community/Qwen3-0.6B-4bit.")
        let apple = ModelEndpoint(name: "Apple", kind: .appleOnDevice, baseURL: "", model: "")
        XCTAssertEqual(PlannerDisclosure.stepLabel(for: apple, device: .phone).line,
                       "Chosen by an AI model, not a person: This phone, Apple's on-device model.")
    }

    func testAnUnknownPlannerIsLabelledNotSkipped() {
        let made = PlannerInfo(id: "new.thing", modelVersion: "v1", label: "x", runsOn: .robotComputer, key: .none,
                               decisionDeadline: .seconds(1))
        XCTAssertEqual(PlannerDisclosure.stepLabel(for: made)?.line,
                       "Chosen by an AI model, not a person: The duck's computer, thing.")
    }

    // MARK: 2. the local disclosure

    func testLocalPlannersSayAModelNotAPersonChose() {
        for device in [DeviceWords.phone, .mac] {
            for kind in ModelEndpoint.Kind.allCases {
                let line = LocalPlannerWords.aiDisclosure(kind, model: "qwen3.5:4b", device: device)
                XCTAssertTrue(line.hasPrefix("Decisions come from an AI model ("), line)
                XCTAssertTrue(line.hasSuffix("), not a person."), line)
                let card = LocalPlannerWords.card(kind, model: "qwen3.5:4b", device: device)
                XCTAssertEqual(card.first, line)
                XCTAssertTrue(card.contains(HostedPlannerWords.forChildren))
                XCTAssertTrue(card.contains(HostedPlannerWords.canBeWrong))
                XCTAssertTrue(card.contains(HostedPlannerWords.adultWatches))
                XCTAssertTrue(card.contains(LocalPlannerWords.noPicture))
            }
        }
        XCTAssertEqual(LocalPlannerWords.aiDisclosure(.downloadedMLX, model: "mlx-community/Qwen3-0.6B-4bit", device: .phone),
                       "Decisions come from an AI model (mlx-community/Qwen3-0.6B-4bit, on this phone), not a person.")
        XCTAssertEqual(LocalPlannerWords.aiDisclosure(.openAICompatible, model: "qwen3.5:4b", device: .phone),
                       "Decisions come from an AI model (qwen3.5:4b, on a computer you chose), not a person.")
        XCTAssertEqual(LocalPlannerWords.aiDisclosure(.appleOnDevice, model: "", device: .mac),
                       "Decisions come from an AI model (Apple's on-device model, on this Mac), not a person.")
        XCTAssertEqual(LocalPlannerWords.aiDisclosure(.openAICompatible, model: " ", device: .phone),
                       "Decisions come from an AI model (a model, on a computer you chose), not a person.")
    }

    // MARK: 3. camera consent

    func testEveryCameraSwitchIsOffByDefault() throws {
        let s = settings()
        for (name, info) in try Self.everyPlanner() {
            XCTAssertFalse(s.cameraConsent(info.id), name)
        }
    }

    func testNoFrameIsAttachedWithConsentOffForEveryPlanner() throws {
        let s = settings()
        for (name, info) in try Self.everyPlanner() {
            let calls = LockedBox<[String]>([])
            let outcome = PlannerFrameGate.frame("picture", for: info, settings: s,
                                                 blur: PlannerFaceBlur { p in calls.value.append("blur"); return p },
                                                 encode: { _ in calls.value.append("encode"); return Data([1]) })
            XCTAssertEqual(outcome, .noConsent, name)
            XCTAssertNil(outcome.jpeg, name)
            XCTAssertEqual(calls.value, [], "\(name): nothing is blurred or encoded without consent")
        }
    }

    func testAHostedPlannerSendsNoPictureWithConsentOffEvenIfOneIsInTheAsk() throws {
        let ask = H.ask(frame: H.jpeg)
        let base64 = H.jpeg.base64EncodedString()
        let a = try AnthropicPlanner(key: H.anthropicKey, cameraConsent: false, http: StubPlannerHTTP()).body(ask)
        let o = try OpenAIPlanner(key: H.openaiKey, cameraConsent: false, http: StubPlannerHTTP()).body(ask)
        for body in [a, o] {
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(base64))
        }
        // And the same planners, consent on, do carry it: the check above can fail.
        let on = try AnthropicPlanner(key: H.anthropicKey, cameraConsent: true, http: StubPlannerHTTP()).body(ask)
        XCTAssertTrue(String(decoding: on, as: UTF8.self).contains(base64))
    }

    func testLocalPlannersTakeNoPictureEvenWithConsentOn() async throws {
        let s = settings()
        let base64 = H.jpeg.base64EncodedString()
        let ask = PlannerAsk(goal: "walk to the ball", frame: H.jpeg, state: DuckStateSnapshot(standing: true), allowed: L.sim)
        // Network planners: no request mode has a place for a picture.
        let lan = try LANPlanner(endpoint: L.endpoint(), version: L.pinned, http: StubLocalHTTP(json: "{}"))
        XCTAssertFalse(PlannerFrameGate.takesPictures(lan.info))
        for mode in LocalOutputMode.allCases {
            let body = try lan.request(ask, mode: mode).body
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(base64), "\(mode)")
        }
        // The phone planner: the prompt the runner is given carries no picture.
        let seen = LockedBox<String>("")
        let phone = PhoneMLXPlanner(repository: PhoneMLXPlannerTests.repo, version: PhoneMLXPlannerTests.version,
                                    runner: StubRunner { s in seen.value = s.prompt + s.instructions; return L.walk })
        _ = try await phone.decide(ask)
        XCTAssertFalse(seen.value.isEmpty)
        XCTAssertFalse(seen.value.contains(base64))
        XCTAssertFalse(PlannerFrameGate.takesPictures(phone.info))
        // With consent given for them, the gate still refuses before blurring.
        for info in [lan.info, phone.info] {
            let outcome = PlannerFrameGate.frame("picture", for: info, consent: true,
                                                 blur: PlannerFaceBlur { $0 }, encode: { _ in Data([1]) })
            XCTAssertEqual(outcome, .providerTakesNoPictures)
        }
    }

    func testTurningASwitchOnNeedsTheAgreementAndIsPerProvider() throws {
        let s = settings(agreed: false)
        XCTAssertThrowsError(try s.setCameraConsent(true, for: HostedVendor.anthropic.providerId)) { e in
            XCTAssertEqual(e as? PlannerSafetyRefusal, .noAgreement)
        }
        XCTAssertFalse(s.cameraConsent(HostedVendor.anthropic.providerId))
        s.agree(on: Date(), appVersion: "2.0 (96)")
        try s.setCameraConsent(true, for: HostedVendor.anthropic.providerId)
        XCTAssertTrue(s.cameraConsent(HostedVendor.anthropic.providerId))
        XCTAssertFalse(s.cameraConsent(HostedVendor.openai.providerId), "one provider's switch is not another's")
        try s.setCameraConsent(false, for: HostedVendor.anthropic.providerId)
        XCTAssertFalse(s.cameraConsent(HostedVendor.anthropic.providerId))
        try s.setCameraConsent(true, for: HostedVendor.openai.providerId)
        s.withdraw()
        XCTAssertFalse(s.cameraConsent(HostedVendor.openai.providerId), "withdrawing turns the camera off")
    }

    func testTheSwitchSaysWhatIsSentToWhomUnderWhoseRules() {
        for v in HostedVendor.allCases {
            let detail = PlannerSafetyWords.cameraDetail(v)
            XCTAssertTrue(detail.hasPrefix("Off unless you turn it on."), detail)
            XCTAssertTrue(detail.contains("each decision sends \(v.name) one picture"), detail)
            XCTAssertTrue(detail.contains("faces blurred on this device first"), detail)
            XCTAssertTrue(detail.contains("no picture is sent"), detail)
            XCTAssertTrue(detail.contains(v.terms.imageRetention ?? "missing"), detail)
            XCTAssertEqual(PlannerSafetyWords.cameraSwitch(v), "Send camera pictures to \(v.name)")
        }
    }

    // MARK: 4. face blur, fail closed, in order

    func testBlurRunsBeforeEncodeAndThePlannerSendsTheEncodedBlurredPicture() throws {
        let s = settings()
        try s.setCameraConsent(true, for: HostedVendor.anthropic.providerId)
        let calls = LockedBox<[String]>([])
        let outcome = PlannerFrameGate.frame("raw", for: HostedVendor.anthropic.info(), settings: s,
                                             blur: PlannerFaceBlur { p in calls.value.append("blur:\(p)"); return "blurred" },
                                             encode: { p in calls.value.append("encode:\(p)"); return Data(p.utf8) })
        XCTAssertEqual(calls.value, ["blur:raw", "encode:blurred"])
        let jpeg = try XCTUnwrap(outcome.jpeg)
        XCTAssertEqual(jpeg, Data("blurred".utf8), "what is encoded is the blurred picture, never the raw one")
        let body = try AnthropicPlanner(key: H.anthropicKey, cameraConsent: true, http: StubPlannerHTTP())
            .body(H.ask(frame: outcome.jpeg))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains(Data("blurred".utf8).base64EncodedString()))
        XCTAssertFalse(text.contains(Data("raw".utf8).base64EncodedString()))
    }

    func testNoFaceFindingMeansNoPicture() {
        let calls = LockedBox<[String]>([])
        for v in HostedVendor.allCases {
            let outcome = PlannerFrameGate.frame("raw", for: v.info(), consent: true, blur: PlannerFaceBlur<String>.unavailable,
                                                 encode: { _ in calls.value.append("encode"); return Data([1]) })
            XCTAssertEqual(outcome, .faceBlurUnavailable)
            XCTAssertNil(outcome.jpeg)
        }
        XCTAssertEqual(calls.value, [], "nothing is encoded when faces cannot be found")
    }

    func testAFailedBlurOrEncodeSendsNothing() {
        let info = HostedVendor.openai.info()
        let encoded = LockedBox<Int>(0)
        XCTAssertEqual(PlannerFrameGate.frame("raw", for: info, consent: true, blur: PlannerFaceBlur { _ in nil },
                                              encode: { _ in encoded.value += 1; return Data([1]) }), .faceBlurFailed)
        XCTAssertEqual(encoded.value, 0)
        XCTAssertEqual(PlannerFrameGate.frame("raw", for: info, consent: true, blur: PlannerFaceBlur { $0 },
                                              encode: { _ in nil }), .encodeFailed)
        XCTAssertEqual(PlannerFrameGate.frame("raw", for: info, consent: true, blur: PlannerFaceBlur { $0 },
                                              encode: { _ in Data() }), .encodeFailed)
        XCTAssertEqual(PlannerFrameGate.frame(String?.none, for: info, consent: true, blur: PlannerFaceBlur { $0 },
                                              encode: { _ in Data([1]) }), .noPicture)
    }

    // MARK: 5. the adult's agreement

    func testNoKeyIsSavedWithoutTheAgreement() {
        let s = settings(agreed: false)
        let written = LockedBox<[String]>([])
        for v in HostedVendor.allCases {
            let key = v == .anthropic ? H.anthropicKey : H.openaiKey
            XCTAssertEqual(s.saveKey(key, for: v) { written.value.append($0) }, .failure(.agreement(.noAgreement)))
        }
        XCTAssertEqual(written.value, [], "nothing reaches the Keychain")
        XCTAssertEqual(PlannerSafetySettings.KeySaveRefusal.agreement(.noAgreement).says, ParentalAgreementWords.needed)

        s.agree(on: Date(), appVersion: "2.0 (96)")
        XCTAssertEqual(s.saveKey("  \(H.anthropicKey)\n", for: .anthropic) { written.value.append($0) }, .success(H.anthropicKey))
        XCTAssertEqual(written.value, [H.anthropicKey])
        // The shape check still runs after the agreement.
        XCTAssertEqual(s.saveKey(H.anthropicKey, for: .openai) { written.value.append($0) }, .failure(.key(.wrongVendor(.openai))))
        XCTAssertEqual(written.value.count, 1)
    }

    func testTheRecordHoldsTheDayTheVersionAndTheWordsNothingElse() throws {
        let storage = MemoryPlannerSettingsStorage()
        let s = PlannerSafetySettings(storage: storage)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(ParentalAgreement.day(Date(timeIntervalSince1970: 1_794_614_400), calendar: utc), "2026-11-14")
        let record = s.agree(on: Date(), appVersion: "2.0 (96)")
        XCTAssertEqual(record.appVersion, "2.0 (96)")
        XCTAssertEqual(record.textVersion, ParentalAgreementWords.textVersion)
        let stored = try XCTUnwrap(storage.data(forKey: PlannerSafetySettings.agreementKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: stored) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["agreedOn", "appVersion", "textVersion"])
        // It survives a new settings object over the same storage: a relaunch.
        XCTAssertEqual(PlannerSafetySettings(storage: storage).agreement, record)
    }

    func testNewWordsAskAgain() throws {
        let s = settings()
        XCTAssertTrue(s.agreementStatus().isCurrent)
        let bumped = ParentalAgreementWords.textVersion + 1
        guard case .outdated = s.agreementStatus(textVersion: bumped) else { return XCTFail("a new text version asks again") }
        XCTAssertThrowsError(try s.requireAgreement(textVersion: bumped)) { e in
            XCTAssertEqual(e as? PlannerSafetyRefusal, .agreementOutdated)
        }
        XCTAssertEqual(PlannerSafetyRefusal.agreementOutdated.says, ParentalAgreementWords.askAgain)
        // An older record, read under today's words, is outdated too.
        let old = ParentalAgreement(agreedOn: "2026-11-01", appVersion: "2.0 (95)", textVersion: ParentalAgreementWords.textVersion - 1)
        XCTAssertEqual(ParentalAgreement.status(old), .outdated(old))
        XCTAssertEqual(ParentalAgreement.status(nil), .none)
    }

    /// The text and its version move together. If this fails, the agreement's words changed:
    /// bump `ParentalAgreementWords.textVersion`, then update the pinned pair here.
    func testTheAgreementTextIsPinnedToItsVersion() {
        XCTAssertEqual(ParentalAgreementWords.textVersion, 1)
        XCTAssertEqual(ParentalAgreementWords.text,
                       "I am an adult. If a child uses these planners, I am their parent or guardian and I agree to it. "
                       + "I hold any key, I decide whether the camera is used, and I watch the duck while a model chooses its steps.")
    }

    func testNoModelPlannerIsUsedWithoutTheAgreement() async throws {
        let s = settings(agreed: false)
        let stub = StubPlannerHTTP(json: H.anthropicToolUse("walk", #"{"forward_m":0.3,"side_m":0,"why":"ahead"}"#))
        let gated = AgreedPlanner(AnthropicPlanner(key: H.anthropicKey, http: stub), settings: s)
        do {
            _ = try await gated.decide(H.ask())
            XCTFail("refused before asking")
        } catch let r as PlannerSafetyRefusal {
            XCTAssertEqual(r, .noAgreement)
        }
        XCTAssertEqual(stub.sent.count, 0, "nothing was sent")
        for (name, info) in try Self.everyPlanner() { XCTAssertFalse(s.mayUse(info), name) }
        XCTAssertTrue(s.mayUse(.duckTalk), "a fixed rule needs no agreement")

        s.agree(on: Date(), appVersion: "2.0 (96)")
        let d = try await gated.decide(H.ask())
        XCTAssertEqual(d.decision, .walk(forwardM: 0.3, sideM: 0))
        XCTAssertEqual(stub.sent.count, 1)
        for (name, info) in try Self.everyPlanner() { XCTAssertTrue(s.mayUse(info), name) }
    }

    func testThePrivacyLinkIsTheChildrenSection() {
        XCTAssertEqual(ParentalAgreementWords.privacyURL.absoluteString, "https://microduckstudio.com/privacy/#children")
    }

    // MARK: the words

    func testTheWordsMakeNoClaimTheyCannotKeep() {
        let lines = PlannerSafetyWords.all + ParentalAgreementWords.all
            + LocalPlannerWords.disclosures(device: .phone) + LocalPlannerWords.disclosures(device: .mac)
        for s in lines {
            let lower = s.lowercased()
            for banned in ["safe", "safety", "guarantee", "powered by"] {
                XCTAssertFalse(lower.contains(banned), "\(banned): \(s)")
            }
            XCTAssertFalse(s.contains("\u{2014}"), "no em-dashes: \(s)")
            XCTAssertFalse(s.contains("\u{2013}"), "no en-dashes: \(s)")
        }
    }
}
