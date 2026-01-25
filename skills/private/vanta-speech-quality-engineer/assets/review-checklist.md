# Code Review Checklist

## Universal (Both Platforms)
- [ ] **Secrets:** No API keys, passwords, or hardcoded tokens in source files.
- [ ] **Formatting:** No trailing whitespace, consistent indentation (4 spaces Swift, 4 spaces Kotlin).
- [ ] **Comments:** "Why" comments present for complex logic; no "What" comments.
- [ ] **Unused Code:** No commented-out code blocks or unused imports.
- [ ] **Error Handling:** No empty `catch` blocks. Errors must be logged or surfaced to UI.
- [ ] **Threading:** Network/DB calls are OFF the Main Thread. UI updates are ON the Main Thread.

## iOS (Swift/SwiftUI)
- [ ] **Memory:** `[weak self]` used in closures to prevent retain cycles.
- [ ] **SwiftData:** `@Model` classes are `final`.
- [ ] **MVVM:** View does not access `Core` services directly; goes through ViewModel.
- [ ] **Concurrency:** Use `async/await` over completion handlers where possible.
- [ ] **UI:** `@State` is private. Components are broken down if body > 50 lines.

## Android (Kotlin/Compose)
- [ ] **State Management:** `StateFlow` used over `LiveData`.
- [ ] **Lifecycle:** Flow collection is lifecycle-aware (`repeatOnLifecycle` or `collectAsStateWithLifecycle`).
- [ ] **Compose:** Modifiers are passed as the first optional argument.
- [ ] **DI:** Hilt ViewModels annotated with `@HiltViewModel`.
- [ ] **Resources:** String literals extracted to `strings.xml`.
