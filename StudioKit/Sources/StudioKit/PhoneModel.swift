import Foundation

/// Language models small enough to run on the phone itself, downloaded from
/// Hugging Face.
///
/// WHY THIS EXISTS. "A model on this phone" already existed as a preset and
/// meant something narrower than it sounded: an address, `localhost:8080`,
/// where ANOTHER APP was serving a model. So the honest version of that row was
/// "a model in a different app on this phone", and somebody without that other
/// app had no on-device option but Apple's.
///
/// THE SIZE IS THE WHOLE PROBLEM, AND IT IS WHY THIS TYPE IS MOSTLY NUMBERS.
/// iOS does not give an app the phone's RAM; it gives it a budget, and kills it
/// for exceeding one. A 4-bit 4B model is 2.3 GB of weights before any working
/// memory, which fits comfortably on an 8 GB phone, marginally on 6 GB, and not
/// at all on 4 GB. A catalogue that listed models without saying that would
/// invite somebody to spend twenty minutes downloading three gigabytes over
/// cellular and then watch the app die.
///
/// SO EVERY SIZE HERE WAS MEASURED, NOT ESTIMATED. Downloaded byte counts come
/// from the Hugging Face tree API on 2026-08-31, summed over each repository's
/// files. They are recorded rather than rounded because the difference between
/// 984 MB and "about a gigabyte" is the difference between fitting and not.
///
/// AND A SMALL MODEL IS ACCEPTABLE HERE FOR A REASON THAT IS NOT TRUE OF MOST
/// APPS. Everything a model writes in Duck Studio is parsed, resolved and
/// clamped by tested code before it reaches a joint — `IntentDraft` refuses a
/// pose outside the robot's travel, and `DraftRouting` refuses an answer it
/// cannot read. The failure mode of a weak model here is a refusal, not a duck
/// doing something dangerous. That is what makes a 1B model worth offering.
public struct PhoneModel: Equatable, Sendable, Identifiable {

    public var id: String { repository }
    /// The Hugging Face repository, which is also what the loader is given.
    public let repository: String
    public let name: String
    /// Parameters, as the publisher counts them.
    public let parameters: String
    /// Total bytes of the repository, measured.
    public let downloadBytes: Int
    /// What it is like to use for this app's job, honestly.
    public let note: String

    public init(repository: String, name: String, parameters: String,
                downloadBytes: Int, note: String) {
        self.repository = repository; self.name = name
        self.parameters = parameters
        self.downloadBytes = downloadBytes; self.note = note
    }

    /// Roughly what it needs resident to answer, which is more than it weighs
    /// on disk: the weights, plus room for the context and the arithmetic.
    ///
    /// THE MULTIPLIER IS A RULE OF THUMB AND IS LABELLED AS ONE. It is not
    /// measured on a phone — nothing here has been — so `fits` is deliberately
    /// conservative and the sentence beside it says the number is an estimate.
    public var estimatedPeakBytes: Int { downloadBytes + 350_000_000 }

    public var downloadDescription: String { PhoneModel.megabytes(downloadBytes) }

    static func megabytes(_ bytes: Int) -> String {
        bytes >= 1_000_000_000
            ? String(format: "%.1f GB", Double(bytes) / 1e9)
            : String(format: "%.0f MB", Double(bytes) / 1e6)
    }

    /// Whether this is worth starting, given what iOS says this app may use.
    ///
    /// TAKES THE BUDGET RATHER THAN READING IT. `os_proc_available_memory()` is
    /// the only honest source and it lives in the app; passing the number in
    /// keeps the rule testable.
    public func fits(budgetBytes: Int) -> Bool { estimatedPeakBytes <= budgetBytes }

