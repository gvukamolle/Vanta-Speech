# iOS 26 Liquid Glass: Кнопки, стили и цвета

> Справочник по созданию кнопок и элементов управления с эффектом Liquid Glass в SwiftUI

## Быстрый старт

```swift
// Стандартная glass-кнопка
Button("Action") { }
    .buttonStyle(.glass)

// Prominent (primary action)
Button("Save") { }
    .buttonStyle(.glassProminent)
```

---

## Button Styles

### Доступные стили

| Стиль | Вид | Когда использовать |
|-------|-----|-------------------|
| `.glass` | Полупрозрачный, видно фон | Вторичные действия |
| `.glassProminent` | Непрозрачный, фон не виден | Primary actions |

### Примеры

```swift
// Вторичное действие
Button("Cancel") { }
    .buttonStyle(.glass)

// Главное действие
Button("Save") { }
    .buttonStyle(.glassProminent)
    .tint(.blue)
```

---

## Цвета и Tint

### Принцип использования цвета

**Важно:** Цвет (tint) используется для передачи семантического значения, а НЕ для декора. Применяй только для call-to-action элементов.

### Способы задания цвета

#### 1. Через `.tint()` на кнопке

```swift
Button("Primary Action") { }
    .buttonStyle(.glass)
    .tint(.purple)

Button("Destructive") { }
    .buttonStyle(.glassProminent)
    .tint(.red)
```

#### 2. Через модификатор Glass типа

```swift
Text("Tinted Glass")
    .padding()
    .glassEffect(.regular.tint(.blue))

// С прозрачностью
Text("Subtle Tint")
    .padding()
    .glassEffect(.regular.tint(.purple.opacity(0.6)))
```

#### 3. Комбинирование с interactive

```swift
Button("Interactive Tinted") { }
    .glassEffect(.regular.tint(.orange).interactive())
```

### Примеры цветовых схем

```swift
// Подтверждение / Success
.tint(.green)

// Предупреждение / Warning  
.tint(.orange)

// Удаление / Destructive
.tint(.red)

// Информация / Info
.tint(.blue)

// Нейтральный акцент
.tint(.purple)
```

---

## Размеры кнопок (Control Size)

```swift
.controlSize(.mini)        // Самый маленький
.controlSize(.small)       // Маленький
.controlSize(.regular)     // По умолчанию
.controlSize(.large)       // Большой
.controlSize(.extraLarge)  // Новый в iOS 26
```

### Пример

```swift
Button("Large Button") { }
    .buttonStyle(.glassProminent)
    .controlSize(.large)
    .tint(.blue)
```

---

## Форма кнопок (Border Shape)

```swift
.buttonBorderShape(.capsule)                    // По умолчанию (скруглённая)
.buttonBorderShape(.circle)                     // Круг
.buttonBorderShape(.roundedRectangle(radius: 8)) // Скруглённый прямоугольник
```

### Пример круглой кнопки

```swift
Button {
    // action
} label: {
    Image(systemName: "plus")
        .font(.title2.bold())
        .frame(width: 56, height: 56)
}
.buttonStyle(.glassProminent)
.buttonBorderShape(.circle)
.tint(.orange)
```

### ⚠️ Known Issue (Beta)

`.glassProminent` + `.circle` даёт артефакты рендеринга.

**Workaround:**

```swift
Button("Action") { }
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.circle)
    .clipShape(Circle())  // Фиксит артефакты
```

---

## Glass Effect напрямую

Для кастомных элементов (не кнопок):

### Варианты Glass

| Вариант | Прозрачность | Когда использовать |
|---------|--------------|-------------------|
| `.regular` | Средняя | По умолчанию для большинства UI |
| `.clear` | Высокая | Поверх медиа-контента |
| `.identity` | Нет эффекта | Условное отключение |

### Базовое использование

```swift
Text("Glass Text")
    .padding()
    .glassEffect()  // .regular по умолчанию

Text("Clear Glass")
    .padding()
    .glassEffect(.clear)
```

### С кастомной формой

```swift
// Capsule (по умолчанию)
.glassEffect(.regular, in: .capsule)

// Круг
.glassEffect(.regular, in: .circle)

// Эллипс
.glassEffect(.regular, in: .ellipse)

// Скруглённый прямоугольник
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
```

