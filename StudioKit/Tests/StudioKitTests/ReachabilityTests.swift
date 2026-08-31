import XCTest
@testable import StudioKit

/// The five different problems that used to be one line of error, asserted
/// letter by letter.
///
/// NOTHING HERE OPENS A SOCKET, and nothing here needs to. `Reachability` takes
/// what a probe saw and answers, so every branch is reachable from a test —
/// including the three that are near-impossible to produce on a phone you own:
/// a refused Local Network permission, an ATS refusal of a private address, and
/// a certificate failure against a box on your desk.
final class ReachabilityTests: XCTestCase {

    /// A Pi running Ollama on the LAN, which is the address most of these are
    /// about.
    private func pi(_ change: (inout Reachability.Observation) -> Void = { _ in })
        -> Reachability.Observation {
        var seen = Reachability.Observation(host: "192.168.1.10", port: 11434)
        change(&seen)
        return seen
    }

    private func explain(_ seen: Reachability.Observation) -> Reachability.Verdict {
        Reachability.explain(seen)
    }

    // MARK: - it worked

    func testAnEndpointThatListsItsModelsQuicklySaysTheAddressIsRight() {
        let verdict = explain(pi {
            $0.status = 200; $0.modelsFound = 3; $0.seconds = 0.4
        })
        XCTAssertEqual(verdict.cause, .answered)
        XCTAssertEqual(verdict.sentence,
            "192.168.1.10 port 11434 answered as an OpenAI-compatible API and listed 3 models, "
            + "in 0.4 s. The address is right.")
        XCTAssertTrue(verdict.isReady)
        XCTAssertTrue(verdict.foundAnAPI)
    }

    /// One model is one model, not "1 models".
    ///
    /// AND 1.25 s PRINTS AS "1.2 s", WHICH IS NOT A BUG. `%.1f` rounds a value
    /// sitting exactly on the half to the even digit, and 1.25 is one of the
    /// few decimals a Double holds exactly. Pinned here so that nobody meets it
    /// in the wild and "fixes" the formatter.
    func testASingleModelIsCountedInTheSingular() {
        let verdict = explain(pi { $0.status = 200; $0.modelsFound = 1; $0.seconds = 1.25 })
        XCTAssertEqual(verdict.sentence,
            "192.168.1.10 port 11434 answered as an OpenAI-compatible API and listed 1 model, "
            + "in 1.2 s. The address is right.")
    }

    /// A machine slow to hand over a list it already has is the honest early
    /// warning about what drafting will cost, and the remedy is the app's own
    /// measured one.
    func testAServerSlowToListItsModelsIsToldTheRemedyIsASmallerModel() {
        let verdict = explain(pi { $0.status = 200; $0.modelsFound = 2; $0.seconds = 9.2 })
        XCTAssertEqual(verdict.cause, .answeredSlowly)
        XCTAssertEqual(verdict.sentence,
            "192.168.1.10 port 11434 answered as an OpenAI-compatible API and listed 2 models — "
            + "but it took 9.2 s to hand over a list it holds on disk, with no model run at all. "
            + "Drafting asks it to run the model, which is far more work than reading a list: a "
            + "7.5B model on a Raspberry Pi 5 took 766 s to write one motion here. A smaller "
            + "model is the remedy, not a shorter timeout.")
        XCTAssertTrue(verdict.isReady)
    }

    /// The threshold is a strict `>`, so a probe landing exactly on it is quick.
    func testFiveSecondsExactlyIsStillQuickAndFiveAndABitIsNot() {
        XCTAssertEqual(explain(pi { $0.status = 200; $0.modelsFound = 1; $0.seconds = 5 }).cause,
                       .answered)
        XCTAssertEqual(explain(pi { $0.status = 200; $0.modelsFound = 1; $0.seconds = 5.1 }).cause,
                       .answeredSlowly)
    }

