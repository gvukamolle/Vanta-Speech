import Foundation
import SwiftData

/// Сервис для полного сброса данных приложения при выходе пользователя
/// Удаляет все записи, очищает все интеграции и credentials
@MainActor
final class AppResetService {
    static let shared = AppResetService()
    
    private init() {}
    
    /// Полный сброс приложения при выходе пользователя
    /// - Parameter modelContext: SwiftData context для удаления записей
    func performFullReset(modelContext: ModelContext) async {
        debugLog("Starting full app reset...", module: "AppReset", level: .info)
        
        // 1. Останавливаем активную запись если есть
        await stopActiveRecording()
        
        // 2. Удаляем все записи из SwiftData
        await deleteAllRecordings(modelContext: modelContext)
        
        // 3. Очищаем Exchange/EAS интеграцию
        await disconnectExchange()
        
        // 4. Очищаем Confluence интеграцию
        await disconnectConfluence()
        
        // 5. Очищаем все настройки и кеши
        await clearUserDefaults()
        
        // 6. Очищаем ключи из Keychain (кроме device ID для EAS - его оставляем)
        clearKeychainData()
        
        debugLog("Full app reset completed", module: "AppReset", level: .info)
    }
    
    /// Полный сброс без modelContext (используется когда контекст недоступен)
    func performFullResetWithoutContext() async {
        debugLog("Starting partial app reset (no context)...", module: "AppReset", level: .info)
        
        // 1. Останавливаем активную запись если есть
        await stopActiveRecording()
        
        // 2. Очищаем Exchange/EAS интеграцию
        await disconnectExchange()
        
        // 3. Очищаем Confluence интеграцию
        await disconnectConfluence()
        
        // 4. Очищаем настройки
        await clearUserDefaults()
        
        // 5. Очищаем ключи из Keychain
        clearKeychainData()
        
        debugLog("Partial app reset completed", module: "AppReset", level: .info)
    }
    
    // MARK: - Private Methods
    
    private func stopActiveRecording() async {
        let coordinator = RecordingCoordinator.shared
        if coordinator.audioRecorder.isRecording {
            debugLog("Stopping active recording...", module: "AppReset", level: .info)
            _ = await coordinator.stopRecording()
        }
        
        // Завершаем Live Activity
        await LiveActivityManager.shared.endActivityImmediately()
    }
    
    private func deleteAllRecordings(modelContext: ModelContext) async {
        debugLog("Deleting all recordings...", module: "AppReset", level: .info)
        
        do {
            let descriptor = FetchDescriptor<Recording>()
            let allRecordings = try modelContext.fetch(descriptor)
            
            // Удаляем аудио файлы
            for recording in allRecordings {
                await deleteAudioFile(recording)
                modelContext.delete(recording)
            }
            
            // Сохраняем изменения
            try modelContext.save()
            
            debugLog("Deleted \(allRecordings.count) recordings", module: "AppReset", level: .info)
        } catch {
            debugLog("Failed to delete recordings: \(error)", module: "AppReset", level: .error)
        }
    }
    
    private func deleteAudioFile(_ recording: Recording) async {
        guard !recording.audioFileURL.isEmpty else { return }
        
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        guard let documentsDirectory = urls.first else { return }
        
        let fileURL = documentsDirectory.appendingPathComponent(recording.audioFileURL)
        
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
                debugLog("Deleted audio file: \(recording.audioFileURL)", module: "AppReset", level: .info)
            }
        } catch {
            debugLog("Failed to delete audio file: \(error)", module: "AppReset", level: .error)
        }
    }
    
    private func disconnectExchange() async {
        debugLog("Disconnecting Exchange...", module: "AppReset", level: .info)
        
        let calendarManager = EASCalendarManager.shared
        if calendarManager.isConnected {
            calendarManager.disconnect()
            debugLog("Exchange disconnected", module: "AppReset", level: .info)
        }
    }
    
    private func disconnectConfluence() async {
        debugLog("Disconnecting Confluence...", module: "AppReset", level: .info)
        
        let confluenceManager = ConfluenceManager.shared
        if confluenceManager.isAvailable {
            confluenceManager.disconnect()
            debugLog("Confluence disconnected", module: "AppReset", level: .info)
        }
    }
    
    private func clearUserDefaults() async {
        debugLog("Clearing UserDefaults...", module: "AppReset", level: .info)
        
        let defaults = UserDefaults.standard
        
        // Список ключей для удаления
        let keysToRemove = [
            // Confluence настройки
            "ConfluenceDefaultSpaceKey",
            "ConfluenceDefaultParentPageId",
            "ConfluenceDefaultParentPageTitle",
            "confluence_default_space",
            "confluence_default_page_id",
            "confluence_default_page_title",
            
            // Настройки записи
            "defaultRecordingMode",
            "autoTranscribe",
            
            // Пресеты
            "enabledPresets",
            "presetOrder",
            
            // Прочее
            "appTheme",
        ]
        
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }
        
        // Очищаем AppGroup UserDefaults
        if let appGroupDefaults = UserDefaults(suiteName: AppGroupConstants.suiteName) {
            let appGroupKeys = [
                AppGroupConstants.recordingActionKey,
                "lastRecordingId",
                "pendingPreset"
            ]
            for key in appGroupKeys {
                appGroupDefaults.removeObject(forKey: key)
            }
            appGroupDefaults.synchronize()
        }
        
        defaults.synchronize()
        
        debugLog("UserDefaults cleared", module: "AppReset", level: .info)
    }
    
    private func clearKeychainData() {
        debugLog("Clearing Keychain data...", module: "AppReset", level: .info)
        
        let keychain = KeychainManager.shared
        
        // Удаляем сессию пользователя
        keychain.deleteSession()
        
        // Удаляем EAS credentials (device ID оставляем для последующих подключений)
        keychain.deleteEASCredentials()
        keychain.deleteEASSyncState()
        keychain.deleteEASCachedEvents()
        
        // Очищаем Confluence credentials
        keychain.deleteConfluenceCredentials()
        
        debugLog("Keychain data cleared", module: "AppReset", level: .info)
    }
}
