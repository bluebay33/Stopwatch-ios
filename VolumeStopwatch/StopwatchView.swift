import SwiftUI

struct StopwatchView: View {
    @StateObject private var stopwatch = StopwatchModel()

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.067, blue: 0.118)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 26)
                timeCard
                Text("TAP START / PAUSE     •     LAP / RESET")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.secondary.opacity(0.85))
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                controls
                lapList
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PRECISION TIMER")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(Color.mint)
            Text("Stopwatch")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeCard: some View {
        Text(stopwatch.displayTime)
            .font(.system(size: 48, weight: .bold, design: .monospaced))
            .minimumScaleFactor(0.65)
            .foregroundStyle(Color.mint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .background(Color(red: 0.086, green: 0.129, blue: 0.216), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityLabel("Elapsed time \(stopwatch.displayTime)")
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
    struct Lap: Identifiable {
        let id = UUID()
        let number: Int
        let duration: TimeInterval
    }

    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var laps: [Lap] = []

    private var startedAt: Date?
    private var lapStartedAt: Date?
    private var timer: Timer?
    private let haptics = UINotificationFeedbackGenerator()

    var displayTime: String { Self.format(elapsed) }
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
        haptics.prepare()
        beginUpdates()
    }

    func pause() {
        updateElapsed()
        isRunning = false
        startedAt = nil
        timer?.invalidate()
        timer = nil
        haptics.notificationOccurred(.warning)
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        elapsed = 0
        startedAt = nil
        lapStartedAt = nil
        laps.removeAll()
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
    }

    static func format(_ interval: TimeInterval) -> String {
        let totalHundredths = max(0, Int((interval * 100).rounded(.down)))
        let minutes = totalHundredths / 6_000
        let seconds = (totalHundredths / 100) % 60
        let hundredths = totalHundredths % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }
}

#Preview {
    StopwatchView()
}
