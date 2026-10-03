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

    /// The job in flight, kept across launches so closing the window does not lose it.
    struct SavedJob: Codable, Equatable {
        let id: String
        let batchID: String
        let dataset: String
        let namespace: String

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
            token = TokenStore.load() ?? ""
            if !token.isEmpty { await check() }
            await watch()
        }
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
        guard let account, let url = HubTraining.jobsURL(namespace: account) else { return }
        busy = true; defer { busy = false }
        failure = nil; fetched = nil
        let batchID = recipe.batchID(at: Date())
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: HubTraining.requestBody(
            recipe: recipe, batchID: batchID, dataset: dataset, token: token))
        do {
            let data = try await call(request)
            guard let started = HubTraining.jobState(from: data) else {
                failure = "Hugging Face accepted the job but its answer could not be read. Check huggingface.co/jobs."
                return
            }
            let saved = SavedJob(id: started.id, batchID: batchID, dataset: dataset, namespace: account)
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
            fetched = "\(job.batchID) is in Behaviours. Measure it on a bench before trusting it."
        } catch { failure = error.localizedDescription }
    }
}
