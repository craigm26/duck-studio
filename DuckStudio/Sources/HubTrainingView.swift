import SwiftUI
import StudioKit

/// Train with PPO on Hugging Face: write the reward here, run Pollen's PPO on a rented GPU,
/// bring the trained network back.
///
/// ON THE PHONE TOO, BECAUSE THE PHONE IS THE POINT. The stated goal (2026-10-02) is an
/// iPhone that trains new policies by renting the RL steps on Hugging Face. Nothing here
/// needs a Mac: it is a token, a form, HTTP and a poll, and the GPU is Hugging Face's. If iOS
/// suspends the app mid-run the job carries on at Hugging Face; `SavedJob` is what the
/// screen picks back up on return.
///
/// WHAT THIS SCREEN DECIDES IS SMALL ON PURPOSE. `HubTraining.Recipe` is b003b's recipe with
/// two numbers a person may move and a length. Everything else — which student, which teacher,
/// the anchor, the measuring — is duckbatch's at the pinned commit, so a run started here is
/// comparable with every run before it.
struct HubTrainingView: View {
    /// Where a finished network goes: the same door a file dropped on the app goes through.
    let onPolicy: (URL) -> Void

    @State private var token = ""
    @State private var account: String?
    @State private var recipe = HubTraining.Recipe(name: "Walk slowly")
    @State private var full = false
    @State private var dataset = ""
    @State private var job: SavedJob? = SavedJob.load()
    @State private var state: HubTraining.JobState?
    @State private var failure: String?
    @State private var busy = false
    @State private var fetched: String?
    /// Network-vs-network picks with features, read from the feedback log on appear.
    @State private var picks: [PreferenceModel.Pick] = []
    @State private var usePicks = false
    /// Kick picks per skill, from the kick duels in Compare.
    @State private var skillPicks: [String: [PreferenceModel.Pick]] = [:]

    /// The job in flight, kept across launches so closing the window does not lose it.
    struct SavedJob: Codable, Equatable {
        let id: String
        let batchID: String
        let dataset: String
        let namespace: String
        /// The skill a kick job trains; nil for walking. A kick starts from Pollen's kick, which
        /// ships in the app, so only a walking job fetches the network it started from.
        var skill: String? = nil

