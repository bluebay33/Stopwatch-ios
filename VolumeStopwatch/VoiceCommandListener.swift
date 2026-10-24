import AVFAudio
import Speech

enum VoiceCommand {
    case start
    case stopAndReset
}

@MainActor
final class VoiceCommandListener: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var statusMessage = "VOICE: REQUESTING ACCESS…"
    @Published private(set) var commandSequence = 0
    private(set) var latestCommand: VoiceCommand?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastRecognizedCommandAt = Date.distantPast
    private var wantsListening = false
    private var isRestarting = false

    func requestAccessAndStart() {
        wantsListening = true
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self else { return }
                guard authorization == .authorized else {
                    self.statusMessage = "VOICE: SPEECH ACCESS IS OFF"
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.statusMessage = "VOICE: MICROPHONE ACCESS IS OFF"
                            return
                        }
                        self.startListening()
                    }
                }
            }
        }
    }

    func restartListening() {
        wantsListening = true
        stopEngine()
        startListening()
    }

    func startListening() {
        guard wantsListening, !audioEngine.isRunning else { return }
        guard recognizer?.isAvailable == true else {
            statusMessage = "VOICE: NOT AVAILABLE"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .confirmation
            request.contextualStrings = ["start", "go", "stop", "reset", "MarkLap"]
            request.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition == true
            recognitionRequest = request

            let input = audioEngine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                let transcript = result?.bestTranscription.formattedString
                let isFinished = result?.isFinal == true || error != nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let transcript { self.consume(transcript) }
                    if isFinished { self.restartAfterRecognitionEnds() }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            statusMessage = "VOICE ON: SAY START, GO, OR STOP"
        } catch {
            statusMessage = "VOICE: COULDN’T START"
            stopListening()
        }
    }

    func stopListening() {
        wantsListening = false
        stopEngine()
    }

    private func stopEngine() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    private func restartAfterRecognitionEnds() {
        guard wantsListening, !isRestarting else { return }
        isRestarting = true
        stopEngine()
        statusMessage = "VOICE: RECONNECTING…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.isRestarting = false
            self.startListening()
        }
    }

    private func consume(_ transcript: String) {
        let words = Set(transcript.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let now = Date()
        guard now.timeIntervalSince(lastRecognizedCommandAt) > 1.2 else { return }

        if words.contains("start") || words.contains("go") {
            lastRecognizedCommandAt = now
            statusMessage = "VOICE HEARD: START"
            publish(.start)
        } else if words.contains("stop") || words.contains("reset") {
            lastRecognizedCommandAt = now
            statusMessage = "VOICE HEARD: STOP & RESET"
            publish(.stopAndReset)
        }
    }

    private func publish(_ command: VoiceCommand) {
        latestCommand = command
        commandSequence &+= 1
    }
}

@MainActor
final class TimeAnnouncer {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(seconds: Int) {
        let phrase: String
        if seconds < 60 {
            phrase = "\(seconds) seconds"
        } else {
            let minutes = seconds / 60
            let remainder = seconds % 60
            phrase = remainder == 0 ? "\(minutes) minute\(minutes == 1 ? "" : "s")" : "\(minutes) minute\(minutes == 1 ? "" : "s"), \(remainder) seconds"
        }
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }
}
