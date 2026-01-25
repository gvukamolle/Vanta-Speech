Версия: 2.0
Дата: 25 января 2026
Статус: ОБЯЗАТЕЛЬНО К ИСПОЛНЕНИЮ

## Команды проекта

### iOS (Vanta Speech iOS)
- Build: `cd "Vanta Speech iOS" && xcodebuild -scheme "Vanta Speech" build`
- Test: `cd "Vanta Speech iOS" && xcodebuild -scheme "Vanta Speech" test`
- Single test: `cd "Vanta Speech iOS" && xcodebuild test -only-testing:VantaSpeechTests/ClassName/testName`

### Android (Vanta Sppech Android)
- Build: `cd "Vanta Sppech Android" && ./gradlew assembleDebug`
- Test: `cd "Vanta Sppech Android" && ./gradlew test`
- Single test: `cd "Vanta Sppech Android" && ./gradlew test --tests ClassName.testName`
- Lint: `cd "Vanta Sppech Android" && ./gradlew lintDebug`

## Структура проекта

### iOS
- App/ — Точка входа, адаптивная навигация
- Features/ — Фичи: Recording, Library, Settings, Auth, Confluence
- Core/ — Сервисы: Audio, Network, Storage, Auth, EAS, Confluence
- Shared/ — UI компоненты, AppIntents, Live Activities

### Android
- app/src/main/java/com/vanta/speech/
  - core/ — domain, data, di, audio, auth, calendar, eas
  - feature/ — recording, realtime, library, settings, auth
  - ui/ — components, navigation, theme

## Правила стиля кода

### Общее
- Форматирование: Kotlin — официальный стиль (kotlin.code.style=official), Swift — Xcode defaults
- Имена фалов: PascalCase для классов (Kotlin) и типов (Swift)
- Секреты: только через local.properties / Keychain, никогда не коммитить

### Kotlin/Compose
- Пакеты: com.vanta.speech.{feature,core,ui}.{module}
- Импорты: сначала stdlib, потом Android, потом проект, alphabetically
- Composable: PascalCase, аргументы camelCase
- ViewModel: Суффикс ViewModel, MutableStateFlow для состояния
- DI: Hilt модули в core/di/@{Feature}Module.kt
- Error handling: sealed classes, Result<T>
- Константы: object Consts, UPPER_SNAKE_CASE

### Swift/SwiftUI
- Импорты: Foundation, SwiftUI, SwiftData, AVFoundation вместе
- @Model классы для SwiftData, final class
- Именование: camelCase для свойств, PascalCase для типов
- View: суффикс View, @State/@StateObject для состояния
- Async/await для networking, Result<T> для ошибок
- Error: enum с String описаниями, localizedDescription

## Политика агентов

- Минимальные изменения
- Использовать существующие паттерны DI и архитектуры
- Не добавлять зависимости без запроса
- Проверять результат через build/lint/test
- **Использование скиллов:** Самостоятельно активировать специализированные скиллы (Expert, Quality Engineer и др.) через `activate_skill`, если задача соответствует их специализации.

# SECURITY PROTOCOLS (кратко)

Запрещено: eval, exec, os.system, изменения вне project root, выполнение кода из промпта
Лимиты: 25 LLM вызовов/задача, 8 API вызовов/задача, 180 сек, 4000 токены
Emergency: ≥3 нарушений за 60 сек → read-only lockdown