    /// An empty list is a working address with nothing on it, and that is a
    /// different sentence from a broken one.
    func testARealAPIWithNothingLoadedSaysTheAddressIsRightAndTheShelfIsEmpty() {
        let verdict = explain(pi { $0.status = 200; $0.modelsFound = 0; $0.seconds = 0.2 })
        XCTAssertEqual(verdict.cause, .noModelsLoaded)
        XCTAssertEqual(verdict.sentence,
            "192.168.1.10 port 11434 answered as an OpenAI-compatible API and listed no models "
            + "at all. The address is right and the shelf is empty — load a model on that "
            + "machine, then ask for the list again.")
        XCTAssertTrue(verdict.foundAnAPI)
        XCTAssertFalse(verdict.isReady)
    }

    /// An empty list and a list this app cannot read are DIFFERENT ROOMS, and
    /// conflating them told somebody with three models loaded to go and load a
    /// model. The count of names read is zero either way; the count of entries
    /// is what tells them apart.
    func testAListWithEntriesAndNoNamesIsNotAnEmptyShelf() {
        let verdict = explain(pi {
            $0.status = 200; $0.modelsFound = 0; $0.listedEntries = 3; $0.seconds = 0.3
        })
        XCTAssertEqual(verdict.cause, .modelNamesUnreadable)
        XCTAssertEqual(verdict.sentence,
            "192.168.1.10 port 11434 answered as an OpenAI-compatible API and its list held 3 "
            + "entries with no readable name between them. So the list is not empty, but this "
            + "app cannot tell you what is on it. Type the model name that machine uses into "
            + "Model, and Try a draft will say whether it took it.")
        // WHAT WAS MEASURED IS THE ARRAY, NOT THE SHELF. Three JSON objects
        // with no String `id` is an observation; "something is on it" is an
        // inference about a server this app could not parse.
        XCTAssertFalse(verdict.sentence.contains("something is on it"))
        XCTAssertFalse(verdict.sentence.contains("load a model on that machine"),
                       "the empty-shelf remedy would send them to fix a problem they do not have")
        XCTAssertTrue(verdict.foundAnAPI)
        XCTAssertFalse(verdict.isReady)
    }

    func testASingleUnreadableEntryIsCountedInTheSingular() {
        let verdict = explain(pi { $0.status = 200; $0.modelsFound = 0; $0.listedEntries = 1 })
        XCTAssertEqual(verdict.cause, .modelNamesUnreadable)
        XCTAssertTrue(verdict.sentence.contains("its list held 1 entry with no readable name"))
    }

    /// And a list that really is empty holds no entries either, so it keeps the
    /// sentence it had.
    func testAnEmptyListStillReadsAsAnEmptyShelf() {
        XCTAssertEqual(explain(pi { $0.status = 200; $0.modelsFound = 0; $0.listedEntries = 0 })
                        .cause, .noModelsLoaded)
    }

    // MARK: - it answered, and said no

    func testAnUnauthorisedAnswerIsAKeyQuestionRatherThanAnAddressQuestion() {
        let verdict = explain(pi { $0.status = 401; $0.body = "{\"error\":\"no key\"}" })
        XCTAssertEqual(verdict.cause, .notAuthorised)
        XCTAssertEqual(verdict.sentence,
            "192.168.1.10 port 11434 answered 401, which is a refusal to let the request in "
            + "rather than anything wrong with the address. Put the bearer token that server "
            + "expects under Advanced — or clear it, if it wants none.")
        XCTAssertFalse(verdict.foundAnAPI)
    }

    /// A proxy that wants a key often answers with a login PAGE. Reading that
    /// as "not an API" would send somebody off to check a correct address.
    func testAnHTMLLoginPageWithA403IsStillAnAuthorisationProblem() {
        let verdict = explain(pi { $0.status = 403; $0.body = "<!doctype html><title>Sign in" })
        XCTAssertEqual(verdict.cause, .notAuthorised)
        XCTAssertTrue(verdict.sentence.hasPrefix("192.168.1.10 port 11434 answered 403,"))
    }

