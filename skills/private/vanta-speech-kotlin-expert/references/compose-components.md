# Compose components and style primitives (Vanta Speech Android)

## Buttons and controls
- `VantaButton.kt` – primary/secondary/ghost variants
- `FloatingMicButton.kt` – main recording CTA
- `ModePicker.kt`, `PresetPicker.kt`

## Cards and surfaces
- `GlassCard.kt` – glass card composable + modifier extensions (`vantaGlassCard`, `vantaGlassProminent`, `vantaSurface`)
- `RecordingCard.kt`, `StatCard.kt`

## Utility components
- `TimerDisplay.kt`, `AudioVisualizer.kt`
- `DecorativeBackground.kt`
- `DayRecordingsBottomSheet.kt`
- Calendar components: `ui/components/calendar/*`

## Theme
- `ui/theme/Color.kt`
- `ui/theme/Theme.kt`
- `ui/theme/Type.kt` (if present)

## Pattern notes
- Prefer glass cards + sparse layout for primary screens.
- Avoid heavy shadows; keep motion subtle.
- Use Material Icons; only use custom vector assets when already present.
