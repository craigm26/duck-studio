import SwiftUI
import AVFoundation
import Speech
import StudioKit

/// The mic on Tell and on Ask the duck: on-device speech recognition only (build 92).
///
/// STOP IS HEARD ON THE WAY, NOT AT THE END. Every partial transcript goes to the kit's
/// `StopWords`; "stop", "freeze" or "no" calls `onStop` at once, before the sentence is finished,
/// and the listening ends. The finished sentence goes to `onFinal`, which hands it to the same
/// matcher or decider as typed words, so speech adds no second way to move the duck.
///
/// ON THE DEVICE OR NOT AT ALL. `requiresOnDeviceRecognition` is set, and a recogniser that
/// cannot run on the device leaves the mic off with the kit's sentence, rather than sending a
/// person's voice to a server they did not choose.
@MainActor
final class DuckListener: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var heard = ""
    /// Why the mic cannot be used here, or nil.
    @Published private(set) var problem: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var stopWords = StopWords()
    private var onStop: (() -> Void)?
    private var onFinal: ((String) -> Void)?
    private var delivered = false

    private lazy var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    /// Tap the mic: start, or finish if already listening.
    func toggle(onStop: @escaping () -> Void, onFinal: @escaping (String) -> Void) {
        if listening { finish(); return }
        Task { await start(onStop: onStop, onFinal: onFinal) }
    }

    func start(onStop: @escaping () -> Void, onFinal: @escaping (String) -> Void) async {
        guard !listening else { return }
        problem = nil
        guard await Self.allowed() else { problem = MicWords.notAllowed; return }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            problem = MicWords.notOnDevice
            return
        }
        self.onStop = onStop
        self.onFinal = onFinal
        delivered = false
        heard = ""
        stopWords.begin()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = ["Microduck", "quack", "roulade", "kick left", "kick right",
                                     "sit down", "stand up", "turn left", "turn right"]
        self.request = request

        do {
#if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            teardown()
            problem = MicWords.notAllowed
            return
        }
        listening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text { self.hear(text, final: isFinal) }
                if error != nil, self.listening { self.finish() }
            }
        }
    }

    /// Finish listening and hand over what was heard.
    func finish() {
        guard listening else { return }
        request?.endAudio()
        teardown()
        deliver()
    }

    /// Stop listening and hand nothing over.
    func cancel() {
        onFinal = nil
        onStop = nil
        task?.cancel()
        teardown()
    }

    private func hear(_ text: String, final: Bool) {
        heard = text
        // THE KEYWORD PATH, before the sentence is done. No model is involved.
        if stopWords.hear(text) {
            let stop = onStop
            cancel()
            heard = MicWords.heardStop
            stop?()
            return
        }
        if final {
            teardown()
            deliver()
        }
    }

    private func deliver() {
        guard !delivered else { return }
        delivered = true
        let said = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = onFinal
        onFinal = nil
        onStop = nil
        if said.isEmpty { problem = MicWords.heardNothing; return }
        final?(said)
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        listening = false
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }

    /// Speech recognition and the microphone, both allowed.
    private static func allowed() async -> Bool {
        let speech: Bool = await withCheckedContinuation { k in
            SFSpeechRecognizer.requestAuthorization { k.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
#if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
#else
        return await AVCaptureDevice.requestAccess(for: .audio)
#endif
    }
}

/// The round mic button, the same on Tell and on Ask the duck.
struct MicButton: View {
    @ObservedObject var listener: DuckListener
    let onStop: () -> Void
    let onFinal: (String) -> Void

    var body: some View {
        Button {
            listener.toggle(onStop: onStop, onFinal: onFinal)
        } label: {
            Image(systemName: listener.listening ? "waveform" : "mic.fill")
                .font(.body.weight(.semibold))
                .frame(width: DesignMetric.minimumTarget, height: DesignMetric.minimumTarget)
                .symbolEffect(.variableColor.iterative, isActive: listener.listening)
        }
        .buttonStyle(.bordered)
        .clipShape(Circle())
        .accessibilityLabel(Text(listener.listening ? MicWords.listening : MicWords.speak))
    }
}
