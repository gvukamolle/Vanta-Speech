# App Icons

This directory contains source files for app icons across all platforms.

## Required Icon Sizes

### iOS
- 20x20, 29x29, 40x40, 60x60, 76x76, 83.5x83.5, 1024x1024
- @1x, @2x, @3x variants

### macOS
- 16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024
- @1x, @2x variants

### Android
- mdpi (48x48)
- hdpi (72x72)
- xhdpi (96x96)
- xxhdpi (144x144)
- xxxhdpi (192x192)
- Adaptive icon (foreground + background layers)

### Windows
- 16x16, 24x24, 32x32, 48x48, 64x64, 256x256
- .ico file with all sizes embedded

## Source Files

Place the following source files in this directory:

1. `app-icon-1024.png` - Master icon at 1024x1024 (used for iOS/macOS App Store)
2. `app-icon-foreground.png` - Android adaptive icon foreground (108dp with 72dp visible area)
3. `app-icon-background.png` - Android adaptive icon background
4. `app-icon.svg` - Vector source for Windows icons

## Icon Design Guidelines

### Color Palette
- Primary: #E94560 (Recording Red)
- Secondary: #1A1A2E (Dark Blue)
- Accent: #2D2D44 (Light Dark Blue)

### Design Elements
- Waveform symbol representing audio
- Circular or rounded square shape
- Minimal, modern design
- High contrast for visibility

### Generation Tools
- iOS: Use Xcode Asset Catalog or https://appicon.co
- Android: Android Studio Image Asset Studio
- Windows: Use icofx or similar for .ico generation
- macOS: iconutil command or Xcode