### Interactive режим (только iOS)

```swift
Button("Tap Me") { }
    .glassEffect(.regular.interactive())
```

Включает:
- Scale при нажатии
- Bounce анимация
- Shimmer эффект
- Подсветка от точки касания

---

## GlassEffectContainer

**Когда нужен:** Когда несколько glass-элементов рядом.

**Зачем:** Glass не может сэмплировать другой glass. Container создаёт общий sampling region.

```swift
GlassEffectContainer {
    HStack(spacing: 20) {
        Button("Edit") { }
            .buttonStyle(.glass)
        
        Button("Delete") { }
            .buttonStyle(.glass)
            .tint(.red)
    }
}
```

### С контролем spacing (для морфинга)

```swift
GlassEffectContainer(spacing: 40.0) {
    // Элементы в пределах 40pt будут морфить друг в друга
    HStack(spacing: 40) {
        // buttons...
    }
}
```

---

## Морфинг между состояниями

```swift
struct MorphingButtons: View {
    @State private var isExpanded = false
    @Namespace private var namespace
    
    var body: some View {
        GlassEffectContainer(spacing: 30) {
            HStack(spacing: 30) {
                Button("Main") {
                    withAnimation(.bouncy) {
                        isExpanded.toggle()
                    }
                }
                .buttonStyle(.glass)
                .glassEffectID("main", in: namespace)
                
                if isExpanded {
                    Button("Extra") { }
                        .buttonStyle(.glass)
                        .glassEffectID("extra", in: namespace)
                }
            }
        }
    }
}
```

---

## Toolbar кнопки

Toolbar автоматически получает Liquid Glass стиль в iOS 26:

```swift
NavigationStack {
    ContentView()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") { }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { }
                // Автоматически получает .glassProminent
            }
        }
}
```

### Кастомный стиль в toolbar

```swift
ToolbarItem(placement: .topBarTrailing) {
    Button("Edit", systemImage: "pencil") { }
        .buttonStyle(.glassProminent)
        .tint(.green)
}
```

### Badge на кнопке

```swift
ToolbarItem(placement: .topBarLeading) {
    Button("Notifications", systemImage: "bell") { }
        .badge(5)
        .tint(.red)
}
```

---

## Полный пример: Floating Action Button

```swift
struct FloatingActionCluster: View {
    @State private var showActions = false
    @Namespace private var namespace
    
    let actions = [
        ("photo", Color.blue),
        ("video", Color.purple),
        ("doc.text", Color.green)
    ]
    
    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 12) {
                if showActions {
                    ForEach(actions, id: \.0) { icon, color in
                        Button {
                            // action
                        } label: {
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 48, height: 48)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .tint(color)
                        .glassEffectID(icon, in: namespace)
                    }
                }
                
                // Main toggle button
                Button {
                    withAnimation(.bouncy(duration: 0.35)) {
                        showActions.toggle()
                    }
                } label: {
                    Image(systemName: showActions ? "xmark" : "plus")
                        .font(.title2.bold())
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.orange)
                .glassEffectID("toggle", in: namespace)
            }
        }
    }
}
```

---

## Чек-лист

- [ ] Используй `.buttonStyle(.glass)` для вторичных действий
- [ ] Используй `.buttonStyle(.glassProminent)` для primary actions
- [ ] `.tint()` только для семантики, не для декора
- [ ] Оборачивай группы glass-элементов в `GlassEffectContainer`
- [ ] Для морфинга: `@Namespace` + `.glassEffectID()`
- [ ] Workaround для `.glassProminent` + `.circle`: добавь `.clipShape(Circle())`

---

## Минимальные требования

- iOS 26.0+
- Xcode 26.0+
- iPhone 11 / iPhone SE (2nd gen) или новее

---

## Ссылки

- [conorluddy/LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference) — полный референс
- [GonzaloFuentes28/LiquidGlassCheatsheet](https://github.com/GonzaloFuentes28/LiquidGlassCheatsheet) — cheatsheet
- [artemnovichkov/iOS-26-by-Examples](https://github.com/artemnovichkov/iOS-26-by-Examples) — примеры iOS 26
- WWDC 2025 Session 219: Meet Liquid Glass
- WWDC 2025 Session 323: Build a SwiftUI app with the new design