    /// The measured catalogue. Ordered smallest first, because the smallest one
    /// that works is the right answer on a phone.
    ///
    /// EVERY ENTRY IS TEXT-ONLY, AND THAT IS A REQUIREMENT RATHER THAN A
    /// COINCIDENCE. A multimodal repository ships vision and audio towers that
    /// this app's text path loads and throws away — `MLXLLM/Models/Gemma4.swift`
    /// skips every `vision_tower`, `audio_tower` and `multi_modal_projector`
    /// key — so its download size is money spent on weights that never run, and
    /// `estimatedPeakBytes` computed from that size is wrong. `gemma-3-4b-it-qat-4bit`
    /// was here and came out for exactly that: 3.0 GB, part of it a vision
    /// tower, where `Qwen3-4B` covers the same size point at 2.28 GB with all
    /// of it doing work.
    ///
    /// THERE IS NO GEMMA 4 ROW YET, AND ITS ABSENCE IS MEASURED TOO. Gemma 4
    /// has no 1B tier; its smallest loadable artifact is 2.67 GB, 3.5× the
    /// Gemma 3 1B here. Half of an E2B download — 1,321,205,760 of 2,634,394,182
    /// tensor bytes — is the Per-Layer Embedding table, which Google's card
    /// calls "only used for quick lookups" and which this stack builds as a
    /// plain resident `Embedding` and materialises with `eval(model)`. So the
    /// "2.3B effective" framing buys back no memory here, and a Gemma 4 row
    /// would need a device run before this list, whose contract is that it has
    /// been tried, could honestly carry it.
    public static let catalogue: [PhoneModel] = [
        .init(repository: "mlx-community/Qwen3-0.6B-4bit",
              name: "Qwen3 0.6B", parameters: "0.6B", downloadBytes: 351_000_000,
              note: "Small enough for any phone that runs this app. It will get simple motions "
                  + "roughly right and will lose the thread on anything with two clauses in it. "
                  + "Worth trying first because it costs a third of a gigabyte to find out."),
        .init(repository: "mlx-community/Llama-3.2-1B-Instruct-4bit",
              name: "Llama 3.2 1B", parameters: "1B", downloadBytes: 713_000_000,
              note: "The smallest one that follows a format reliably, which is what this app "
                  + "actually asks of it — every angle it writes is checked and clamped here "
                  + "afterwards."),
        .init(repository: "mlx-community/gemma-3-1b-it-qat-4bit",
              name: "Gemma 3 1B", parameters: "1B", downloadBytes: 772_000_000,
              note: "Quantisation-aware trained, so it loses less at 4-bit than a model squashed "
                  + "after the fact. A good default on a phone with 6 GB or more."),
        .init(repository: "mlx-community/Qwen3-1.7B-4bit",
              name: "Qwen3 1.7B", parameters: "1.7B", downloadBytes: 984_000_000,
              note: "Noticeably better at following a sentence with a condition in it. Under a "
                  + "gigabyte, which still leaves room on most phones."),
        .init(repository: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
              name: "Qwen3 4B", parameters: "4B", downloadBytes: 2_279_000_000,
              note: "The best of these at reading a whole paragraph, and the first that will not "
                  + "fit on a 4 GB phone. Download it on Wi-Fi."),

    ]

    /// What has to be said above the list.
    public static let preamble =
        "These run on the phone itself: nothing you type leaves it, and they work with no network "
      + "once downloaded. They are also slower and weaker than anything on a desktop, so the "
      + "smallest one that does the job is the right one."

    /// Said next to a model that will not fit.
    public static func tooBig(_ model: PhoneModel, budgetBytes: Int) -> String {
        "\(model.name) needs roughly \(megabytes(model.estimatedPeakBytes)) resident and iOS is "
      + "offering this app about \(megabytes(budgetBytes)). It would be killed part-way through "
      + "an answer. That estimate is a rule of thumb, not a measurement on this phone."
    }

    /// Why Apple's model is still there, and when to prefer it.
    public static let versusApple =
        "Apple's on-device model needs no download and no space, and on a recent phone it is "
      + "better than the small end of this list. Download one of these when Apple's is "
      + "unavailable on your device, or when you want the same model this app uses everywhere "
      + "else."
}
