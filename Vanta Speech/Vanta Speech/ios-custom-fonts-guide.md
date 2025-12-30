# Интеграция шрифтов в Vanta Speech (iOS/SwiftUI)

> Руководство по добавлению Golos Text VF в приложение Vanta Speech.
> Минимальная версия: **iOS 18.6**

---

## Дизайн-система шрифтов Vanta Speech

### Основной шрифт
**Golos Text VF** (Variable Font) — один файл с вариативной осью веса (400–900).

### Стилистика заголовков
На трёх основных экранах заголовки используют **широкое (extended) начертание** в стиле логотипа:

```
* ВАНТА
```

Характеристики:
- Вес: **Black (900)** или **ExtraBold (800)**
- Трекинг (межбуквенный интервал): **увеличенный** (~0.1–0.2 em)
- Регистр: **UPPERCASE**
- Опционально: символ `*` перед текстом как брендовый элемент

### Остальная типографика
Стандартное начертание Golos Text для:
- Body текста
- Кнопок
- Подписей
- UI элементов

---

## Оглавление

1. [Скачивание шрифта](#1-скачивание-шрифта)
2. [Добавление в Xcode проект](#2-добавление-в-xcode-проект)
3. [Регистрация в Info.plist](#3-регистрация-в-infoplist)
4. [Определение имени шрифта](#4-определение-имени-шрифта)
5. [Использование в SwiftUI](#5-использование-в-swiftui)
6. [Типографика Vanta Speech](#6-типографика-vanta-speech)
7. [Dynamic Type](#7-dynamic-type)
8. [Типичные ошибки](#8-типичные-ошибки)
9. [Чеклист](#9-чеклист)

---

## 1. Скачивание шрифта

### Golos Text VF
**Ссылка:** https://fonts.google.com/specimen/Golos+Text

1. Нажми **"Get font"** → **"Download all"**
2. Из архива нужен файл: `GolosText-VariableFont_wght.ttf`

### Характеристики
- Формат: Variable Font (VF)
- Ось: `wght` (вес) — 400 до 900
- Поддержка: полная кириллица, латиница
- Лицензия: SIL Open Font License 1.1 (бесплатно для коммерческих проектов)
- Размер: ~100 КБ

### Почему VF, а не статичные файлы
- Один файл вместо шести
- Плавная анимация веса (если нужна)
- Меньший размер бандла
- iOS 18.6 полностью поддерживает Variable Fonts

---

## 2. Добавление в Xcode проект

### Структура папок (рекомендуется)
```
VantaSpeech/
├── Resources/
│   └── Fonts/
│       └── GolosText-VariableFont_wght.ttf
```

### Шаги добавления
1. Перетащи `GolosText-VariableFont_wght.ttf` в Xcode (в папку Fonts)
2. В диалоге **обязательно отметь**:
   - ☑️ **Copy items if needed**
   - ☑️ **Add to targets: VantaSpeech**

### Проверка Target Membership
1. Выбери файл шрифта в Project Navigator
2. File Inspector (⌘ + Option + 1)
3. Убедись, что **VantaSpeech** отмечен галочкой

### Проверка Copy Bundle Resources
1. Project → Target → **Build Phases**
2. Раскрой **Copy Bundle Resources**
3. Убедись, что `GolosText-VariableFont_wght.ttf` в списке

Если нет — добавь вручную через **+**.

---

## 3. Регистрация в Info.plist

### Через Xcode UI
1. Project → Target → вкладка **Info**
2. Custom iOS Target Properties → Add Row
3. Ключ: **Fonts provided by application**
4. Значение: `GolosText-VariableFont_wght.ttf`

### Через редактирование Info.plist
```xml
<key>UIAppFonts</key>
<array>
    <string>GolosText-VariableFont_wght.ttf</string>
</array>
```

Один файл — один элемент массива. Всё.

---

## 4. Определение имени шрифта

> **Имя в коде ≠ имя файла!** Нужен PostScript Name.

### Для Golos Text VF
PostScript Name: **`GolosText`**

Это проверено — используй именно это имя.

### Проверка через runtime (если сомневаешься)
```swift
// Добавь в onAppear любого view
for family in UIFont.familyNames.sorted() {
    if family.lowercased().contains("golos") {
        print("Family: \(family)")
        for name in UIFont.fontNames(forFamilyName: family) {
            print("    → \(name)")
        }
    }
}
```

### Проверка загрузки
```swift
let font = UIFont(name: "GolosText", size: 16)
print(font != nil ? "✅ Golos загружен" : "❌ Шрифт не найден")
```

---

## 5. Использование в SwiftUI

### Базовое использование
```swift
Text("Привет, мир!")
    .font(.custom("GolosText", size: 16))
```

### Управление весом (Variable Font)
```swift
// Через модификатор fontWeight
Text("Regular")
    .font(.custom("GolosText", size: 16))
    .fontWeight(.regular)  // 400

Text("Bold")
    .font(.custom("GolosText", size: 16))
    .fontWeight(.bold)     // 700

Text("Black")
    .font(.custom("GolosText", size: 16))
    .fontWeight(.black)    // 900

// Произвольное значение (400-900)
Text("Custom 650")
    .font(.custom("GolosText", size: 16))
    .fontWeight(.init(650))
```

### С поддержкой Dynamic Type
```swift
Text("Масштабируемый текст")
    .font(.custom("GolosText", size: 16, relativeTo: .body))
```

### Фиксированный размер (игнорирует настройки доступности)
```swift
Text("Фиксированный")
    .font(.custom("GolosText", fixedSize: 16))
```

---

## 6. Типографика Vanta Speech

### Заголовки главных экранов (3 экрана)
Широкий стиль в духе логотипа:

```swift
// Стиль заголовка главного экрана
struct VantaHeadlineStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.custom("GolosText", size: 32, relativeTo: .largeTitle))
            .fontWeight(.black)           // 900
            .tracking(4)                   // Увеличенный межбуквенный интервал
            .textCase(.uppercase)          // ЗАГЛАВНЫЕ
    }
}

extension View {
    func vantaHeadline() -> some View {
        modifier(VantaHeadlineStyle())
    }
}

// Использование
Text("Записи")
    .vantaHeadline()

// С брендовым символом
HStack(spacing: 8) {
    Text("✱")
        .font(.custom("GolosText", size: 24))
        .fontWeight(.black)
    Text("ВАНТА")
        .vantaHeadline()
}
```

### Font Extension для всего приложения

```swift
import SwiftUI

extension Font {
    // MARK: - Заголовки (широкий стиль)
    static let vantaLargeTitle = Font.custom("GolosText", size: 32, relativeTo: .largeTitle)
    static let vantaTitle = Font.custom("GolosText", size: 24, relativeTo: .title)
    
    // MARK: - UI элементы
    static let vantaHeadline = Font.custom("GolosText", size: 17, relativeTo: .headline)
    static let vantaBody = Font.custom("GolosText", size: 16, relativeTo: .body)
    static let vantaCallout = Font.custom("GolosText", size: 15, relativeTo: .callout)
    static let vantaSubheadline = Font.custom("GolosText", size: 14, relativeTo: .subheadline)
    static let vantaFootnote = Font.custom("GolosText", size: 13, relativeTo: .footnote)
    static let vantaCaption = Font.custom("GolosText", size: 12, relativeTo: .caption)
}

// MARK: - View Modifiers

extension View {
    /// Широкий заголовок для главных экранов (3 экрана)
    func vantaScreenTitle() -> some View {
        self
            .font(.vantaLargeTitle)
            .fontWeight(.black)
            .tracking(4)
            .textCase(.uppercase)
    }
    
    /// Стандартный заголовок секции
    func vantaSectionTitle() -> some View {
        self
            .font(.vantaTitle)
            .fontWeight(.bold)
    }
    
    /// Основной текст
    func vantaBodyText() -> some View {
        self
            .font(.vantaBody)
            .fontWeight(.regular)
    }
}
```

### Примеры использования

```swift
// Главный экран
VStack(alignment: .leading, spacing: 16) {
    Text("Записи")
        .vantaScreenTitle()
    
    Text("Все ваши транскрипции в одном месте")
        .vantaBodyText()
        .foregroundStyle(.secondary)
}

// Кнопка
Button("Начать запись") {
    // ...
}
.font(.vantaHeadline)
.fontWeight(.semibold)

// Подпись
Text("Последнее обновление: сегодня")
    .font(.vantaCaption)
    .foregroundStyle(.tertiary)
```

### Таблица стилей

| Элемент | Font | Weight | Size | Tracking | Case |
|---------|------|--------|------|----------|------|
| Screen Title (3 экрана) | GolosText | Black (900) | 32 | 4 | UPPERCASE |
| Section Title | GolosText | Bold (700) | 24 | 0 | Normal |
| Headline | GolosText | SemiBold (600) | 17 | 0 | Normal |
| Body | GolosText | Regular (400) | 16 | 0 | Normal |
| Callout | GolosText | Regular (400) | 15 | 0 | Normal |
| Subheadline | GolosText | Regular (400) | 14 | 0 | Normal |
| Footnote | GolosText | Regular (400) | 13 | 0 | Normal |
| Caption | GolosText | Regular (400) | 12 | 0 | Normal |

---

## 7. Dynamic Type

Все стили из секции 6 уже поддерживают Dynamic Type через параметр `relativeTo:`.

Для проверки масштабирования:
1. Settings → Accessibility → Display & Text Size → Larger Text
2. Или в Xcode: Environment Overrides → Text Size

```swift
// Масштабируется с системными настройками
Text("Масштабируемый")
    .font(.custom("GolosText", size: 16, relativeTo: .body))

// Игнорирует системные настройки (для логотипов, иконок)
Text("ВАНТА")
    .font(.custom("GolosText", fixedSize: 32))
```

---

## 8. Типичные ошибки

### Шрифт не отображается
**Причины:**
- Имя `GolosText` написано с ошибкой
- Файл не добавлен в Target Membership
- Файл не в Copy Bundle Resources
- Имя файла в Info.plist не совпадает с реальным

**Решение:** Пройдись по чеклисту в секции 9.

### Работает в симуляторе, не работает на устройстве
**Причина:** Файл не копируется в бандл.

**Решение:** Build Phases → Copy Bundle Resources → добавь файл.

### Вес шрифта не меняется
**Причина:** Используешь неправильный синтаксис для VF.

**Решение:**
```swift
// ✅ Правильно для Variable Font
Text("Bold")
    .font(.custom("GolosText", size: 16))
    .fontWeight(.bold)

// ❌ Неправильно (это для статичных файлов)
Text("Bold")
    .font(.custom("GolosText-Bold", size: 16))
```

### Tracking не применяется
**Причина:** `.tracking()` должен идти после `.font()`.

```swift
// ✅ Правильно
Text("ЗАГОЛОВОК")
    .font(.custom("GolosText", size: 32))
    .tracking(4)

// ❌ Неправильно
Text("ЗАГОЛОВОК")
    .tracking(4)
    .font(.custom("GolosText", size: 32))
```

---

## 9. Чеклист

### Файлы
- [ ] `GolosText-VariableFont_wght.ttf` добавлен в проект
- [ ] Target Membership: VantaSpeech ✓
- [ ] Build Phases → Copy Bundle Resources ✓
- [ ] Info.plist → UIAppFonts → `GolosText-VariableFont_wght.ttf`

### Код
- [ ] Имя шрифта: `"GolosText"` (не имя файла!)
- [ ] Font Extension создан (`Font+Vanta.swift`)
- [ ] View Modifiers для заголовков созданы

### Дизайн
- [ ] Заголовки 3 главных экранов: Black (900) + tracking(4) + uppercase
- [ ] Остальной UI: стандартные веса

### Тестирование
- [ ] Работает в симуляторе
- [ ] Работает на устройстве
- [ ] Dynamic Type масштабирует текст
- [ ] Широкие заголовки выглядят как в дизайне

---

## Быстрый старт (копипаста)

### 1. Info.plist
```xml
<key>UIAppFonts</key>
<array>
    <string>GolosText-VariableFont_wght.ttf</string>
</array>
```

### 2. Font+Vanta.swift
```swift
import SwiftUI

extension Font {
    static let vantaLargeTitle = Font.custom("GolosText", size: 32, relativeTo: .largeTitle)
    static let vantaTitle = Font.custom("GolosText", size: 24, relativeTo: .title)
    static let vantaHeadline = Font.custom("GolosText", size: 17, relativeTo: .headline)
    static let vantaBody = Font.custom("GolosText", size: 16, relativeTo: .body)
    static let vantaCaption = Font.custom("GolosText", size: 12, relativeTo: .caption)
}

extension View {
    /// Широкий заголовок для 3 главных экранов
    func vantaScreenTitle() -> some View {
        self
            .font(.vantaLargeTitle)
            .fontWeight(.black)
            .tracking(4)
            .textCase(.uppercase)
    }
}
```

### 3. Использование
```swift
// Заголовок главного экрана
Text("Записи")
    .vantaScreenTitle()

// Обычный текст
Text("Описание")
    .font(.vantaBody)
```

### 4. Дебаг (если шрифт не работает)
```swift
.onAppear {
    for family in UIFont.familyNames where family.contains("Golos") {
        print("✅ \(family): \(UIFont.fontNames(forFamilyName: family))")
    }
}
```

---

*Документ для Vanta Speech. iOS 18.6+. Golos Text VF. Декабрь 2024.*