    func testA404OnThePathSaysTheAPILivesUnderV1() {
        let verdict = explain(pi {
            $0.status = 404; $0.path = "/api/models"; $0.body = "{\"detail\":\"not found\"}"
        })
        XCTAssertEqual(verdict.cause, .noAPIAtThatPath)
        XCTAssertEqual(verdict.sentence,
            "Something is listening on 192.168.1.10 port 11434, and it answered 404 for "
            + "/api/models. Either the route is wrong — Ollama, LM Studio and llama.cpp all "
            + "serve theirs under /v1, so the address wants /v1 on the end and nothing after it "
            + "— or what is on that port is not a model server at all. A 404 does not say which.")
    }

    /// A 404 CARRYING AN HTML ERROR PAGE IS STILL A 404. A real model server
    /// behind a reverse proxy answers an unknown route with the proxy's own
    /// page, and the body heuristic used to outrank the status code and call
    /// that "a router, a printer, a web server" — sending somebody to check an
    /// address that was right except for its path. The status is what the
    /// server SAID; the body's shape is a guess about what it IS.
    func testA404WithAnHTMLBodyIsStillAboutTheRouteAndNotTheService() {
        let verdict = explain(pi {
            $0.status = 404
            $0.path = "/api/models"
            $0.body = "<html><head><title>404 Not Found</title></head><body>nginx</body></html>"
        })
        XCTAssertEqual(verdict.cause, .noAPIAtThatPath)
        XCTAssertFalse(verdict.sentence.contains("a router, a printer"),
                       "a 404 does not establish what is on the port")
        XCTAssertTrue(verdict.sentence.contains("A 404 does not say which."))
    }

    /// A router, a printer, or a web server on the port you guessed.
    func testAWebPageBackFromA200IsADifferentServiceOnThatPort() {
        let verdict = explain(pi {
            $0.status = 200; $0.body = "<html><body>Router admin</body></html>"; $0.port = 80
        })
        XCTAssertEqual(verdict.cause, .notAnAPI)
        XCTAssertEqual(verdict.sentence,
            "Something is listening on 192.168.1.10 port 80, and it answered with a page rather "
            + "than a list of models. That is a different service on that port — a router, a "
            + "printer, a web server — and not an OpenAI-compatible API.")
    }

    /// A 200 whose body is JSON but not a model list is the same story.
    func testATwoHundredThatIsNotAModelListIsNotAnAPIEither() {
        XCTAssertEqual(explain(pi { $0.status = 200; $0.body = "{\"ok\":true}" }).cause, .notAnAPI)
    }

    func testAnUnexplainedStatusQuotesTheServerRatherThanInterpretingIt() {
        let verdict = explain(pi { $0.status = 500; $0.body = "  model runner crashed\n" })
        XCTAssertEqual(verdict.cause, .serverRefused)
        XCTAssertEqual(verdict.sentence,
            "192.168.1.10 port 11434 answered 500. It is listening and it understood enough to "
            + "say no, so the address is close. It said: model runner crashed")
    }

    func testAStatusWithAnEmptyBodySaysThereWasNothingToQuote() {
        let verdict = explain(pi { $0.status = 502; $0.body = "   " })
        XCTAssertEqual(verdict.cause, .serverRefused)
        XCTAssertEqual(verdict.sentence,
            "192.168.1.10 port 11434 answered 502, with nothing in the body to explain it. It is "
            + "listening and it understood enough to say no, so the address is close.")
    }

    // MARK: - nothing was listening

    /// The single most common setup failure in this app, and Ollama documents
    /// the fix itself — so it is quoted rather than paraphrased.
    func testARefusedConnectionOnOllamasPortQuotesOllamasOwnFAQ() {
        let verdict = explain(pi { $0.urlErrorCode = -1004 })
        XCTAssertEqual(verdict.cause, .nothingListening)
        XCTAssertEqual(verdict.sentence,
            "Nothing answered on 192.168.1.10 port 11434. Something has to be listening there, "
            + "and on an address other machines can reach rather than only on its own localhost."
            + " Ollama's own FAQ says it: “Ollama binds 127.0.0.1 port 11434 by default. Change "
            + "the bind address with the OLLAMA_HOST environment variable.”")
    }

