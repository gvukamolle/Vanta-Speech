import Foundation

/// Darwin Notification Center для межпроцессной коммуникации между Widget Extension и Main App
/// CFNotificationCenter работает между процессами, в отличие от NotificationCenter.default
final class DarwinNotificationCenter {

    static let shared = DarwinNotificationCenter()

    // MARK: - Notification Names

    private enum NotificationName {
        static let prefix = "ru.poscredit.VantaSpeech."

        static let pauseRecording = CFNotificationName(rawValue: "\(prefix)pauseRecording" as CFString)
        static let resumeRecording = CFNotificationName(rawValue: "\(prefix)resumeRecording" as CFString)
        static let stopRecording = CFNotificationName(rawValue: "\(prefix)stopRecording" as CFString)
        static let startTranscription = CFNotificationName(rawValue: "\(prefix)startTranscription" as CFString)
        static let dismissActivity = CFNotificationName(rawValue: "\(prefix)dismissActivity" as CFString)
        static let hideActivity = CFNotificationName(rawValue: "\(prefix)hideActivity" as CFString)
    }

    // MARK: - Private Properties

    private var onPause: (() -> Void)?
    private var onResume: (() -> Void)?
    private var onStop: (() -> Void)?
    private var onStartTranscription: (() -> Void)?
    private var onDismiss: (() -> Void)?
    private var onHide: (() -> Void)?

    private let center = CFNotificationCenterGetDarwinNotifyCenter()

    private init() {}

    // MARK: - Post Notifications (Widget Extension → Main App)

    func postPauseRecording() {
        CFNotificationCenterPostNotification(center, NotificationName.pauseRecording, nil, nil, true)
    }

    func postResumeRecording() {
        CFNotificationCenterPostNotification(center, NotificationName.resumeRecording, nil, nil, true)
    }

    func postStopRecording() {
        CFNotificationCenterPostNotification(center, NotificationName.stopRecording, nil, nil, true)
    }

    func postStartTranscription() {
        CFNotificationCenterPostNotification(center, NotificationName.startTranscription, nil, nil, true)
    }

    func postDismissActivity() {
        CFNotificationCenterPostNotification(center, NotificationName.dismissActivity, nil, nil, true)
    }

    func postHideActivity() {
        CFNotificationCenterPostNotification(center, NotificationName.hideActivity, nil, nil, true)
    }

    // MARK: - Observe Notifications (Main App side)

    func startObserving(
        onPause: @escaping () -> Void,
        onResume: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onStartTranscription: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onHide: @escaping () -> Void
    ) {
        self.onPause = onPause
        self.onResume = onResume
        self.onStop = onStop
        self.onStartTranscription = onStartTranscription
        self.onDismiss = onDismiss
        self.onHide = onHide

        addObserver(name: NotificationName.pauseRecording)
        addObserver(name: NotificationName.resumeRecording)
        addObserver(name: NotificationName.stopRecording)
        addObserver(name: NotificationName.startTranscription)
        addObserver(name: NotificationName.dismissActivity)
        addObserver(name: NotificationName.hideActivity)
    }

    func stopObserving() {
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
        onPause = nil
        onResume = nil
        onStop = nil
        onStartTranscription = nil
        onDismiss = nil
        onHide = nil
    }

    // MARK: - Private Methods

    private func addObserver(name: CFNotificationName) {
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { center, observer, name, object, userInfo in
                guard let observer = observer,
                      let name = name else { return }

                let instance = Unmanaged<DarwinNotificationCenter>.fromOpaque(observer).takeUnretainedValue()
                let notificationName = name.rawValue as String

                // Оптимизация: если уже на main thread, выполняем немедленно
                if Thread.isMainThread {
                    instance.handleNotification(named: notificationName)
                } else {
                    DispatchQueue.main.async {
                        instance.handleNotification(named: notificationName)
                    }
                }
            },
            name.rawValue,
            nil,
            .deliverImmediately
        )
    }

    private func handleNotification(named name: String) {
        let prefix = NotificationName.prefix

        switch name {
        case "\(prefix)pauseRecording":
            print("[DarwinNotificationCenter] Received: pauseRecording")
            onPause?()
        case "\(prefix)resumeRecording":
            print("[DarwinNotificationCenter] Received: resumeRecording")
            onResume?()
        case "\(prefix)stopRecording":
            print("[DarwinNotificationCenter] Received: stopRecording")
            onStop?()
        case "\(prefix)startTranscription":
            print("[DarwinNotificationCenter] Received: startTranscription")
            onStartTranscription?()
        case "\(prefix)dismissActivity":
            print("[DarwinNotificationCenter] Received: dismissActivity")
            onDismiss?()
        case "\(prefix)hideActivity":
            print("[DarwinNotificationCenter] Received: hideActivity")
            onHide?()
        default:
            print("[DarwinNotificationCenter] Unknown notification: \(name)")
        }
    }
}
