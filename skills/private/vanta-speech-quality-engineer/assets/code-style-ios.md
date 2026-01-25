# iOS Code Style (Swift)

## Naming
*   **Types (Classes, Structs, Enums, Protocols):** `PascalCase`
*   **Properties, Functions, Variables:** `camelCase`
*   **File Names:** Match the primary type name.
*   **Acronyms:** `URLSession`, not `UrlSession`. `ID`, not `Id`.

## Formatting
*   **Indentation:** 4 spaces.
*   **Line Length:** Soft limit 120 chars.
*   **Braces:** K&R style (opening brace on same line).

## SwiftUI Patterns
*   **View Hierarchy:**
    ```swift
    var body: some View {
        Content()
            .modifier1()
            .modifier2()
    }
    ```
*   **State:**
    *   `@State` for simple local UI state (toggle, input).
    *   `@StateObject` for owning a ViewModel.
    *   `@ObservedObject` for observing an external ViewModel.

## Error Handling
*   Use `Result<T, Error>` for async completion handlers.
*   Use `do-catch` with specific error cases.
*   Custom errors should conform to `LocalizedError`.
