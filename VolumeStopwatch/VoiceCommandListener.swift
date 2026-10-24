import AVFAudio
import Speech

enum AnnouncementLanguage {
    case english
    case chinese
}

enum VoiceCommand {
    case start(AnnouncementLanguage)
    case stopAndReset
}

@MainActor
final class VoiceCommandListener: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var statusMessage = "VOICE: REQUESTING ACCESS…"
    @Published private(set) var commandSequence = 0
    private(set) var latestCommand: VoiceCommand?

    private let englishRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let chineseRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequests: [SFSpeechAudioBufferRecognitionRequest] = []
    private var recognitionTasks: [SFSpeechRecognitionTask] = []
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
        let candidates: [(AnnouncementLanguage, SFSpeechRecognizer?)] = [
            (.english, englishRecognizer),
            (.chinese, chineseRecognizer)
        ]
        let activeRecognizers = candidates.compactMap { candidate -> (AnnouncementLanguage, SFSpeechRecognizer)? in
            guard let recognizer = candidate.1, recognizer.isAvailable else { return nil }
            return (candidate.0, recognizer)
        }
        guard !activeRecognizers.isEmpty else {
            statusMessage = "VOICE: NOT AVAILABLE"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let requests = activeRecognizers.map { language, recognizer -> (AnnouncementLanguage, SFSpeechAudioBufferRecognitionRequest) in
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                request.taskHint = .confirmation
                request.contextualStrings = language == .english
                    ? ["start", "go", "stop", "reset", "MarkLap"]
                    : ["开始", "起", "停", "停止", "复位", "MarkLap"]
                request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
                return (language, request)
            }
            recognitionRequests = requests.map { $0.1 }

            let input = audioEngine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                for (_, request) in requests {
                    request.append(buffer)
                }
            }

            recognitionTasks = activeRecognizers.enumerated().map { element in
                let (index, entry) = element
                let (language, recognizer) = entry
                return recognizer.recognitionTask(with: requests[index].1) { [weak self] result, error in
                    let transcript = result?.bestTranscription.formattedString
                    let isFinished = result?.isFinal == true || error != nil
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let transcript { self.consume(transcript, language: language) }
                        if isFinished { self.restartAfterRecognitionEnds() }
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            statusMessage = "VOICE ON: SAY START / 开始 / 停"
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
        recognitionRequests.forEach { $0.endAudio() }
        recognitionTasks.forEach { $0.cancel() }
        recognitionRequests.removeAll()
        recognitionTasks.removeAll()
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

    private func consume(_ transcript: String, language: AnnouncementLanguage) {
        let words = Set(transcript.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let compact = transcript.replacingOccurrences(of: " ", with: "")
        let now = Date()
        guard now.timeIntervalSince(lastRecognizedCommandAt) > 1.2 else { return }

        let wantsToStart = words.contains("start") || words.contains("go")
            || compact.contains("开始") || compact == "起"
        let wantsToStop = words.contains("stop") || words.contains("reset")
            || compact.contains("停止") || compact.contains("结束") || compact.contains("复位")
            || compact == "停"

        if wantsToStart {
            lastRecognizedCommandAt = now
            statusMessage = language == .chinese ? "VOICE HEARD: 开始" : "VOICE HEARD: START"
            publish(.start(language))
        } else if wantsToStop {
            lastRecognizedCommandAt = now
            statusMessage = language == .chinese ? "VOICE HEARD: 停止 & 复位" : "VOICE HEARD: STOP & RESET"
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

    func speak(seconds: Int, language: AnnouncementLanguage) {
        let phrase: String
        if language == .chinese, seconds < 60 {
            phrase = "\(seconds) 秒"
        } else if language == .chinese {
            let minutes = seconds / 60
            let remainder = seconds % 60
            phrase = remainder == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(remainder) 秒"
        } else if seconds < 60 {
            phrase = "\(seconds) seconds"
        } else {
            let minutes = seconds / 60
            let remainder = seconds % 60
            phrase = remainder == 0 ? "\(minutes) minute\(minutes == 1 ? "" : "s")" : "\(minutes) minute\(minutes == 1 ? "" : "s"), \(remainder) seconds"
        }
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: language == .chinese ? "zh-CN" : "en-US")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }
}
