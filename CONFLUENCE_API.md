# Confluence API - Документация методов

Документация методов подключения и работы со страницами Confluence в плагине Confydian.

## Содержание

- [Подключение](#подключение)
- [Работа со страницами](#работа-со-страницами)
- [Иерархия страниц](#иерархия-страниц)
- [Пространства](#пространства)
- [Поиск](#поиск)
- [Вложения](#вложения)
- [Пользователи](#пользователи)
- [Обработка ошибок](#обработка-ошибок)
- [Типы данных](#типы-данных)

---

## Подключение

### Создание клиента

```typescript
import { ConfluenceClient } from './api/ConfluenceClient';

const client = new ConfluenceClient(
  'https://confluence.example.com',  // URL сервера
  'username',                         // Имя пользователя
  'password'                          // Пароль или API-токен
);
```

**Параметры конструктора:**

| Параметр | Тип | Описание |
|----------|-----|----------|
| `serverUrl` | `string` | URL сервера Confluence (без `/rest/api`) |
| `username` | `string` | Имя пользователя |
| `password` | `string` | Пароль или API-токен |

**Особенности:**
- Использует Basic Authentication
- Поддерживает Unicode в учётных данных (UTF-8 → Base64)
- Автоматически обрабатывает редиректы (301, 302, 303, 307, 308)
- Отключена проверка SSL сертификатов (`rejectUnauthorized: false`) для работы с самоподписанными сертификатами

---

### testConnection()

Проверяет подключение к серверу Confluence.

```typescript
async testConnection(): Promise<{ success: boolean; error?: string }>
```

**Пример:**

```typescript
const result = await client.testConnection();

if (result.success) {
  console.log('Подключение успешно!');
} else {
  console.error('Ошибка:', result.error);
}
```

**Возвращает:**

| Поле | Тип | Описание |
|------|-----|----------|
| `success` | `boolean` | `true` если подключение успешно |
| `error` | `string?` | Сообщение об ошибке (если `success: false`) |

---

## Работа со страницами

### getPage()

Получает страницу по ID.

```typescript
async getPage(
  pageId: string,
  expand?: string
): Promise<ConfluencePage>
```

**Параметры:**

| Параметр | Тип | По умолчанию | Описание |
|----------|-----|--------------|----------|
| `pageId` | `string` | - | ID страницы |
| `expand` | `string` | `'body.storage,version,ancestors'` | Поля для раскрытия |

**Пример:**

```typescript
// Получить страницу с контентом
const page = await client.getPage('12345');
console.log(page.title);
console.log(page.body?.storage.value); // XHTML контент

// Получить только версию (быстрее)
const pageMinimal = await client.getPage('12345', 'version');
console.log(pageMinimal.version.number);
```

**Возможные значения expand:**
- `body.storage` - контент страницы в Storage Format (XHTML)
- `version` - информация о версии
- `ancestors` - родительские страницы
- `history` - история изменений
- `space` - информация о пространстве

---

### createPage()

Создаёт новую страницу в Confluence.

```typescript
async createPage(
  spaceKey: string,
  title: string,
  content: string,
  parentId?: string
): Promise<ConfluencePage>
```

**Параметры:**

| Параметр | Тип | Описание |
|----------|-----|----------|
| `spaceKey` | `string` | Ключ пространства (например, `'MYSPACE'`) |
| `title` | `string` | Заголовок страницы |
| `content` | `string` | Контент в Confluence Storage Format (XHTML) |
| `parentId` | `string?` | ID родительской страницы (опционально) |

**Пример:**

```typescript
// Создать корневую страницу
const page = await client.createPage(
  'MYSPACE',
  'Новая страница',
  '<p>Привет, мир!</p>'
);

// Создать дочернюю страницу
const childPage = await client.createPage(
  'MYSPACE',
  'Дочерняя страница',
  '<h1>Заголовок</h1><p>Текст</p>',
  '12345'  // ID родительской страницы
);

console.log('Создана страница:', childPage.id);
```

---

### updatePage()

Обновляет существующую страницу.

```typescript
async updatePage(
  pageId: string,
  title: string,
  content: string,
  currentVersion: number
): Promise<ConfluencePage>
```

**Параметры:**

| Параметр | Тип | Описание |
|----------|-----|----------|
| `pageId` | `string` | ID страницы |
| `title` | `string` | Новый заголовок |
| `content` | `string` | Новый контент (Storage Format) |
| `currentVersion` | `number` | Текущий номер версии (будет автоматически +1) |

**Пример:**

```typescript
// Сначала получаем текущую версию
const page = await client.getPage('12345', 'version');

// Обновляем страницу
const updated = await client.updatePage(
  page.id,
  'Обновлённый заголовок',
  '<p>Новый контент</p>',
  page.version.number
);

console.log('Новая версия:', updated.version.number);
```

**Ошибки:**
- `VersionConflictError` - если версия устарела (HTTP 409)

---

### updatePageWithRetry()

Обновляет страницу с автоматическим retry при конфликте версий.

```typescript
async updatePageWithRetry(
  pageId: string,
  title: string,
  content: string,
  maxRetries?: number
): Promise<ConfluencePage>
```

**Параметры:**

| Параметр | Тип | По умолчанию | Описание |
|----------|-----|--------------|----------|
| `pageId` | `string` | - | ID страницы |
| `title` | `string` | - | Новый заголовок |
| `content` | `string` | - | Новый контент |
| `maxRetries` | `number` | `3` | Макс. количество попыток |

**Пример:**

```typescript
// Не нужно предварительно получать версию
const updated = await client.updatePageWithRetry(
  '12345',
  'Заголовок',
  '<p>Контент</p>',
  5  // до 5 попыток
);
```

**Особенности:**
- Автоматически получает текущую версию перед обновлением
- При конфликте использует exponential backoff (100мс, 200мс, 400мс...)
- Выбрасывает ошибку после исчерпания попыток

---

### deletePage()

Удаляет страницу.

```typescript
async deletePage(pageId: string): Promise<void>
```

**Пример:**

```typescript
await client.deletePage('12345');
console.log('Страница удалена');
```

---

## Иерархия страниц

### getChildren()

Получает дочерние страницы с поддержкой пагинации.

```typescript
async getChildren(
  pageId: string,
  limit?: number
): Promise<ConfluencePage[]>
```

**Параметры:**

| Параметр | Тип | По умолчанию | Описание |
|----------|-----|--------------|----------|
| `pageId` | `string` | - | ID родительской страницы |
| `limit` | `number` | `100` | Размер порции для пагинации |

**Пример:**

```typescript
const children = await client.getChildren('12345');
console.log(`Найдено ${children.length} дочерних страниц`);

for (const child of children) {
  console.log(`- ${child.title} (ID: ${child.id})`);
}
```

**Особенности:**
- Автоматически собирает все страницы через пагинацию
- Возвращает страницы с `version` и `ancestors`

---

### getDescendants()

Рекурсивно получает всех потомков страницы (детей, внуков и т.д.).

```typescript
async getDescendants(pageId: string): Promise<ConfluencePage[]>
```

**Пример:**

```typescript
const descendants = await client.getDescendants('12345');
console.log(`Всего ${descendants.length} страниц в поддереве`);
```

**Особенности:**
- Обходит дерево рекурсивно через `getChildren()`
- Работает с Confluence Server (не использует `/descendant/page`)

---

## Пространства

### getSpaces()

Получает список пространств Confluence.

```typescript
async getSpaces(limit?: number): Promise<ConfluenceSpace[]>
```

**Параметры:**

| Параметр | Тип | По умолчанию | Описание |
|----------|-----|--------------|----------|
| `limit` | `number` | `100` | Макс. количество пространств |

**Пример:**

```typescript
const spaces = await client.getSpaces();

for (const space of spaces) {
  console.log(`${space.name} (${space.key}) - ${space.type}`);
}
```

---

### getSpaceRootPages()

Получает корневые страницы пространства.

```typescript
async getSpaceRootPages(spaceKey: string): Promise<ConfluencePage[]>
```

**Пример:**

```typescript
const rootPages = await client.getSpaceRootPages('MYSPACE');

for (const page of rootPages) {
  console.log(`${page.title} - версия ${page.version.number}`);
}
```

---

## Поиск

### searchCQL()

Выполняет поиск через Confluence Query Language (CQL).

```typescript
async searchCQL(
  cql: string,
  expand?: string,
  limit?: number
): Promise<ConfluenceSearchResult<ConfluencePage>>
```

**Параметры:**

| Параметр | Тип | По умолчанию | Описание |
|----------|-----|--------------|----------|
| `cql` | `string` | - | CQL запрос |
| `expand` | `string?` | - | Поля для раскрытия |
| `limit` | `number` | `25` | Макс. количество результатов |

**Пример:**

```typescript
// Поиск по пространству
const result = await client.searchCQL(
  'space=MYSPACE AND type=page',
  'version,ancestors',
  50
);

console.log(`Найдено: ${result.size} страниц`);
for (const page of result.results) {
  console.log(`- ${page.title}`);
}
```

**Примеры CQL запросов:**
- `space=KEY` - все страницы пространства
- `title~"keyword"` - поиск по заголовку
- `text~"content"` - полнотекстовый поиск
- `creator=username` - страницы пользователя
- `lastModified>=now("-7d")` - изменённые за 7 дней

---

### findPageByTitle()

Находит страницу по точному названию в пространстве.

```typescript
async findPageByTitle(
  spaceKey: string,
  title: string
): Promise<ConfluencePage | null>
```

**Пример:**

```typescript
const page = await client.findPageByTitle('MYSPACE', 'Моя страница');

if (page) {
  console.log(`Найдена: ${page.id}`);
} else {
  console.log('Страница не найдена');
}
```

---

## Вложения

### getAttachments()

Получает список вложений страницы.

```typescript
async getAttachments(pageId: string): Promise<ConfluenceAttachment[]>
```

**Пример:**

```typescript
const attachments = await client.getAttachments('12345');

for (const att of attachments) {
  console.log(`${att.title} (${att.mediaType}, ${att.fileSize} bytes)`);
}
```

---

### downloadAttachment()

Скачивает вложение (бинарные данные).

```typescript
async downloadAttachment(downloadPath: string): Promise<ArrayBuffer>
```

**Параметры:**

| Параметр | Тип | Описание |
|----------|-----|----------|
| `downloadPath` | `string` | Путь из `_links.download` или полный URL |

**Пример:**

```typescript
const attachments = await client.getAttachments('12345');

for (const att of attachments) {
  const data = await client.downloadAttachment(att._links.download);
  console.log(`Скачано ${att.title}: ${data.byteLength} bytes`);

  // Сохранить в файл (в Obsidian)
  await app.vault.createBinary(`attachments/${att.title}`, data);
}
```

---

### uploadAttachment()

Загружает вложение к странице.

```typescript
async uploadAttachment(
  pageId: string,
  filename: string,
  data: ArrayBuffer,
  mimeType: string
): Promise<ConfluenceAttachment>
```

**Параметры:**

| Параметр | Тип | Описание |
|----------|-----|----------|
| `pageId` | `string` | ID страницы |
| `filename` | `string` | Имя файла |
| `data` | `ArrayBuffer` | Бинарные данные |
| `mimeType` | `string` | MIME-тип (например, `'image/png'`) |

**Пример:**

```typescript
const imageData = await fetch('image.png').then(r => r.arrayBuffer());

const attachment = await client.uploadAttachment(
  '12345',
  'image.png',
  imageData,
  'image/png'
);

console.log(`Загружено: ${attachment.id}`);
```

---

## Пользователи

### getUserByKey()

Получает информацию о пользователе по userkey.

```typescript
async getUserByKey(userkey: string): Promise<{ displayName: string; username: string } | null>
```

**Пример:**

```typescript
const user = await client.getUserByKey('abc123');
if (user) {
  console.log(`${user.displayName} (@${user.username})`);
}
```

---

### getUserByUsername()

Получает информацию о пользователе по имени.

```typescript
async getUserByUsername(username: string): Promise<{ displayName: string; username: string } | null>
```

**Пример:**

```typescript
const user = await client.getUserByUsername('john.doe');
if (user) {
  console.log(`${user.displayName}`);
}
```

---

## Обработка ошибок

### Классы ошибок

```typescript
import {
  ConfluenceApiError,
  VersionConflictError,
  AuthenticationError,
  NotFoundError,
  NetworkError,
} from './api/errors';
```

| Класс | HTTP код | Описание |
|-------|----------|----------|
| `AuthenticationError` | 401 | Неверные учётные данные |
| `NotFoundError` | 404 | Ресурс не найден |
| `VersionConflictError` | 409 | Конфликт версий при обновлении |
| `ConfluenceApiError` | * | Любая другая ошибка API |
| `NetworkError` | - | Ошибка сети |

### Пример обработки

```typescript
try {
  const page = await client.getPage('12345');
} catch (error) {
  if (error instanceof AuthenticationError) {
    console.error('Проверьте логин/пароль');
  } else if (error instanceof NotFoundError) {
    console.error('Страница не найдена');
  } else if (error instanceof VersionConflictError) {
    console.error('Страница была изменена другим пользователем');
  } else if (error instanceof NetworkError) {
    console.error('Проблемы с сетью');
  } else if (error instanceof ConfluenceApiError) {
    console.error(`Ошибка API (${error.status}): ${error.message}`);
  }
}
```

---

## Типы данных

### ConfluencePage

```typescript
interface ConfluencePage {
  id: string;
  type: 'page';
  title: string;
  space?: { key: string; name: string };
  version: ConfluenceVersion;
  history?: ConfluenceHistory;
  ancestors?: Array<{ id: string; title: string }>;
  body?: {
    storage: {
      value: string;           // XHTML контент
      representation: 'storage';
    };
  };
  _links: { webui: string; self: string };
}
```

### ConfluenceVersion

```typescript
interface ConfluenceVersion {
  number: number;
  when: string;              // ISO дата
  by: ConfluenceUser;
  message?: string;
}
```

### ConfluenceSpace

```typescript
interface ConfluenceSpace {
  id: number;
  key: string;
  name: string;
  type: 'global' | 'personal';
  description?: { plain: { value: string } };
  _links: { webui: string };
}
```

### ConfluenceAttachment

```typescript
interface ConfluenceAttachment {
  id: string;
  title: string;
  mediaType: string;
  fileSize: number;
  _links: { download: string };
}
```

### ConfluenceSearchResult

```typescript
interface ConfluenceSearchResult<T = ConfluencePage> {
  results: T[];
  start: number;
  limit: number;
  size: number;
  _links: { next?: string };
}
```

---

## Файлы исходного кода

- [ConfluenceClient.ts](../src/api/ConfluenceClient.ts) - HTTP клиент
- [errors.ts](../src/api/errors.ts) - классы ошибок
- [confluence.ts](../src/types/confluence.ts) - типы данных
