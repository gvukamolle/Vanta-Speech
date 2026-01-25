# Testing Strategy

## The Testing Pyramid

### 1. Unit Tests (70%)
*   **Scope:** Individual classes, functions, ViewModels.
*   **Tools:**
    *   iOS: `XCTest`
    *   Android: `JUnit4`/`JUnit5`, `Mockk`.
*   **Rules:**
    *   Fast execution (< 100ms).
    *   No network/disk access (mock everything).
    *   Test naming: `test_<methodName>_<condition>_<expectedResult>` or BDD style `should return X when Y`.

### 2. Integration Tests (20%)
*   **Scope:** Interaction between modules (e.g., Repository + Local DataSource).
*   **Tools:**
    *   iOS: `XCTest` with in-memory CoreData/SwiftData.
    *   Android: `Room` in-memory database tests.
*   **Rules:**
    *   Verify data integrity.
    *   Verify mapping logic.

### 3. UI/E2E Tests (10%)
*   **Scope:** Critical user flows (Login -> Record -> Save).
*   **Tools:**
    *   iOS: `XCUITest`
    *   Android: `Compose Test Rule`, `Espresso`.
*   **Rules:**
    *   Run on CI only (slow).
    *   Mock the backend API.

## Mocking Policy
*   **Interfaces:** Always program to interfaces/protocols to facilitate mocking.
*   **Data Generation:** Use helper factories to generate dummy models for tests. Do not rely on hardcoded JSON strings inside test methods if possible.
