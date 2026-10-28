import SwiftUI

struct StopwatchView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var stopwatch = StopwatchModel()
    @StateObject private var voice = VoiceCommandListener()
    @State private var awakeWindowRelease: DispatchWorkItem?

    private let awakeWindow: TimeInterval = 10 * 60

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.067, blue: 0.118)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)
                timeCard
                Text("SAY \"START\" OR \"GO\"  •  \"STOP\" RESETS")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.secondary.opacity(0.85))
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                Text(voice.statusMessage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(voice.isListening ? Color.mint : Color.orange)
                    .padding(.bottom, 14)
                controls
                lapList
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            voice.requestAccessAndStart()
            applyPendingSystemAction()
        }
        .onDisappear {
            voice.stopListening()
            endAwakeWindow()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                applyPendingSystemAction()
            } else if newPhase == .background {
                endAwakeWindow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: MarkLapActionStore.didQueueAction)) { _ in
            applyPendingSystemAction()
        }
        .onChange(of: voice.commandSequence) { _, _ in
            guard let command = voice.latestCommand else { return }
            stopwatch.handle(command)
        }
        .onChange(of: stopwatch.awakeWindowSequence) { _, _ in
            beginAwakeWindow()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PRECISION TIMER")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(Color.mint)
            Text("Eyes-up timing")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyPendingSystemAction() {
        guard let action = MarkLapActionStore.takePendingAction() else { return }
        switch action {
        case .start:
            stopwatch.handle(.start)
        case .stopAndReset:
            stopwatch.handle(.stopAndReset)
        }
    }

    private func beginAwakeWindow() {
        awakeWindowRelease?.cancel()
        UIApplication.shared.isIdleTimerDisabled = true

        let release = DispatchWorkItem {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        awakeWindowRelease = release
        DispatchQueue.main.asyncAfter(deadline: .now() + awakeWindow, execute: release)
    }

    private func endAwakeWindow() {
        awakeWindowRelease?.cancel()
        awakeWindowRelease = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private var timeCard: some View {
        GeometryReader { proxy in
            let mainFontSize = min(max(64, proxy.size.width * 0.22), 96)
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(stopwatch.displayTime.main)
                    .font(.system(size: mainFontSize, weight: .bold, design: .monospaced))
                Text(stopwatch.displayTime.fraction)
                    .font(.system(size: mainFontSize * 0.48, weight: .bold, design: .monospaced))
                    .padding(.bottom, mainFontSize * 0.06)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .foregroundStyle(Color.mint)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityLabel("Elapsed time \(stopwatch.displayTime.full)")
        }
        .frame(height: 176)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.086, green: 0.129, blue: 0.216), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(stopwatch.isRunning ? "Pause" : (stopwatch.hasElapsed ? "Resume" : "Start")) {
                stopwatch.toggle()
            }
            .buttonStyle(StopwatchButtonStyle(fill: .mint, label: Color(red: 0.04, green: 0.15, blue: 0.15)))
            .accessibilityHint("Starts or pauses the stopwatch")

            Button(stopwatch.isRunning ? "Lap" : "Reset") {
                stopwatch.lapOrReset()
            }
            .buttonStyle(StopwatchButtonStyle(fill: Color(red: 0.13, green: 0.19, blue: 0.29), label: .white))
            .disabled(!stopwatch.isRunning && !stopwatch.hasElapsed)
            .opacity((!stopwatch.isRunning && !stopwatch.hasElapsed) ? 0.45 : 1)
            .accessibilityHint(stopwatch.isRunning ? "Records a lap" : "Resets the stopwatch")

            Button {
                voice.restartListening()
            } label: {
                Image(systemName: voice.isListening ? "mic.fill" : "mic.slash.fill")
            }
            .buttonStyle(VoiceButtonStyle(isActive: voice.isListening))
            .accessibilityLabel("Restart voice commands")
        }
    }

    private var lapList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAPS")
                .font(.caption.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(.secondary)
                .padding(.top, 27)

            if stopwatch.laps.isEmpty {
                ContentUnavailableView("No laps yet", systemImage: "flag.checkered", description: Text("Start the stopwatch, then tap Lap to record a split."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(stopwatch.laps) { lap in
                        HStack {
                            Text("LAP \(lap.number.formatted(.number.precision(.integerLength(2))))")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(StopwatchModel.format(lap.duration))
                                .fontDesign(.monospaced)
                                .foregroundStyle(.white)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.white.opacity(0.12))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct VoiceButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isActive ? Color.mint : Color.orange)
            .frame(width: 54, height: 54)
            .background(Color(red: 0.13, green: 0.19, blue: 0.29), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct StopwatchButtonStyle: ButtonStyle {
    let fill: Color
    let label: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(label)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(fill.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

@MainActor
final class StopwatchModel: ObservableObject {
    struct DisplayTime {
        let main: String
        let fraction: String
        let full: String
    }
    struct Lap: Identifiable {
        let id = UUID()
        let number: Int
        let duration: TimeInterval
    }

    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var laps: [Lap] = []
    @Published private(set) var awakeWindowSequence = 0

    private var startedAt: Date?
    private var lapStartedAt: Date?
    private var timer: Timer?
    private let haptics = UINotificationFeedbackGenerator()
    private let announcer = TimeAnnouncer()
    private let metronome = Metronome()
    private var nextAnnouncementSecond = 10
    private var lastTickedSecond = 0

    var displayTime: DisplayTime { Self.displayTime(for: elapsed) }
    var hasElapsed: Bool { elapsed > 0 }

    func toggle() {
        isRunning ? pause() : start()
    }

    func lapOrReset() {
        if isRunning {
            guard let lapStartedAt else { return }
            let now = Date()
            let lapDuration = now.timeIntervalSince(lapStartedAt)
            laps.insert(Lap(number: laps.count + 1, duration: lapDuration), at: 0)
            self.lapStartedAt = now
            haptics.notificationOccurred(.success)
        } else {
            reset()
        }
    }

    func start() {
        let now = Date()
        startedAt = now
        lapStartedAt = now
        isRunning = true
        awakeWindowSequence &+= 1
        haptics.prepare()
        beginUpdates()
    }

    func pause() {
        updateElapsed()
        isRunning = false
        startedAt = nil
        timer?.invalidate()
        timer = nil
        metronome.stop()
        announcer.stop()
        haptics.notificationOccurred(.warning)
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        metronome.stop()
        announcer.stop()
        elapsed = 0
        startedAt = nil
        lapStartedAt = nil
        laps.removeAll()
        nextAnnouncementSecond = 10
        lastTickedSecond = 0
        haptics.notificationOccurred(.success)
    }

    private func beginUpdates() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            self?.updateElapsed()
        }
        RunLoop.main.add(timer!, forMode: .common)
        updateElapsed()
    }

    private func updateElapsed() {
        guard let startedAt else { return }
        elapsed += Date().timeIntervalSince(startedAt)
        self.startedAt = Date()
        let seconds = Int(elapsed.rounded(.down))
        guard seconds > lastTickedSecond else { return }
        lastTickedSecond = seconds
        if !announceMilestoneIfNeeded() {
            metronome.tick()
        }
    }

    func handle(_ command: VoiceCommand) {
        switch command {
        case .start:
            guard !isRunning else { return }
            start()
        case .stopAndReset:
            guard isRunning || hasElapsed else { return }
            reset()
        }
    }

    private func announceMilestoneIfNeeded() -> Bool {
        let seconds = Int(elapsed.rounded(.down))
        guard seconds >= nextAnnouncementSecond else { return false }

        // Timer callbacks aren't guaranteed to land exactly on an integer second.
        // Advance the schedule only after speaking, so 60, 90, 120… aren't skipped
        // when a frame arrives slightly late.
        announcer.speak(seconds: nextAnnouncementSecond)
        switch nextAnnouncementSecond {
        case 50:
            nextAnnouncementSecond = 60
        case 10, 20, 30, 40:
            nextAnnouncementSecond += 10
        default:
            nextAnnouncementSecond += 30
        }
        return true
    }

    static func format(_ interval: TimeInterval) -> String {
        let totalHundredths = max(0, Int((interval * 100).rounded(.down)))
        let minutes = totalHundredths / 6_000
        let seconds = (totalHundredths / 100) % 60
        let hundredths = totalHundredths % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    static func displayTime(for interval: TimeInterval) -> DisplayTime {
        let full = format(interval)
        let split = full.split(separator: ".", maxSplits: 1)
        return DisplayTime(main: String(split[0]), fraction: "." + String(split[1]), full: full)
    }
}

#Preview {
    StopwatchView()
}
