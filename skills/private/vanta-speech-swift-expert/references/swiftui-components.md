# SwiftUI components and style primitives (Vanta Speech)

## Buttons
- Primary/secondary/icon button styles: `Vanta Speech iOS/Vanta Speech/Core/Theme/ButtonStyles.swift`
  - `VantaPrimaryButtonStyle`, `VantaSecondaryButtonStyle`, `VantaIconButtonStyle`, `VantaGlassIconButtonStyle`
  - Use via `.buttonStyle(.vantaPrimary)` or `.buttonStyle(.vantaSecondary)` where appropriate.

## Cards and surfaces
- Glass/surface modifiers: `Vanta Speech iOS/Vanta Speech/Core/Theme/GlassModifiers.swift`
  - `.vantaGlassCard(...)`, `.vantaGlassProminent(...)`, `.vantaSurface(...)`
  - Use for elevated, minimal card layouts.

## Hover effects (iPad)
- Hover modifiers: `Vanta Speech iOS/Vanta Speech/Core/Theme/HoverEffectModifier.swift`
  - `.vantaHover(.lift|.highlight|.scale)`

## Decorative elements
- Gradient/sphere/ring backgrounds: `Vanta Speech iOS/Vanta Speech/Core/Theme/DecorativeViews.swift`
  - `VantaDecorativeBackground`, `VantaSphere`, `VantaRing`, `VantaRecordingIndicator`

## Reusable views
- Recording cards: `Vanta Speech iOS/Vanta Speech/Shared/Components/RecordingCard.swift`
  - `RecordingCard`, `RecordingCardLarge`
- Calendar UI: `Vanta Speech iOS/Vanta Speech/Shared/Components/CalendarView.swift`
  - `CalendarView`, `CalendarDayView`
- Markdown rendering for summaries: `Vanta Speech iOS/Vanta Speech/Shared/Components/MarkdownView.swift`

## Pattern notes
- Favor glass cards + sparse layout for primary screens.
- Avoid heavy shadows; keep hover and motion subtle.
- Keep SF Symbols consistent with existing iconography.
