# Android Code Style (Kotlin)

## Naming
*   **Classes, Interfaces:** `PascalCase`
*   **Functions, Properties:** `camelCase`
*   **Constants (`const val`, `object` fields):** `UPPER_SNAKE_CASE`
*   **Composables:** `PascalCase` (Function that returns Unit and emits UI).

## Formatting
*   **Indentation:** 4 spaces.
*   **Imports:** No wildcards (`*`). Order: stdlib, androidx, com.google, com.vanta.

## Compose Patterns
*   **Parameters:**
    *   Required parameters first.
    *   `modifier: Modifier = Modifier` as the first optional parameter.
    *   Composable lambdas (slots) last.
*   **Preview:** Use `@Preview(showBackground = true)` and `Theme` wrapper.

## Architecture (MVVM)
*   **ViewModel:**
    *   Exposes `StateFlow<UiState>` (immutable state wrapper).
    *   Handles events via `fun onEvent(event: UiEvent)`.
*   **Coroutines:**
    *   Use `viewModelScope` in ViewModels.
    *   Inject `DispatcherProvider` (IO, Default, Main) for testability.
