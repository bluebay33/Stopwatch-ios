import AppIntents
import Foundation

enum MarkLapAction: String {
    case start
    case stopAndReset
}

enum MarkLapActionStore {
    private static let actionKey = "pendingMarkLapAction"
    static let didQueueAction = Notification.Name("MarkLapActionQueued")

    static func queue(_ action: MarkLapAction) {
        UserDefaults.standard.set(action.rawValue, forKey: actionKey)
        NotificationCenter.default.post(name: didQueueAction, object: nil)
    }

    static func takePendingAction() -> MarkLapAction? {
        guard let rawValue = UserDefaults.standard.string(forKey: actionKey),
              let action = MarkLapAction(rawValue: rawValue) else { return nil }
        UserDefaults.standard.removeObject(forKey: actionKey)
        return action
    }
}

struct StartMarkLapIntent: AppIntent {
    static let title: LocalizedStringResource = "Start MarkLap"
    static let description = IntentDescription("Starts the MarkLap stopwatch.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        MarkLapActionStore.queue(.start)
        return .result()
    }
}

struct StopMarkLapIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop MarkLap"
    static let description = IntentDescription("Stops and resets the MarkLap stopwatch.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        MarkLapActionStore.queue(.stopAndReset)
        return .result()
    }
}

struct MarkLapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMarkLapIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Begin \(.applicationName)"
            ],
            shortTitle: "Start MarkLap",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopMarkLapIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Reset \(.applicationName)"
            ],
            shortTitle: "Stop MarkLap",
            systemImageName: "stop.fill"
        )
    }
}
