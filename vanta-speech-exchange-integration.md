# Vanta Speech: Интеграция с Microsoft Exchange Server

> **Версия:** 1.0  
> **Дата:** 29.12.2024  
> **Статус:** Спецификация

---

## Содержание

1. [Обзор и архитектура](#обзор-и-архитектура)
2. [Аутентификация](#аутентификация)
3. [EWS API: операции с календарём](#ews-api-операции-с-календарём)
4. [Работа с контактами](#работа-с-контактами)
5. [Реализация на Swift](#реализация-на-swift)
6. [Обработка ошибок](#обработка-ошибок)
7. [Безопасность](#безопасность)
8. [Ограничения и риски](#ограничения-и-риски)

---

## Обзор и архитектура

### Выбор API

Для on-premises Exchange Server единственный полнофункциональный вариант — **Exchange Web Services (EWS)**. Microsoft Graph API не поддерживает чистый on-premises без гибридной конфигурации с Azure AD.

### Схема взаимодействия

```
┌─────────────────┐     HTTPS/SOAP      ┌──────────────────┐
│   Vanta Speech  │ ◄─────────────────► │  Exchange Server │
│   (iOS Client)  │                     │     (EWS API)    │
└─────────────────┘                     └──────────────────┘
        │                                        │
        │  NTLM Auth                             │
        └────────────────────────────────────────┘
```

### Endpoint

```
https://<exchange-server>/EWS/Exchange.asmx
```

Точный URL определяется через Autodiscover или предоставляется администратором.

---

## Аутентификация

### Рекомендуемый метод: NTLM

NTLM — наиболее совместимый метод для on-premises Exchange. Поддерживается iOS через `URLSession` delegate.

#### Матрица совместимости

| Метод | Exchange 2016 | Exchange 2019 | iOS Support | Рекомендация |
|-------|---------------|---------------|-------------|--------------|
| NTLM | ✅ | ✅ | ✅ Native | **Использовать** |
| Basic Auth | ✅ | ✅ | ✅ | Только dev |
| OAuth 2.0 | CU8+ (HMA) | CU7+ | ✅ MSAL | При наличии Azure AD |

### Данные для аутентификации

От пользователя требуется:

| Поле | Формат | Пример |
|------|--------|--------|
| Email | user@domain.com | ivanov@company.ru |
| Username | DOMAIN\user или user@domain.com | CORP\ivanov |
| Password | string | ••••••••• |

---

## EWS API: операции с календарём

### Общая структура SOAP-запроса

```xml
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
               xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
               xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
  <soap:Header>
    <t:RequestServerVersion Version="Exchange2019" />
  </soap:Header>
  <soap:Body>
    <!-- Операция -->
  </soap:Body>
</soap:Envelope>
```

---

### 1. Получение списка встреч (FindItem)

**Назначение:** Загрузка событий календаря за указанный период.

**SOAP Action:** `http://schemas.microsoft.com/exchange/services/2006/messages/FindItem`

#### Запрос

```xml
<m:FindItem Traversal="Shallow">
  <m:ItemShape>
    <t:BaseShape>Default</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="calendar:Start" />
      <t:FieldURI FieldURI="calendar:End" />
      <t:FieldURI FieldURI="calendar:Location" />
      <t:FieldURI FieldURI="calendar:Organizer" />
      <t:FieldURI FieldURI="calendar:RequiredAttendees" />
      <t:FieldURI FieldURI="calendar:OptionalAttendees" />
      <t:FieldURI FieldURI="item:Subject" />
      <t:FieldURI FieldURI="item:Body" />
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:CalendarView MaxEntriesReturned="100" 
                  StartDate="2025-01-01T00:00:00Z" 
                  EndDate="2025-01-31T23:59:59Z" />
  <m:ParentFolderIds>
    <t:DistinguishedFolderId Id="calendar" />
  </m:ParentFolderIds>
</m:FindItem>
```

#### Ответ (структура)

```xml
<m:FindItemResponseMessage ResponseClass="Success">
  <m:RootFolder TotalItemsInView="5" IncludesLastItemInRange="true">
    <t:Items>
      <t:CalendarItem>
        <t:ItemId Id="AAMkAG..." ChangeKey="DwAAAB..." />
        <t:Subject>Планёрка</t:Subject>
        <t:Start>2025-01-15T10:00:00Z</t:Start>
        <t:End>2025-01-15T11:00:00Z</t:End>
        <t:Location>Переговорная 1</t:Location>
        <t:Organizer>
          <t:Mailbox>
            <t:Name>Иванов Пётр</t:Name>
            <t:EmailAddress>ivanov@company.ru</t:EmailAddress>
          </t:Mailbox>
        </t:Organizer>
        <t:RequiredAttendees>
          <t:Attendee>
            <t:Mailbox>
              <t:Name>Сидоров Алексей</t:Name>
              <t:EmailAddress>sidorov@company.ru</t:EmailAddress>
            </t:Mailbox>
            <t:ResponseType>Accept</t:ResponseType>
          </t:Attendee>
        </t:RequiredAttendees>
      </t:CalendarItem>
    </t:Items>
  </m:RootFolder>
</m:FindItemResponseMessage>
```

#### Маппинг на модель Vanta Speech

| EWS Field | Vanta Speech Model | Тип |
|-----------|-------------------|-----|
| `ItemId/@Id` | `Meeting.exchangeId` | String |
| `ItemId/@ChangeKey` | `Meeting.changeKey` | String |
| `Subject` | `Meeting.title` | String |
| `Start` | `Meeting.startDate` | Date |
| `End` | `Meeting.endDate` | Date |
| `Location` | `Meeting.location` | String? |
| `Body` | `Meeting.description` | String? |
| `RequiredAttendees` | `Meeting.participants` | [Participant] |
| `Organizer` | `Meeting.organizer` | Participant |

---

### 2. Получение участников встречи (GetItem)

**Назначение:** Детальная информация о конкретном событии с полным списком участников.

**SOAP Action:** `http://schemas.microsoft.com/exchange/services/2006/messages/GetItem`

#### Запрос

```xml
<m:GetItem>
  <m:ItemShape>
    <t:BaseShape>AllProperties</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="calendar:RequiredAttendees" />
      <t:FieldURI FieldURI="calendar:OptionalAttendees" />
      <t:FieldURI FieldURI="calendar:Resources" />
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:ItemIds>
    <t:ItemId Id="AAMkAG..." ChangeKey="DwAAAB..." />
  </m:ItemIds>
</m:GetItem>
```

#### Структура участника

```xml
<t:Attendee>
  <t:Mailbox>
    <t:Name>Полное Имя</t:Name>
    <t:EmailAddress>email@company.ru</t:EmailAddress>
    <t:RoutingType>SMTP</t:RoutingType>
    <t:MailboxType>Mailbox</t:MailboxType>
  </t:Mailbox>
  <t:ResponseType>Accept</t:ResponseType>
  <t:LastResponseTime>2025-01-10T15:30:00Z</t:LastResponseTime>
</t:Attendee>
```

#### ResponseType значения

| Значение | Описание | UI |
|----------|----------|-----|
| `Accept` | Принял | ✅ |
| `Tentative` | Под вопросом | ❓ |
| `Decline` | Отклонил | ❌ |
| `NoResponseReceived` | Нет ответа | ⏳ |
| `Organizer` | Организатор | 👤 |

---

### 3. Изменение названия встречи (UpdateItem)

**Назначение:** Обновление Subject события.

**SOAP Action:** `http://schemas.microsoft.com/exchange/services/2006/messages/UpdateItem`

#### Запрос

```xml
<m:UpdateItem ConflictResolution="AlwaysOverwrite" 
              SendMeetingInvitationsOrCancellations="SendToNone">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="AAMkAG..." ChangeKey="DwAAAB..." />
      <t:Updates>
        <t:SetItemField>
          <t:FieldURI FieldURI="item:Subject" />
          <t:CalendarItem>
            <t:Subject>Новое название встречи</t:Subject>
          </t:CalendarItem>
        </t:SetItemField>
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>
```

#### Параметр SendMeetingInvitationsOrCancellations

| Значение | Поведение | Когда использовать |
|----------|-----------|-------------------|
| `SendToNone` | Без уведомлений | Косметические правки |
| `SendToAllAndSaveCopy` | Уведомить всех | Важные изменения |
| `SendToChangedAndSaveCopy` | Только затронутым | Изменение участников |

---

### 4. Обновление описания встречи (UpdateItem)

**Назначение:** Добавление саммари транскрипции в Body события.

#### Запрос

```xml
<m:UpdateItem ConflictResolution="AlwaysOverwrite" 
              SendMeetingInvitationsOrCancellations="SendToNone">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="AAMkAG..." ChangeKey="DwAAAB..." />
      <t:Updates>
        <t:SetItemField>
          <t:FieldURI FieldURI="item:Body" />
          <t:CalendarItem>
            <t:Body BodyType="HTML"><![CDATA[
              <h2>Саммари встречи</h2>
              <p>Сгенерировано в Vanta Speech</p>
              <h3>Ключевые решения:</h3>
              <ul>
                <li>Пункт 1</li>
                <li>Пункт 2</li>
              </ul>
              <h3>Action Items:</h3>
              <ul>
                <li>Задача для Иванова — до 20.01</li>
              </ul>
            ]]></t:Body>
          </t:CalendarItem>
        </t:SetItemField>
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>
```

**Важно:** Используй `BodyType="HTML"` для форматированного текста. При `BodyType="Text"` — plain text.

---

### 5. Создание встречи с участниками (CreateItem)

**Назначение:** Создание нового события с выбранными участниками.

**SOAP Action:** `http://schemas.microsoft.com/exchange/services/2006/messages/CreateItem`

#### Запрос

```xml
<m:CreateItem SendMeetingInvitations="SendToAllAndSaveCopy">
  <m:SavedItemFolderId>
    <t:DistinguishedFolderId Id="calendar" />
  </m:SavedItemFolderId>
  <m:Items>
    <t:CalendarItem>
      <t:Subject>Встреча по проекту X</t:Subject>
      <t:Body BodyType="HTML">
        <![CDATA[<p>Повестка встречи:</p><ul><li>Обсуждение статуса</li></ul>]]>
      </t:Body>
      <t:Start>2025-01-25T14:00:00+03:00</t:Start>
      <t:End>2025-01-25T15:00:00+03:00</t:End>
      <t:Location>Переговорная 2</t:Location>
      <t:RequiredAttendees>
        <t:Attendee>
          <t:Mailbox>
            <t:EmailAddress>sidorov@company.ru</t:EmailAddress>
          </t:Mailbox>
        </t:Attendee>
        <t:Attendee>
          <t:Mailbox>
            <t:EmailAddress>petrov@company.ru</t:EmailAddress>
          </t:Mailbox>
        </t:Attendee>
      </t:RequiredAttendees>
      <t:OptionalAttendees>
        <t:Attendee>
          <t:Mailbox>
            <t:EmailAddress>kozlov@company.ru</t:EmailAddress>
          </t:Mailbox>
        </t:Attendee>
      </t:OptionalAttendees>
    </t:CalendarItem>
  </m:Items>
</m:CreateItem>
```

#### Ответ

```xml
<m:CreateItemResponseMessage ResponseClass="Success">
  <m:Items>
    <t:CalendarItem>
      <t:ItemId Id="AAMkAGNew..." ChangeKey="DwAAABNew..." />
    </t:CalendarItem>
  </m:Items>
</m:CreateItemResponseMessage>
```

---

### 6. Отправка письма участникам (CreateItem для Message)

**Назначение:** Рассылка саммари или материалов участникам от имени организатора.

**SOAP Action:** `http://schemas.microsoft.com/exchange/services/2006/messages/CreateItem`

#### Запрос

```xml
<m:CreateItem MessageDisposition="SendAndSaveCopy">
  <m:SavedItemFolderId>
    <t:DistinguishedFolderId Id="sentitems" />
  </m:SavedItemFolderId>
  <m:Items>
    <t:Message>
      <t:Subject>Саммари встречи: Планёрка 15.01</t:Subject>
      <t:Body BodyType="HTML">
        <![CDATA[
        <p>Коллеги,</p>
        <p>Прикрепляю саммари нашей встречи.</p>
        <h3>Ключевые решения:</h3>
        <ul>
          <li>Решение 1</li>
          <li>Решение 2</li>
        </ul>
        <p>С уважением,<br/>Vanta Speech</p>
        ]]>
      </t:Body>
      <t:ToRecipients>
        <t:Mailbox>
          <t:EmailAddress>sidorov@company.ru</t:EmailAddress>
        </t:Mailbox>
        <t:Mailbox>
          <t:EmailAddress>petrov@company.ru</t:EmailAddress>
        </t:Mailbox>
      </t:ToRecipients>
    </t:Message>
  </m:Items>
</m:CreateItem>
```

#### MessageDisposition значения

| Значение | Поведение |
|----------|-----------|
| `SaveOnly` | Сохранить в Drafts |
| `SendOnly` | Отправить без сохранения |
| `SendAndSaveCopy` | Отправить и сохранить в Sent Items |

---

## Работа с контактами

### ResolveNames — поиск контактов

**Назначение:** Автодополнение при выборе участников. Ищет по AD и личным контактам.

**SOAP Action:** `http://schemas.microsoft.com/exchange/services/2006/messages/ResolveNames`

#### Запрос

```xml
<m:ResolveNames ReturnFullContactData="true" 
                SearchScope="ContactsActiveDirectory">
  <m:UnresolvedEntry>сидор</m:UnresolvedEntry>
</m:ResolveNames>
```

#### SearchScope варианты

| Значение | Источник поиска |
|----------|-----------------|
| `ActiveDirectory` | Только AD (GAL) |
| `Contacts` | Только личные контакты |
| `ContactsActiveDirectory` | Оба источника |
| `ContactsThenActiveDirectory` | Сначала контакты, потом AD |

#### Ответ

```xml
<m:ResolveNamesResponseMessage ResponseClass="Success">
  <m:ResolutionSet TotalItemsInView="2" IncludesLastItemInRange="true">
    <t:Resolution>
      <t:Mailbox>
        <t:Name>Сидоров Алексей</t:Name>
        <t:EmailAddress>sidorov@company.ru</t:EmailAddress>
        <t:RoutingType>SMTP</t:RoutingType>
        <t:MailboxType>Mailbox</t:MailboxType>
      </t:Mailbox>
      <t:Contact>
        <t:DisplayName>Сидоров Алексей Петрович</t:DisplayName>
        <t:GivenName>Алексей</t:GivenName>
        <t:Surname>Сидоров</t:Surname>
        <t:Department>IT</t:Department>
        <t:JobTitle>Senior Developer</t:JobTitle>
      </t:Contact>
    </t:Resolution>
  </m:ResolutionSet>
</m:ResolveNamesResponseMessage>
```

---

## Реализация на Swift

### Модели данных

```swift
struct ExchangeCalendarEvent: Codable, Identifiable {
    let id: String           // ItemId
    let changeKey: String    // ChangeKey для UpdateItem
    var subject: String
    var body: String?
    let start: Date
    let end: Date
    var location: String?
    let organizer: ExchangeParticipant
    var requiredAttendees: [ExchangeParticipant]
    var optionalAttendees: [ExchangeParticipant]
}

struct ExchangeParticipant: Codable, Identifiable {
    var id: String { email }
    let name: String
    let email: String
    let responseType: ResponseType
    
    enum ResponseType: String, Codable {
        case accept = "Accept"
        case tentative = "Tentative"
        case decline = "Decline"
        case noResponse = "NoResponseReceived"
        case organizer = "Organizer"
    }
}

struct ExchangeContact: Codable, Identifiable {
    var id: String { email }
    let name: String
    let email: String
    let department: String?
    let jobTitle: String?
}
```

### EWS Client

```swift
import Foundation

actor EWSClient {
    private let serverURL: URL
    private let session: URLSession
    private var credentials: URLCredential?
    
    init(serverURL: URL) {
        self.serverURL = serverURL
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        
        self.session = URLSession(
            configuration: config,
            delegate: NTLMAuthDelegate(),
            delegateQueue: nil
        )
    }
    
    func setCredentials(username: String, password: String) {
        self.credentials = URLCredential(
            user: username,
            password: password,
            persistence: .forSession
        )
    }
    
    // MARK: - Calendar Operations
    
    func fetchCalendarEvents(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [ExchangeCalendarEvent] {
        let body = buildFindItemBody(start: startDate, end: endDate)
        let response = try await sendRequest(soapAction: "FindItem", body: body)
        return try parseFindItemResponse(response)
    }
    
    func getEventDetails(itemId: String, changeKey: String) async throws -> ExchangeCalendarEvent {
        let body = buildGetItemBody(itemId: itemId, changeKey: changeKey)
        let response = try await sendRequest(soapAction: "GetItem", body: body)
        return try parseGetItemResponse(response)
    }
    
    func updateEventSubject(
        itemId: String,
        changeKey: String,
        newSubject: String,
        notifyAttendees: Bool = false
    ) async throws {
        let body = buildUpdateSubjectBody(
            itemId: itemId,
            changeKey: changeKey,
            subject: newSubject,
            notify: notifyAttendees
        )
        let response = try await sendRequest(soapAction: "UpdateItem", body: body)
        try validateUpdateResponse(response)
    }
    
    func updateEventBody(
        itemId: String,
        changeKey: String,
        newBody: String,
        bodyType: BodyType = .html
    ) async throws {
        let body = buildUpdateBodyBody(
            itemId: itemId,
            changeKey: changeKey,
            content: newBody,
            type: bodyType
        )
        let response = try await sendRequest(soapAction: "UpdateItem", body: body)
        try validateUpdateResponse(response)
    }
    
    func createEvent(_ event: NewCalendarEvent) async throws -> String {
        let body = buildCreateItemBody(event: event)
        let response = try await sendRequest(soapAction: "CreateItem", body: body)
        return try parseCreateItemResponse(response)
    }
    
    func sendEmail(
        to recipients: [String],
        subject: String,
        body: String,
        bodyType: BodyType = .html
    ) async throws {
        let messageBody = buildSendEmailBody(
            recipients: recipients,
            subject: subject,
            content: body,
            type: bodyType
        )
        let response = try await sendRequest(soapAction: "CreateItem", body: messageBody)
        try validateCreateItemResponse(response)
    }
    
    // MARK: - Contacts
    
    func searchContacts(query: String) async throws -> [ExchangeContact] {
        let body = buildResolveNamesBody(query: query)
        let response = try await sendRequest(soapAction: "ResolveNames", body: body)
        return try parseResolveNamesResponse(response)
    }
    
    // MARK: - Private
    
    private func sendRequest(soapAction: String, body: String) async throws -> Data {
        let envelope = wrapInSOAPEnvelope(body: body)
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.httpBody = envelope.data(using: .utf8)
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "http://schemas.microsoft.com/exchange/services/2006/messages/\(soapAction)",
            forHTTPHeaderField: "SOAPAction"
        )
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EWSError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw EWSError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return data
    }
    
    private func wrapInSOAPEnvelope(body: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                       xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages"
                       xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types">
          <soap:Header>
            <t:RequestServerVersion Version="Exchange2019" />
          </soap:Header>
          <soap:Body>
            \(body)
          </soap:Body>
        </soap:Envelope>
        """
    }
    
    enum BodyType {
        case html, text
        
        var xmlValue: String {
            switch self {
            case .html: return "HTML"
            case .text: return "Text"
            }
        }
    }
}
```

### NTLM Auth Delegate

```swift
class NTLMAuthDelegate: NSObject, URLSessionTaskDelegate {
    private var credentials: URLCredential?
    
    func setCredentials(_ credentials: URLCredential) {
        self.credentials = credentials
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.previousFailureCount < 3 else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodNTLM:
            if let credentials = credentials {
                completionHandler(.useCredential, credentials)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            
        case NSURLAuthenticationMethodServerTrust:
            // Для self-signed сертификатов в dev-среде
            if let serverTrust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
```

### Errors

```swift
enum EWSError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case authenticationFailed
    case parseError(String)
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Exchange server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .authenticationFailed:
            return "Authentication failed"
        case .parseError(let detail):
            return "Parse error: \(detail)"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
```

---

## Обработка ошибок

### Коды ошибок EWS

| ResponseCode | Описание | Действие |
|--------------|----------|----------|
| `NoError` | Успех | — |
| `ErrorItemNotFound` | Событие удалено | Обновить список |
| `ErrorChangeKeyRequired` | Нужен ChangeKey | Получить актуальный |
| `ErrorIrresolvableConflict` | Конфликт версий | Перезагрузить и повторить |
| `ErrorCalendarOccurrenceIndexIsOutOfRecurrenceRange` | Индекс вне диапазона | Проверить логику |
| `ErrorInvalidPropertyRequest` | Некорректное свойство | Исправить запрос |

### Пример обработки

```swift
func handleEWSResponse(_ data: Data) throws {
    let parser = EWSResponseParser()
    let result = try parser.parseResponse(data)
    
    switch result.responseClass {
    case .success:
        return
    case .warning:
        print("Warning: \(result.messageText ?? "")")
    case .error:
        switch result.responseCode {
        case "ErrorItemNotFound":
            throw EWSError.itemNotFound
        case "ErrorChangeKeyRequired":
            throw EWSError.changeKeyRequired
        default:
            throw EWSError.serverError(result.messageText ?? "Unknown error")
        }
    }
}
```

---

## Безопасность

### Хранение credentials

```swift
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.vantaspeech.exchange"
    
    func saveCredentials(username: String, password: String) throws {
        let passwordData = password.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    func loadCredentials(username: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.loadFailed(status)
        }
        
        return password
    }
}
```

### TLS требования

- Минимум TLS 1.2
- Валидный SSL-сертификат (не self-signed в production)
- Certificate pinning рекомендуется для enterprise

---

## Ограничения и риски

### Deprecation Warning

> ⚠️ **Microsoft объявила о прекращении поддержки EWS в Exchange Online в октябре 2026.**
> 
> Для on-premises Exchange Server EWS продолжит работать, но новых фич не будет.

### Throttling

| Параметр | Default | Рекомендация |
|----------|---------|--------------|
| EWSMaxConcurrency | 27 | Ограничить параллельные запросы |
| EWSFindCountLimit | 1000 | Использовать пагинацию |
| EWSMaxSubscriptions | 20 | Не использовать push |

---

## Чек-лист готовности

- [ ] Получен EWS URL от администратора
- [ ] Настроена NTLM-аутентификация
- [ ] Реализован FindItem для списка событий
- [ ] Реализован GetItem для деталей
- [ ] Реализован UpdateItem для Subject
- [ ] Реализован UpdateItem для Body
- [ ] Реализован CreateItem для событий
- [ ] Реализован CreateItem для email
- [ ] Реализован ResolveNames для контактов
- [ ] Credentials хранятся в Keychain
- [ ] Обработка ошибок и retry-логика
- [ ] Тестирование на реальном Exchange
