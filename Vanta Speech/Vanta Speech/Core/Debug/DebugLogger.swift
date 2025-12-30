import Foundation

/// Логирует сообщение в консоль и захватывает для debug mode при ошибках
/// Замена для print() с поддержкой режима отладки
/// - Parameters:
///   - message: Сообщение для логирования
///   - module: Имя модуля (например "RecordingCoordinator")
///   - level: Уровень логирования
///   - file: Файл (автоматически)
///   - function: Функция (автоматически)
///   - line: Строка (автоматически)
func debugLog(
    _ message: String,
    module: String,
    level: DebugManager.LogLevel = .info,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    // Стандартный вывод в консоль
    let prefix = "[\(module)]"
    print("\(prefix) \(message)")

    // При ошибках захватываем для показа пользователю
    if level == .error {
        let location = "\(URL(fileURLWithPath: file).lastPathComponent):\(line)"
        Task { @MainActor in
            DebugManager.shared.captureError(
                message: message,
                context: "\(module) at \(location)"
            )
        }
    }
}

/// Захватывает ошибку для отображения в debug mode
/// - Parameters:
///   - error: Ошибка
///   - context: Контекст где произошла ошибка
///   - file: Файл (автоматически)
///   - function: Функция (автоматически)
///   - line: Строка (автоматически)
func debugCaptureError(
    _ error: Error,
    context: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    let location = "\(URL(fileURLWithPath: file).lastPathComponent):\(line) \(function)"

    Task { @MainActor in
        DebugManager.shared.captureError(error, context: "\(context) at \(location)")
    }
}
