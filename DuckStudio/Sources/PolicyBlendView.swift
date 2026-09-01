import SwiftUI
import DuckKit
import StudioKit

/// Averaging two trained networks into a third, and finding out what it does.
///
/// THIS IS THE REMIX SCREEN. Nothing on this phone can train a policy — there
/// is no MuJoCo and no gradient here — but every policy in this family shares
/// one architecture, so two of them can be averaged into a file that loads. The
/// arithmetic runs in about a second over 197,774 numbers. That is the whole
/// capability, and it is real.
///
/// AND IT MOSTLY DOES NOT WORK, WHICH IS SAID BEFORE THE BUTTON, NOT AFTER.
/// Measured on the duckbench: `alpha_walking` averaged with `alpha_stand`
/// falls over at 25% and 50%, and at 75% stands still. `PolicyBlend` carries
/// that table. A screen that let somebody discover it as a surprise would be
/// selling a trick.
///
/// THE MEASURE BUTTON IS THE POINT OF THE SCREEN. A blend is a hypothesis and
/// this is the only place in the app that can settle one, because the bench has
/// physics and the phone does not. What comes back is a count AND a distance:
/// see `PolicyBlend.Behaviour` for why either alone is misleading.
struct PolicyBlendView: View {
    let library: PolicyLibrary

    /// THE BENCH IS CHOSEN, NOT TYPED. Every screen that reached a bench used
    /// to carry its own address box, so the same machine was configured three
    /// times and a token entered on one was missing on the next.
    @ObservedObject var benches: BenchStore
    /// Pre-chosen when this was opened from a policy's own screen: that screen
    /// knows which policy you were looking at and this one otherwise starts
    /// blank, asking you to find it again in a picker.
    var starting: PolicyLibrary.Entry?

    @State private var first: String?
    @State private var second: String?
    @State private var towardSecond = 0.5
    @State private var blended: Data?
    /// What the bytes in `blended` were ACTUALLY made from.
    ///
    /// THE PICKERS AND THE SLIDER MOVE AFTERWARDS, AND EVERYTHING DOWNSTREAM
    /// USED TO READ THEM. `mix()` is the only thing that clears `blended`, so a
    /// blend survives every later change to the controls above it — and then
    /// `measure` re-read `chosenPair` to decide which two networks to upload as
    /// the yardstick, and `PolicyBlend.measured` printed "it travelled X where
    /// the liveliest network it was made from travels Y" about two networks it
    /// was not made from. `export` had the same shape one level down: mix at
    /// 50/50, drag to 75, Save, and the 50/50 bytes leave the phone in a file
    /// called `blend-25-75.onnx`. The recipe footer identifies ingredients by
    /// digest precisely so a blend can be reproduced; the file name was the one
    /// artefact that then misidentified it.
    @State private var recipe: Recipe?

    /// The ingredients and ratio a blend was actually mixed from.
    struct Recipe {
        let first: PolicyLibrary.Entry
        let second: PolicyLibrary.Entry
        let towardSecond: Double
    }
    @State private var failure: String?
    @State private var busy = false
    @State private var outgoing: ExportedFile?
    @State private var verdict: String?
    @State private var uploadedAs: String?
    /// Whether `starting` has been offered to the First slot. See the `.task`.
    @State private var seeded = false

    /// Only policies that actually load. A blend of something this app refused
    /// would be a blend of nothing.
    private var candidates: [PolicyLibrary.Entry] { library.entries.filter(\.isRunnable) }