        private static let key = "hubTraining.lastJob"
        static func load() -> SavedJob? {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(SavedJob.self, from: data)
        }
        func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key) }
        static func clear() { UserDefaults.standard.removeObject(forKey: key) }
    }

    var body: some View {
        Form {
            Section {
                Text(HubTraining.whatThisIs)
                Text(HubTraining.notClaimed).foregroundStyle(Theme.textSecondary)
            } header: { SectionHeading(text: "What this is") }

            Section {
                SecureField("hf_…", text: $token)
                Button("Check this token") { Task { await check() } }
                    .disabled(token.isEmpty || busy)
                if let account { Text("Signed in as \(account). Jobs are billed to this account.") }
            } header: { SectionHeading(text: "Your Hugging Face token") } footer: {
                Text("A WRITE token: the job uploads its records with it. It is sent to huggingface.co as a job secret, never in the job's environment or its log.")
            }

            Section {
                Text(PreferenceModel.whatThisDoes).font(.callout)
                if picks.count < PreferenceModel.minimumPicks {
                    Text(PreferenceModel.notEnoughPicks(picks.count))
                        .foregroundStyle(Theme.textSecondary)
                } else if let fitted = fittedFromPicks {
                    Toggle("Train from my \(picks.count) picks", isOn: $usePicks)
                        .onChange(of: usePicks) { _, on in recipe.fromPicks = on ? fitted : nil }
                    ForEach(PreferenceModel.groups, id: \.name) { g in
                        LabeledContent(g.said.prefix(1).uppercased() + g.said.dropFirst(),
                                       value: String(format: "×%.2f", fitted.plan.multipliers[g.name] ?? 1))
                    }
                    if !fitted.plan.reversed.isEmpty {
                        Text("Left at Pollen's weight, because your picks favoured more of it: "
                             + fitted.plan.reversed.joined(separator: ", ") + ".")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            } header: { SectionHeading(text: "Train from your picks") } footer: {
                Text("Picks come from Compare: two networks walking under the same command. Each multiplier scales Pollen's weight for that part of the reward, between ×0.5 and ×2.")
            }

            Section {
                ForEach([PreferenceModel.Profile.kickRight, .kickLeft], id: \.skill) { profile in
                    let n = skillPicks[profile.skill]?.count ?? 0
                    if n < PreferenceModel.minimumPicks {
                        Text(PreferenceModel.notEnoughPicks(n, profile: profile))
                            .foregroundStyle(Theme.textSecondary)
                    } else if let fitted = fitted(profile) {
                        ForEach(profile.groups, id: \.name) { g in
                            LabeledContent(g.said.prefix(1).uppercased() + g.said.dropFirst(),
                                           value: String(format: "×%.2f", fitted.plan.multipliers[g.name] ?? 1))
                        }
                        Button("Train a \(profile.plural.dropLast()) from my \(n) picks") {
                            Task { await launchSkill(profile, fitted) }
                        }
                        .disabled(busy || account == nil || dataset.isEmpty || job != nil)
                    }
                }
            } header: { SectionHeading(text: "Train a kick from your picks") } footer: {
                Text("Picks come from Compare's kick duels, where the simulator measured each kick. A kick is trained the way k001 was: from Pollen's network, 1,000 iterations, judged by your picks against the kick it started from.")
            }

            Section {
                TextField("Name", text: $recipe.name)
                Toggle("Full run (1,500 iterations, about 1½ h on an L4)", isOn: $full)
                    .onChange(of: full) { _, on in recipe.iterations = on ? 1500 : 100 }
                Stepper(value: $recipe.linearProgressWeight, in: 0...4, step: 0.25) {
                    Text("Pay for walking: \(recipe.linearProgressWeight, specifier: "%.2f")")
                }
                Stepper(value: $recipe.angularProgressWeight, in: 0...4, step: 0.25) {
                    Text("Pay for turning: \(recipe.angularProgressWeight, specifier: "%.2f")")
                }
                TextField("Records dataset", text: $dataset)
                if let refusal = recipe.refusal { Text(refusal).foregroundStyle(.red) }
            } header: { SectionHeading(text: "The reward") } footer: {
                Text("Each weight pays for going: speed along the commanded direction, as a fraction of the command, nothing for standing still. The tracking terms beside them weigh 2.0 each. \(recipe.isPilot ? "A pilot is 100 iterations, about a quarter of an hour with setup, and is judged only on whether it runs." : "")")
            }

            Section {
                ScrollView(.horizontal) {
                    Text(recipe.menuYAML(batchID: recipe.batchID(at: Date())))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(minHeight: 220)
            } header: { SectionHeading(text: "The menu, pass lines first") } footer: {
                Text("The pass lines are written into the menu before it runs, so the result cannot move them.")
            }

            Section {
                Button(job == nil ? "Train on Hugging Face" : "Train another") { Task { await launch() } }
                    .disabled(busy || account == nil || recipe.refusal != nil || dataset.isEmpty
                              || (state.map { !$0.stage.isFinal } ?? false))
                if let job {
                    LabeledContent("Job", value: String(job.id.prefix(12)))
                    LabeledContent("Batch", value: job.batchID)
                    Text(state?.stage.said ?? "Checking…")
                    if let message = state?.message, !message.isEmpty { Text(message).font(.caption) }
                    if let url = URL(string: "https://huggingface.co/jobs/\(job.namespace)/\(job.id)") {
                        Link("Open the job and its log", destination: url)
                    }
                    if state?.stage == .completed {
                        if let url = URL(string: "https://huggingface.co/datasets/\(job.dataset)/tree/main/jobs/\(job.id)/\(job.batchID)") {
                            Link("Open the records (record.json has the speed curve)", destination: url)
                        }
                        Button("Add the trained network to Behaviours") { Task { await bringBack(job) } }
                            .disabled(busy)
                    }
                }
                if let fetched { Text(fetched) }
                if let failure { Text(failure).foregroundStyle(.red) }
            } header: { SectionHeading(text: "Run it") } footer: {
                Text("Runs duckbatch \(String(HubTraining.duckbatchCommit.prefix(7))) on an \(HubTraining.flavor) GPU. Billed by Hugging Face to the account above.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(HubTraining.rowTitle)
        .task {
            let log = FeedbackStore().log
            picks = PreferenceModel.picks(fromLog: log)
            for profile in [PreferenceModel.Profile.kickRight, .kickLeft] {
                skillPicks[profile.skill] = PreferenceModel.picks(fromLog: log, profile: profile)
            }
            token = TokenStore.load() ?? ""
            if !token.isEmpty { await check() }
            await watch()
        }
    }

    /// The taste your picks describe and the reward it becomes, once there are enough.
    private var fittedFromPicks: HubTraining.Recipe.FromPicks? {
        guard picks.count >= PreferenceModel.minimumPicks else { return nil }
        let taste = PreferenceModel.fit(picks)
        return .init(taste: taste, plan: PreferenceModel.rewardPlan(from: taste))
    }

    private func fitted(_ profile: PreferenceModel.Profile) -> HubTraining.Recipe.FromPicks? {
        guard let p = skillPicks[profile.skill], p.count >= PreferenceModel.minimumPicks else { return nil }
        let taste = PreferenceModel.fit(p)
        return .init(taste: taste, plan: PreferenceModel.rewardPlan(from: taste, profile: profile))
    }

    private func launchSkill(_ profile: PreferenceModel.Profile,
                             _ fitted: HubTraining.Recipe.FromPicks) async {
        let skill = HubTraining.SkillRecipe(name: "My \(profile.plural.dropLast())", profile: profile,
                                            fromPicks: fitted)
        let batchID = skill.batchID(at: Date())
        await launch(batchID: batchID, skill: profile.skill, body: HubTraining.requestBody(
            skill: skill, batchID: batchID, dataset: dataset, token: token))
    }

    private func call(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "HubTraining", code: code, userInfo: [NSLocalizedDescriptionKey:
                "Hugging Face answered \(code): \(String(decoding: data.prefix(300), as: UTF8.self))"])
        }
        return data
    }

    private func check() async {
        busy = true; defer { busy = false }
        do {
            let data = try await call(HuggingFacePublish.urlRequest(for: HuggingFacePublish.whoami(),
                                                                   token: token))
            account = HuggingFacePublish.parseWhoami(data)
            if let account {
                TokenStore.save(token)
                if dataset.isEmpty { dataset = "\(account)/duckbatch-records" }
            }
        } catch { failure = error.localizedDescription; account = nil }
    }

    private func launch() async {
        let batchID = recipe.batchID(at: Date())
        await launch(batchID: batchID, body: HubTraining.requestBody(
            recipe: recipe, batchID: batchID, dataset: dataset, token: token))
    }

    private func launch(batchID: String, skill: String? = nil, body: [String: Any]) async {
        guard let account, let url = HubTraining.jobsURL(namespace: account) else { return }
        busy = true; defer { busy = false }
        failure = nil; fetched = nil
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let data = try await call(request)
            guard let started = HubTraining.jobState(from: data) else {
                failure = "Hugging Face accepted the job but its answer could not be read. Check huggingface.co/jobs."
                return
            }
            let saved = SavedJob(id: started.id, batchID: batchID, dataset: dataset, namespace: account,
                                 skill: skill)
            saved.save(); job = saved; state = started
            Haptic.finished()
            await watch()
        } catch { failure = error.localizedDescription }
    }

    /// Every 30 s until the job is over. A job outlives this screen; coming back resumes it.
    private func watch() async {
        while let job, !Task.isCancelled {
            guard let url = URL(string: "https://huggingface.co/api/jobs/\(job.namespace)/\(job.id)") else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let data = try? await call(request), let now = HubTraining.jobState(from: data) {
                state = now
                if now.stage.isFinal { return }
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private func bringBack(_ job: SavedJob) async {
        guard let url = HubTraining.fileURL(dataset: job.dataset, jobID: job.id,
                                            batchID: job.batchID, path: HubTraining.policyPath)
        else { return }
        busy = true; defer { busy = false }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let data = try await call(request)
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(job.batchID).onnx")
            try data.write(to: file, options: .atomic)
            onPolicy(file)
            // AND THE NETWORK IT STARTED FROM, for the duel the run is judged by.
            if job.skill == nil, let start = HubTraining.startingNetworkURL,
               let (bytes, _) = try? await URLSession.shared.data(from: start) {
                let startFile = FileManager.default.temporaryDirectory
                    .appendingPathComponent(HubTraining.startingNetworkName)
                if (try? bytes.write(to: startFile, options: .atomic)) != nil { onPolicy(startFile) }
            }
            fetched = job.skill == nil
                ? "\(job.batchID) and the network it started from are in Behaviours. "
                  + "Compare the two: the run is judged by you picking the trained one at least 12 times in 20."
                : "\(job.batchID) is in Behaviours, beside Pollen's kick it started from. Compare the "
                  + "two: the run is judged by you picking the trained one at least 12 times in 20."
        } catch { failure = error.localizedDescription }
    }
}