    /// The quote is Ollama's and belongs only to Ollama's port. On any other
    /// port it would be a sentence about software that is not running there.
    func testARefusedConnectionOnAnotherPortDoesNotQuoteOllama() {
        let verdict = explain(pi { $0.port = 1234; $0.urlErrorCode = -1004 })
        XCTAssertEqual(verdict.cause, .nothingListening)
        XCTAssertEqual(verdict.sentence,
            "Nothing answered on 192.168.1.10 port 1234. Something has to be listening there, "
            + "and on an address other machines can reach rather than only on its own localhost.")
        XCTAssertFalse(verdict.sentence.contains("OLLAMA_HOST"))
    }

    // MARK: - the name did not resolve

    func testALocalNameThatDoesNotResolveOffersBonjourThePermissionAndANumericAddress() {
        let verdict = explain(Reachability.Observation(host: "duck.local", port: 11434,
                                                       urlErrorCode: -1003))
        XCTAssertEqual(verdict.cause, .hostNotFound)
        XCTAssertEqual(verdict.sentence,
            "Nothing on this network answers to the name duck.local. A .local name is found over "
            + "Bonjour, and iOS asks for Local Network permission the first time an app looks; if "
            + "that was declined, nothing here can reach it until Duck Studio is turned back on "
            + "under Settings, Privacy & Security, Local Network. An address like 192.168.1.10 "
            + "does not need the name to resolve, and is the quicker thing to try.")
    }

    /// The DNS-lookup code lands in the same place as the name-lookup one: same
    /// failure, same remedy.
    func testTheDNSLookupCodeIsTheSameStoryAsTheNameLookupCode() {
        let verdict = explain(Reachability.Observation(host: "duck.local", urlErrorCode: -1006))
        XCTAssertEqual(verdict.cause, .hostNotFound)
    }

    // MARK: - iOS blocked it before it left the phone

    /// A name lookup cannot be what failed when there was no name to look up.
    /// That is the fingerprint, and it is offered as a shape rather than as a
    /// reading of a switch this app does not read.
    func testANameLookupFailureAgainstALiteralAddressIsTheLocalNetworkPermission() {
        let verdict = explain(pi { $0.urlErrorCode = -1003 })
        XCTAssertEqual(verdict.cause, .localNetworkBlocked)
        XCTAssertEqual(verdict.sentence,
            "192.168.1.10 is an address rather than a name, so there was nothing to look up — "
            + "and iOS would not make the connection anyway. That is what a refused Local "
            + "Network permission looks like from in here, and this app does not read that "
            + "switch — so it is the shape of the failure and not a reading of the setting. Open "
            + "Settings, then Privacy & Security, then Local Network, and turn Duck Studio on. "
            + "If it is already on, then the address itself is the thing to check.")
    }

    /// An address on your own network needs no internet, so "the internet
    /// appears to be offline" cannot be why this one failed.
    func testOfflineAgainstAnAddressOnYourOwnNetworkIsTheLocalNetworkPermission() {
        let verdict = explain(Reachability.Observation(host: "duck.local", port: 8080,
                                                       urlErrorCode: -1009))
        XCTAssertEqual(verdict.cause, .localNetworkBlocked)
        XCTAssertEqual(verdict.sentence,
            "iOS said this phone has no connection at all, and yet duck.local port 8080 is on "
            + "your own network and needs none. That is what a refused Local Network permission "
            + "looks like from in here, and this app does not read that switch — so it is the "
            + "shape of the failure and not a reading of the setting. Open Settings, then "
            + "Privacy & Security, then Local Network, and turn Duck Studio on. If it is already "
            + "on, then the address itself is the thing to check.")
    }

    /// A Tailscale address is on your own network too, and the rule that says
    /// so is `ModelEndpoint.isLocalHost` rather than a second copy here.
    func testATailscaleAddressCountsAsYourOwnNetworkForThisToo() {
        let verdict = explain(Reachability.Observation(host: "100.101.102.103",
                                                       urlErrorCode: -1009))
        XCTAssertEqual(verdict.cause, .localNetworkBlocked)
    }

