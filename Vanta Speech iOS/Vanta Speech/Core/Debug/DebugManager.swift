import Combine
import Foundation
import SwiftUI

/// Менеджер режима отладки
/// Активируется при 5 нажатиях на версию приложения в настройках
@MainActor
final class DebugManager: ObservableObject {
    static let shared = DebugManager()

    // MARK: - Persistent State

    @AppStorage("debug_mode_enabled") private(set) var isDebugModeEnabled = false
    @AppStorage("debug_fake_transcription_enabled") var isFakeTranscriptionEnabled = false

    // MARK: - Fake Transcription Data

    static let fakeTranscription = """
    [Debug Mode] Это тестовая транскрипция для отладки приложения.

    Участник 1: Добрый день, коллеги. Сегодня мы обсудим планы на следующую неделю.

    Участник 2: Да, у меня есть несколько вопросов по текущим задачам.

    Участник 1: Давайте начнём с обзора прогресса. Как продвигается работа над новым функционалом?

    Участник 3: Мы закончили основную часть, осталось провести тестирование.

    Участник 2: Отлично. Когда планируете завершить?

    Участник 3: К концу недели должны успеть.

    Участник 1: Хорошо, тогда запланируем демо на понедельник.
    """

    static let fakeSummary = """
    ## Тестовое саммари (Debug Mode)

    **Ключевые обсуждения:**
    - Обзор прогресса по текущим задачам
    - Планирование работы на следующую неделю

    **Принятые решения:**
    - Демо нового функционала запланировано на понедельник
    - Тестирование должно быть завершено к концу недели

    **Задачи:**
    - [ ] Провести тестирование нового функционала
    - [ ] Подготовить демо-презентацию
    - [ ] Обновить документацию
    """

    static let fakeTitle = "Debug: Тестовая встреча"

    // MARK: - Runtime State

    @Published var lastError: DebugError?
    @Published var showErrorSheet = false

    // MARK: - Types

    struct DebugError: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let errorDescription: String
        let errorDetails: String
        let context: String
        let stackTrace: String

        var fullText: String {
            """
            === Vanta Speech Debug Error ===
            Время: \(timestamp.formatted(date: .abbreviated, time: .standard))

            Ошибка: \(errorDescription)

            Контекст: \(context)

            Stack Trace:
            \(stackTrace)

            Технические детали:
            \(errorDetails)
            """
        }
    }

    enum LogLevel: String, Sendable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    // MARK: - Init

    private init() {}

    // MARK: - Public Methods

    func enableDebugMode() {
        isDebugModeEnabled = true
    }

    func disableDebugMode() {
        isDebugModeEnabled = false
        lastError = nil
    }

    func toggleDebugMode() {
        if isDebugModeEnabled {
            disableDebugMode()
        } else {
            enableDebugMode()
        }
    }

    func captureError(_ error: Error, context: String) {
        guard isDebugModeEnabled else { return }

        let debugError = DebugError(
            timestamp: Date(),
            errorDescription: error.localizedDescription,
            errorDetails: String(describing: error),
            context: context,
            stackTrace: Thread.callStackSymbols.joined(separator: "\n")
        )

        lastError = debugError
        showErrorSheet = true
    }

    func captureError(message: String, context: String) {
        guard isDebugModeEnabled else { return }

        let debugError = DebugError(
            timestamp: Date(),
            errorDescription: message,
            errorDetails: message,
            context: context,
            stackTrace: Thread.callStackSymbols.joined(separator: "\n")
        )

        lastError = debugError
        showErrorSheet = true
    }
}