    var body: some View {
        Form {
            Section {
                Text(PolicyBlend.beforeYouRunIt)
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Ingredients") {
                picker("First", selection: $first)
                picker("Second", selection: $second)
                if chosenPair != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Slider(value: $towardSecond, in: 0...1, step: 0.05)
                        Text(shares).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }

            if let pair = chosenPair {
                Section {
                    Button(busy ? "Mixing…" : "Mix them") { mix(pair) }
                        .disabled(busy)
                } footer: {
                    Text(PolicyBlend.recipe(ingredients(pair)))
                        .font(.caption)
                }
            }

            if let blended {
                Section("The blend") {
                    if let recipe {
                        LabeledContent("Mixed from", value: String(
                            format: "%.0f%% %@ / %.0f%% %@",
                            (1 - recipe.towardSecond) * 100, recipe.first.displayName,
                            recipe.towardSecond * 100, recipe.second.displayName))
                        .font(.caption)
                    }
                    LabeledContent("Size", value: "\(blended.count / 1024) KB")
                    LabeledContent("Loads here", value: (try? DuckPolicy.load(from: blended)) != nil
                                                        ? "yes" : "no")
                    // THE SENTENCE THAT HAS TO SIT HERE. Everything above this
                    // row is about a file, and a file loading is the free claim.
                    Text(verdict ?? PolicyBlend.notYetMeasured)
                        .font(.footnote)
                        .foregroundStyle(verdict == nil ? .secondary : .primary)
                    Button("Save as .onnx") { export(blended) }
                }

                // A STRING TITLE AND A FOOTER CLOSURE DO NOT COMBINE.
                // `Section("x") { } footer: { }` is not an initializer that
                // exists — the header has to become a closure too. Caught by
                // the Mac; `swiftc -parse` sees valid syntax here because the
                // mistake is in overload resolution, not grammar.
                Section {
                    if benches.benches.isEmpty {
                        NavigationLink { BenchSettingsView(store: benches) } label: {
                            Label("Set up a bench", systemImage: "plus.circle")
                        }
                        Text("Blending happens on this phone. Finding out whether the result "
                           + "does anything needs physics, and that lives on another machine.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Bench", selection: Binding(
                            get: { benches.selectedID },
                            set: { benches.selectedID = $0 })) {
                            ForEach(benches.benches) { one in
                                Text(one.name).tag(UUID?.some(one.id))
                            }
                        }
                        Button(busy ? "Running…" : "Send to the bench and measure") {
                            Task { await measure(blended) }
                        }
                        .disabled(benches.selected == nil || busy)
                        // ALWAYS REACHABLE, NOT ONLY WHEN EMPTY. Every one of
                        // these screens used to offer a route to bench settings
                        // right up until a bench existed, and then hide it —
                        // so the moment you had two machines was the moment you
                        // could no longer switch between them from here.
                        NavigationLink { BenchSettingsView(store: benches) } label: {
                            Label("Manage benches", systemImage: "slider.horizontal.3")
                        }
                    }
                    if let uploadedAs {
                        Text("The bench called it \(uploadedAs).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Run it somewhere with physics")
                } footer: {
                    Text("Six seconds, commanded forward at vx 0.5 — below about 0.3 the walking "
                       + "policy simply stands, and two ducks standing still look alike.")
                }
            }

            if let failure {
                Section { Text(failure).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Blend policies")
        .task {
            // ONCE PER SCREEN, NOT ONCE PER APPEARANCE. `.task` re-runs every
            // time this view comes back, and pushing "Set up a bench" or
            // "Manage benches" from inside it is exactly that: leave, come
            // back, and the seed fires again. `first == nil` cannot tell "never
            // seeded" from "set to None on purpose to pick a different pair",
            // so returning from bench settings silently put the originating
            // policy back in the First slot.
            guard !seeded else { return }
            seeded = true
            if first == nil, let starting { first = starting.id }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $outgoing) { file in
            ShareSheet(items: [file.url]) { outgoing = nil }
        }
    }

    /// TAGGED BY IDENTITY, NOT BY THE ENTRY. `PolicyLibrary.Entry` is Equatable
    /// and not Hashable, which a `Picker` tag requires — and the identity is
    /// the better key anyway, being the digest of the weights rather than a
    /// filename anybody can retype.
    private func picker(_ label: String, selection: Binding<String?>) -> some View {
        Picker(label, selection: selection) {
            Text("None").tag(String?.none)
            ForEach(candidates) { entry in
                Text(entry.displayName).tag(String?.some(entry.id))
            }
        }
    }

    private func entry(_ id: String?) -> PolicyLibrary.Entry? {
        id.flatMap { wanted in candidates.first { $0.id == wanted } }
    }

    private var chosenPair: (PolicyLibrary.Entry, PolicyLibrary.Entry)? {
        guard let a = entry(first), let b = entry(second), a.id != b.id else { return nil }
        return (a, b)
    }

    private var shares: String {
        String(format: "%.0f%% / %.0f%%", (1 - towardSecond) * 100, towardSecond * 100)
    }

    private func ingredients(_ pair: (PolicyLibrary.Entry, PolicyLibrary.Entry))
        -> [PolicyBlend.Ingredient] {
        [.init(name: pair.0.displayName, fingerprint: pair.0.identity.value,
               share: 1 - towardSecond),
         .init(name: pair.1.displayName, fingerprint: pair.1.identity.value,
               share: towardSecond)]
    }

    // MARK: - doing it

    private func mix(_ pair: (PolicyLibrary.Entry, PolicyLibrary.Entry)) {
        busy = true; failure = nil; blended = nil; verdict = nil; uploadedAs = nil
        recipe = nil
        defer { busy = false }
        do {
            guard let a = PolicyStore.data(for: pair.0),
                  let b = PolicyStore.data(for: pair.1) else {
                failure = "One of those files is not on this phone any more."
                return
            }
            let x = try DuckPolicy.load(from: a).parameters
            let y = try DuckPolicy.load(from: b).parameters
            // CAPTURED WITH THE BYTES, not read back off the controls later.
            let ratio = towardSecond
            blended = try PolicyBlend.mix([(x, 1 - ratio), (y, ratio)])
            recipe = Recipe(first: pair.0, second: pair.1, towardSecond: ratio)
        } catch let refusal as PolicyBlend.Refusal {
            failure = refusal.message
        } catch let refusal as DuckPolicyWriter.WriteError {
            failure = refusal.message
        } catch {
            failure = error.localizedDescription
        }
    }

    private func export(_ data: Data) {
        do {
            let toward = recipe?.towardSecond ?? towardSecond
            let ratio = String(format: "%.0f-%.0f", (1 - toward) * 100, toward * 100)
            outgoing = ExportedFile(url: try ExportFile.write(data, named: "blend-\(ratio).onnx"))
        } catch let refusal as ExportFile.Failure {
            failure = refusal.message
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Upload, then run the blend and its liveliest ingredient under the SAME
    /// command — because the ingredient's distance is the yardstick, and a
    /// yardstick measured under a different command is not one.
    @MainActor private func measure(_ data: Data) async {
        busy = true; failure = nil; verdict = nil
        defer { busy = false }
        do {
            guard let chosen = benches.selected else { throw DuckBench.Refusal.empty }
            let armed = benches.armed(chosen)
            let address = try armed.resolved()
            func ask(_ call: DuckBench.Call) async throws -> Data {
                try await URLSession.shared.data(
                    for: DuckBench.urlRequest(for: call, token: armed.token)).0
            }

            let name = try DuckBench.readUploaded(
                await ask(try DuckBench.upload(address, onnx: data)))
            uploadedAs = name

            let blend = try DuckBench.readTravel(await ask(try DuckBench.record(
                address, policy: name, seconds: 6, schedule: DuckBench.walkingCommand)))
            let rate = try DuckBench.readSuccess(await ask(try DuckBench.measure(
                address, policy: name, seconds: 6, rollouts: 8,
                schedule: DuckBench.walkingCommand)))

            // The yardstick: whichever ingredient goes furthest under this same
            // command. Uploading them is how a bench that has never seen them
            // gets to run them.
            var furthest = 0.0
            // THE RECIPE'S OWN INGREDIENTS. `chosenPair` is whatever the
            // pickers say now, and it is also nil the moment either is set to
            // "None" — which skipped this loop entirely, left `furthest` at 0.0
            // and let the verdict compare the blend against nothing.
            if let recipe {
                for entry in [recipe.first, recipe.second] {
                    guard let bytes = PolicyStore.data(for: entry) else { continue }
                    let put = try DuckBench.readUploaded(
                        await ask(try DuckBench.upload(address, onnx: bytes)))
                    let seen = try DuckBench.readTravel(await ask(try DuckBench.record(
                        address, policy: put, seconds: 6, schedule: DuckBench.walkingCommand)))
                    furthest = max(furthest, seen.travelled)
                }
            }

            verdict = PolicyBlend.measured(.init(
                achieves: rate.achieves, rollouts: rate.rollouts, criterion: rate.criterion,
                travelled: blend.travelled, liveliestIngredientTravelled: furthest,
                plant: DuckBench.recordedCredit(plantName: blend.plantName,
                                                plantDigest: blend.plantDigest)))
        } catch let refusal as DuckBench.Refusal {
            failure = refusal.message
        } catch let refusal as BenchEndpoint.Refusal {
            failure = refusal.message
        } catch let error as DuckBench.ReadError {
            failure = error.message
        } catch {
            failure = error.localizedDescription
        }
    }
}