    /// THE BRANCH THAT MUST NOT OVERREACH: off your own network, the offline
    /// code means exactly what it says.
    func testOfflineAgainstAPublicHostIsJustOffline() {
        let verdict = explain(Reachability.Observation(host: "api.example.com", scheme: "https",
                                                       urlErrorCode: -1009))
        XCTAssertEqual(verdict.cause, .offline)
        XCTAssertEqual(verdict.sentence,
            "This phone has no network connection, so nothing could be tried. Nothing was "
            + "learned about api.example.com either way.")
    }

    // MARK: - it waited

    /// Both readings, because a slow machine and a firewall that drops packets
    /// are indistinguishable from here and have opposite remedies.
    func testATimeoutNamesBothTheSlowMachineAndTheFirewallThatDropsPackets() {
        let verdict = explain(pi { $0.urlErrorCode = -1001; $0.allowance = 15 })
        XCTAssertEqual(verdict.cause, .timedOut)
        XCTAssertEqual(verdict.sentence,
            "Nothing came back from 192.168.1.10 port 11434 inside 15.0 s. Two different things "
            + "look like this. A machine slow enough that even a list took longer than that — "
            + "slow is real here, a 7.5B model on a Raspberry Pi 5 took 766 s to write one "
            + "motion. Or a firewall on that machine swallowing the connection instead of "
            + "refusing it: a refused connection comes back at once, a dropped one leaves you "
            + "waiting.")
    }

    // MARK: - the transport refused it

    /// This one blames the build, because it is the build's fault: the app is
    /// supposed to declare the exception that lets a private address through.
    func testATransportSecurityRefusalOfAPrivateAddressBlamesTheBuild() {
        let verdict = explain(pi { $0.urlErrorCode = -1022 })
        XCTAssertEqual(verdict.cause, .plaintextBlocked)
        XCTAssertEqual(verdict.sentence,
            "iOS refused this connection as plain http even though 192.168.1.10 is on your own "
            + "network. That is a fault in this build rather than anything you did — the app is "
            + "meant to declare an exception for addresses like that one.")
    }

    func testATransportSecurityRefusalOfAPublicAddressSaysUseHTTPS() {
        let verdict = explain(Reachability.Observation(host: "api.example.com",
                                                       urlErrorCode: -1022))
        XCTAssertEqual(verdict.cause, .plaintextBlocked)
        XCTAssertEqual(verdict.sentence,
            "iOS refused this connection because it is plain http to api.example.com, which is "
            + "not on your own network. Use https for anything off your LAN.")
    }

    func testACertificateFailureOnYourOwnDeskSaysWhyHTTPIsAllowedThere() {
        let verdict = explain(pi { $0.scheme = "https"; $0.urlErrorCode = -1200 })
        XCTAssertEqual(verdict.cause, .tlsFailed)
        XCTAssertEqual(verdict.sentence,
            "The https handshake with 192.168.1.10 failed. A machine on your own desk usually "
            + "has no certificate anything trusts, which is why plain http is allowed here for "
            + "addresses on your own network — try http for this one.")
    }

    /// The whole certificate family, -1200 through -1206, is one story. -1199
    /// is not in it.
    func testEveryCertificateCodeIsTheSameStoryAndTheOneBelowThemIsNot() {
        for code in -1206...(-1200) {
            XCTAssertEqual(explain(pi { $0.urlErrorCode = code }).cause, .tlsFailed, "\(code)")
        }
        XCTAssertEqual(explain(pi { $0.urlErrorCode = -1199 }).cause, .unknown)
    }

    func testACertificateFailureOffYourNetworkDoesNotSuggestPlainHTTP() {
        let verdict = explain(Reachability.Observation(host: "api.example.com", scheme: "https",
                                                       urlErrorCode: -1200))
        XCTAssertEqual(verdict.sentence,
            "The https handshake with api.example.com failed. That is a certificate this phone "
            + "could not check, not a wrong address.")
        XCTAssertFalse(verdict.sentence.contains("try http"))
    }

