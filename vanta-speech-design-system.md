# Vanta Speech Design System

## Color Palette

### Primary Colors

| Name | HEX | RGB | Usage |
|------|-----|-----|-------|
| White | `#FFFFFF` | 255, 255, 255 | Backgrounds, light surfaces |
| Gray | `#808080` | 128, 128, 128 | Secondary elements, disabled states |
| Charcoal | `#363636` | 54, 54, 54 | Dark surfaces, text on light bg |

### Accent Colors

| Name | HEX | RGB | Usage |
|------|-----|-----|-------|
| Pink Light | `#F9B9EB` | 249, 185, 235 | Glass surfaces, soft accents |
| Pink Vibrant | `#FA68D5` | 250, 104, 213 | Primary accent, interactive elements |
| Blue Light | `#B3E5FF` | 179, 229, 255 | Secondary accent, highlights |
| Blue Vibrant | `#3DBAFC` | 61, 186, 252 | Secondary interactive, info states |

### Semantic Mapping

```swift
// Light Theme
static let background = Color(hex: "#FFFFFF")
static let surface = Color(hex: "#FFFFFF")
static let textPrimary = Color(hex: "#363636")
static let textSecondary = Color(hex: "#808080")
static let accentPrimary = Color(hex: "#FA68D5")
static let accentSecondary = Color(hex: "#3DBAFC")
static let glassTint = Color(hex: "#F9B9EB")
```

---

## Dark Theme

Адаптация палитры для темной темы с сохранением контраста и узнаваемости бренда.

### Dark Theme Colors

| Role | Light | Dark | Notes |
|------|-------|------|-------|
| Background | `#FFFFFF` | `#1A1A1A` | Глубокий черный, не чистый |
| Surface | `#FFFFFF` | `#252525` | Карточки, elevated surfaces |
| Surface Elevated | — | `#2F2F2F` | Модалки, popover |
| Text Primary | `#363636` | `#FFFFFF` | Инверсия |
| Text Secondary | `#808080` | `#A0A0A0` | Чуть светлее для читаемости |
| Accent Primary | `#FA68D5` | `#FA68D5` | Без изменений |
| Accent Secondary | `#3DBAFC` | `#3DBAFC` | Без изменений |
| Glass Tint | `#F9B9EB` | `#F9B9EB` @ 15% | Меньше opacity на темном |

### Semantic Mapping (Dark)

```swift
// Dark Theme
static let background = Color(hex: "#1A1A1A")
static let surface = Color(hex: "#252525")
static let surfaceElevated = Color(hex: "#2F2F2F")
static let textPrimary = Color(hex: "#FFFFFF")
static let textSecondary = Color(hex: "#A0A0A0")
static let accentPrimary = Color(hex: "#FA68D5")
static let accentSecondary = Color(hex: "#3DBAFC")
static let glassTint = Color(hex: "#F9B9EB").opacity(0.15)
```

---

## Materials & Effects

### Glassmorphism

Основной эффект для surfaces и карточек.

**Параметры для Light Theme:**
```swift
.background(.ultraThinMaterial)
.background(Color.glassTint.opacity(0.3))
.cornerRadius(24)
.shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
```

**Параметры для Dark Theme:**
```swift
.background(.ultraThinMaterial)
.background(Color.glassTint.opacity(0.1))
.cornerRadius(24)
.shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
```

### 3D Spheres

Сферы используются как декоративные элементы. Характеристики:

- Градиент от светлого к насыщенному (top-left → bottom-right)
- Мягкая тень под объектом
- Возможен эффект отражения/блика в верхней части

**Цветовые варианты сфер:**
- Pink: `#F9B9EB` → `#FA68D5`
- Blue: `#B3E5FF` → `#3DBAFC`
- Gray: `#A0A0A0` → `#363636`
- Black: `#4A4A4A` → `#1A1A1A`

```swift
// Пример градиента для сферы
LinearGradient(
    colors: [Color(hex: "#F9B9EB"), Color(hex: "#FA68D5")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

### Transparency & Layering

- Glass surfaces: 30-50% opacity на светлой теме, 10-20% на темной
- Overlapping elements создают эффект глубины
- Сферы могут частично перекрывать glass surfaces

---

## Shapes & Geometry

### Primitives

| Shape | Usage | Corner Radius |
|-------|-------|---------------|
| Circle / Sphere | Декор, акценты, индикаторы | — |
| Ring (Torus) | Прогресс, обрамление, декор | — |
| Rounded Rectangle | Карточки, кнопки, контейнеры | 16-24pt |
| Semi-circle | Декоративные элементы | — |
| Shield | Безопасность, защита данных | — |
| Vertical Bars | Branding element, паттерн | 8pt |

### Composition Rules

1. **Layering**: Элементы накладываются друг на друга с частичным перекрытием
2. **Scale contrast**: Комбинация крупных и мелких сфер создает глубину
3. **Color balance**: В композиции присутствуют и pink, и blue акценты
4. **Asymmetry**: Элементы расположены асимметрично, не по центру

---

## Component Tokens

### Buttons

```swift
// Primary Button
background: accentPrimary
foreground: .white
cornerRadius: 16
padding: (horizontal: 24, vertical: 14)

// Secondary Button
background: surface + glassTint.opacity(0.2)
foreground: textPrimary
cornerRadius: 16
border: 1pt, glassTint
```

### Cards

```swift
// Standard Card
background: .ultraThinMaterial + glassTint.opacity(0.3)
cornerRadius: 24
shadow: (color: .black.opacity(0.1), radius: 20, y: 10)
padding: 20
```

### Recording Indicator

```swift
// Active Recording
ring: accentPrimary
sphere: pink gradient
pulse: accentPrimary.opacity(0.3), scale 1.0 → 1.2
```

---

## Animation Principles

### Timing

- **Fast**: 150ms — micro-interactions, button press
- **Normal**: 250ms — transitions, state changes  
- **Slow**: 400ms — page transitions, modals

### Easing

```swift
// Default
.easeInOut

// Bouncy (для сфер и декора)
.spring(response: 0.5, dampingFraction: 0.7)

// Smooth (для glass surfaces)
.easeOut
```

### Motion Patterns

- Сферы могут плавно перемещаться при scroll/gesture
- Glass surfaces появляются с fade + slight scale
- Rings могут вращаться как индикатор загрузки

---

## Implementation Notes

### SwiftUI Color Extension

```swift
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

### Theme Provider

```swift
enum AppTheme {
    case light
    case dark
    
    var background: Color {
        switch self {
        case .light: return Color(hex: "#FFFFFF")
        case .dark: return Color(hex: "#1A1A1A")
        }
    }
    
    var surface: Color {
        switch self {
        case .light: return Color(hex: "#FFFFFF")
        case .dark: return Color(hex: "#252525")
        }
    }
    
    var textPrimary: Color {
        switch self {
        case .light: return Color(hex: "#363636")
        case .dark: return Color(hex: "#FFFFFF")
        }
    }
    
    var textSecondary: Color {
        switch self {
        case .light: return Color(hex: "#808080")
        case .dark: return Color(hex: "#A0A0A0")
        }
    }
    
    var accentPrimary: Color { Color(hex: "#FA68D5") }
    var accentSecondary: Color { Color(hex: "#3DBAFC") }
    
    var glassTintOpacity: Double {
        switch self {
        case .light: return 0.3
        case .dark: return 0.15
        }
    }
}
```
