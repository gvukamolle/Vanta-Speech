import Combine
import Foundation
import UIKit

/// Главный координатор интеграции с Outlook Calendar
@MainActor
final class OutlookCalendarManager: ObservableObject {

    // MARK: - Singleton

    static let shared = OutlookCalendarManager()

    // MARK: - Dependencies

    let authManager: MSALAuthManager
    private(set) var calendarService: GraphCalendarService?
    private(set) var syncService: CalendarSyncService?

    // MARK: - State

    @Published private(set) var isConnected = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var cachedEvents: [GraphEvent] = []
    @Published var error: String?

    /// Имя пользователя Outlook
    var userName: String? {
        authManager.userName
    }

    /// Email пользователя Outlook
    var userEmail: String? {
        authManager.userEmail
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        self.authManager = MSALAuthManager()
        setupObservers()
    }

    private func setupObservers() {
        // Отслеживаем статус авторизации
        authManager.$isSignedIn
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signedIn in
                guard let self = self else { return }

                self.isConnected = signedIn

                if signedIn {
                    // Инициализируем сервисы при подключении
                    self.calendarService = GraphCalendarService(authManager: self.authManager)
                    self.syncService = CalendarSyncService(authManager: self.authManager)
                    self.lastSyncDate = self.syncService?.lastSyncDate

                    // Автоматическая синхронизация при подключении
                    Task {
                        await self.performSync()
                    }
                } else {
                    // Очищаем при отключении
                    self.calendarService = nil
                    self.syncService = nil
                    self.cachedEvents = []
                    self.lastSyncDate = nil
                }
            }
            .store(in: &cancellables)

        // Пробрасываем ошибки из authManager
        authManager.$error
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
    }

    // MARK: - Connection

    /// Подключить Outlook Calendar
    /// - Parameter viewController: UIViewController для презентации OAuth
    func connect(from viewController: UIViewController) async {
        do {
            _ = try await authManager.signIn(from: viewController)
            debugLog("Connected successfully", module: "OutlookCalendarManager")
        } catch MSALAuthError.userCanceled {
            // Пользователь отменил — не показываем ошибку
            debugLog("User canceled sign in", module: "OutlookCalendarManager", level: .warning)
        } catch {
            self.error = error.localizedDescription
            debugLog("Connection failed: \(error)", module: "OutlookCalendarManager", level: .error)
            debugCaptureError(error, context: "OutlookCalendarManager.connect")
        }
    }

    /// Отключить Outlook Calendar
    /// - Parameter viewController: UIViewController для презентации logout
    func disconnect(from viewController: UIViewController) async {
        do {
            try await authManager.signOut(from: viewController)
            debugLog("Disconnected successfully", module: "OutlookCalendarManager")
        } catch {
            // Fallback на локальный logout
            authManager.signOutLocally()
            debugLog("Fallback to local signout: \(error)", module: "OutlookCalendarManager", level: .warning)
        }
    }

    // MARK: - Sync

    /// Выполнить синхронизацию календаря
    @discardableResult
    func performSync() async -> Bool {
        guard isConnected, let syncService = syncService else {
            debugLog("Cannot sync: not connected", module: "OutlookCalendarManager", level: .warning)
            return false
        }

        guard !isSyncing else {
            debugLog("Sync already in progress", module: "OutlookCalendarManager", level: .warning)
            return false
        }

        isSyncing = true
        error = nil

        defer { isSyncing = false }

        do {
            let result = try await syncService.sync()

            // Обновляем кэш событий
            if result.isFullSync {
                cachedEvents = result.updatedEvents
            } else {
                // Применяем инкрементальные изменения
                applyIncrementalChanges(result)
            }

            lastSyncDate = syncService.lastSyncDate

            debugLog("Sync completed: \(cachedEvents.count) events cached", module: "OutlookCalendarManager")
            return true

        } catch MSALAuthError.interactionRequired {
            self.error = "Требуется повторный вход в Outlook"
            debugLog("Sync failed: interaction required", module: "OutlookCalendarManager", level: .warning)
            return false
        } catch {
            self.error = error.localizedDescription
            debugLog("Sync failed: \(error)", module: "OutlookCalendarManager", level: .error)
            debugCaptureError(error, context: "OutlookCalendarManager.performSync")
            return false
        }
    }

    /// Сбросить и выполнить полную синхронизацию
    func resetAndSync() async {
        syncService?.resetSync()
        await performSync()
    }

    private func applyIncrementalChanges(_ result: SyncResult) {
        // Удаляем удалённые события
        cachedEvents.removeAll { event in
            result.deletedEventIds.contains(event.id)
        }

        // Обновляем/добавляем события
        for updatedEvent in result.updatedEvents {
            if let index = cachedEvents.firstIndex(where: { $0.id == updatedEvent.id }) {
                cachedEvents[index] = updatedEvent
            } else {
                cachedEvents.append(updatedEvent)
            }
        }

        // Сортируем по дате начала
        cachedEvents.sort { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    // MARK: - Events API

    /// Получить события на сегодня
    func getTodayEvents() async throws -> [GraphEvent] {
        guard let service = calendarService else {
            throw OutlookError.notConnected
        }
        return try await service.fetchTodayEvents()
    }

    /// Получить события за период
    func getEvents(from startDate: Date, to endDate: Date) async throws -> [GraphEvent] {
        guard let service = calendarService else {
            throw OutlookError.notConnected
        }
        return try await service.fetchEvents(from: startDate, to: endDate)
    }

    /// Найти событие, перекрывающееся с указанным временем
    /// Полезно для автоматического связывания записи со встречей
    func findOverlappingEvent(at date: Date, duration: TimeInterval) -> GraphEvent? {
        let endDate = date.addingTimeInterval(duration)

        return cachedEvents.first { event in
            guard let eventStart = event.startDate,
                  let eventEnd = event.endDate else { return false }

            // Проверяем перекрытие временных интервалов
            return eventStart <= endDate && eventEnd >= date
        }
    }

    /// Получить ближайшее событие
    func getNextEvent() -> GraphEvent? {
        let now = Date()
        return cachedEvents.first { event in
            guard let eventStart = event.startDate else { return false }
            return eventStart > now
        }
    }

    /// Получить текущее событие (которое идёт сейчас)
    func getCurrentEvent() -> GraphEvent? {
        let now = Date()
        return cachedEvents.first { event in
            guard let eventStart = event.startDate,
                  let eventEnd = event.endDate else { return false }
            return eventStart <= now && eventEnd >= now
        }
    }
}

// MARK: - Errors

enum OutlookError: LocalizedError {
    case notConnected
    case syncFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Outlook Calendar не подключён"
        case .syncFailed(let error):
            return "Ошибка синхронизации: \(error.localizedDescription)"
        }
    }
}