    // MARK: - and when it is none of those

    func testAnUnrecognisedFailureQuotesTheSystemRatherThanInventingAReason() {
        let verdict = explain(pi {
            $0.urlErrorCode = -1005
            $0.systemText = "The network connection was lost."
        })
        XCTAssertEqual(verdict.cause, .unknown)
        XCTAssertEqual(verdict.sentence,
            "The connection to 192.168.1.10 port 11434 failed: The network connection was lost. "
            + "(-1005).")
    }

    func testAnUnrecognisedFailureWithNoSystemTextStillGivesTheCode() {
        let verdict = explain(pi { $0.urlErrorCode = -9999 })
        XCTAssertEqual(verdict.sentence,
            "The connection to 192.168.1.10 port 11434 failed, and the system gave no reason "
            + "beyond the code -9999.")
    }

    /// Neither a status nor a code: the probe came back with nothing at all,
    /// and saying so is better than pretending to know.
    func testAProbeThatSawNothingAtAllSaysExactlyThat() {
        let verdict = explain(Reachability.Observation(host: "192.168.1.10"))
        XCTAssertEqual(verdict.cause, .unknown)
        XCTAssertEqual(verdict.sentence,
            "The connection to 192.168.1.10 failed, and nothing came back to say why.")
    }

    // MARK: - the shape of the whole thing

    /// Every cause has to be producible and has to say something. A case added
    /// without a sentence, or a case no observation can reach, fails here.
    func testEveryCauseIsReachableAndEveryOneOfThemSaysSomething() {
        var produced: Set<Reachability.Cause> = []
        let table: [Reachability.Observation] = [
            pi { $0.status = 200; $0.modelsFound = 2 },
            pi { $0.status = 200; $0.modelsFound = 2; $0.seconds = 60 },
            pi { $0.status = 200; $0.modelsFound = 0 },
            pi { $0.status = 200; $0.modelsFound = 0; $0.listedEntries = 2 },
            pi { $0.status = 401 },
            pi { $0.status = 404 },
            pi { $0.status = 200; $0.body = "<html>" },
            pi { $0.status = 503 },
            pi { $0.urlErrorCode = -1004 },
            Reachability.Observation(host: "duck.local", urlErrorCode: -1003),
            pi { $0.urlErrorCode = -1003 },
            pi { $0.urlErrorCode = -1001 },
            pi { $0.urlErrorCode = -1022 },
            pi { $0.urlErrorCode = -1200 },
            Reachability.Observation(host: "api.example.com", urlErrorCode: -1009),
            pi { $0.urlErrorCode = -7 },
        ]
        for seen in table {
            let verdict = Reachability.explain(seen)
            produced.insert(verdict.cause)
            XCTAssertFalse(verdict.sentence.isEmpty, verdict.cause.rawValue)
        }
        XCTAssertEqual(produced, Set(Reachability.Cause.allCases))
    }

    /// The reason that sits beside the check button when there is nothing to
    /// check, so the disabled control is never silent.
    func testAnEmptyAddressHasItsOwnReasonRatherThanADisabledButtonWithNothingBesideIt() {
        XCTAssertEqual(Reachability.nothingToCheck,
            "There is no address to check yet. Paste the one that machine prints when its "
            + "server starts, with /v1 on the end.")
    }

    /// A literal address is one this app must not tell people to look up.
    func testAddressesAreToldApartFromNames() {
        XCTAssertTrue(Reachability.looksLikeAnAddress("192.168.1.10"))
        XCTAssertTrue(Reachability.looksLikeAnAddress("100.64.0.1"))
        XCTAssertTrue(Reachability.looksLikeAnAddress("fe80::1"))
        XCTAssertFalse(Reachability.looksLikeAnAddress("duck.local"))
        XCTAssertFalse(Reachability.looksLikeAnAddress("192.168.1"))
        XCTAssertFalse(Reachability.looksLikeAnAddress("999.1.1.1"))
        XCTAssertFalse(Reachability.looksLikeAnAddress("a.b.c.d"))
    }
}
